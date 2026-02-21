defmodule EventModeler.Prd.Element do
  @moduledoc """
  Represents a single element (wireframe, command, event, view, exception) in a slice.
  """

  defstruct [
    :id,
    :type,
    :label,
    :swimlane,
    props: %{}
  ]

  @type element_type :: :wireframe | :command | :event | :view | :exception | :automation

  @type t :: %__MODULE__{
          id: String.t() | nil,
          type: element_type(),
          label: String.t(),
          swimlane: String.t() | nil,
          props: map()
        }

  @doc """
  Maps emlang type prefix to element type atom.
  """
  @spec type_from_prefix(String.t()) :: element_type()
  def type_from_prefix("t"), do: :wireframe
  def type_from_prefix("c"), do: :command
  def type_from_prefix("e"), do: :event
  def type_from_prefix("v"), do: :view
  def type_from_prefix("x"), do: :exception
  def type_from_prefix("a"), do: :automation

  @doc """
  Maps element type atom to emlang type prefix.
  """
  @spec prefix_from_type(element_type()) :: String.t()
  def prefix_from_type(:wireframe), do: "t"
  def prefix_from_type(:command), do: "c"
  def prefix_from_type(:event), do: "e"
  def prefix_from_type(:view), do: "v"
  def prefix_from_type(:exception), do: "x"
  def prefix_from_type(:automation), do: "a"
end
