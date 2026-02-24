defmodule EventModeler.Canvas.Layout do
  @moduledoc """
  Pure module that takes a parsed `%EventModel{}` and computes element positions
  for SVG rendering.

  Elements are laid out left-to-right per slice in step order
  (wireframe -> command -> event -> view). Swimlane rows group elements
  by their swimlane prefix and are ordered by type: triggers on top,
  commands/views in the middle, events at the bottom.
  """

  alias EventModeler.EventModel
  alias EventModeler.Canvas.Swimlane

  @element_width 180
  @element_height 60
  @h_gap 60
  @v_gap 40
  @swimlane_label_width 120
  @slice_gap 100
  @padding 40

  defmodule PositionedElement do
    @moduledoc false
    defstruct [:id, :type, :label, :swimlane, :props, :x, :y, :width, :height, :slice_name]
  end

  defmodule Connection do
    @moduledoc false
    defstruct [:from_id, :to_id, :from_x, :from_y, :to_x, :to_y]
  end

  defmodule LayoutResult do
    @moduledoc false
    defstruct [
      :width,
      :height,
      elements: [],
      connections: [],
      swimlanes: [],
      slice_labels: []
    ]
  end

  @doc """
  Computes layout positions for all elements in a parsed Event Model.
  Returns a `%LayoutResult{}` with positioned elements and connections.
  """
  @spec compute(%EventModel{}) :: %LayoutResult{}
  def compute(%EventModel{slices: slices}) do
    # Collect all unique typed swimlanes
    all_swimlanes = collect_swimlanes(slices)

    # Assign vertical positions per swimlane (sorted by type then name)
    swimlane_y = assign_swimlane_positions(all_swimlanes)

    # Position elements slice by slice, left to right
    {positioned, connections, slice_labels, total_width} =
      layout_slices(slices, swimlane_y)

    # Calculate canvas dimensions
    total_height = calculate_height(swimlane_y)

    # Build swimlane data for rendering (with type info)
    swimlane_data =
      Enum.map(all_swimlanes, fn %Swimlane{name: name, type: type} ->
        %{
          name: name,
          type: type,
          y: Map.get(swimlane_y, name, @padding),
          height: @element_height + @v_gap
        }
      end)

    %LayoutResult{
      elements: positioned,
      connections: connections,
      swimlanes: swimlane_data,
      slice_labels: slice_labels,
      width: max(total_width + @padding * 2, 800),
      height: max(total_height + @padding * 2, 400)
    }
  end

  defp collect_swimlanes(slices) do
    slices
    |> Enum.flat_map(fn slice ->
      Enum.map(slice.steps, fn step ->
        name = step.swimlane || Swimlane.default_name(Swimlane.type_for_element(step.type))
        type = Swimlane.type_for_element(step.type)
        %Swimlane{name: name, type: type}
      end)
    end)
    |> Enum.uniq_by(fn %Swimlane{name: name, type: type} -> {name, type} end)
    |> Enum.sort_by(fn %Swimlane{name: name, type: type} ->
      {Swimlane.sort_order(type), name}
    end)
  end

  defp assign_swimlane_positions(swimlanes) do
    swimlanes
    |> Enum.with_index()
    |> Map.new(fn {%Swimlane{name: name}, idx} ->
      {name, @padding + idx * (@element_height + @v_gap)}
    end)
  end

  defp calculate_height(swimlane_y) do
    if map_size(swimlane_y) == 0 do
      0
    else
      max_y = swimlane_y |> Map.values() |> Enum.max()
      max_y + @element_height + @v_gap
    end
  end

  defp layout_slices(slices, swimlane_y) do
    initial_x = @swimlane_label_width + @padding

    {positioned, connections, labels, final_x} =
      Enum.reduce(slices, {[], [], [], initial_x}, fn slice, {elems, conns, labels, x_offset} ->
        {slice_elems, slice_conns, next_x} =
          layout_slice(slice, swimlane_y, x_offset)

        {min_y, max_y_bottom} = slice_vertical_bounds(slice_elems)

        label = %{
          name: slice.name,
          x: x_offset,
          width: next_x - x_offset - @slice_gap,
          y: min_y,
          height: max_y_bottom - min_y
        }

        {elems ++ slice_elems, conns ++ slice_conns, labels ++ [label], next_x}
      end)

    {positioned, connections, labels, final_x}
  end

  defp layout_slice(slice, swimlane_y, start_x) do
    {elements, _x} =
      Enum.reduce(slice.steps, {[], start_x}, fn step, {acc, x} ->
        swimlane =
          step.swimlane || Swimlane.default_name(Swimlane.type_for_element(step.type))

        y = Map.get(swimlane_y, swimlane, @padding)

        offset_x = step.props["position_offset_x"] || 0
        offset_y = step.props["position_offset_y"] || 0

        elem = %PositionedElement{
          id: step.id,
          type: step.type,
          label: step.label,
          swimlane: swimlane,
          props: step.props,
          x: x + offset_x,
          y: y + offset_y,
          width: @element_width,
          height: @element_height,
          slice_name: slice.name
        }

        {acc ++ [elem], x + @element_width + @h_gap}
      end)

    # Create connections between consecutive elements
    connections =
      elements
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [from, to] ->
        %Connection{
          from_id: from.id,
          to_id: to.id,
          from_x: from.x + from.width,
          from_y: from.y + div(from.height, 2),
          to_x: to.x,
          to_y: to.y + div(to.height, 2)
        }
      end)

    next_x =
      case elements do
        [] -> start_x + @slice_gap
        elems -> List.last(elems).x + @element_width + @slice_gap
      end

    {elements, connections, next_x}
  end

  defp slice_vertical_bounds([]) do
    {@padding, @padding + @element_height}
  end

  defp slice_vertical_bounds(elements) do
    min_y = elements |> Enum.map(& &1.y) |> Enum.min()
    max_y_bottom = elements |> Enum.map(&(&1.y + &1.height)) |> Enum.max()
    {min_y, max_y_bottom}
  end
end
