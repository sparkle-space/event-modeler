defmodule EventModeler.EventModel.DomainTest do
  use ExUnit.Case, async: true

  alias EventModeler.EventModel.Domain

  describe "from_yaml/1" do
    test "parses simple string name" do
      domain = Domain.from_yaml("Billing")
      assert domain.name == "Billing"
      assert domain.description == nil
      assert domain.color == nil
    end

    test "parses map with all fields" do
      domain =
        Domain.from_yaml(%{
          "name" => "Billing",
          "description" => "Payment processing",
          "color" => "#3B82F6"
        })

      assert domain.name == "Billing"
      assert domain.description == "Payment processing"
      assert domain.color == "#3B82F6"
    end

    test "parses map with name only" do
      domain = Domain.from_yaml(%{"name" => "Inventory"})
      assert domain.name == "Inventory"
      assert domain.description == nil
    end

    test "defaults name for invalid input" do
      domain = Domain.from_yaml(42)
      assert domain.name == "Default"
    end
  end

  describe "to_yaml/1" do
    test "simple domain returns string" do
      domain = %Domain{name: "Billing"}
      assert Domain.to_yaml(domain) == "Billing"
    end

    test "domain with description returns map" do
      domain = %Domain{name: "Billing", description: "Payment processing"}
      result = Domain.to_yaml(domain)
      assert result["name"] == "Billing"
      assert result["description"] == "Payment processing"
    end

    test "domain with color returns map" do
      domain = %Domain{name: "Billing", color: "#3B82F6"}
      result = Domain.to_yaml(domain)
      assert result["name"] == "Billing"
      assert result["color"] == "#3B82F6"
    end

    test "round-trip: from_yaml -> to_yaml -> from_yaml" do
      original =
        Domain.from_yaml(%{
          "name" => "Shipping",
          "description" => "Order delivery",
          "color" => "#F97316"
        })

      yaml = Domain.to_yaml(original)
      round_tripped = Domain.from_yaml(yaml)

      assert round_tripped.name == original.name
      assert round_tripped.description == original.description
      assert round_tripped.color == original.color
    end
  end
end
