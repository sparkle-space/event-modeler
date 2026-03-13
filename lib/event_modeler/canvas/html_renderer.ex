defmodule EventModeler.Canvas.HtmlRenderer do
  @moduledoc """
  Pure module that takes a layout result and produces HTML/CSS render data
  for rendering in a LiveView template using positioned divs.

  Element type styling uses Tailwind classes and CSS custom properties,
  making it easy to apply box-shadows, transitions, and hover states.

  Connection arrows are rendered via a thin inline SVG overlay that shares
  the same coordinate space as the positioned divs.
  """

  alias EventModeler.Canvas.Layout.{
    LayoutResult,
    PositionedElement,
    PositionedSpec,
    Connection,
    SliceConnection
  }

  @type_classes %{
    command: %{bg: "bg-[#3B82F6]", text: "text-white", ring: "ring-[#2563EB]"},
    event: %{bg: "bg-[#F97316]", text: "text-white", ring: "ring-[#EA580C]"},
    view: %{bg: "bg-[#22C55E]", text: "text-white", ring: "ring-[#16A34A]"},
    wireframe: %{bg: "bg-[#E5E7EB]", text: "text-[#374151]", ring: "ring-[#6366F1]"},
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
      slice_labels: layout.slice_labels,
      slice_connections: Enum.map(layout.slice_connections, &slice_connection_data/1)
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

  defp swimlane_data(swimlane, canvas_width) do
    %{
      name: swimlane.name,
      type: swimlane.type,
      y: swimlane.y - 10,
      height: swimlane.height,
      width: canvas_width
    }
  end

  defp slice_connection_data(%SliceConnection{} = conn) do
    # Arc above slice labels — higher arc for more distant slices
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

  @type_colors %{
    "c" => "#3B82F6",
    "e" => "#F97316",
    "v" => "#22C55E",
    "x" => "#EF4444"
  }

  @doc """
  Renders spec card data for template rendering.
  Takes a list of `PositionedSpec` structs and returns render-ready maps.
  """
  @spec render_spec_cards([%PositionedSpec{}]) :: [map()]
  def render_spec_cards(spec_cards) do
    Enum.map(spec_cards, &spec_card_data/1)
  end

  defp spec_card_data(%PositionedSpec{} = spec) do
    %{
      name: spec.name,
      slice_name: spec.slice_name,
      x: spec.x,
      y: spec.y,
      width: spec.width,
      height: spec.height,
      given: Enum.map(spec.given, &mini_element/1),
      when_clause: Enum.map(spec.when_clause, &mini_element/1),
      then_clause: Enum.map(spec.then_clause, &mini_element/1)
    }
  end

  defp mini_element(%{type: type, label: label}) do
    %{
      type: type,
      label: label,
      color: Map.get(@type_colors, type, "#9CA3AF")
    }
  end

  defp mini_element(%{} = item) do
    type = Map.get(item, :type, "e")
    label = Map.get(item, :label, "")

    %{
      type: type,
      label: label,
      color: Map.get(@type_colors, type, "#9CA3AF")
    }
  end
end
