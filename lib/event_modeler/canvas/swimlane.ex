defmodule EventModeler.Canvas.Swimlane do
  @moduledoc """
  Typed swimlane system for Event Modeling canvas layout.

  Three swimlane types enforce element placement rules matching
  Event Modeling conventions:

  - `:trigger` (top) — wireframes and automations
  - `:command_view` (middle) — commands and views
  - `:event` (bottom) — events and exceptions
  """

  defstruct [:name, :type, :domain]

  @type swimlane_type :: :trigger | :command_view | :event

  @type t :: %__MODULE__{
          name: String.t(),
          type: swimlane_type(),
          domain: String.t() | nil
        }

  @doc """
  Returns the swimlane type for a given element type.
  """
  @spec type_for_element(atom()) :: swimlane_type()
  def type_for_element(:wireframe), do: :trigger
  def type_for_element(:automation), do: :trigger
  def type_for_element(:processor), do: :trigger
  def type_for_element(:translator), do: :trigger
  def type_for_element(:command), do: :command_view
  def type_for_element(:view), do: :command_view
  def type_for_element(:event), do: :event
  def type_for_element(:exception), do: :event

  @doc """
  Returns allowed element types for a swimlane type.
  """
  @spec allowed_element_types(swimlane_type()) :: [atom()]
  def allowed_element_types(:trigger), do: [:wireframe, :automation, :processor, :translator]
  def allowed_element_types(:command_view), do: [:command, :view]
  def allowed_element_types(:event), do: [:event, :exception]

  @doc """
  Checks if an element type is allowed in a swimlane type.
  """
  @spec allowed?(atom(), swimlane_type()) :: boolean()
  def allowed?(element_type, swimlane_type) do
    element_type in allowed_element_types(swimlane_type)
  end

  @doc """
  Default swimlane name for a type.
  """
  @spec default_name(swimlane_type()) :: String.t()
  def default_name(:trigger), do: "Triggers"
  def default_name(:command_view), do: "Processing"
  def default_name(:event), do: "Events"

  @doc """
  Sort order for swimlane types (triggers top, events bottom).
  """
  @spec sort_order(swimlane_type()) :: non_neg_integer()
  def sort_order(:trigger), do: 0
  def sort_order(:command_view), do: 1
  def sort_order(:event), do: 2
end
