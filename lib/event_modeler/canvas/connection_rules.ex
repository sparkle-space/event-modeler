defmodule EventModeler.Canvas.ConnectionRules do
  @moduledoc """
  Pure module implementing connection validation rules between element types.

  Follows Event Modeling conventions:
  - Trigger/Wireframe -> Command (user action from screen)
  - Trigger/Wireframe -> View (screen displays view data)
  - Command -> Event (command produces event)
  - Command -> Exception (command produces error event)
  - Event -> View (event updates read model)
  - Event -> Automation (event triggers automated process)
  - Exception -> View (exception updates error display)
  - Automation -> Command (automation issues new command)
  """

  @valid_connections [
    {:command, :event},
    {:command, :exception},
    {:event, :view},
    {:event, :automation},
    {:exception, :view},
    {:automation, :command},
    {:wireframe, :command},
    {:wireframe, :view}
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

  Provides descriptive messages explaining why the connection is
  invalid based on Event Modeling methodology.
  """
  @spec rejection_reason(atom(), atom()) :: String.t() | nil
  def rejection_reason(from_type, to_type) do
    if valid?(from_type, to_type) do
      nil
    else
      describe_rejection(from_type, to_type)
    end
  end

  @doc """
  Returns the list of valid target types for a given source type.
  Useful for UI hints (highlighting valid drop targets).
  """
  @spec valid_targets(atom()) :: [atom()]
  def valid_targets(from_type) do
    @valid_connections
    |> Enum.filter(fn {from, _to} -> from == from_type end)
    |> Enum.map(fn {_from, to} -> to end)
  end

  @doc """
  Returns the list of valid source types for a given target type.
  """
  @spec valid_sources(atom()) :: [atom()]
  def valid_sources(to_type) do
    @valid_connections
    |> Enum.filter(fn {_from, to} -> to == to_type end)
    |> Enum.map(fn {from, _to} -> from end)
  end

  @doc """
  Returns all valid connections as a list of {from, to} tuples.
  """
  @spec all_valid() :: [{atom(), atom()}]
  def all_valid, do: @valid_connections

  # Descriptive rejection reasons based on Event Modeling methodology

  defp describe_rejection(:view, _to_type) do
    "Views are read-only and cannot have outgoing connections"
  end

  defp describe_rejection(_from_type, :wireframe) do
    "Wireframes are entry points and cannot be connection targets"
  end

  defp describe_rejection(:event, :command) do
    "Events cannot connect directly to Commands — use an Automation to trigger a Command from an Event"
  end

  defp describe_rejection(:command, :view) do
    "Commands cannot connect directly to Views — a Command must first produce an Event, which then updates a View"
  end

  defp describe_rejection(:wireframe, :event) do
    "Wireframes cannot connect directly to Events — a Wireframe invokes a Command, which then produces an Event"
  end

  defp describe_rejection(:wireframe, :automation) do
    "Wireframes represent user interactions and cannot connect to Automations"
  end

  defp describe_rejection(:wireframe, :exception) do
    "Wireframes cannot connect directly to Exceptions — a Wireframe invokes a Command, which may produce an Exception"
  end

  defp describe_rejection(from_type, to_type) do
    "#{format_type(from_type)} cannot connect to #{format_type(to_type)}"
  end

  defp format_type(:command), do: "Command"
  defp format_type(:event), do: "Event"
  defp format_type(:view), do: "View"
  defp format_type(:wireframe), do: "Wireframe"
  defp format_type(:automation), do: "Automation"
  defp format_type(:exception), do: "Exception"
  defp format_type(other), do: to_string(other)
end
