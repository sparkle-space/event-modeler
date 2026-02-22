defmodule EventModelerWeb.BoardLive do
  use EventModelerWeb, :live_view

  alias EventModeler.Board
  alias EventModeler.Canvas.Swimlane

  @impl true
  def mount(%{"path" => encoded_path}, _session, socket) do
    case Base.url_decode64(encoded_path, padding: false) do
      {:ok, file_path} ->
        case Board.open(file_path) do
          {:ok, _pid} ->
            case Board.get_state(file_path) do
              {:ok, state} ->
                {:ok,
                 assign(socket,
                   page_title: state.event_model.title || "Board",
                   file_path: file_path,
                   event_model: state.event_model,
                   canvas_data: state.canvas_data,
                   dirty: state.dirty,
                   slice_names: Enum.map(state.event_model.slices, & &1.name),
                   slices: state.event_model.slices,
                   save_message: nil,
                   error: nil,
                   selected_element: nil,
                   editing_element: nil,
                   editing_element_data: nil,
                   flash_message: nil,
                   palette_type: nil,
                   selected_slice: nil,
                   defining_slice: false,
                   slice_selection: [],
                   new_slice_name: "",
                   editing_scenario: nil,
                   editing_scenario_data: nil,
                   adding_scenario: false,
                   new_scenario_name: "",
                   swimlane_options: existing_swimlanes(state.canvas_data)
                 )}

              {:error, reason} ->
                {:ok,
                 assign(socket,
                   error: "Failed to load board: #{reason}",
                   page_title: "Error"
                 )}
            end

          {:error, reason} ->
            {:ok,
             assign(socket,
               error: "Failed to open board: #{inspect(reason)}",
               page_title: "Error"
             )}
        end

      :error ->
        {:ok, assign(socket, error: "Invalid board path", page_title: "Error")}
    end
  end

  @impl true
  def handle_event("save", _params, socket) do
    case Board.save(socket.assigns.file_path) do
      :ok ->
        {:noreply, assign(socket, dirty: false, save_message: "Saved")}

      {:error, reason} ->
        {:noreply, assign(socket, save_message: "Save failed: #{reason}")}
    end
  end

  def handle_event("select_palette", %{"type" => type}, socket) do
    {:noreply, assign(socket, palette_type: String.to_existing_atom(type))}
  end

  def handle_event("clear_palette", _params, socket) do
    {:noreply, assign(socket, palette_type: nil)}
  end

  def handle_event("place_element", %{"x" => _x, "y" => _y}, socket) do
    type = socket.assigns.palette_type

    if type do
      label = default_label(type)
      swimlane = nil

      case Board.place_element(socket.assigns.file_path, type, label, swimlane) do
        {:ok, _element_id} ->
          {:noreply, refresh_state(socket) |> assign(palette_type: nil)}

        {:error, reason} ->
          {:noreply, assign(socket, flash_message: "Error: #{inspect(reason)}")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("move_element", %{"element_id" => id, "x" => x, "y" => y}, socket) do
    Board.move_element(socket.assigns.file_path, id, x, y)
    {:noreply, refresh_state(socket)}
  end

  def handle_event("element_selected", %{"element_id" => id}, socket) do
    if socket.assigns.defining_slice do
      # In define-slice mode, toggle element selection for the slice
      selection = socket.assigns.slice_selection

      updated =
        if id in selection,
          do: List.delete(selection, id),
          else: selection ++ [id]

      {:noreply, assign(socket, slice_selection: updated)}
    else
      {:noreply, assign(socket, selected_element: id)}
    end
  end

  def handle_event("element_dblclick", %{"element_id" => id}, socket) do
    elem = Enum.find(socket.assigns.canvas_data.elements, &(&1.id == id))

    if elem do
      props = elem[:props] || %{}

      editing_data = %{
        label: elem.label,
        type: elem.type,
        swimlane: elem[:swimlane] || "",
        props: Enum.map(props, fn {k, v} -> %{key: k, value: v} end)
      }

      {:noreply, assign(socket, editing_element: id, editing_element_data: editing_data)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("edit_element", params, socket) do
    id = socket.assigns.editing_element
    data = socket.assigns.editing_element_data

    label = params["label"] || data.label
    swimlane = params["swimlane"]
    swimlane = if swimlane == "", do: nil, else: swimlane

    props =
      data.props
      |> Enum.reject(fn row -> String.trim(row.key) == "" end)
      |> Map.new(fn row -> {row.key, row.value} end)

    changes =
      %{"label" => label}
      |> then(fn c -> Map.put(c, "swimlane", swimlane) end)
      |> then(fn c -> Map.put(c, "props", props) end)

    Board.edit_element(socket.assigns.file_path, id, changes)

    {:noreply,
     refresh_state(socket)
     |> assign(editing_element: nil, editing_element_data: nil)}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing_element: nil, editing_element_data: nil)}
  end

  def handle_event("swimlane_select_changed", %{"swimlane_select" => "__new__"}, socket) do
    data = socket.assigns.editing_element_data
    updated = Map.merge(data, %{custom_swimlane: true, custom_swimlane_value: ""})
    {:noreply, assign(socket, editing_element_data: updated)}
  end

  def handle_event("swimlane_select_changed", %{"swimlane_select" => value}, socket) do
    data = socket.assigns.editing_element_data
    updated = Map.merge(data, %{swimlane: value, custom_swimlane: false})
    {:noreply, assign(socket, editing_element_data: updated)}
  end

  def handle_event("add_prop", _params, socket) do
    data = socket.assigns.editing_element_data
    updated = %{data | props: data.props ++ [%{key: "", value: ""}]}
    {:noreply, assign(socket, editing_element_data: updated)}
  end

  def handle_event(
        "update_prop",
        %{"index" => index_str, "field" => field, "value" => value},
        socket
      ) do
    index = String.to_integer(index_str)
    data = socket.assigns.editing_element_data

    updated_props =
      List.update_at(data.props, index, fn row ->
        Map.put(row, String.to_existing_atom(field), value)
      end)

    {:noreply, assign(socket, editing_element_data: %{data | props: updated_props})}
  end

  def handle_event("remove_prop", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)
    data = socket.assigns.editing_element_data
    updated_props = List.delete_at(data.props, index)
    {:noreply, assign(socket, editing_element_data: %{data | props: updated_props})}
  end

  def handle_event("connect_elements", %{"from_id" => from_id, "to_id" => to_id}, socket) do
    case Board.connect_elements(socket.assigns.file_path, from_id, to_id) do
      :ok ->
        {:noreply, refresh_state(socket)}

      {:error, reason} ->
        {:noreply, assign(socket, flash_message: reason)}
    end
  end

  def handle_event("remove_element", %{"element_id" => id}, socket) do
    Board.remove_element(socket.assigns.file_path, id)

    {:noreply,
     refresh_state(socket)
     |> assign(selected_element: nil)}
  end

  def handle_event("dismiss_flash", _params, socket) do
    {:noreply, assign(socket, flash_message: nil)}
  end

  # Slice management events

  def handle_event("select_slice", %{"name" => name}, socket) do
    socket = assign(socket, selected_slice: name)

    case Enum.find(socket.assigns.canvas_data.slice_labels, &(&1.name == name)) do
      %{x: x, width: width, y: y, height: height} ->
        {:noreply,
         push_event(socket, "pan_to_slice", %{x: x, width: width, y: y, height: height})}

      nil ->
        {:noreply, socket}
    end
  end

  def handle_event("start_define_slice", _params, socket) do
    {:noreply, assign(socket, defining_slice: true, slice_selection: [], new_slice_name: "")}
  end

  def handle_event("cancel_define_slice", _params, socket) do
    {:noreply, assign(socket, defining_slice: false, slice_selection: [], new_slice_name: "")}
  end

  def handle_event("toggle_slice_element", %{"element_id" => id}, socket) do
    selection = socket.assigns.slice_selection

    updated =
      if id in selection,
        do: List.delete(selection, id),
        else: selection ++ [id]

    {:noreply, assign(socket, slice_selection: updated)}
  end

  def handle_event("set_slice_name", %{"name" => name}, socket) do
    {:noreply, assign(socket, new_slice_name: name)}
  end

  def handle_event("confirm_define_slice", _params, socket) do
    name = socket.assigns.new_slice_name
    element_ids = socket.assigns.slice_selection

    cond do
      String.trim(name) == "" ->
        {:noreply, assign(socket, flash_message: "Slice name is required")}

      element_ids == [] ->
        {:noreply, assign(socket, flash_message: "Select at least one element")}

      true ->
        case Board.define_slice(socket.assigns.file_path, name, element_ids) do
          :ok ->
            {:noreply,
             refresh_state(socket)
             |> assign(
               defining_slice: false,
               slice_selection: [],
               new_slice_name: "",
               selected_slice: name
             )}

          {:error, reason} ->
            {:noreply, assign(socket, flash_message: "Error: #{reason}")}
        end
    end
  end

  def handle_event("generate_scenarios", %{"slice" => slice_name}, socket) do
    case Board.generate_scenarios(socket.assigns.file_path, slice_name) do
      {:ok, scenarios} ->
        {:noreply,
         refresh_state(socket)
         |> assign(flash_message: "Generated #{length(scenarios)} scenario(s)")}

      {:error, reason} ->
        {:noreply, assign(socket, flash_message: "Error: #{reason}")}
    end
  end

  def handle_event("rename_slice", %{"old_name" => old_name, "new_name" => new_name}, socket) do
    if String.trim(new_name) == "" do
      {:noreply, assign(socket, flash_message: "Slice name cannot be empty")}
    else
      case Board.rename_slice(socket.assigns.file_path, old_name, new_name) do
        :ok ->
          selected =
            if socket.assigns.selected_slice == old_name,
              do: new_name,
              else: socket.assigns.selected_slice

          {:noreply,
           refresh_state(socket)
           |> assign(selected_slice: selected)}

        {:error, reason} ->
          {:noreply, assign(socket, flash_message: "Error: #{reason}")}
      end
    end
  end

  # Disconnect elements
  def handle_event("disconnect_elements", %{"from_id" => from_id, "to_id" => to_id}, socket) do
    case Board.disconnect_elements(socket.assigns.file_path, from_id, to_id) do
      :ok ->
        {:noreply, refresh_state(socket)}

      {:error, reason} ->
        {:noreply, assign(socket, flash_message: "Error: #{reason}")}
    end
  end

  # Slice removal
  def handle_event("remove_slice", %{"name" => name}, socket) do
    case Board.remove_slice(socket.assigns.file_path, name) do
      :ok ->
        selected =
          if socket.assigns.selected_slice == name, do: nil, else: socket.assigns.selected_slice

        {:noreply,
         refresh_state(socket)
         |> assign(selected_slice: selected)}

      {:error, reason} ->
        {:noreply, assign(socket, flash_message: "Error: #{reason}")}
    end
  end

  # Remove element from slice
  def handle_event(
        "remove_element_from_slice",
        %{"slice" => slice_name, "element_id" => element_id},
        socket
      ) do
    case Board.remove_element_from_slice(socket.assigns.file_path, slice_name, element_id) do
      :ok ->
        {:noreply, refresh_state(socket)}

      {:error, reason} ->
        {:noreply, assign(socket, flash_message: "Error: #{reason}")}
    end
  end

  # Scenario removal
  def handle_event(
        "remove_scenario",
        %{"slice" => slice_name, "scenario" => scenario_name},
        socket
      ) do
    case Board.remove_scenario(socket.assigns.file_path, slice_name, scenario_name) do
      :ok ->
        {:noreply, refresh_state(socket)}

      {:error, reason} ->
        {:noreply, assign(socket, flash_message: "Error: #{reason}")}
    end
  end

  # Start editing scenario
  def handle_event(
        "start_edit_scenario",
        %{"slice" => slice_name, "scenario" => scenario_name},
        socket
      ) do
    slice = Enum.find(socket.assigns.slices, &(&1.name == slice_name))
    scenario = slice && Enum.find(slice.tests || [], &(&1.name == scenario_name))

    if scenario do
      {:noreply,
       assign(socket,
         editing_scenario: %{slice: slice_name, name: scenario_name},
         editing_scenario_data: %{name: scenario.name}
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("cancel_edit_scenario", _params, socket) do
    {:noreply, assign(socket, editing_scenario: nil, editing_scenario_data: nil)}
  end

  def handle_event("save_scenario", %{"name" => new_name}, socket) do
    %{slice: slice_name, name: old_name} = socket.assigns.editing_scenario
    new_name = String.trim(new_name)

    if new_name == "" do
      {:noreply, assign(socket, flash_message: "Scenario name cannot be empty")}
    else
      case Board.update_scenario(socket.assigns.file_path, slice_name, old_name, %{
             "name" => new_name
           }) do
        :ok ->
          {:noreply,
           refresh_state(socket)
           |> assign(editing_scenario: nil, editing_scenario_data: nil)}

        {:error, reason} ->
          {:noreply, assign(socket, flash_message: "Error: #{reason}")}
      end
    end
  end

  # Add scenario
  def handle_event("start_add_scenario", %{"slice" => slice_name}, socket) do
    {:noreply, assign(socket, adding_scenario: slice_name, new_scenario_name: "")}
  end

  def handle_event("cancel_add_scenario", _params, socket) do
    {:noreply, assign(socket, adding_scenario: false, new_scenario_name: "")}
  end

  def handle_event("confirm_add_scenario", %{"name" => name}, socket) do
    name = String.trim(name)
    slice_name = socket.assigns.adding_scenario

    if name == "" do
      {:noreply, assign(socket, flash_message: "Scenario name cannot be empty")}
    else
      case Board.add_scenario(socket.assigns.file_path, slice_name, %{"name" => name}) do
        :ok ->
          {:noreply,
           refresh_state(socket)
           |> assign(adding_scenario: false, new_scenario_name: "")}

        {:error, reason} ->
          {:noreply, assign(socket, flash_message: "Error: #{reason}")}
      end
    end
  end

  defp refresh_state(socket) do
    case Board.get_state(socket.assigns.file_path) do
      {:ok, state} ->
        assign(socket,
          event_model: state.event_model,
          canvas_data: state.canvas_data,
          dirty: state.dirty,
          slice_names: Enum.map(state.event_model.slices, & &1.name),
          slices: state.event_model.slices,
          swimlane_options: existing_swimlanes(state.canvas_data)
        )

      {:error, _} ->
        socket
    end
  end

  defp default_label(:command), do: "NewCommand"
  defp default_label(:event), do: "NewEvent"
  defp default_label(:view), do: "NewView"
  defp default_label(:wireframe), do: "NewWireframe"
  defp default_label(:automation), do: "NewAutomation"
  defp default_label(:exception), do: "NewException"
  defp default_label(_), do: "New"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[var(--color-bg)]">
      <div :if={assigns[:error]} class="max-w-4xl mx-auto px-4 py-6">
        <div class="bg-error/10 border border-error/20 rounded-[var(--radius-card)] p-4">
          <p class="text-error">{@error}</p>
          <.link navigate={~p"/boards"} class="text-primary hover:underline mt-2 block">
            Back to boards
          </.link>
        </div>
      </div>

      <div :if={assigns[:canvas_data]} class="h-screen flex flex-col">
        <%!-- Header --%>
        <div class="bg-[var(--color-surface)] border-b border-[var(--color-border)] px-4 py-3 flex items-center justify-between shrink-0">
          <div class="flex items-center gap-4">
            <.link
              navigate={~p"/boards"}
              class="text-[var(--color-text-secondary)] hover:text-[var(--color-text-primary)] transition-colors"
            >
              &larr; Boards
            </.link>
            <h1 class="font-semibold text-[var(--color-text-primary)]">
              {@event_model.title || "Untitled"}
            </h1>
            <span
              :if={@event_model.status}
              class="text-xs px-2.5 py-0.5 rounded-full font-medium bg-[var(--color-surface-alt)] text-[var(--color-text-secondary)]"
            >
              {@event_model.status}
            </span>
            <span :if={@dirty} class="text-xs text-warning font-medium">Unsaved changes</span>
          </div>
          <div class="flex items-center gap-2">
            <span :if={@event_model.updated} class="text-xs text-[var(--color-text-secondary)]">
              Updated: {String.slice(@event_model.updated || "", 0..18)}
            </span>
            <p :if={@save_message} class="text-sm text-success">{@save_message}</p>
            <Layouts.theme_toggle />
            <a
              href={~p"/boards/#{Base.url_encode64(@file_path, padding: false)}/export"}
              class="bg-[var(--color-surface-alt)] text-[var(--color-text-primary)] px-3 py-1.5 rounded-[var(--radius-element)] text-sm hover:opacity-80 transition-opacity border border-[var(--color-border)]"
            >
              Export
            </a>
            <button
              phx-click="save"
              class="bg-primary text-primary-content px-3 py-1.5 rounded-[var(--radius-element)] text-sm hover:opacity-90 transition-opacity"
            >
              Save
            </button>
          </div>
        </div>

        <%!-- Flash message --%>
        <div
          :if={@flash_message}
          class="bg-warning/10 border-b border-warning/20 px-4 py-2 flex items-center justify-between"
        >
          <p class="text-sm text-warning">{@flash_message}</p>
          <button
            phx-click="dismiss_flash"
            class="text-warning/60 hover:text-warning text-sm transition-colors"
          >
            Dismiss
          </button>
        </div>

        <%!-- Main content --%>
        <div class="flex-1 flex overflow-hidden">
          <%!-- Left sidebar: Element palette --%>
          <div class="w-48 bg-[var(--color-surface)] border-r border-[var(--color-border)] p-3 shrink-0 overflow-y-auto">
            <h2 class="text-xs font-semibold text-[var(--color-text-secondary)] uppercase tracking-wider mb-2">
              Add Element
            </h2>
            <div class="space-y-1">
              <button
                :for={
                  {type, label, color, shadow_var} <- [
                    {:event, "Event", "bg-[#F97316]", "--shadow-event"},
                    {:command, "Command", "bg-[#3B82F6]", "--shadow-command"},
                    {:view, "View", "bg-[#22C55E]", "--shadow-view"},
                    {:wireframe, "Wireframe", "bg-[#9CA3AF]", "--shadow-wireframe"},
                    {:automation, "Automation", "bg-[#8B5CF6]", "--shadow-automation"},
                    {:exception, "Exception", "bg-[#EF4444]", "--shadow-exception"}
                  ]
                }
                phx-click="select_palette"
                phx-value-type={type}
                class={[
                  "w-full text-left px-3 py-2 rounded-[var(--radius-element)] text-sm flex items-center gap-2 transition-colors",
                  if(@palette_type == type,
                    do: "bg-[var(--color-surface-alt)] ring-2 ring-primary",
                    else: "hover:bg-[var(--color-surface-alt)]"
                  )
                ]}
              >
                <span
                  class={"w-3 h-3 rounded-sm #{color}"}
                  style={"box-shadow: var(#{shadow_var})"}
                >
                </span>
                <span class="text-[var(--color-text-primary)]">{label}</span>
              </button>
            </div>

            <button
              :if={@palette_type}
              phx-click="clear_palette"
              class="mt-2 w-full text-xs text-[var(--color-text-secondary)] hover:text-[var(--color-text-primary)] transition-colors"
            >
              Cancel placement
            </button>

            <div class="mt-6 text-xs text-[var(--color-text-secondary)] space-y-1">
              <p>Click canvas to place</p>
              <p>Shift+click to connect</p>
              <p>Double-click to edit</p>
              <p>Delete to remove</p>
            </div>
          </div>

          <%!-- HTML Canvas --%>
          <div
            id="canvas-viewport"
            class={[
              "flex-1 overflow-hidden relative select-none bg-[var(--color-surface)] border border-[var(--color-border)] rounded-[var(--radius-card)]",
              if(@palette_type, do: "cursor-crosshair", else: "cursor-grab")
            ]}
            phx-hook="EventModelerCanvas"
            phx-click={if(@palette_type, do: "place_element")}
            phx-value-x="100"
            phx-value-y="100"
          >
            <div
              id="canvas-world"
              style={"width: #{@canvas_data.canvas_width}px; height: #{@canvas_data.canvas_height}px; position: relative; transform-origin: 0 0;"}
            >
              <%!-- Swimlane bands --%>
              <div
                :for={sl <- @canvas_data.swimlanes}
                style={"position: absolute; left: 0; top: #{sl.y}px; width: #{sl.width}px; height: #{sl.height}px;"}
                class={[
                  "border-y border-[var(--swimlane-border)]",
                  swimlane_bg_class(sl.type)
                ]}
              >
                <span class="absolute left-2.5 top-1/2 -translate-y-1/2 text-xs font-semibold text-[var(--color-text-secondary)]">
                  {sl.name}
                </span>
              </div>

              <%!-- Connection SVG overlay --%>
              <svg
                style={"position: absolute; top: 0; left: 0; width: #{@canvas_data.canvas_width}px; height: #{@canvas_data.canvas_height}px; overflow: visible;"}
                xmlns="http://www.w3.org/2000/svg"
              >
                <defs>
                  <marker
                    id="arrowhead"
                    markerWidth="10"
                    markerHeight="7"
                    refX="0"
                    refY="3.5"
                    orient="auto"
                  >
                    <polygon points="0 0, 10 3.5, 0 7" fill="var(--color-connection)" />
                  </marker>
                </defs>
                <g :for={conn <- @canvas_data.connections}>
                  <%!-- Invisible wider path for easier clicking --%>
                  <path
                    d={conn.path}
                    fill="none"
                    stroke="transparent"
                    stroke-width="12"
                    style="cursor: pointer; pointer-events: stroke;"
                    phx-click="disconnect_elements"
                    phx-value-from_id={conn.from_id}
                    phx-value-to_id={conn.to_id}
                  />
                  <%!-- Visible path --%>
                  <path
                    d={conn.path}
                    fill="none"
                    stroke="var(--color-connection)"
                    stroke-width="2"
                    marker-end="url(#arrowhead)"
                    style="pointer-events: none;"
                  />
                </g>
              </svg>

              <%!-- Element divs --%>
              <div
                :for={elem <- @canvas_data.elements}
                id={"elem-#{elem.id}"}
                data-element-id={elem.id}
                data-selected={to_string(@selected_element == elem.id)}
                phx-click="element_selected"
                phx-value-element_id={elem.id}
                style={"position: absolute; left: #{elem.x}px; top: #{elem.y}px; width: #{elem.width}px; height: #{elem.height}px;"}
                class={[
                  "rounded-xl flex flex-col items-center justify-center cursor-pointer transition-all select-none",
                  elem.bg_class,
                  elem.text_class,
                  if(@selected_element == elem.id,
                    do: "ring-3 ring-offset-1 " <> elem.ring_class,
                    else: ""
                  ),
                  if(elem.id in @slice_selection, do: "ring-dashed-selection", else: "")
                ]}
              >
                <span class="text-xs font-semibold px-2 text-center leading-tight">
                  {elem.label}
                </span>
                <span class="text-[10px] opacity-75 mt-0.5">{type_label(elem.type)}</span>
              </div>

              <%!-- Slice labels --%>
              <div
                :for={sl <- @canvas_data.slice_labels}
                style={"position: absolute; left: #{sl.x}px; top: 4px; width: #{sl.width}px;"}
                class="text-center text-[11px] font-medium text-[var(--color-text-secondary)] pointer-events-none"
              >
                {sl.name}
              </div>
            </div>
          </div>

          <%!-- Right sidebar --%>
          <div class="w-64 bg-[var(--color-surface)] border-l border-[var(--color-border)] p-4 overflow-y-auto shrink-0">
            <%!-- Define Slice mode --%>
            <div
              :if={@defining_slice}
              class="mb-4 bg-primary/10 border border-primary/20 rounded-[var(--radius-element)] p-3"
            >
              <h3 class="text-xs font-semibold text-primary mb-2">Define New Slice</h3>
              <form phx-change="set_slice_name">
                <input
                  type="text"
                  name="name"
                  placeholder="Slice name"
                  value={@new_slice_name}
                  class="w-full text-sm border border-primary/30 rounded-[8px] px-2 py-1 mb-2 bg-[var(--color-surface)] text-[var(--color-text-primary)]"
                />
              </form>
              <p class="text-xs text-primary/80 mb-2">
                Click elements on the canvas to select them.
                Selected: {length(@slice_selection)}
              </p>
              <div class="flex gap-2">
                <button
                  phx-click="confirm_define_slice"
                  class="flex-1 bg-primary text-primary-content px-2 py-1 rounded-[8px] text-xs"
                >
                  Create
                </button>
                <button
                  phx-click="cancel_define_slice"
                  class="flex-1 bg-[var(--color-surface-alt)] text-[var(--color-text-primary)] px-2 py-1 rounded-[8px] text-xs"
                >
                  Cancel
                </button>
              </div>
            </div>

            <%!-- Slices list --%>
            <div class="flex items-center justify-between mb-3">
              <h2 class="text-sm font-semibold text-[var(--color-text-primary)]">Slices</h2>
              <button
                :if={!@defining_slice}
                phx-click="start_define_slice"
                class="text-xs text-primary hover:text-primary/80 transition-colors"
              >
                + Define
              </button>
            </div>

            <div :if={@slice_names == []} class="text-sm text-[var(--color-text-secondary)] mb-4">
              No slices defined.
            </div>

            <ul class="space-y-1 mb-4">
              <li
                :for={name <- @slice_names}
                phx-click="select_slice"
                phx-value-name={name}
                class={[
                  "text-sm text-[var(--color-text-primary)] flex items-center gap-2 px-2 py-1 rounded-[8px] cursor-pointer transition-colors group",
                  if(@selected_slice == name,
                    do: "bg-primary/10 ring-1 ring-primary/20",
                    else: "hover:bg-[var(--color-surface-alt)]"
                  )
                ]}
              >
                <span class="w-2 h-2 bg-primary rounded-full shrink-0"></span>
                <span class="truncate flex-1">{name}</span>
                <button
                  :if={name != "Unassigned"}
                  phx-click="remove_slice"
                  phx-value-name={name}
                  class="text-xs text-error/60 hover:text-error opacity-0 group-hover:opacity-100 transition-opacity shrink-0"
                  title="Delete slice"
                >
                  &times;
                </button>
              </li>
            </ul>

            <%!-- Selected slice details --%>
            <div :if={@selected_slice} class="mb-4">
              <% slice = Enum.find(@slices, &(&1.name == @selected_slice)) %>
              <div
                :if={slice}
                class="bg-[var(--color-surface-alt)] rounded-[var(--radius-element)] p-3"
              >
                <div class="flex items-center justify-between mb-2">
                  <h3 class="text-xs font-semibold text-[var(--color-text-primary)]">{slice.name}</h3>
                  <span class="text-xs text-[var(--color-text-secondary)]">
                    {length(slice.steps)} elements
                  </span>
                </div>

                <%!-- Elements in slice --%>
                <div :if={slice.steps != []} class="mb-2">
                  <div
                    :for={elem <- slice.steps}
                    class="flex items-center justify-between text-xs py-0.5 group/elem"
                  >
                    <span class="text-[var(--color-text-primary)] truncate">
                      {elem.label}
                      <span class="text-[var(--color-text-secondary)]">
                        ({type_label(elem.type)})
                      </span>
                    </span>
                    <button
                      phx-click="remove_element_from_slice"
                      phx-value-slice={slice.name}
                      phx-value-element_id={elem.id}
                      class="text-error/60 hover:text-error opacity-0 group-hover/elem:opacity-100 transition-opacity text-xs shrink-0 ml-1"
                      title="Remove from slice"
                    >
                      &times;
                    </button>
                  </div>
                </div>

                <button
                  phx-click="generate_scenarios"
                  phx-value-slice={slice.name}
                  class="w-full bg-success text-success-content px-2 py-1 rounded-[8px] text-xs mb-2 hover:opacity-90 transition-opacity"
                >
                  Generate Scenarios
                </button>

                <%!-- Scenarios list --%>
                <div :if={slice.tests != nil and slice.tests != []}>
                  <h4 class="text-xs font-semibold text-[var(--color-text-secondary)] mb-1">
                    Scenarios
                  </h4>
                  <div
                    :for={scenario <- slice.tests}
                    class="text-xs bg-[var(--color-surface)] rounded-[8px] p-2 mb-1 border border-[var(--color-border)]"
                  >
                    <%!-- Scenario header with edit/delete --%>
                    <div class="flex items-center justify-between group/sc">
                      <%= if @editing_scenario && @editing_scenario.slice == slice.name && @editing_scenario.name == scenario.name do %>
                        <form phx-submit="save_scenario" class="flex gap-1 flex-1">
                          <input
                            type="text"
                            name="name"
                            value={@editing_scenario_data.name}
                            class="flex-1 text-xs border border-primary/30 rounded px-1 py-0.5 bg-[var(--color-surface)] text-[var(--color-text-primary)]"
                            autofocus
                          />
                          <button type="submit" class="text-xs text-primary">Save</button>
                          <button
                            type="button"
                            phx-click="cancel_edit_scenario"
                            class="text-xs text-[var(--color-text-secondary)]"
                          >
                            Cancel
                          </button>
                        </form>
                      <% else %>
                        <p class="font-medium text-[var(--color-text-primary)] flex-1">
                          {scenario.name}
                        </p>
                        <div class="flex gap-1 opacity-0 group-hover/sc:opacity-100 transition-opacity">
                          <button
                            phx-click="start_edit_scenario"
                            phx-value-slice={slice.name}
                            phx-value-scenario={scenario.name}
                            class="text-primary/60 hover:text-primary text-[10px]"
                            title="Rename"
                          >
                            Edit
                          </button>
                          <button
                            phx-click="remove_scenario"
                            phx-value-slice={slice.name}
                            phx-value-scenario={scenario.name}
                            class="text-error/60 hover:text-error text-[10px]"
                            title="Delete"
                          >
                            &times;
                          </button>
                        </div>
                      <% end %>
                    </div>
                    <div :if={scenario.given != []} class="mt-1">
                      <span class="text-[var(--color-text-secondary)]">Given:</span>
                      <span :for={g <- scenario.given} class="ml-1 text-warning">{g.label}</span>
                    </div>
                    <div class="mt-0.5">
                      <span class="text-[var(--color-text-secondary)]">When:</span>
                      <span :for={w <- scenario.when_clause} class="ml-1 text-info">
                        {w.label}
                      </span>
                    </div>
                    <div :if={scenario.then_clause != []} class="mt-0.5">
                      <span class="text-[var(--color-text-secondary)]">Then:</span>
                      <span :for={t <- scenario.then_clause} class="ml-1 text-success">
                        {t.label}
                      </span>
                    </div>
                  </div>
                </div>

                <div :if={slice.tests == nil or slice.tests == []}>
                  <p class="text-xs text-[var(--color-text-secondary)] italic">No scenarios yet.</p>
                </div>

                <%!-- Add scenario --%>
                <%= if @adding_scenario == slice.name do %>
                  <form phx-submit="confirm_add_scenario" class="mt-2 flex gap-1">
                    <input
                      type="text"
                      name="name"
                      placeholder="Scenario name"
                      value={@new_scenario_name}
                      class="flex-1 text-xs border border-primary/30 rounded-[6px] px-1.5 py-0.5 bg-[var(--color-surface)] text-[var(--color-text-primary)]"
                      autofocus
                    />
                    <button type="submit" class="text-xs text-primary">Add</button>
                    <button
                      type="button"
                      phx-click="cancel_add_scenario"
                      class="text-xs text-[var(--color-text-secondary)]"
                    >
                      Cancel
                    </button>
                  </form>
                <% else %>
                  <button
                    phx-click="start_add_scenario"
                    phx-value-slice={slice.name}
                    class="mt-1 text-xs text-primary hover:text-primary/80 transition-colors"
                  >
                    + Add Scenario
                  </button>
                <% end %>
              </div>
            </div>

            <%!-- Element editor --%>
            <div
              :if={@editing_element && @editing_element_data}
              class="mt-4 bg-[var(--color-surface-alt)] rounded-[var(--radius-element)] p-3"
            >
              <h3 class="text-xs font-semibold text-[var(--color-text-secondary)] mb-2">
                Edit Element
              </h3>
              <form phx-submit="edit_element">
                <label class="block text-xs text-[var(--color-text-secondary)] mb-1">Label</label>
                <input
                  type="text"
                  name="label"
                  value={@editing_element_data.label}
                  class="w-full text-sm border border-[var(--color-border)] rounded-[8px] px-2 py-1 mb-2 bg-[var(--color-surface)] text-[var(--color-text-primary)]"
                  autofocus
                />

                <label class="block text-xs text-[var(--color-text-secondary)] mb-1">Swimlane</label>
                <select
                  name="swimlane_select"
                  phx-change="swimlane_select_changed"
                  class="w-full text-sm border border-[var(--color-border)] rounded-[8px] px-2 py-1 mb-2 bg-[var(--color-surface)] text-[var(--color-text-primary)]"
                >
                  <option
                    :for={
                      sl <- filtered_swimlane_options(@swimlane_options, @editing_element_data.type)
                    }
                    value={sl.name}
                    selected={sl.name == (@editing_element_data.swimlane || "")}
                  >
                    {sl.name}
                  </option>
                  <option value="__new__">+ New swimlane...</option>
                </select>
                <input
                  :if={@editing_element_data[:custom_swimlane]}
                  type="text"
                  name="swimlane"
                  value={@editing_element_data[:custom_swimlane_value] || ""}
                  placeholder="Enter new swimlane name"
                  autofocus
                  class="w-full text-sm border border-[var(--color-border)] rounded-[8px] px-2 py-1 mb-2 bg-[var(--color-surface)] text-[var(--color-text-primary)]"
                />
                <input
                  :if={!@editing_element_data[:custom_swimlane]}
                  type="hidden"
                  name="swimlane"
                  value={@editing_element_data.swimlane}
                />

                <div class="flex items-center justify-between mb-1">
                  <label class="text-xs text-[var(--color-text-secondary)]">Fields</label>
                  <button
                    type="button"
                    phx-click="add_prop"
                    class="text-xs text-primary hover:text-primary/80 transition-colors"
                  >
                    + Add
                  </button>
                </div>

                <div
                  :for={{row, idx} <- Enum.with_index(@editing_element_data.props)}
                  class="flex items-center gap-1 mb-1"
                >
                  <input
                    type="text"
                    value={row.key}
                    placeholder="key"
                    phx-blur="update_prop"
                    phx-value-index={idx}
                    phx-value-field="key"
                    class="flex-1 text-xs border border-[var(--color-border)] rounded-[6px] px-1.5 py-0.5 bg-[var(--color-surface)] text-[var(--color-text-primary)]"
                  />
                  <input
                    type="text"
                    value={row.value}
                    placeholder="type"
                    phx-blur="update_prop"
                    phx-value-index={idx}
                    phx-value-field="value"
                    class="flex-1 text-xs border border-[var(--color-border)] rounded-[6px] px-1.5 py-0.5 bg-[var(--color-surface)] text-[var(--color-text-primary)]"
                  />
                  <button
                    type="button"
                    phx-click="remove_prop"
                    phx-value-index={idx}
                    class="text-xs text-error hover:text-error/80 px-1 transition-colors"
                  >
                    &times;
                  </button>
                </div>

                <div
                  :if={@editing_element_data.props == []}
                  class="text-xs text-[var(--color-text-secondary)] italic mb-2"
                >
                  No fields defined.
                </div>

                <div class="flex gap-2 mt-2">
                  <button
                    type="submit"
                    class="flex-1 bg-primary text-primary-content px-2 py-1 rounded-[8px] text-sm"
                  >
                    Update
                  </button>
                  <button
                    type="button"
                    phx-click="cancel_edit"
                    class="flex-1 bg-[var(--color-surface)] text-[var(--color-text-primary)] px-2 py-1 rounded-[8px] text-sm border border-[var(--color-border)]"
                  >
                    Cancel
                  </button>
                </div>
              </form>
            </div>

            <div :if={@event_model.overview} class="mt-6">
              <h2 class="text-sm font-semibold text-[var(--color-text-primary)] mb-2">Overview</h2>
              <p class="text-xs text-[var(--color-text-secondary)]">
                {String.slice(@event_model.overview || "", 0..200)}
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp existing_swimlanes(canvas_data) do
    canvas_data.swimlanes
    |> Enum.map(fn sl -> %{name: sl.name, type: sl.type} end)
    |> Enum.sort_by(fn sl -> {Swimlane.sort_order(sl.type), sl.name} end)
  end

  defp filtered_swimlane_options(swimlane_options, element_type) do
    target_type = Swimlane.type_for_element(element_type)

    swimlane_options
    |> Enum.filter(fn sl -> sl.type == target_type end)
  end

  defp swimlane_bg_class(:trigger), do: "bg-[var(--swimlane-trigger-bg)]"
  defp swimlane_bg_class(:command_view), do: "bg-[var(--swimlane-command-view-bg)]"
  defp swimlane_bg_class(:event), do: "bg-[var(--swimlane-event-bg)]"
  defp swimlane_bg_class(_), do: "bg-[var(--swimlane-command-view-bg)]"

  defp type_label(:command), do: "Command"
  defp type_label(:event), do: "Event"
  defp type_label(:view), do: "View"
  defp type_label(:wireframe), do: "Wireframe"
  defp type_label(:exception), do: "Exception"
  defp type_label(:automation), do: "Automation"
  defp type_label(_), do: ""
end
