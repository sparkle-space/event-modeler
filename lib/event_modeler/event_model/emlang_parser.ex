defmodule EventModeler.EventModel.EmlangParser do
  @moduledoc """
  Finds and parses fenced `emlang` code blocks from Event Model markdown.
  """

  alias EventModeler.EventModel.{Element, Slice}

  @doc """
  Extracts all emlang blocks from markdown and parses them into slices.

  Each emlang block should contain YAML with a `slices:` top-level key.
  Returns a list of `%Slice{}` structs.
  """
  @spec parse(String.t()) :: {:ok, [Slice.t()]} | {:error, String.t()}
  def parse(markdown) do
    blocks = extract_emlang_blocks(markdown)
    parse_blocks(blocks, [])
  end

  @doc """
  Extracts raw emlang block strings from markdown.
  """
  @spec extract_emlang_blocks(String.t()) :: [String.t()]
  def extract_emlang_blocks(markdown) do
    Regex.scan(~r/```yaml emlang\n(.*?)```/s, markdown, capture: :all_but_first)
    |> Enum.map(fn [block] -> String.trim(block) end)
  end

  defp parse_blocks([], acc), do: {:ok, Enum.reverse(acc)}

  defp parse_blocks([block | rest], acc) do
    case parse_block(block) do
      {:ok, slices} -> parse_blocks(rest, Enum.reverse(slices) ++ acc)
      {:error, _} = err -> err
    end
  end

  defp parse_block(yaml_str) do
    case YamlElixir.read_from_string(yaml_str) do
      {:ok, %{"slices" => slices}} when is_map(slices) ->
        parsed =
          Enum.map(slices, fn {name, definition} ->
            parse_slice(name, definition, yaml_str)
          end)

        {:ok, parsed}

      {:ok, _} ->
        {:error, "Emlang block missing 'slices:' top-level key"}

      {:error, reason} ->
        {:error, "Failed to parse emlang YAML: #{inspect(reason)}"}
    end
  end

  defp parse_slice(name, definition, raw_yaml) do
    steps = parse_steps(Map.get(definition, "steps", []))
    tests = parse_tests(Map.get(definition, "tests", %{}))

    %Slice{
      name: name,
      steps: steps,
      tests: tests,
      raw_emlang: raw_yaml
    }
  end

  defp parse_steps(steps) when is_list(steps) do
    Enum.map(steps, &parse_step/1)
  end

  defp parse_steps(_), do: []

  defp parse_step(step) when is_map(step) do
    {type_prefix, label_with_swimlane} = extract_type_and_label(step)
    {swimlane, label} = extract_swimlane(label_with_swimlane)
    props = Map.get(step, "props", %{}) || %{}

    %Element{
      id: generate_id(),
      type: Element.type_from_prefix(type_prefix),
      label: label,
      swimlane: swimlane,
      props: props
    }
  end

  defp parse_step(other) when is_binary(other) do
    # Simple string step like "- c: RegisterUser" parsed by YAML as string
    %Element{
      id: generate_id(),
      type: :command,
      label: other,
      swimlane: nil,
      props: %{}
    }
  end

  defp extract_type_and_label(step) do
    Enum.find_value(step, {"c", "Unknown"}, fn
      {"t", label} -> {"t", to_string(label)}
      {"c", label} -> {"c", to_string(label)}
      {"e", label} -> {"e", to_string(label)}
      {"v", label} -> {"v", to_string(label)}
      {"x", label} -> {"x", to_string(label)}
      {"a", label} -> {"a", to_string(label)}
      _ -> nil
    end)
  end

  defp extract_swimlane(label) do
    case String.split(label, "/", parts: 2) do
      [swimlane, actual_label] -> {swimlane, actual_label}
      [label] -> {nil, label}
    end
  end

  defp parse_tests(nil), do: []
  defp parse_tests(tests) when not is_map(tests), do: []

  defp parse_tests(tests) do
    Enum.map(tests, fn {name, definition} ->
      %{
        name: name,
        given: parse_test_clause(Map.get(definition, "given", [])),
        when_clause: parse_test_clause(Map.get(definition, "when", [])),
        then_clause: parse_test_clause(Map.get(definition, "then", []))
      }
    end)
  end

  defp parse_test_clause(nil), do: []

  defp parse_test_clause(clauses) when is_list(clauses) do
    Enum.map(clauses, fn clause when is_map(clause) ->
      {type_prefix, label} = extract_type_and_label(clause)
      props = Map.get(clause, "props", %{}) || %{}

      %{
        type: type_prefix,
        label: label,
        props: props
      }
    end)
  end

  defp parse_test_clause(_), do: []

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end
end
