defmodule EventModeler.Canvas.Layout do
  @moduledoc """
  Pure module that takes a parsed `%EventModel{}` and computes element positions
  for SVG rendering.

  Elements are laid out left-to-right per slice in step order
  (wireframe -> command -> event -> view). Swimlane rows group elements
  by their swimlane prefix and are ordered by type: triggers on top,
  commands/views in the middle, events at the bottom.
  """

  alias EventModeler.EventModel
  alias EventModeler.EventModel.Pattern
  alias EventModeler.Canvas.Swimlane

  @element_width 180
  @element_height 60
  @h_gap 60
  @v_gap 40
  @swimlane_label_width 120
  @slice_gap 100
  @padding 40

  @spec_card_height 80
  @spec_card_gap 10
  @spec_top_margin 20
  @spec_indicator_height 24

  defmodule PositionedElement do
    @moduledoc false
    defstruct [
      :id,
      :type,
      :label,
      :swimlane,
      :props,
      :fields,
      :x,
      :y,
      :width,
      :height,
      :slice_name
    ]
  end

  defmodule Connection do
    @moduledoc false
    defstruct [:from_id, :to_id, :from_x, :from_y, :to_x, :to_y]
  end

  defmodule PositionedSpec do
    @moduledoc false
    defstruct [:name, :slice_name, :x, :y, :width, :height, :given, :when_clause, :then_clause]
  end

  defmodule SliceConnection do
    @moduledoc false

    defstruct [
      :from_slice,
      :to_slice,
      :type,
      :style,
      :from_x,
      :from_y,
      :to_x,
      :to_y,
      :from_element_id,
      :to_element_id,
      :anchor_mode
    ]
  end

  defmodule DomainBand do
    @moduledoc false
    defstruct [:name, :y, :height, :color, :description]
  end

  defmodule LayoutResult do
    @moduledoc false
    defstruct [
      :width,
      :height,
      elements: [],
      connections: [],
      swimlanes: [],
      slice_labels: [],
      slice_connections: [],
      domain_bands: []
    ]
  end

  @domain_header_height 30
  @domain_gap 20

  @detailed_element_height 120

  @doc """
  Computes layout positions for all elements in a parsed Event Model.
  Returns a `%LayoutResult{}` with positioned elements and connections.

  Options:
    - `:view_mode` - `:compact` (default) or `:detailed` (shows field schemas)
  """
  @spec compute(%EventModel{}, keyword()) :: %LayoutResult{}
  def compute(event_model, opts \\ [])

  def compute(%EventModel{slices: slices, domains: domains} = event_model, opts) do
    view_mode = Keyword.get(opts, :view_mode, :compact)
    has_domains = domains != nil and domains != []
    elem_height = if view_mode == :detailed, do: @detailed_element_height, else: @element_height

    # Collect all unique typed swimlanes (with domain info when available)
    all_swimlanes = collect_swimlanes(slices, has_domains)

    # Assign vertical positions — domain-grouped or flat
    {swimlane_y, domain_bands} =
      if has_domains do
        assign_domain_grouped_positions(all_swimlanes, event_model, elem_height)
      else
        {assign_swimlane_positions(all_swimlanes, elem_height), []}
      end

    # Position elements slice by slice, left to right
    {positioned, connections, slice_labels, total_width} =
      layout_slices(slices, swimlane_y, elem_height, view_mode)

    # Calculate canvas dimensions
    total_height = calculate_height(swimlane_y, elem_height)

    # Build swimlane data for rendering (with type info)
    swimlane_data =
      Enum.map(all_swimlanes, fn %Swimlane{name: name, type: type, domain: domain} ->
        %{
          name: name,
          type: type,
          domain: domain,
          y: Map.get(swimlane_y, swimlane_key(name, domain), @padding),
          height: elem_height + @v_gap
        }
      end)

    slice_conns = compute_slice_connections(slices, slice_labels, positioned)

    %LayoutResult{
      elements: positioned,
      connections: connections,
      swimlanes: swimlane_data,
      slice_labels: slice_labels,
      slice_connections: slice_conns,
      domain_bands: domain_bands,
      width: max(total_width + @padding * 2, 800),
      height: max(total_height + @padding * 2, 400)
    }
  end

  defp compute_slice_connections(slices, slice_labels, positioned) do
    label_map = Map.new(slice_labels, fn l -> {l.name, l} end)

    # Build element lookup by slice name
    elements_by_slice = Enum.group_by(positioned, & &1.slice_name)

    # Build a map of event labels to producing slice names.
    # Use put_new to keep the first occurrence — later slices (e.g. view slices)
    # may reference the same events as inputs, not producers.
    event_to_slice =
      Enum.reduce(slices, %{}, fn slice, acc ->
        slice.steps
        |> Enum.filter(&(&1.type == :event))
        |> Enum.reduce(acc, fn step, inner_acc ->
          full = if step.swimlane, do: "#{step.swimlane}/#{step.label}", else: step.label

          inner_acc
          |> Map.put_new(full, slice.name)
          |> Map.put_new(step.label, slice.name)
        end)
      end)

    slices
    |> Enum.flat_map(fn slice ->
      case slice.connections do
        nil ->
          []

        %{consumes: consumes, produces_for: produces_for} ->
          consume_conns =
            Enum.flat_map(consumes, fn event_ref ->
              source_slice = Map.get(event_to_slice, event_ref)
              cross_context = String.contains?(event_ref, "/") and is_nil(source_slice)
              from = source_slice

              if from && Map.has_key?(label_map, from) && Map.has_key?(label_map, slice.name) do
                # Try to resolve element anchors
                source_event = find_source_event(elements_by_slice, from, event_ref)
                target_entry = find_target_entry(elements_by_slice, slice.name)

                case {source_event, target_entry} do
                  {%PositionedElement{} = src, %PositionedElement{} = tgt} ->
                    [
                      %SliceConnection{
                        from_slice: from,
                        to_slice: slice.name,
                        type: :consumes,
                        style: :solid,
                        from_x: src.x + src.width,
                        from_y: src.y + div(src.height, 2),
                        to_x: tgt.x,
                        to_y: tgt.y + div(tgt.height, 2),
                        from_element_id: src.id,
                        to_element_id: tgt.id,
                        anchor_mode: :element
                      }
                    ]

                  _ ->
                    # Fallback to label-based
                    from_label = label_map[from]
                    to_label = label_map[slice.name]

                    [
                      %SliceConnection{
                        from_slice: from,
                        to_slice: slice.name,
                        type: :consumes,
                        style: :solid,
                        from_x: from_label.x + div(from_label.width, 2),
                        from_y: 24,
                        to_x: to_label.x + div(to_label.width, 2),
                        to_y: 24,
                        anchor_mode: :label
                      }
                    ]
                end
              else
                if cross_context do
                  # External reference with no local match — create dashed stub
                  case Map.get(label_map, slice.name) do
                    nil ->
                      []

                    to_label ->
                      [
                        %SliceConnection{
                          from_slice: event_ref,
                          to_slice: slice.name,
                          type: :consumes,
                          style: :dashed,
                          from_x: to_label.x - 60,
                          from_y: 24,
                          to_x: to_label.x + div(to_label.width, 2),
                          to_y: 24,
                          anchor_mode: :stub
                        }
                      ]
                  end
                else
                  []
                end
              end
            end)

          produce_conns =
            Enum.flat_map(produces_for, fn target_ref ->
              if Map.has_key?(label_map, target_ref) &&
                   Map.has_key?(label_map, slice.name) do
                cross = String.contains?(target_ref, "/")

                # Try to resolve element anchors
                source_event = find_last_event(elements_by_slice, slice.name)
                target_entry = find_target_entry(elements_by_slice, target_ref)

                case {source_event, target_entry} do
                  {%PositionedElement{} = src, %PositionedElement{} = tgt} ->
                    [
                      %SliceConnection{
                        from_slice: slice.name,
                        to_slice: target_ref,
                        type: :produces_for,
                        style: if(cross, do: :dashed, else: :solid),
                        from_x: src.x + src.width,
                        from_y: src.y + div(src.height, 2),
                        to_x: tgt.x,
                        to_y: tgt.y + div(tgt.height, 2),
                        from_element_id: src.id,
                        to_element_id: tgt.id,
                        anchor_mode: :element
                      }
                    ]

                  _ ->
                    # Fallback to label-based
                    from_label = label_map[slice.name]
                    to_label = label_map[target_ref]

                    [
                      %SliceConnection{
                        from_slice: slice.name,
                        to_slice: target_ref,
                        type: :produces_for,
                        style: if(cross, do: :dashed, else: :solid),
                        from_x: from_label.x + div(from_label.width, 2),
                        from_y: 24,
                        to_x: to_label.x + div(to_label.width, 2),
                        to_y: 24,
                        anchor_mode: :label
                      }
                    ]
                end
              else
                []
              end
            end)

          consume_conns ++ produce_conns
      end
    end)
    |> Enum.uniq_by(fn c ->
      {c.from_slice, c.to_slice, c.from_element_id, c.to_element_id}
    end)
  end

  # Find the event element in source_slice whose label matches the event_ref
  defp find_source_event(elements_by_slice, source_slice, event_ref) do
    elems = Map.get(elements_by_slice, source_slice, [])
    # Strip swimlane prefix from event_ref (e.g. "Domain/Produced" -> "Produced")
    bare_label = event_ref |> String.split("/") |> List.last()

    Enum.find(elems, fn e ->
      e.type == :event and (e.label == event_ref or e.label == bare_label)
    end)
  end

  # Find the last event element in a slice (for produces_for)
  defp find_last_event(elements_by_slice, slice_name) do
    elems = Map.get(elements_by_slice, slice_name, [])

    elems
    |> Enum.filter(&(&1.type == :event))
    |> List.last()
  end

  # Find the first command/trigger element in a slice (the entry point)
  @entry_types [:command, :wireframe, :automation, :processor, :translator]
  defp find_target_entry(elements_by_slice, slice_name) do
    elems = Map.get(elements_by_slice, slice_name, [])

    Enum.find(elems, fn e -> e.type in @entry_types end) || List.first(elems)
  end

  defp collect_swimlanes(slices, has_domains) do
    slices
    |> Enum.flat_map(fn slice ->
      slice_domain = if has_domains, do: slice.domain, else: nil

      Enum.map(slice.steps, fn step ->
        name = step.swimlane || Swimlane.default_name(Swimlane.type_for_element(step.type))
        type = Swimlane.type_for_element(step.type)
        domain = if has_domains, do: slice_domain, else: nil
        %Swimlane{name: name, type: type, domain: domain}
      end)
    end)
    |> Enum.uniq_by(fn %Swimlane{name: name, type: type, domain: domain} ->
      {name, type, domain}
    end)
    |> Enum.sort_by(fn %Swimlane{name: name, type: type, domain: domain} ->
      {domain || "", Swimlane.sort_order(type), name}
    end)
  end

  defp assign_swimlane_positions(swimlanes, elem_height) do
    swimlanes
    |> Enum.with_index()
    |> Map.new(fn {%Swimlane{name: name, domain: domain}, idx} ->
      {swimlane_key(name, domain), @padding + idx * (elem_height + @v_gap)}
    end)
  end

  defp assign_domain_grouped_positions(swimlanes, event_model, elem_height) do
    domain_map =
      Map.new(event_model.domains || [], fn d -> {d.name, d} end)

    # Group swimlanes by domain, preserving order
    domain_order =
      swimlanes
      |> Enum.map(& &1.domain)
      |> Enum.uniq()
      |> Enum.reject(&is_nil/1)

    # Add nil domain at end for any elements without domain
    has_nil = Enum.any?(swimlanes, &is_nil(&1.domain))
    domain_order = if has_nil, do: domain_order ++ [nil], else: domain_order

    grouped = Enum.group_by(swimlanes, & &1.domain)

    {swimlane_y, domain_bands, _y} =
      Enum.reduce(domain_order, {%{}, [], @padding}, fn domain_name, {y_map, bands, y} ->
        domain_swimlanes =
          (Map.get(grouped, domain_name) || [])
          |> Enum.sort_by(fn sl -> {Swimlane.sort_order(sl.type), sl.name} end)

        # Domain header
        band_y = y
        content_y = y + @domain_header_height

        # Assign positions to swimlanes within this domain
        {updated_y_map, next_y} =
          Enum.reduce(domain_swimlanes, {y_map, content_y}, fn sl, {acc, current_y} ->
            key = swimlane_key(sl.name, sl.domain)
            {Map.put(acc, key, current_y), current_y + elem_height + @v_gap}
          end)

        domain_info = if domain_name, do: Map.get(domain_map, domain_name), else: nil

        band = %DomainBand{
          name: domain_name || "Unassigned",
          y: band_y,
          height: next_y - band_y,
          color: if(domain_info, do: domain_info.color, else: nil),
          description: if(domain_info, do: domain_info.description, else: nil)
        }

        {updated_y_map, bands ++ [band], next_y + @domain_gap}
      end)

    {swimlane_y, domain_bands}
  end

  defp swimlane_key(name, nil), do: name
  defp swimlane_key(name, domain), do: "#{domain}::#{name}"

  defp calculate_height(swimlane_y, elem_height) do
    if map_size(swimlane_y) == 0 do
      0
    else
      max_y = swimlane_y |> Map.values() |> Enum.max()
      max_y + elem_height + @v_gap
    end
  end

  defp layout_slices(slices, swimlane_y, elem_height, view_mode) do
    initial_x = @swimlane_label_width + @padding

    {positioned, connections, labels, final_x} =
      Enum.reduce(slices, {[], [], [], initial_x}, fn slice, {elems, conns, labels, x_offset} ->
        {slice_elems, slice_conns, next_x} =
          layout_slice(slice, swimlane_y, x_offset, elem_height, view_mode)

        {min_y, max_y_bottom} = slice_vertical_bounds(slice_elems)
        detected_pattern = Pattern.detect(slice)

        label = %{
          name: slice.name,
          x: x_offset,
          width: next_x - x_offset - @slice_gap,
          y: min_y,
          height: max_y_bottom - min_y,
          pattern: detected_pattern,
          pattern_label: if(detected_pattern, do: Pattern.label(detected_pattern), else: nil),
          domain: slice.domain
        }

        {elems ++ slice_elems, conns ++ slice_conns, labels ++ [label], next_x}
      end)

    {positioned, connections, labels, final_x}
  end

  defp layout_slice(slice, swimlane_y, start_x, elem_height, view_mode) do
    # In detailed mode, elements with fields get taller
    {elements, _x} =
      Enum.reduce(slice.steps, {[], start_x}, fn step, {acc, x} ->
        swimlane =
          step.swimlane || Swimlane.default_name(Swimlane.type_for_element(step.type))

        # Look up Y position using domain-aware key, falling back to plain name
        key = swimlane_key(swimlane, slice.domain)
        y = Map.get(swimlane_y, key, Map.get(swimlane_y, swimlane, @padding))

        offset_x = step.props["position_offset_x"] || 0
        offset_y = step.props["position_offset_y"] || 0

        # In detailed mode, height scales with number of fields
        height =
          if view_mode == :detailed and step.fields != [] do
            field_count = length(step.fields)
            max(elem_height, @element_height + field_count * 18)
          else
            elem_height
          end

        elem = %PositionedElement{
          id: step.id,
          type: step.type,
          label: step.label,
          swimlane: swimlane,
          props: step.props,
          fields: step.fields || [],
          x: x + offset_x,
          y: y + offset_y,
          width: @element_width,
          height: height,
          slice_name: slice.name
        }

        {acc ++ [elem], x + @element_width + @h_gap}
      end)

    # Create connections between consecutive elements
    connections =
      elements
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [from, to] ->
        %Connection{
          from_id: from.id,
          to_id: to.id,
          from_x: from.x + from.width,
          from_y: from.y + div(from.height, 2),
          to_x: to.x,
          to_y: to.y + div(to.height, 2)
        }
      end)

    next_x =
      case elements do
        [] -> start_x + @slice_gap
        elems -> List.last(elems).x + @element_width + @slice_gap
      end

    {elements, connections, next_x}
  end

  defp slice_vertical_bounds([]) do
    {@padding, @padding + @element_height}
  end

  defp slice_vertical_bounds(elements) do
    min_y = elements |> Enum.map(& &1.y) |> Enum.min()
    max_y_bottom = elements |> Enum.map(&(&1.y + &1.height)) |> Enum.max()
    {min_y, max_y_bottom}
  end

  @doc """
  Computes spec card positions for a selected slice on demand.

  Given the slices list, a slice name, and the existing layout result,
  returns `{spec_cards, indicator, extra_height}` where:
  - `spec_cards` — list of `%PositionedSpec{}` positioned below the slice
  - `indicator` — map with position data for the spec count badge
  - `extra_height` — additional canvas height needed when expanded
  """
  @spec compute_spec_cards(
          [%EventModeler.EventModel.Slice{}],
          String.t(),
          %LayoutResult{} | map()
        ) ::
          {[%PositionedSpec{}], map() | nil, non_neg_integer()}
  def compute_spec_cards(slices, slice_name, layout) do
    slice = Enum.find(slices, &(&1.name == slice_name))
    slice_labels = get_slice_labels(layout)
    label = Enum.find(slice_labels, &(&1.name == slice_name))
    canvas_height = get_canvas_height(layout)

    tests = (slice && slice.tests) || []

    if tests == [] || label == nil do
      {[], nil, 0}
    else
      # Position indicator below the slice's lowest element
      indicator_y = label.y + label.height + @spec_top_margin

      indicator = %{
        slice_name: slice_name,
        x: label.x,
        y: indicator_y,
        width: label.width,
        count: length(tests)
      }

      # Position spec cards below the indicator
      cards_start_y = indicator_y + @spec_indicator_height + @spec_card_gap

      {spec_cards, _y} =
        Enum.reduce(tests, {[], cards_start_y}, fn test, {acc, y} ->
          card = %PositionedSpec{
            name: test.name,
            slice_name: slice_name,
            x: label.x,
            y: y,
            width: label.width,
            height: @spec_card_height,
            given: test.given || [],
            when_clause: test.when_clause || [],
            then_clause: test.then_clause || []
          }

          {acc ++ [card], y + @spec_card_height + @spec_card_gap}
        end)

      # Extra height = from layout bottom to spec cards bottom
      last_card_bottom =
        case List.last(spec_cards) do
          nil -> 0
          card -> card.y + card.height + @padding
        end

      extra_height = max(0, last_card_bottom - canvas_height)

      {spec_cards, indicator, extra_height}
    end
  end

  defp get_slice_labels(%LayoutResult{slice_labels: labels}), do: labels
  defp get_slice_labels(%{slice_labels: labels}), do: labels
  defp get_slice_labels(_), do: []

  defp get_canvas_height(%LayoutResult{height: h}), do: h
  defp get_canvas_height(%{canvas_height: h}), do: h
  defp get_canvas_height(%{height: h}), do: h
  defp get_canvas_height(_), do: 0
end
