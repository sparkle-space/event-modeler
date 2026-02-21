defmodule EventModeler.Canvas.ConnectionRules do
  @moduledoc """
  Pure module implementing connection validation rules between element types.

  Follows Event Modeling conventions from the technical design.
  """

  @valid_connections [
    {:command, :event},
    {:event, :view},
    {:event, :automation},
    {:automation, :command},
    {:trigger, :command},
    {:trigger, :view}
  ]

  @doc """
  Checks if a connection between two element types is valid.
  """
  @spec valid?(atom(), atom()) :: boolean()
  def valid?(from_type, to_type) do
    {from_type, to_type} in @valid_connections
  end

  @doc """
  Returns the reason a connection is invalid, or nil if valid.
  """
  @spec rejection_reason(atom(), atom()) :: String.t() | nil
  def rejection_reason(from_type, to_type) do
    if valid?(from_type, to_type) do
      nil
    else
      "#{format_type(from_type)} cannot connect to #{format_type(to_type)}"
    end
  end

  @doc """
  Returns all valid connections as a list of {from, to} tuples.
  """
  @spec all_valid() :: [{atom(), atom()}]
  def all_valid, do: @valid_connections

  defp format_type(:command), do: "Command"
  defp format_type(:event), do: "Event"
  defp format_type(:view), do: "View"
  defp format_type(:trigger), do: "Trigger/Wireframe"
  defp format_type(:automation), do: "Automation"
  defp format_type(:exception), do: "Exception"
  defp format_type(other), do: to_string(other)
end
