defmodule EventModeler.Canvas.HtmlRenderer do
  @moduledoc """
  Pure module that takes a layout result and produces HTML/CSS render data
  for rendering in a LiveView template using positioned divs.

  Element type styling uses Tailwind classes and CSS custom properties,
  making it easy to apply box-shadows, transitions, and hover states.

  Connection arrows are rendered via a thin inline SVG overlay that shares
  the same coordinate space as the positioned divs.
  """

  alias EventModeler.Canvas.Layout.{LayoutResult, PositionedElement, Connection}

  @type_classes %{
    command: %{bg: "bg-[#3B82F6]", text: "text-white", ring: "ring-[#2563EB]"},
    event: %{bg: "bg-[#F97316]", text: "text-white", ring: "ring-[#EA580C]"},
    view: %{bg: "bg-[#22C55E]", text: "text-white", ring: "ring-[#16A34A]"},
    trigger: %{bg: "bg-[#E5E7EB]", text: "text-[#374151]", ring: "ring-[#9CA3AF]"},
    automation: %{bg: "bg-[#8B5CF6]", text: "text-white", ring: "ring-[#7C3AED]"},
    exception: %{bg: "bg-[#EF4444]", text: "text-white", ring: "ring-[#DC2626]"}
  }

  @doc """
  Returns the HTML canvas data needed for rendering.
  """
  @spec render(%LayoutResult{}) :: map()
  def render(%LayoutResult{} = layout) do
    %{
      canvas_width: layout.width,
      canvas_height: layout.height,
      elements: Enum.map(layout.elements, &element_data/1),
      connections: Enum.map(layout.connections, &connection_data/1),
      swimlanes: Enum.map(layout.swimlanes, &swimlane_data(&1, layout.width)),
      slice_labels: layout.slice_labels
    }
  end

  defp element_data(%PositionedElement{} = elem) do
    classes = Map.get(@type_classes, elem.type, @type_classes.command)

    %{
      id: elem.id,
      type: elem.type,
      label: elem.label,
      swimlane: elem.swimlane,
      x: elem.x,
      y: elem.y,
      width: elem.width,
      height: elem.height,
      bg_class: classes.bg,
      text_class: classes.text,
      ring_class: classes.ring,
      props: elem.props,
      slice_name: elem.slice_name
    }
  end

  defp connection_data(%Connection{} = conn) do
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
