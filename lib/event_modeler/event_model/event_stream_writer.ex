defmodule EventModeler.EventModel.EventStreamWriter do
  @moduledoc """
  Appends events to a `%EventModel{}` struct's event stream.

  Auto-increments sequence numbers and timestamps with UTC ISO 8601.
  """

  alias EventModeler.EventModel
  alias EventModeler.EventModel.EventEntry

  @doc """
  Appends a new event to the Event Model's event stream.
  Auto-assigns seq (next after last) and ts (current UTC time).
  """
  @spec append(%EventModel{}, String.t(), String.t(), map(), keyword()) :: %EventModel{}
  def append(%EventModel{} = event_model, type, actor, data, opts \\ []) do
    next_seq = next_sequence(event_model.event_stream)
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    entry = %EventEntry{
      seq: next_seq,
      ts: now,
      type: type,
      actor: actor,
      data: data,
      session: Keyword.get(opts, :session),
      ref: Keyword.get(opts, :ref),
      note: Keyword.get(opts, :note)
    }

    %{event_model | event_stream: (event_model.event_stream || []) ++ [entry]}
  end

  defp next_sequence(nil), do: 1
  defp next_sequence([]), do: 1

  defp next_sequence(entries) do
    entries
    |> Enum.map(& &1.seq)
    |> Enum.max()
    |> Kernel.+(1)
  end
end
