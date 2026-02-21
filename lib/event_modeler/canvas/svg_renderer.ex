defmodule EventModeler.Canvas.SvgRenderer do
  @moduledoc """
  Pure module that takes a layout result and produces SVG markup data
  for rendering in a LiveView template.

  Element type colors follow Event Modeling conventions:
  - Commands = blue rounded rectangles
  - Events = orange rectangles
  - Views = green rectangles
  - Triggers/Wireframes = gray with monospace text
  - Exceptions = red rectangles
  """

  alias EventModeler.Canvas.Layout.{LayoutResult, PositionedElement, Connection}

  @type_colors %{
    command: %{fill: "#3B82F6", stroke: "#2563EB", text: "#FFFFFF"},
    event: %{fill: "#F97316", stroke: "#EA580C", text: "#FFFFFF"},
    view: %{fill: "#22C55E", stroke: "#16A34A", text: "#FFFFFF"},
    trigger: %{fill: "#E5E7EB", stroke: "#9CA3AF", text: "#374151"},
    exception: %{fill: "#EF4444", stroke: "#DC2626", text: "#FFFFFF"}
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
      slice_labels: layout.slice_labels
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
    # Calculate a simple curved path between elements
    mid_x = div(conn.from_x + conn.to_x, 2)

    %{
      from_id: conn.from_id,
      to_id: conn.to_id,
      path:
        "M #{conn.from_x} #{conn.from_y} C #{mid_x} #{conn.from_y} #{mid_x} #{conn.to_y} #{conn.to_x} #{conn.to_y}"
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
