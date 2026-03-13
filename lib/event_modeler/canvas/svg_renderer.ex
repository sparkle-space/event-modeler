defmodule EventModeler.Canvas.SvgRenderer do
  @moduledoc """
  Pure module that takes a layout result and produces SVG markup data
  for rendering in a LiveView template.

  Element type colors follow Event Modeling conventions:
  - Commands = blue rounded rectangles
  - Events = orange rectangles
  - Views = green rectangles
  - Wireframes = gray with monospace text
  - Exceptions = red rectangles
  """

  alias EventModeler.Canvas.Layout.{LayoutResult, PositionedElement, Connection, SliceConnection}

  @type_colors %{
    command: %{fill: "#3B82F6", stroke: "#2563EB", text: "#FFFFFF"},
    event: %{fill: "#F97316", stroke: "#EA580C", text: "#FFFFFF"},
    view: %{fill: "#22C55E", stroke: "#16A34A", text: "#FFFFFF"},
    wireframe: %{fill: "#E5E7EB", stroke: "#9CA3AF", text: "#374151"},
    exception: %{fill: "#EF4444", stroke: "#DC2626", text: "#FFFFFF"},
    automation: %{fill: "#8B5CF6", stroke: "#7C3AED", text: "#FFFFFF"}
  }

  @doc """
  Returns the SVG data needed for rendering.
  """
  @spec render(%LayoutResult{}) :: map()
  def render(%LayoutResult{} = layout) do
    %{
      viewbox: "0 0 #{layout.width} #{layout.height}",
      width: layout.width,
      height: layout.height,
      elements: Enum.map(layout.elements, &element_data/1),
      connections: Enum.map(layout.connections, &connection_data/1),
      swimlanes: Enum.map(layout.swimlanes, &swimlane_data(&1, layout.width)),
      slice_labels: layout.slice_labels,
      slice_connections: Enum.map(layout.slice_connections, &slice_connection_data/1)
    }
  end

  defp element_data(%PositionedElement{} = elem) do
    colors = Map.get(@type_colors, elem.type, @type_colors.command)

    %{
      id: elem.id,
      type: elem.type,
      label: elem.label,
      swimlane: elem.swimlane,
      x: elem.x,
      y: elem.y,
      width: elem.width,
      height: elem.height,
      fill: colors.fill,
      stroke: colors.stroke,
      text_color: colors.text,
      rx: 12,
      props: elem.props,
      slice_name: elem.slice_name
    }
  end

  defp connection_data(%Connection{} = conn) do
    end_x = conn.to_x - 10

    path =
      if conn.from_x <= end_x do
        # Normal left-to-right: smooth S-curve
        mid_x = div(conn.from_x + end_x, 2)

        "M #{conn.from_x} #{conn.from_y} C #{mid_x} #{conn.from_y} #{mid_x} #{conn.to_y} #{end_x} #{conn.to_y}"
      else
        # Reversed: loop above and approach target from left
        loop_y = max(10, min(conn.from_y, conn.to_y) - 80)
        approach_x = end_x - 30

        "M #{conn.from_x} #{conn.from_y} " <>
          "C #{conn.from_x} #{loop_y} #{approach_x} #{loop_y} #{approach_x} #{conn.to_y} " <>
          "L #{end_x} #{conn.to_y}"
      end

    %{
      from_id: conn.from_id,
      to_id: conn.to_id,
      path: path
    }
  end

  defp slice_connection_data(%SliceConnection{} = conn) do
    dx = abs(conn.to_x - conn.from_x)
    arc_height = min(max(30, dx * 0.15), 80)
    arc_y = conn.from_y - arc_height

    path =
      "M #{conn.from_x} #{conn.from_y} " <>
        "C #{conn.from_x} #{arc_y} #{conn.to_x} #{arc_y} #{conn.to_x} #{conn.to_y}"

    %{
      from_slice: conn.from_slice,
      to_slice: conn.to_slice,
      type: conn.type,
      style: conn.style,
      path: path
    }
  end

  defp swimlane_data(swimlane, canvas_width) do
    %{
      name: swimlane.name,
      y: swimlane.y - 10,
      height: swimlane.height,
      width: canvas_width
    }
  end
end
