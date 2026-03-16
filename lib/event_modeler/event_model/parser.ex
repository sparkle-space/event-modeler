defmodule EventModeler.EventModel.Parser do
  @moduledoc """
  Main entry point for parsing Event Model markdown into structured data.

  Combines frontmatter, section, emlang, and event stream parsing
  into a single `%EventModel{}` struct.
  """

  alias EventModeler.EventModel

  alias EventModeler.EventModel.{
    Domain,
    FrontmatterParser,
    SectionParser,
    EmlangParser,
    EventStreamParser
  }

  @doc """
  Parses an Event Model markdown string into a `%EventModel{}` struct.

  Returns `{:ok, %EventModel{}}` on success or `{:error, reason}` on failure.
  """
  @spec parse(String.t()) :: {:ok, EventModel.t()} | {:error, String.t()}
  def parse(markdown) when is_binary(markdown) do
    with {:ok, frontmatter, body} <- FrontmatterParser.parse(markdown),
         sections <- SectionParser.parse(body),
         {:ok, slices} <- EmlangParser.parse(body),
         {:ok, event_stream} <- EventStreamParser.parse(markdown) do
      slices_with_wireframes = attach_wireframe_descriptions(slices, sections["Slices"])

      domains = parse_domains(frontmatter["domains"])

      event_model = %EventModel{
        title: frontmatter["title"],
        status: frontmatter["status"],
        domain: frontmatter["domain"],
        format: frontmatter["format"],
        version: frontmatter["version"],
        created: to_string_or_nil(frontmatter["created"]),
        updated: to_string_or_nil(frontmatter["updated"]),
        dependencies: frontmatter["dependencies"] || [],
        tags: frontmatter["tags"] || [],
        domains: domains,
        overview: sections["Overview"],
        key_ideas: SectionParser.extract_key_ideas(sections["Key Ideas"]),
        slices: slices_with_wireframes,
        scenarios: parse_scenarios(sections["Scenarios"]),
        data_flows: sections["Data Flows"],
        model_dependencies: sections["Dependencies"],
        sources: sections["Sources"],
        event_stream: event_stream,
        raw_markdown: markdown,
        sections: sections
      }

      {:ok, event_model}
    end
  end

  def parse(nil), do: {:error, "Cannot parse nil input"}
  def parse(_), do: {:error, "Input must be a string"}

  defp to_string_or_nil(nil), do: nil
  defp to_string_or_nil(value), do: to_string(value)

  defp parse_domains(nil), do: []
  defp parse_domains(domains) when is_list(domains), do: Enum.map(domains, &Domain.from_yaml/1)
  defp parse_domains(_), do: []

  defp attach_wireframe_descriptions(slices, nil), do: slices

  defp attach_wireframe_descriptions(slices, slices_content) do
    Enum.map(slices, fn slice ->
      wireframe = extract_wireframe_for_slice(slice.name, slices_content)
      %{slice | wireframe_description: wireframe}
    end)
  end

  defp extract_wireframe_for_slice(slice_name, content) do
    # Look for **Wireframe:** text after the slice heading
    pattern = ~r/### Slice:\s*#{Regex.escape(slice_name)}\s*\n+\*\*Wireframe:\*\*\s*(.+)/

    case Regex.run(pattern, content) do
      [_, wireframe] -> String.trim(wireframe)
      nil -> nil
    end
  end

  defp parse_scenarios(nil), do: []

  defp parse_scenarios(content) do
    # Split by ### Scenario: headings
    parts = Regex.split(~r/^### Scenario:\s*/m, content)

    parts
    |> Enum.drop(1)
    |> Enum.map(fn part ->
      [name_line | body_lines] = String.split(part, "\n", parts: 2)

      body =
        case body_lines do
          [b] -> String.trim(b)
          [] -> ""
        end

      %{
        name: String.trim(name_line),
        body: body,
        given: extract_gwt_clause(body, "Given"),
        when_clause: extract_gwt_clause(body, "When"),
        then_clause: extract_gwt_clause(body, "Then")
      }
    end)
  end

  defp extract_gwt_clause(body, clause_name) do
    pattern = ~r/\*\*#{clause_name}\*\*\s+(.+)/

    case Regex.run(pattern, body) do
      [_, value] -> String.trim(value)
      nil -> nil
    end
  end
end
