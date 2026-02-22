defmodule EventModeler.EventModel.SectionParser do
  @moduledoc """
  Extracts named sections from Event Model markdown body (after frontmatter removal).
  """

  @known_sections [
    "Overview",
    "Key Ideas",
    "Slices",
    "Scenarios",
    "Data Flows",
    "Dependencies",
    "Sources",
    "Event Stream"
  ]

  @doc """
  Parses the markdown body into a map of section name => content.

  Sections are identified by `## Section Name` headings.
  The Event Stream section is excluded (handled separately).
  """
  @spec parse(String.t()) :: map()
  def parse(markdown) do
    # Split on event stream sentinel first
    {content_part, _event_stream_part} = split_event_stream(markdown)

    content_part
    |> split_sections()
    |> Map.new()
  end

  @doc """
  Splits markdown into content before and after the event stream sentinel.
  """
  @spec split_event_stream(String.t()) :: {String.t(), String.t()}
  def split_event_stream(markdown) do
    case String.split(markdown, "<!-- event-stream -->", parts: 2) do
      [before, event_stream_part] -> {before, event_stream_part}
      [all] -> {all, ""}
    end
  end

  defp split_sections(markdown) do
    # Split by ## headings
    parts = Regex.split(~r/^## /m, markdown)

    parts
    |> Enum.drop(1)
    |> Enum.map(fn part ->
      case String.split(part, "\n", parts: 2) do
        [heading, body] ->
          section_name = String.trim(heading)

          if section_name in @known_sections do
            {section_name, String.trim(body)}
          else
            nil
          end

        [heading] ->
          section_name = String.trim(heading)

          if section_name in @known_sections do
            {section_name, ""}
          else
            nil
          end
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Extracts key ideas from the Key Ideas section content.
  Returns a list of strings (each bullet point).
  """
  @spec extract_key_ideas(String.t() | nil) :: [String.t()]
  def extract_key_ideas(nil), do: []

  def extract_key_ideas(content) do
    content
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(String.trim(&1), "- "))
    |> Enum.map(fn line ->
      line |> String.trim() |> String.trim_leading("- ")
    end)
  end
end
