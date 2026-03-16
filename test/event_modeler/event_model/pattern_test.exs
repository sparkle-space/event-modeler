defmodule EventModeler.EventModel.PatternTest do
  use ExUnit.Case, async: true

  alias EventModeler.EventModel.{Pattern, Slice, Element}

  describe "detect/1" do
    test "returns explicit pattern when set" do
      slice = %Slice{
        name: "Test",
        pattern: :translation,
        steps: [%Element{type: :command, label: "Cmd"}]
      }

      assert Pattern.detect(slice) == :translation
    end

    test "detects command pattern: wireframe -> command -> event" do
      slice = %Slice{
        name: "PlaceOrder",
        steps: [
          %Element{type: :wireframe, label: "Form"},
          %Element{type: :command, label: "PlaceOrder"},
          %Element{type: :event, label: "OrderPlaced"}
        ]
      }

      assert Pattern.detect(slice) == :command
    end

    test "detects command pattern: command -> event (no wireframe)" do
      slice = %Slice{
        name: "PlaceOrder",
        steps: [
          %Element{type: :command, label: "PlaceOrder"},
          %Element{type: :event, label: "OrderPlaced"}
        ]
      }

      assert Pattern.detect(slice) == :command
    end

    test "detects view pattern: event(s) -> view" do
      slice = %Slice{
        name: "OrderDashboard",
        steps: [
          %Element{type: :event, label: "OrderPlaced"},
          %Element{type: :event, label: "OrderShipped"},
          %Element{type: :view, label: "OrderDashboard"}
        ]
      }

      assert Pattern.detect(slice) == :view
    end

    test "detects automation pattern: processor -> command" do
      slice = %Slice{
        name: "AutoReorder",
        steps: [
          %Element{type: :processor, label: "LowStockMonitor"},
          %Element{type: :command, label: "ReorderFromSupplier"},
          %Element{type: :event, label: "ReorderPlaced"}
        ]
      }

      assert Pattern.detect(slice) == :automation
    end

    test "detects automation pattern: automation -> command" do
      slice = %Slice{
        name: "AutoProcess",
        steps: [
          %Element{type: :automation, label: "AutoProcessor"},
          %Element{type: :command, label: "ProcessItem"}
        ]
      }

      assert Pattern.detect(slice) == :automation
    end

    test "detects translation pattern: translator -> command" do
      slice = %Slice{
        name: "ReserveStock",
        steps: [
          %Element{type: :translator, label: "OrderToInventory"},
          %Element{type: :command, label: "ReserveStock"},
          %Element{type: :event, label: "StockReserved"}
        ]
      }

      assert Pattern.detect(slice) == :translation
    end

    test "returns nil for ambiguous patterns" do
      slice = %Slice{
        name: "Mixed",
        steps: [
          %Element{type: :view, label: "Dashboard"}
        ]
      }

      assert Pattern.detect(slice) == nil
    end

    test "returns nil for empty slice" do
      assert Pattern.detect(%Slice{name: "Empty", steps: []}) == nil
    end
  end

  describe "label/1" do
    test "returns human labels" do
      assert Pattern.label(:command) == "Command"
      assert Pattern.label(:view) == "View"
      assert Pattern.label(:automation) == "Automation"
      assert Pattern.label(:translation) == "Translation"
      assert Pattern.label(nil) == "Unknown"
    end
  end

  describe "validate/1" do
    test "translation without translator returns error" do
      slice = %Slice{
        name: "Bad",
        pattern: :translation,
        steps: [
          %Element{type: :command, label: "Cmd"},
          %Element{type: :event, label: "Evt"}
        ]
      }

      assert {:error, _reason} = Pattern.validate(slice)
    end

    test "valid translation returns ok" do
      slice = %Slice{
        name: "Good",
        pattern: :translation,
        steps: [
          %Element{type: :translator, label: "Trans"},
          %Element{type: :command, label: "Cmd"}
        ]
      }

      assert {:ok, :translation} = Pattern.validate(slice)
    end

    test "command pattern validates ok" do
      slice = %Slice{
        name: "Cmd",
        steps: [
          %Element{type: :command, label: "Cmd"},
          %Element{type: :event, label: "Evt"}
        ]
      }

      assert {:ok, :command} = Pattern.validate(slice)
    end
  end

  describe "pattern detection in layout" do
    test "slice labels include detected pattern" do
      event_model = %EventModeler.EventModel{
        slices: [
          %Slice{
            name: "PlaceOrder",
            steps: [
              %Element{id: "1", type: :wireframe, label: "Form"},
              %Element{id: "2", type: :command, label: "PlaceOrder"},
              %Element{id: "3", type: :event, label: "OrderPlaced"}
            ]
          }
        ]
      }

      result = EventModeler.Canvas.Layout.compute(event_model)
      [label] = result.slice_labels

      assert label.pattern == :command
      assert label.pattern_label == "Command"
    end

    test "slice labels include domain" do
      event_model = %EventModeler.EventModel{
        domains: [%EventModeler.EventModel.Domain{name: "Billing"}],
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

      result = EventModeler.Canvas.Layout.compute(event_model)
      [label] = result.slice_labels
      assert label.domain == "Billing"
    end
  end
end
