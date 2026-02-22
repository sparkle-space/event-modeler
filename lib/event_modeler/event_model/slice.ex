defmodule EventModeler.EventModel.Slice do
  @moduledoc """
  Represents a named slice within an Event Model, containing steps and tests.
  """

  defstruct [
    :name,
    :wireframe_description,
    steps: [],
    tests: [],
    raw_emlang: nil
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          wireframe_description: String.t() | nil,
          steps: [EventModeler.EventModel.Element.t()],
          tests: [map()],
          raw_emlang: String.t() | nil
        }
end
