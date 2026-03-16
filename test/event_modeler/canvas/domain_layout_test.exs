defmodule EventModeler.Canvas.DomainLayoutTest do
  use ExUnit.Case, async: true

  alias EventModeler.Canvas.Layout
  alias EventModeler.EventModel
  alias EventModeler.EventModel.{Domain, Slice, Element}

  describe "domain-based layout" do
    test "multi-domain model produces domain bands" do
      event_model = %EventModel{
        domains: [
          %Domain{name: "Billing", color: "#3B82F6"},
          %Domain{name: "Inventory", color: "#22C55E"}
        ],
        slices: [
          %Slice{
            name: "PlaceOrder",
            domain: "Billing",
            steps: [
              %Element{id: "1", type: :command, label: "PlaceOrder"},
              %Element{id: "2", type: :event, label: "OrderPlaced", swimlane: "Billing"}
            ]
          },
          %Slice{
            name: "ReserveStock",
            domain: "Inventory",
            steps: [
              %Element{id: "3", type: :command, label: "ReserveStock"},
              %Element{id: "4", type: :event, label: "StockReserved", swimlane: "Inventory"}
            ]
          }
        ]
      }

      result = Layout.compute(event_model)

      # Should have domain bands
      assert length(result.domain_bands) == 2

      [billing_band, inventory_band] = result.domain_bands
      assert billing_band.name == "Billing"
      assert billing_band.color == "#3B82F6"
      assert inventory_band.name == "Inventory"
      assert inventory_band.color == "#22C55E"

      # Billing band should be above Inventory band
      assert billing_band.y < inventory_band.y

      # Band height should be positive
      assert billing_band.height > 0
      assert inventory_band.height > 0
    end

    test "elements in different domains have different Y positions" do
      event_model = %EventModel{
        domains: [
          %Domain{name: "Billing"},
          %Domain{name: "Shipping"}
        ],
        slices: [
          %Slice{
            name: "PlaceOrder",
            domain: "Billing",
            steps: [
              %Element{id: "1", type: :command, label: "PlaceOrder"}
            ]
          },
          %Slice{
            name: "ShipOrder",
            domain: "Shipping",
            steps: [
              %Element{id: "2", type: :command, label: "ShipOrder"}
            ]
          }
        ]
      }

      result = Layout.compute(event_model)

      billing_cmd = Enum.find(result.elements, &(&1.id == "1"))
      shipping_cmd = Enum.find(result.elements, &(&1.id == "2"))

      # Same type (command) but different domains — different Y positions
      assert billing_cmd.y != shipping_cmd.y
    end

    test "single-domain model has no domain bands (backward compat)" do
      event_model = %EventModel{
        domains: [],
        slices: [
          %Slice{
            name: "Test",
            steps: [
              %Element{id: "1", type: :command, label: "DoThing"},
              %Element{id: "2", type: :event, label: "ThingDone"}
            ]
          }
        ]
      }

      result = Layout.compute(event_model)

      assert result.domain_bands == []
    end

    test "swimlanes within a domain are sorted by type (trigger, cmd/view, event)" do
      event_model = %EventModel{
        domains: [%Domain{name: "Billing"}],
        slices: [
          %Slice{
            name: "PlaceOrder",
            domain: "Billing",
            steps: [
              %Element{id: "1", type: :wireframe, label: "Form"},
              %Element{id: "2", type: :command, label: "PlaceOrder"},
              %Element{id: "3", type: :event, label: "OrderPlaced"}
            ]
          }
        ]
      }

      result = Layout.compute(event_model)

      form = Enum.find(result.elements, &(&1.id == "1"))
      cmd = Enum.find(result.elements, &(&1.id == "2"))
      evt = Enum.find(result.elements, &(&1.id == "3"))

      # Trigger (wireframe) above command/view, above event
      assert form.y < cmd.y
      assert cmd.y < evt.y
    end

    test "domain bands have description from domain definition" do
      event_model = %EventModel{
        domains: [
          %Domain{name: "Billing", description: "Payment processing", color: "#3B82F6"}
        ],
        slices: [
          %Slice{
            name: "PlaceOrder",
            domain: "Billing",
            steps: [
              %Element{id: "1", type: :command, label: "PlaceOrder"}
            ]
          }
        ]
      }

      result = Layout.compute(event_model)
      [band] = result.domain_bands
      assert band.description == "Payment processing"
    end

    test "HtmlRenderer includes domain_bands" do
      event_model = %EventModel{
        domains: [%Domain{name: "Billing", color: "#3B82F6"}],
        slices: [
          %Slice{
            name: "PlaceOrder",
            domain: "Billing",
            steps: [
              %Element{id: "1", type: :command, label: "PlaceOrder"}
            ]
          }
        ]
      }

      layout = Layout.compute(event_model)
      canvas_data = EventModeler.Canvas.HtmlRenderer.render(layout)

      assert length(canvas_data.domain_bands) == 1
      [band] = canvas_data.domain_bands
      assert band.name == "Billing"
      assert band.color == "#3B82F6"
      assert band.width > 0
    end

    test "SvgRenderer includes domain_bands" do
      event_model = %EventModel{
        domains: [%Domain{name: "Billing", color: "#3B82F6"}],
        slices: [
          %Slice{
            name: "PlaceOrder",
            domain: "Billing",
            steps: [
              %Element{id: "1", type: :command, label: "PlaceOrder"}
            ]
          }
        ]
      }

      layout = Layout.compute(event_model)
      svg_data = EventModeler.Canvas.SvgRenderer.render(layout)

      assert length(svg_data.domain_bands) == 1
      [band] = svg_data.domain_bands
      assert band.name == "Billing"
      assert band.color == "#3B82F6"
    end

    test "multi-domain layout from parsed event model file" do
      source = File.read!("priv/event_models/order-fulfillment.md")
      {:ok, event_model} = EventModeler.EventModel.Parser.parse(source)

      result = Layout.compute(event_model)

      assert length(result.domain_bands) == 3
      domain_names = Enum.map(result.domain_bands, & &1.name)
      assert "Billing" in domain_names
      assert "Inventory" in domain_names
      assert "Shipping" in domain_names

      # All elements positioned
      assert length(result.elements) > 0

      # Domain bands don't overlap
      sorted_bands = Enum.sort_by(result.domain_bands, & &1.y)

      sorted_bands
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.each(fn [a, b] ->
        assert a.y + a.height <= b.y,
               "Domain #{a.name} (y:#{a.y}, h:#{a.height}) overlaps #{b.name} (y:#{b.y})"
      end)
    end
  end
end
