defmodule EventModeler.Canvas.CompletenessCheckerTest do
  use ExUnit.Case, async: true

  alias EventModeler.Canvas.CompletenessChecker
  alias EventModeler.EventModel
  alias EventModeler.EventModel.{Slice, Element, Field}

  describe "check_slice/1" do
    test "fully traced: all view fields match event fields" do
      slice = %Slice{
        name: "PlaceOrder",
        steps: [
          %Element{
            type: :command,
            label: "PlaceOrder",
            props: %{},
            fields: [
              %Field{name: "orderId", type: :uuid},
              %Field{name: "total", type: :decimal}
            ]
          },
          %Element{
            type: :event,
            label: "OrderPlaced",
            props: %{},
            fields: [
              %Field{name: "orderId", type: :uuid},
              %Field{name: "total", type: :decimal},
              %Field{name: "status", type: :string}
            ]
          },
          %Element{
            type: :view,
            label: "OrderConfirmation",
            props: %{},
            fields: [
              %Field{name: "orderId", type: :uuid},
              %Field{name: "status", type: :string}
            ]
          }
        ]
      }

      result = CompletenessChecker.check_slice(slice)

      assert result.complete == true
      assert result.total_fields == 2
      assert result.traced_fields == 2
      assert result.orphan_fields == 0
    end

    test "orphan fields: view field with no event/command source" do
      slice = %Slice{
        name: "Dashboard",
        steps: [
          %Element{
            type: :event,
            label: "OrderPlaced",
            props: %{},
            fields: [%Field{name: "orderId", type: :uuid}]
          },
          %Element{
            type: :view,
            label: "Dashboard",
            props: %{},
            fields: [
              %Field{name: "orderId", type: :uuid},
              %Field{name: "customerRating", type: :decimal}
            ]
          }
        ]
      }

      result = CompletenessChecker.check_slice(slice)

      assert result.complete == false
      assert result.orphan_fields == 1

      orphan = Enum.find(result.traces, &(&1.status == :orphan))
      assert orphan.field_name == "customerRating"
    end

    test "case-insensitive field matching" do
      slice = %Slice{
        name: "Test",
        steps: [
          %Element{
            type: :event,
            label: "Created",
            props: %{},
            fields: [%Field{name: "OrderId", type: :uuid}]
          },
          %Element{
            type: :view,
            label: "View",
            props: %{},
            fields: [%Field{name: "orderId", type: :uuid}]
          }
        ]
      }

      result = CompletenessChecker.check_slice(slice)
      assert result.complete == true
      assert result.traced_fields == 1
    end

    test "props-based fields are also traced" do
      slice = %Slice{
        name: "Legacy",
        steps: [
          %Element{type: :event, label: "Created", props: %{"email" => "string"}, fields: []},
          %Element{type: :view, label: "Profile", props: %{"email" => "string"}, fields: []}
        ]
      }

      result = CompletenessChecker.check_slice(slice)
      assert result.complete == true
      assert result.traced_fields == 1
    end

    test "slice with no views has zero fields" do
      slice = %Slice{
        name: "WriteOnly",
        steps: [
          %Element{type: :command, label: "Cmd", props: %{}, fields: []},
          %Element{type: :event, label: "Evt", props: %{}, fields: []}
        ]
      }

      result = CompletenessChecker.check_slice(slice)
      assert result.total_fields == 0
      # No fields to check means not "complete" in the meaningful sense
      assert result.complete == false
    end

    test "traces point to source element" do
      slice = %Slice{
        name: "Test",
        steps: [
          %Element{
            type: :event,
            label: "OrderPlaced",
            props: %{},
            fields: [%Field{name: "total", type: :decimal}]
          },
          %Element{
            type: :view,
            label: "Summary",
            props: %{},
            fields: [%Field{name: "total", type: :decimal}]
          }
        ]
      }

      result = CompletenessChecker.check_slice(slice)
      [trace] = result.traces

      assert trace.source == "OrderPlaced"
      assert trace.status == :traced
    end
  end

  describe "check/1" do
    test "checks all slices in event model" do
      em = %EventModel{
        slices: [
          %Slice{
            name: "A",
            steps: [
              %Element{type: :command, label: "Cmd", props: %{}, fields: []},
              %Element{type: :event, label: "Evt", props: %{"x" => "string"}, fields: []},
              %Element{type: :view, label: "View", props: %{"x" => "string"}, fields: []}
            ]
          },
          %Slice{
            name: "B",
            steps: [
              %Element{type: :view, label: "Orphan", props: %{"y" => "string"}, fields: []}
            ]
          }
        ]
      }

      results = CompletenessChecker.check(em)
      assert length(results) == 2

      a = Enum.find(results, &(&1.slice_name == "A"))
      b = Enum.find(results, &(&1.slice_name == "B"))

      assert a.complete == true
      assert b.complete == false
      assert b.orphan_fields == 1
    end

    test "checks multi-domain event model from file" do
      source = File.read!("priv/event_models/order-fulfillment.md")
      {:ok, em} = EventModeler.EventModel.Parser.parse(source)

      results = CompletenessChecker.check(em)
      assert length(results) == length(em.slices)

      # PlaceOrder slice has matching fields between event and view
      place_order = Enum.find(results, &(&1.slice_name == "PlaceOrder"))
      assert place_order.total_fields > 0
    end
  end
end
