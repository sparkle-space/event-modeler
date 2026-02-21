defmodule EventModeler.Prd.EventStreamWriter do
  @moduledoc """
  Appends events to a `%Prd{}` struct's event stream.

  Auto-increments sequence numbers and timestamps with UTC ISO 8601.
  """

  alias EventModeler.Prd
  alias EventModeler.Prd.EventEntry

  @doc """
  Appends a new event to the PRD's event stream.
  Auto-assigns seq (next after last) and ts (current UTC time).
  """
  @spec append(%Prd{}, String.t(), String.t(), map(), keyword()) :: %Prd{}
  def append(%Prd{} = prd, type, actor, data, opts \\ []) do
    next_seq = next_sequence(prd.event_stream)
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

    %{prd | event_stream: (prd.event_stream || []) ++ [entry]}
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
