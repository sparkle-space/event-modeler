defmodule EventModeler.EventModel.Slice do
  @moduledoc """
  Represents a named slice within an Event Model, containing steps and tests.
  """

  defstruct [
    :name,
    :wireframe_description,
    steps: [],
    tests: [],
    connections: nil,
    raw_emlang: nil
  ]

  @type connections_t :: %{
          consumes: [String.t()],
          produces_for: [String.t()],
          gates: [String.t()]
        }

  @type t :: %__MODULE__{
          name: String.t(),
          wireframe_description: String.t() | nil,
          steps: [EventModeler.EventModel.Element.t()],
          tests: [map()],
          connections: connections_t() | nil,
          raw_emlang: String.t() | nil
        }
end
