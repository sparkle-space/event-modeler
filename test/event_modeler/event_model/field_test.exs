defmodule EventModeler.EventModel.FieldTest do
  use ExUnit.Case, async: true

  alias EventModeler.EventModel.Field

  describe "from_yaml/1" do
    test "parses simple string type" do
      field = Field.from_yaml({"orderId", "uuid"})
      assert field.name == "orderId"
      assert field.type == :uuid
      assert field.generated == false
      assert field.cardinality == :one
    end

    test "parses all known types" do
      for type <- ~w(string uuid integer decimal boolean datetime date list map any) do
        field = Field.from_yaml({"f", type})
        assert field.type == String.to_atom(type)
      end
    end

    test "unknown type defaults to :any" do
      field = Field.from_yaml({"f", "unknown_type"})
      assert field.type == :any
    end

    test "parses map with type details" do
      field = Field.from_yaml({"orderId", %{"type" => "uuid", "generated" => true}})
      assert field.name == "orderId"
      assert field.type == :uuid
      assert field.generated == true
    end

    test "parses map with of (subtype)" do
      field = Field.from_yaml({"items", %{"type" => "list", "of" => "OrderItem"}})
      assert field.type == :list
      assert field.of == "OrderItem"
    end

    test "parses map with enum values" do
      field = Field.from_yaml({"status", %{"type" => "string", "enum" => ["active", "closed"]}})
      assert field.type == :string
      assert field.enum == ["active", "closed"]
    end

    test "parses map with cardinality" do
      field = Field.from_yaml({"items", %{"type" => "string", "cardinality" => "many"}})
      assert field.cardinality == :many
    end

    test "defaults cardinality to :one" do
      field = Field.from_yaml({"name", %{"type" => "string"}})
      assert field.cardinality == :one
    end

    test "handles non-string non-map value" do
      field = Field.from_yaml({"f", 42})
      assert field.type == :any
    end
  end

  describe "to_yaml/1" do
    test "simple field returns string type" do
      field = %Field{name: "orderId", type: :uuid}
      assert Field.to_yaml(field) == {"orderId", "uuid"}
    end

    test "field with generated flag returns map" do
      field = %Field{name: "orderId", type: :uuid, generated: true}
      {name, map} = Field.to_yaml(field)
      assert name == "orderId"
      assert map["type"] == "uuid"
      assert map["generated"] == true
    end

    test "field with of returns map" do
      field = %Field{name: "items", type: :list, of: "OrderItem"}
      {name, map} = Field.to_yaml(field)
      assert name == "items"
      assert map["of"] == "OrderItem"
    end

    test "field with many cardinality returns map" do
      field = %Field{name: "tags", type: :string, cardinality: :many}
      {_name, map} = Field.to_yaml(field)
      assert map["cardinality"] == "many"
    end

    test "round-trip: from_yaml -> to_yaml -> from_yaml" do
      original =
        Field.from_yaml({"items", %{"type" => "list", "of" => "OrderItem", "generated" => true}})

      {name, yaml_value} = Field.to_yaml(original)
      round_tripped = Field.from_yaml({name, yaml_value})

      assert round_tripped.name == original.name
      assert round_tripped.type == original.type
      assert round_tripped.of == original.of
      assert round_tripped.generated == original.generated
    end
  end
end
