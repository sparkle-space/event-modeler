defmodule EventModeler.Prd.EventEntry do
  @moduledoc """
  Represents a single entry in the PRD's append-only event stream.
  """

  defstruct [
    :seq,
    :ts,
    :type,
    :actor,
    :data,
    :session,
    :ref,
    :note
  ]

  @type t :: %__MODULE__{
          seq: integer(),
          ts: String.t(),
          type: String.t(),
          actor: String.t(),
          data: map(),
          session: String.t() | nil,
          ref: String.t() | nil,
          note: String.t() | nil
        }
end
