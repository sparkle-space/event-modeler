defmodule EventModeler.Prd.Slice do
  @moduledoc """
  Represents a named slice within a PRD, containing steps and tests.
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
          steps: [EventModeler.Prd.Element.t()],
          tests: [map()],
          raw_emlang: String.t() | nil
        }
end
