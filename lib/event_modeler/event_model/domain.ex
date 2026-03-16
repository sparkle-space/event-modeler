defmodule EventModeler.EventModel.Domain do
  @moduledoc """
  Represents a bounded context / domain within an Event Model.

  Multi-domain support allows a single event model to contain
  multiple bounded contexts as domain swimlanes.
  """

  defstruct [
    :name,
    :description,
    :color
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t() | nil,
          color: String.t() | nil
        }

  @doc """
  Parses a domain from YAML format.

  Accepts either a simple string name or a map with details:
    - `"Billing"` -> domain with name only
    - `%{"name" => "Billing", "description" => "...", "color" => "#3B82F6"}` -> full domain
  """
  @spec from_yaml(String.t() | map()) :: t()
  def from_yaml(name) when is_binary(name) do
    %__MODULE__{name: name}
  end

  def from_yaml(%{} = definition) do
    %__MODULE__{
      name: Map.get(definition, "name", "Default"),
      description: Map.get(definition, "description"),
      color: Map.get(definition, "color")
    }
  end

  def from_yaml(_), do: %__MODULE__{name: "Default"}

  @doc """
  Converts a domain to a YAML-serializable map.
  Returns a simple string for name-only domains, or a map for detailed ones.
  """
  @spec to_yaml(t()) :: String.t() | map()
  def to_yaml(%__MODULE__{description: nil, color: nil} = domain) do
    domain.name
  end

  def to_yaml(%__MODULE__{} = domain) do
    result = %{"name" => domain.name}

    result =
      if domain.description, do: Map.put(result, "description", domain.description), else: result

    result = if domain.color, do: Map.put(result, "color", domain.color), else: result
    result
  end
end
