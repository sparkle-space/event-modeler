defmodule EventModeler.EventModel.FrontmatterParser do
  @moduledoc """
  Extracts and parses YAML frontmatter from Event Model markdown.
  """

  @doc """
  Parses YAML frontmatter from a markdown string.

  Returns `{:ok, frontmatter_map, rest_of_markdown}` or `{:ok, %{}, markdown}` if no frontmatter.
  """
  @spec parse(String.t()) :: {:ok, map(), String.t()} | {:error, String.t()}
  def parse(markdown) do
    case extract_frontmatter(markdown) do
      {:ok, yaml_str, rest} ->
        case YamlElixir.read_from_string(yaml_str) do
          {:ok, parsed} when is_map(parsed) ->
            {:ok, normalize(parsed), rest}

          {:ok, _} ->
            {:error, "Frontmatter is not a YAML mapping"}

          {:error, reason} ->
            {:error, "Failed to parse frontmatter YAML: #{inspect(reason)}"}
        end

      :none ->
        {:ok, %{}, markdown}
    end
  end

  defp extract_frontmatter(markdown) do
    trimmed = String.trim_leading(markdown)

    if String.starts_with?(trimmed, "---") do
      # Split after the opening ---
      [_ | rest] = String.split(trimmed, "\n", parts: 2)

      case rest do
        [after_opening] ->
          case String.split(after_opening, ~r/\n---\s*\n|\n---\s*$/, parts: 2) do
            [yaml_str, body] ->
              {:ok, yaml_str, String.trim_leading(body, "\n")}

            [_no_closing] ->
              :none
          end

        [] ->
          :none
      end
    else
      :none
    end
  end

  defp normalize(map) do
    map
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
  end
end
