defmodule EventModeler.Canvas.HtmlRendererTest do
  use ExUnit.Case, async: true

  alias EventModeler.Canvas.HtmlRenderer
  alias EventModeler.Canvas.Layout.{LayoutResult, PositionedElement, Connection}

  test "renders HTML canvas data from layout result" do
    layout = %LayoutResult{
      width: 800,
      height: 400,
      elements: [
        %PositionedElement{
          id: "1",
          type: :command,
          label: "CreateBoard",
          swimlane: "Default",
          props: %{},
          x: 160,
          y: 40,
          width: 180,
          height: 60,
          slice_name: "CreateBoard"
        },
        %PositionedElement{
          id: "2",
          type: :event,
          label: "BoardCreated",
          swimlane: "Default",
          props: %{},
          x: 400,
          y: 40,
          width: 180,
          height: 60,
          slice_name: "CreateBoard"
        }
      ],
      connections: [
        %Connection{
          from_id: "1",
          to_id: "2",
          from_x: 340,
          from_y: 70,
          to_x: 400,
          to_y: 70
        }
      ],
      swimlanes: [%{name: "Default", type: :command_view, y: 40, height: 100}],
      slice_labels: [%{name: "CreateBoard", x: 160, width: 420}]
    }

    canvas_data = HtmlRenderer.render(layout)

    assert canvas_data.canvas_width == 800
    assert canvas_data.canvas_height == 400
    assert length(canvas_data.elements) == 2
    assert length(canvas_data.connections) == 1

    # Command should have blue background class
    cmd = Enum.find(canvas_data.elements, &(&1.type == :command))
    assert cmd.bg_class == "bg-[#3B82F6]"
    assert cmd.text_class == "text-white"
    assert cmd.ring_class =~ "ring-"

    # Event should have orange background class
    evt = Enum.find(canvas_data.elements, &(&1.type == :event))
    assert evt.bg_class == "bg-[#F97316]"
    assert evt.text_class == "text-white"

    # Connection should have a bezier path
    [conn] = canvas_data.connections
    assert conn.path =~ "M 340 70"
  end

  test "renders different classes for each element type" do
    types = [:command, :event, :view, :wireframe, :exception, :automation]

    elements =
      types
      |> Enum.with_index()
      |> Enum.map(fn {type, idx} ->
        %PositionedElement{
          id: "#{idx}",
          type: type,
          label: "Test",
          swimlane: "Default",
          props: %{},
          x: idx * 200,
          y: 40,
          width: 180,
          height: 60,
          slice_name: "Test"
        }
      end)

    layout = %LayoutResult{
      width: 1200,
      height: 400,
      elements: elements,
      connections: [],
      swimlanes: [],
      slice_labels: []
    }

    canvas_data = HtmlRenderer.render(layout)
    bg_classes = Enum.map(canvas_data.elements, & &1.bg_class) |> Enum.uniq()
    assert length(bg_classes) == 6
  end

  test "swimlane data includes width from canvas" do
    layout = %LayoutResult{
      width: 1000,
      height: 400,
      elements: [],
      connections: [],
      swimlanes: [%{name: "UI", type: :trigger, y: 50, height: 100}],
      slice_labels: []
    }

    canvas_data = HtmlRenderer.render(layout)
    [swimlane] = canvas_data.swimlanes
    assert swimlane.width == 1000
    assert swimlane.name == "UI"
    assert swimlane.type == :trigger
  end

  test "unknown element type falls back to command classes" do
    layout = %LayoutResult{
      width: 800,
      height: 400,
      elements: [
        %PositionedElement{
          id: "1",
          type: :unknown,
          label: "Mystery",
          swimlane: "Default",
          props: %{},
          x: 100,
          y: 40,
          width: 180,
          height: 60,
          slice_name: "Test"
        }
      ],
      connections: [],
      swimlanes: [],
      slice_labels: []
    }

    canvas_data = HtmlRenderer.render(layout)
    [elem] = canvas_data.elements
    # Falls back to command (blue)
    assert elem.bg_class == "bg-[#3B82F6]"
  end
end
