defmodule EventModeler.EventModel.Field do
  @moduledoc """
  Represents a typed field within an element's schema.

  Fields define the data contract for commands, events, and views
  with explicit types, cardinality, and metadata.
  """

  defstruct [
    :name,
    :type,
    :of,
    :enum,
    generated: false,
    cardinality: :one
  ]

  @type field_type ::
          :string
          | :uuid
          | :integer
          | :decimal
          | :boolean
          | :datetime
          | :date
          | :list
          | :map
          | :any

  @type cardinality :: :one | :many

  @type t :: %__MODULE__{
          name: String.t(),
          type: field_type(),
          of: String.t() | nil,
          enum: [String.t()] | nil,
          generated: boolean(),
          cardinality: cardinality()
        }

  @known_types ~w(string uuid integer decimal boolean datetime date list map any)

  @doc """
  Parses a field definition from YAML map format.

  Accepts either a simple type string or a map with type details:
    - `{name, "string"}` -> simple typed field
    - `{name, %{"type" => "uuid", "generated" => true}}` -> detailed field
  """
  @spec from_yaml({String.t(), term()}) :: t()
  def from_yaml({name, type}) when is_binary(type) do
    %__MODULE__{
      name: name,
      type: parse_type(type)
    }
  end

  def from_yaml({name, %{} = definition}) do
    %__MODULE__{
      name: name,
      type: parse_type(Map.get(definition, "type", "any")),
      of: Map.get(definition, "of"),
      enum: Map.get(definition, "enum"),
      generated: Map.get(definition, "generated", false) == true,
      cardinality: parse_cardinality(Map.get(definition, "cardinality", "one"))
    }
  end

  def from_yaml({name, _}), do: %__MODULE__{name: name, type: :any}

  @doc """
  Converts a field to a YAML-serializable map.
  Returns a simple type string for basic fields, or a map for complex ones.
  """
  @spec to_yaml(t()) :: {String.t(), String.t() | map()}
  def to_yaml(%__MODULE__{} = field) do
    if simple?(field) do
      {field.name, Atom.to_string(field.type)}
    else
      definition = %{"type" => Atom.to_string(field.type)}

      definition = if field.of, do: Map.put(definition, "of", field.of), else: definition
      definition = if field.enum, do: Map.put(definition, "enum", field.enum), else: definition

      definition =
        if field.generated, do: Map.put(definition, "generated", true), else: definition

      definition =
        if field.cardinality != :one,
          do: Map.put(definition, "cardinality", Atom.to_string(field.cardinality)),
          else: definition

      {field.name, definition}
    end
  end

  defp simple?(%__MODULE__{of: nil, enum: nil, generated: false, cardinality: :one}), do: true
  defp simple?(_), do: false

  defp parse_type(type_str) when is_binary(type_str) do
    normalized = String.downcase(type_str)

    if normalized in @known_types do
      String.to_atom(normalized)
    else
      :any
    end
  end

  defp parse_type(_), do: :any

  defp parse_cardinality("many"), do: :many
  defp parse_cardinality(_), do: :one
end
