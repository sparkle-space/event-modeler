defmodule EventModeler.EventModel.Serializer do
  @moduledoc """
  Converts a `%EventModel{}` struct back to markdown string.

  Renders frontmatter as YAML, sections in order, slices as emlang blocks,
  and event stream entries as eventstream blocks.
  """

  alias EventModeler.EventModel
  alias EventModeler.EventModel.{Domain, Element, EventEntry, Field}

  @doc """
  Serializes a `%EventModel{}` struct to an Event Model markdown string.
  """
  @spec serialize(%EventModel{}) :: String.t()
  def serialize(%EventModel{} = event_model) do
    [
      render_frontmatter(event_model),
      render_title(event_model),
      render_section("Overview", event_model.overview),
      render_key_ideas(event_model.key_ideas),
      render_slices(event_model.slices),
      render_scenarios(event_model.scenarios),
      render_data_flows(event_model),
      render_section("Dependencies", event_model.model_dependencies),
      render_section("Sources", event_model.sources),
      render_event_stream(event_model.event_stream)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
    |> String.trim_trailing()
    |> Kernel.<>("\n")
  end

  @doc """
  Serializes with updated frontmatter for a save operation.
  Updates `status` to "refined" and `updated` to current timestamp.
  """
  @spec serialize_for_save(%EventModel{}) :: String.t()
  def serialize_for_save(%EventModel{} = event_model) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    event_model
    |> Map.put(:updated, now)
    |> maybe_update_status()
    |> serialize()
  end

  defp maybe_update_status(%EventModel{status: "draft"} = event_model) do
    # Only promote to "refined" if we have slices with scenarios
    has_scenarios =
      Enum.any?(event_model.slices || [], fn s -> s.tests != nil and s.tests != [] end)

    if has_scenarios, do: %{event_model | status: "refined"}, else: event_model
  end

  defp maybe_update_status(event_model), do: event_model

  defp render_frontmatter(%EventModel{} = event_model) do
    fm = %{}
    fm = if event_model.title, do: Map.put(fm, "title", event_model.title), else: fm
    fm = if event_model.status, do: Map.put(fm, "status", event_model.status), else: fm
    fm = if event_model.format, do: Map.put(fm, "format", event_model.format), else: fm
    fm = if event_model.domain, do: Map.put(fm, "domain", event_model.domain), else: fm
    fm = if event_model.version, do: Map.put(fm, "version", event_model.version), else: fm
    fm = if event_model.created, do: Map.put(fm, "created", event_model.created), else: fm
    fm = if event_model.updated, do: Map.put(fm, "updated", event_model.updated), else: fm

    fm =
      if event_model.dependencies != nil and event_model.dependencies != [],
        do: Map.put(fm, "dependencies", event_model.dependencies),
        else: fm

    fm =
      if event_model.tags != nil and event_model.tags != [],
        do: Map.put(fm, "tags", event_model.tags),
        else: fm

    fm =
      if event_model.domains != nil and event_model.domains != [],
        do: Map.put(fm, "domains", event_model.domains),
        else: fm

    if map_size(fm) == 0 do
      nil
    else
      yaml = render_yaml_map(fm)
      "---\n#{yaml}---\n"
    end
  end

  defp render_title(%EventModel{title: nil}), do: nil
  defp render_title(%EventModel{title: title}), do: "# #{title}\n"

  defp render_section(_name, nil), do: nil
  defp render_section(_name, ""), do: nil
  defp render_section(name, content), do: "## #{name}\n\n#{content}\n"

  defp render_key_ideas(nil), do: nil
  defp render_key_ideas([]), do: nil

  defp render_key_ideas(ideas) do
    items = Enum.map_join(ideas, "\n", fn idea -> "- #{idea}" end)
    "## Key Ideas\n\n#{items}\n"
  end

  defp render_scenarios(nil), do: nil
  defp render_scenarios([]), do: nil

  defp render_scenarios(scenarios) do
    blocks =
      Enum.map_join(scenarios, "\n", fn scenario ->
        name = scenario[:name] || scenario.name
        body = scenario[:body] || Map.get(scenario, :body, "")
        "### Scenario: #{name}\n\n#{body}\n"
      end)

    "## Scenarios\n\n#{blocks}"
  end

  defp render_slices(nil), do: nil
  defp render_slices([]), do: nil

  defp render_slices(slices) do
    slice_blocks = Enum.map_join(slices, "\n", &render_slice/1)
    "## Slices\n\n#{slice_blocks}"
  end

  defp render_slice(slice) do
    wireframe =
      if slice.wireframe_description,
        do: "**Wireframe:** #{slice.wireframe_description}\n\n",
        else: ""

    emlang = render_emlang_block(slice)
    "### Slice: #{slice.name}\n\n#{wireframe}#{emlang}\n"
  end

  defp render_emlang_block(slice) do
    connections = render_emlang_connections(slice.connections)
    steps = render_emlang_steps(slice.steps)
    tests = render_emlang_tests(slice.tests)
    slice_meta = render_slice_meta(slice)

    body =
      ["slices:", "  #{slice.name}:"]
      |> Enum.concat(slice_meta)
      |> Enum.concat(connections)
      |> Enum.concat(["    steps:"])
      |> Enum.concat(steps)
      |> Enum.concat(tests)
      |> Enum.join("\n")

    "```yaml emlang\n#{body}\n```\n"
  end

  defp render_slice_meta(slice) do
    lines = []
    lines = if slice.pattern, do: lines ++ ["    pattern: #{slice.pattern}"], else: lines
    lines = if slice.domain, do: lines ++ ["    domain: #{slice.domain}"], else: lines
    lines
  end

  defp render_emlang_connections(nil), do: []

  defp render_emlang_connections(%{consumes: c, produces_for: p, gates: g})
       when c == [] and p == [] and g == [] do
    []
  end

  defp render_emlang_connections(%{consumes: consumes, produces_for: produces_for, gates: gates}) do
    lines = ["    connections:"]

    lines =
      if consumes != [] do
        lines ++
          ["      consumes:"] ++
          Enum.map(consumes, &"        - #{&1}")
      else
        lines
      end

    lines =
      if produces_for != [] do
        lines ++
          ["      produces_for:"] ++
          Enum.map(produces_for, &"        - #{&1}")
      else
        lines
      end

    lines =
      if gates != [] do
        lines ++
          ["      gates:"] ++
          Enum.map(gates, &"        - \"#{&1}\"")
      else
        lines
      end

    lines
  end

  defp render_emlang_connections(_), do: []

  defp render_emlang_steps(steps) do
    Enum.flat_map(steps, fn step ->
      prefix = Element.prefix_from_type(step.type)
      label = if step.swimlane, do: "#{step.swimlane}/#{step.label}", else: step.label
      base = "      - #{prefix}: #{label}"
      has_props = step.props != nil and step.props != %{}
      has_fields = step.fields != nil and step.fields != []

      cond do
        has_fields and has_props ->
          props_lines = render_props_lines(step.props)
          fields_lines = render_fields_lines(step.fields)
          [base, "        props:" | props_lines] ++ ["        fields:" | fields_lines]

        has_fields ->
          fields_lines = render_fields_lines(step.fields)
          [base, "        fields:" | fields_lines]

        has_props ->
          props_lines = render_props_lines(step.props)
          [base, "        props:" | props_lines]

        true ->
          [base]
      end
    end)
  end

  defp render_props_lines(props) do
    Enum.map(props, fn {k, v} ->
      "          #{k}: #{v}"
    end)
  end

  defp render_fields_lines(fields) do
    Enum.flat_map(fields, fn field ->
      {name, value} = Field.to_yaml(field)

      case value do
        v when is_binary(v) ->
          ["          #{name}: #{v}"]

        %{} = map ->
          # Render as inline YAML flow mapping: {type: uuid, generated: true}
          inner =
            Enum.map_join(map, ", ", fn {k, v} ->
              "#{k}: #{format_field_value(v)}"
            end)

          ["          #{name}: {#{inner}}"]
      end
    end)
  end

  defp format_field_value(v) when is_boolean(v), do: to_string(v)
  defp format_field_value(v) when is_binary(v), do: v
  defp format_field_value(v) when is_list(v), do: "[#{Enum.join(v, ", ")}]"
  defp format_field_value(v), do: inspect(v)

  defp render_emlang_tests(nil), do: []
  defp render_emlang_tests([]), do: []

  defp render_emlang_tests(tests) do
    test_lines =
      Enum.flat_map(tests, fn test ->
        lines = ["      #{test.name}:"]

        lines =
          lines ++
            render_test_clause("given", test[:given] || test.given)

        lines =
          lines ++
            render_test_clause("when", test[:when_clause] || test.when_clause)

        lines ++
          render_test_clause("then", test[:then_clause] || test.then_clause)
      end)

    ["    tests:" | test_lines]
  end

  defp render_test_clause(_name, nil), do: []
  defp render_test_clause(_name, []), do: []

  defp render_test_clause(name, clauses) do
    clause_lines =
      Enum.flat_map(clauses, fn clause ->
        type = clause[:type] || clause.type
        label = clause[:label] || clause.label
        props = clause[:props] || clause.props || %{}
        base = "          - #{type}: #{label}"

        if props == nil or props == %{} do
          [base]
        else
          props_lines =
            Enum.map(props, fn {k, v} ->
              "              #{k}: #{v}"
            end)

          [base, "            props:" | props_lines]
        end
      end)

    ["        #{name}:" | clause_lines]
  end

  defp render_data_flows(%EventModel{data_flows: data_flows})
       when is_binary(data_flows) and data_flows != "" do
    "## Data Flows\n\n#{data_flows}\n"
  end

  defp render_data_flows(%EventModel{slices: slices}) when is_list(slices) and slices != [] do
    rows = generate_data_flow_rows(slices)

    if rows == [] do
      nil
    else
      header = "| Source | Field | Target | Field |\n|--------|-------|--------|-------|\n"

      table =
        Enum.map_join(rows, "\n", fn {src, sf, tgt, tf} ->
          "| #{src} | #{sf} | #{tgt} | #{tf} |"
        end)

      "## Data Flows\n\n#{header}#{table}\n"
    end
  end

  defp render_data_flows(_event_model), do: nil

  defp generate_data_flow_rows(slices) do
    Enum.flat_map(slices, fn slice ->
      steps = slice.steps || []
      commands = Enum.filter(steps, &(&1.type == :command))
      events = Enum.filter(steps, &(&1.type == :event))
      views = Enum.filter(steps, &(&1.type == :view))

      # Command fields -> Event fields (command produces events)
      cmd_to_evt =
        for cmd <- commands,
            {ck, _cv} <- cmd.props || %{},
            evt <- events,
            {ek, _ev} <- evt.props || %{},
            String.downcase(ck) == String.downcase(ek) do
          {cmd.label, ck, evt.label, ek}
        end

      # Event fields -> View fields (event updates read models)
      evt_to_view =
        for evt <- events,
            {ek, _ev} <- evt.props || %{},
            view <- views,
            {vk, _vv} <- view.props || %{},
            String.downcase(ek) == String.downcase(vk) do
          {evt.label, ek, view.label, vk}
        end

      cmd_to_evt ++ evt_to_view
    end)
    |> Enum.uniq()
  end

  defp render_event_stream(nil), do: nil
  defp render_event_stream([]), do: nil

  defp render_event_stream(entries) do
    blocks = Enum.map_join(entries, "\n", &render_event_entry/1)
    "<!-- event-stream -->\n## Event Stream\n\n#{blocks}"
  end

  defp render_event_entry(%EventEntry{} = entry) do
    lines = [
      "seq: #{entry.seq}",
      "ts: \"#{entry.ts}\"",
      "type: #{entry.type}",
      "actor: #{entry.actor}"
    ]

    lines = if entry.session, do: lines ++ ["session: \"#{entry.session}\""], else: lines
    lines = if entry.ref, do: lines ++ ["ref: \"#{entry.ref}\""], else: lines
    lines = if entry.note, do: lines ++ ["note: \"#{entry.note}\""], else: lines

    data_yaml = render_data(entry.data)
    lines = lines ++ ["data:", data_yaml]

    body = Enum.join(lines, "\n")
    "```eventstream\n#{body}\n```\n"
  end

  defp render_data(nil), do: "  {}"

  defp render_data(data) when is_map(data) do
    Enum.map_join(data, "\n", fn {k, v} ->
      "  #{k}: #{format_value(v)}"
    end)
  end

  defp format_value(v) when is_binary(v) do
    escaped = String.replace(v, "\"", "\\\"")
    "\"#{escaped}\""
  end

  defp format_value(v) when is_number(v), do: to_string(v)
  defp format_value(v) when is_atom(v), do: to_string(v)
  defp format_value(v) when is_list(v), do: "[#{Enum.map_join(v, ", ", &to_string/1)}]"
  defp format_value(v), do: format_value(inspect(v))

  defp render_yaml_map(map) do
    # Render in a stable order for frontmatter
    key_order = [
      "title",
      "status",
      "format",
      "domain",
      "version",
      "created",
      "updated",
      "dependencies",
      "tags",
      "domains"
    ]

    keys = Enum.sort_by(Map.keys(map), fn k -> Enum.find_index(key_order, &(&1 == k)) || 99 end)

    Enum.map_join(keys, "", fn key ->
      value = Map.get(map, key)
      render_yaml_field(key, value)
    end)
  end

  defp render_yaml_field(key, value) when is_binary(value), do: "#{key}: \"#{value}\"\n"
  defp render_yaml_field(key, value) when is_integer(value), do: "#{key}: #{value}\n"
  defp render_yaml_field(key, value) when is_atom(value), do: "#{key}: #{value}\n"

  defp render_yaml_field("domains", domains) when is_list(domains) do
    items =
      Enum.map_join(domains, "", fn domain ->
        yaml = Domain.to_yaml(domain)
        render_domain_item(yaml)
      end)

    "domains:\n#{items}"
  end

  defp render_yaml_field(key, value) when is_list(value) do
    items = Enum.map_join(value, "", fn item -> "  - \"#{item}\"\n" end)
    "#{key}:\n#{items}"
  end

  defp render_yaml_field(key, value), do: "#{key}: #{inspect(value)}\n"

  defp render_domain_item(name) when is_binary(name), do: "  - \"#{name}\"\n"

  defp render_domain_item(%{} = map) do
    # Sort keys: name first, then description, then color, then rest
    key_order = ["name", "description", "color"]

    keys =
      Enum.sort_by(Map.keys(map), fn k ->
        Enum.find_index(key_order, &(&1 == k)) || 99
      end)

    [first_key | rest_keys] = keys
    first_line = "  - #{first_key}: \"#{Map.get(map, first_key)}\"\n"

    rest_lines =
      Enum.map_join(rest_keys, "", fn k ->
        "    #{k}: \"#{Map.get(map, k)}\"\n"
      end)

    first_line <> rest_lines
  end
end
