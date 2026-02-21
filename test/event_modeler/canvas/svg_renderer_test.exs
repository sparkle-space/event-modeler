defmodule EventModeler.Canvas.SvgRendererTest do
  use ExUnit.Case, async: true

  alias EventModeler.Canvas.SvgRenderer
  alias EventModeler.Canvas.Layout.{LayoutResult, PositionedElement, Connection}

  test "renders SVG data from layout result" do
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
      swimlanes: [%{name: "Default", y: 40, height: 100}],
      slice_labels: [%{name: "CreateBoard", x: 160, width: 420}]
    }

    svg_data = SvgRenderer.render(layout)

    assert svg_data.viewbox == "0 0 800 400"
    assert length(svg_data.elements) == 2
    assert length(svg_data.connections) == 1

    # Command should be blue
    cmd = Enum.find(svg_data.elements, &(&1.type == :command))
    assert cmd.fill == "#3B82F6"
    assert cmd.rx == 8

    # Event should be orange
    evt = Enum.find(svg_data.elements, &(&1.type == :event))
    assert evt.fill == "#F97316"
    assert evt.rx == 2

    # Connection should have a path
    [conn] = svg_data.connections
    assert conn.path =~ "M 340 70"
  end

  test "renders different colors for each element type" do
    types = [:command, :event, :view, :trigger, :exception]

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
      width: 1000,
      height: 400,
      elements: elements,
      connections: [],
      swimlanes: [],
      slice_labels: []
    }

    svg_data = SvgRenderer.render(layout)
    fills = Enum.map(svg_data.elements, & &1.fill) |> Enum.uniq()
    assert length(fills) == 5
  end
end
