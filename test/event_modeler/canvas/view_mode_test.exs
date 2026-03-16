defmodule EventModeler.Canvas.ViewModeTest do
  use ExUnit.Case, async: true

  alias EventModeler.Canvas.Layout
  alias EventModeler.EventModel
  alias EventModeler.EventModel.{Slice, Element, Field}

  describe "compact vs detailed view mode" do
    setup do
      event_model = %EventModel{
        slices: [
          %Slice{
            name: "PlaceOrder",
            steps: [
              %Element{
                id: "1",
                type: :command,
                label: "PlaceOrder",
                props: %{},
                fields: [
                  %Field{name: "orderId", type: :uuid},
                  %Field{name: "total", type: :decimal},
                  %Field{name: "items", type: :list, of: "OrderItem"}
                ]
              },
              %Element{
                id: "2",
                type: :event,
                label: "OrderPlaced",
                props: %{},
                fields: [
                  %Field{name: "orderId", type: :uuid},
                  %Field{name: "placedAt", type: :datetime}
                ]
              }
            ]
          }
        ]
      }

      %{event_model: event_model}
    end

    test "compact mode uses standard element height", %{event_model: em} do
      result = Layout.compute(em, view_mode: :compact)
      cmd = Enum.find(result.elements, &(&1.id == "1"))

      # Compact uses standard 60px height regardless of fields
      assert cmd.height == 60
    end

    test "detailed mode uses taller elements for elements with fields", %{event_model: em} do
      result = Layout.compute(em, view_mode: :detailed)
      cmd = Enum.find(result.elements, &(&1.id == "1"))

      # Detailed mode makes elements taller based on field count
      assert cmd.height > 60
    end

    test "detailed mode without fields uses base detailed height", %{event_model: _em} do
      em = %EventModel{
        slices: [
          %Slice{
            name: "Test",
            steps: [
              %Element{id: "1", type: :command, label: "Cmd", props: %{}, fields: []}
            ]
          }
        ]
      }

      result = Layout.compute(em, view_mode: :detailed)
      cmd = Enum.find(result.elements, &(&1.id == "1"))

      # Without fields, uses the detailed base height (120)
      assert cmd.height == 120
    end

    test "elements carry fields in layout result", %{event_model: em} do
      result = Layout.compute(em, view_mode: :compact)
      cmd = Enum.find(result.elements, &(&1.id == "1"))

      assert length(cmd.fields) == 3
      assert Enum.any?(cmd.fields, &(&1.name == "orderId"))
    end

    test "HtmlRenderer includes fields data", %{event_model: em} do
      layout = Layout.compute(em, view_mode: :detailed)
      canvas_data = EventModeler.Canvas.HtmlRenderer.render(layout)

      cmd = Enum.find(canvas_data.elements, &(&1.type == :command))
      assert length(cmd.fields) == 3

      order_field = Enum.find(cmd.fields, &(&1.name == "orderId"))
      assert order_field.type == "uuid"
    end

    test "default view_mode is compact" do
      em = %EventModel{
        slices: [
          %Slice{
            name: "Test",
            steps: [%Element{id: "1", type: :command, label: "Cmd", props: %{}}]
          }
        ]
      }

      result = Layout.compute(em)
      cmd = Enum.find(result.elements, &(&1.id == "1"))
      assert cmd.height == 60
    end

    test "detailed mode produces taller canvas" do
      em = %EventModel{
        slices: [
          %Slice{
            name: "Test",
            steps: [
              %Element{id: "1", type: :wireframe, label: "Form", props: %{}},
              %Element{id: "2", type: :command, label: "Cmd", props: %{}},
              %Element{id: "3", type: :event, label: "Evt", props: %{}}
            ]
          }
        ]
      }

      compact = Layout.compute(em, view_mode: :compact)
      detailed = Layout.compute(em, view_mode: :detailed)

      assert detailed.height > compact.height
    end
  end
end
