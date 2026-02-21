defmodule EventModeler.Prd.EventStreamParser do
  @moduledoc """
  Finds the `<!-- event-stream -->` sentinel and extracts `eventstream` blocks.
  """

  alias EventModeler.Prd.EventEntry

  @doc """
  Parses event stream entries from markdown.

  Looks for the `<!-- event-stream -->` sentinel and extracts all
  fenced `eventstream` blocks after it.
  """
  @spec parse(String.t()) :: {:ok, [EventEntry.t()]} | {:error, String.t()}
  def parse(markdown) do
    case String.split(markdown, "<!-- event-stream -->", parts: 2) do
      [_, after_sentinel] ->
        parse_stream_blocks(after_sentinel)

      [_no_sentinel] ->
        {:ok, []}
    end
  end

  defp parse_stream_blocks(content) do
    blocks = extract_eventstream_blocks(content)

    results =
      Enum.reduce_while(blocks, {:ok, []}, fn block, {:ok, acc} ->
        case parse_block(block) do
          {:ok, entry} -> {:cont, {:ok, [entry | acc]}}
          {:error, _} = err -> {:halt, err}
        end
      end)

    case results do
      {:ok, entries} ->
        sorted = Enum.sort_by(entries, & &1.seq)
        {:ok, sorted}

      error ->
        error
    end
  end

  @doc """
  Extracts raw eventstream block strings from content.
  """
  @spec extract_eventstream_blocks(String.t()) :: [String.t()]
  def extract_eventstream_blocks(content) do
    Regex.scan(~r/```eventstream\n(.*?)```/s, content, capture: :all_but_first)
    |> Enum.map(fn [block] -> String.trim(block) end)
  end

  defp parse_block(yaml_str) do
    case YamlElixir.read_from_string(yaml_str) do
      {:ok, parsed} when is_map(parsed) ->
        entry = %EventEntry{
          seq: parsed["seq"],
          ts: to_string(parsed["ts"]),
          type: to_string(parsed["type"]),
          actor: to_string(parsed["actor"]),
          data: parsed["data"] || %{},
          session: get_optional_string(parsed, "session"),
          ref: get_optional_string(parsed, "ref"),
          note: get_optional_string(parsed, "note")
        }

        {:ok, entry}

      {:ok, _} ->
        {:error, "Event stream block is not a YAML mapping"}

      {:error, reason} ->
        {:error, "Failed to parse event stream YAML: #{inspect(reason)}"}
    end
  end

  defp get_optional_string(map, key) do
    case Map.get(map, key) do
      nil -> nil
      value -> to_string(value)
    end
  end
end
