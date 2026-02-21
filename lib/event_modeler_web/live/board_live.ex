defmodule EventModelerWeb.BoardLive do
  use EventModelerWeb, :live_view

  alias EventModeler.Board

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
                   page_title: state.prd.title || "Board",
                   file_path: file_path,
                   prd: state.prd,
                   svg_data: state.svg_data,
                   dirty: state.dirty,
                   slice_names: Enum.map(state.prd.slices, & &1.name),
                   slices: state.prd.slices,
                   save_message: nil,
                   error: nil,
                   selected_element: nil,
                   editing_element: nil,
                   flash_message: nil,
                   palette_type: nil,
                   selected_slice: nil,
                   defining_slice: false,
                   slice_selection: [],
                   new_slice_name: ""
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
    {:noreply, assign(socket, editing_element: id)}
  end

  def handle_event("edit_label", %{"element_id" => id, "label" => label}, socket) do
    Board.edit_element(socket.assigns.file_path, id, %{"label" => label})

    {:noreply,
     refresh_state(socket)
     |> assign(editing_element: nil)}
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
    {:noreply, assign(socket, selected_slice: name)}
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

  defp refresh_state(socket) do
    case Board.get_state(socket.assigns.file_path) do
      {:ok, state} ->
        assign(socket,
          prd: state.prd,
          svg_data: state.svg_data,
          dirty: state.dirty,
          slice_names: Enum.map(state.prd.slices, & &1.name),
          slices: state.prd.slices
        )

      {:error, _} ->
        socket
    end
  end

  defp default_label(:command), do: "NewCommand"
  defp default_label(:event), do: "NewEvent"
  defp default_label(:view), do: "NewView"
  defp default_label(:trigger), do: "NewTrigger"
  defp default_label(:automation), do: "NewAutomation"
  defp default_label(:exception), do: "NewException"
  defp default_label(_), do: "New"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <div :if={assigns[:error]} class="max-w-4xl mx-auto px-4 py-6">
        <div class="bg-red-50 border border-red-200 rounded-lg p-4">
          <p class="text-red-700">{@error}</p>
          <.link navigate={~p"/boards"} class="text-blue-600 hover:underline mt-2 block">
            Back to boards
          </.link>
        </div>
      </div>

      <div :if={assigns[:svg_data]} class="h-screen flex flex-col">
        <%!-- Header --%>
        <div class="bg-white border-b border-gray-200 px-4 py-3 flex items-center justify-between shrink-0">
          <div class="flex items-center gap-4">
            <.link navigate={~p"/boards"} class="text-gray-400 hover:text-gray-600">
              &larr; Boards
            </.link>
            <h1 class="font-semibold text-gray-900">{@prd.title || "Untitled"}</h1>
            <span
              :if={@prd.status}
              class="text-xs px-2 py-0.5 rounded-full bg-gray-100 text-gray-600"
            >
              {@prd.status}
            </span>
            <span :if={@dirty} class="text-xs text-amber-600 font-medium">Unsaved changes</span>
          </div>
          <div class="flex items-center gap-2">
            <p :if={@save_message} class="text-sm text-green-600">{@save_message}</p>
            <button
              phx-click="save"
              class="bg-blue-600 text-white px-3 py-1.5 rounded text-sm hover:bg-blue-700"
            >
              Save
            </button>
          </div>
        </div>

        <%!-- Flash message --%>
        <div
          :if={@flash_message}
          class="bg-amber-50 border-b border-amber-200 px-4 py-2 flex items-center justify-between"
        >
          <p class="text-sm text-amber-700">{@flash_message}</p>
          <button phx-click="dismiss_flash" class="text-amber-400 hover:text-amber-600 text-sm">
            Dismiss
          </button>
        </div>

        <%!-- Main content --%>
        <div class="flex-1 flex overflow-hidden">
          <%!-- Left sidebar: Element palette --%>
          <div class="w-48 bg-white border-r border-gray-200 p-3 shrink-0 overflow-y-auto">
            <h2 class="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-2">
              Add Element
            </h2>
            <div class="space-y-1">
              <button
                :for={
                  {type, label, color} <- [
                    {:event, "Event", "bg-orange-500"},
                    {:command, "Command", "bg-blue-500"},
                    {:view, "View", "bg-green-500"},
                    {:trigger, "Wireframe", "bg-gray-400"},
                    {:automation, "Automation", "bg-purple-500"}
                  ]
                }
                phx-click="select_palette"
                phx-value-type={type}
                class={[
                  "w-full text-left px-3 py-2 rounded text-sm flex items-center gap-2",
                  if(@palette_type == type,
                    do: "bg-gray-100 ring-2 ring-blue-500",
                    else: "hover:bg-gray-50"
                  )
                ]}
              >
                <span class={"w-3 h-3 rounded-sm #{color}"}></span>
                {label}
              </button>
            </div>

            <button
              :if={@palette_type}
              phx-click="clear_palette"
              class="mt-2 w-full text-xs text-gray-400 hover:text-gray-600"
            >
              Cancel placement
            </button>

            <div class="mt-6 text-xs text-gray-400 space-y-1">
              <p>Click canvas to place</p>
              <p>Shift+click to connect</p>
              <p>Double-click to edit</p>
              <p>Delete to remove</p>
            </div>
          </div>

          <%!-- SVG Canvas --%>
          <div
            class="flex-1 overflow-auto p-4"
            phx-click={if(@palette_type, do: "place_element")}
            phx-value-x="100"
            phx-value-y="100"
          >
            <svg
              id="event-modeler-canvas"
              phx-hook="EventModelerCanvas"
              viewBox={@svg_data.viewbox}
              width={@svg_data.width}
              height={@svg_data.height}
              class={[
                "border border-gray-200 rounded bg-white",
                if(@palette_type, do: "cursor-crosshair", else: "")
              ]}
              xmlns="http://www.w3.org/2000/svg"
            >
              <defs>
                <marker
                  id="arrowhead"
                  markerWidth="10"
                  markerHeight="7"
                  refX="10"
                  refY="3.5"
                  orient="auto"
                >
                  <polygon points="0 0, 10 3.5, 0 7" fill="#6B7280" />
                </marker>
              </defs>

              <%!-- Swimlane backgrounds --%>
              <rect
                :for={sl <- @svg_data.swimlanes}
                x="0"
                y={sl.y}
                width={sl.width}
                height={sl.height}
                fill="#F9FAFB"
                stroke="#E5E7EB"
                stroke-width="1"
              />

              <%!-- Swimlane labels --%>
              <text
                :for={sl <- @svg_data.swimlanes}
                x="10"
                y={sl.y + div(sl.height, 2) + 4}
                font-size="12"
                font-weight="600"
                fill="#6B7280"
              >
                {sl.name}
              </text>

              <%!-- Connection arrows --%>
              <path
                :for={conn <- @svg_data.connections}
                d={conn.path}
                fill="none"
                stroke="#9CA3AF"
                stroke-width="2"
                marker-end="url(#arrowhead)"
              />

              <%!-- Elements --%>
              <g
                :for={elem <- @svg_data.elements}
                data-element-id={elem.id}
                data-selected={to_string(@selected_element == elem.id)}
                phx-click="element_selected"
                phx-value-element_id={elem.id}
                class="cursor-pointer"
              >
                <rect
                  x={elem.x}
                  y={elem.y}
                  width={elem.width}
                  height={elem.height}
                  rx={elem.rx}
                  fill={elem.fill}
                  stroke={
                    cond do
                      elem.id in @slice_selection -> "#7C3AED"
                      @selected_element == elem.id -> "#1D4ED8"
                      true -> elem.stroke
                    end
                  }
                  stroke-width={
                    cond do
                      elem.id in @slice_selection -> "3"
                      @selected_element == elem.id -> "3"
                      true -> "2"
                    end
                  }
                  stroke-dasharray={if(elem.id in @slice_selection, do: "6 3", else: nil)}
                />
                <text
                  x={elem.x + div(elem.width, 2)}
                  y={elem.y + div(elem.height, 2) - 4}
                  text-anchor="middle"
                  font-size="12"
                  font-weight="600"
                  fill={elem.text_color}
                >
                  {elem.label}
                </text>
                <text
                  x={elem.x + div(elem.width, 2)}
                  y={elem.y + div(elem.height, 2) + 12}
                  text-anchor="middle"
                  font-size="10"
                  fill={elem.text_color}
                  opacity="0.8"
                >
                  {type_label(elem.type)}
                </text>
              </g>

              <%!-- Slice labels --%>
              <text
                :for={sl <- @svg_data.slice_labels}
                x={sl.x + div(sl.width, 2)}
                y="20"
                text-anchor="middle"
                font-size="11"
                font-weight="500"
                fill="#6B7280"
              >
                {sl.name}
              </text>
            </svg>
          </div>

          <%!-- Right sidebar --%>
          <div class="w-64 bg-white border-l border-gray-200 p-4 overflow-y-auto shrink-0">
            <%!-- Define Slice mode --%>
            <div :if={@defining_slice} class="mb-4 bg-blue-50 border border-blue-200 rounded p-3">
              <h3 class="text-xs font-semibold text-blue-700 mb-2">Define New Slice</h3>
              <form phx-change="set_slice_name">
                <input
                  type="text"
                  name="name"
                  placeholder="Slice name"
                  value={@new_slice_name}
                  class="w-full text-sm border border-blue-300 rounded px-2 py-1 mb-2"
                />
              </form>
              <p class="text-xs text-blue-600 mb-2">
                Click elements on the canvas to select them.
                Selected: {length(@slice_selection)}
              </p>
              <div class="flex gap-2">
                <button
                  phx-click="confirm_define_slice"
                  class="flex-1 bg-blue-600 text-white px-2 py-1 rounded text-xs"
                >
                  Create
                </button>
                <button
                  phx-click="cancel_define_slice"
                  class="flex-1 bg-gray-200 text-gray-700 px-2 py-1 rounded text-xs"
                >
                  Cancel
                </button>
              </div>
            </div>

            <%!-- Slices list --%>
            <div class="flex items-center justify-between mb-3">
              <h2 class="text-sm font-semibold text-gray-700">Slices</h2>
              <button
                :if={!@defining_slice}
                phx-click="start_define_slice"
                class="text-xs text-blue-600 hover:text-blue-800"
              >
                + Define
              </button>
            </div>

            <div :if={@slice_names == []} class="text-sm text-gray-400 mb-4">No slices defined.</div>

            <ul class="space-y-1 mb-4">
              <li
                :for={name <- @slice_names}
                phx-click="select_slice"
                phx-value-name={name}
                class={[
                  "text-sm text-gray-600 flex items-center gap-2 px-2 py-1 rounded cursor-pointer",
                  if(@selected_slice == name,
                    do: "bg-blue-50 ring-1 ring-blue-200",
                    else: "hover:bg-gray-50"
                  )
                ]}
              >
                <span class="w-2 h-2 bg-blue-500 rounded-full shrink-0"></span>
                <span class="truncate">{name}</span>
              </li>
            </ul>

            <%!-- Selected slice details --%>
            <div :if={@selected_slice} class="mb-4">
              <% slice = Enum.find(@slices, &(&1.name == @selected_slice)) %>
              <div :if={slice} class="bg-gray-50 rounded p-3">
                <div class="flex items-center justify-between mb-2">
                  <h3 class="text-xs font-semibold text-gray-700">{slice.name}</h3>
                  <span class="text-xs text-gray-400">{length(slice.steps)} elements</span>
                </div>

                <button
                  phx-click="generate_scenarios"
                  phx-value-slice={slice.name}
                  class="w-full bg-green-600 text-white px-2 py-1 rounded text-xs mb-2 hover:bg-green-700"
                >
                  Generate Scenarios
                </button>

                <%!-- Scenarios list --%>
                <div :if={slice.tests != nil and slice.tests != []}>
                  <h4 class="text-xs font-semibold text-gray-500 mb-1">Scenarios</h4>
                  <div
                    :for={scenario <- slice.tests}
                    class="text-xs bg-white rounded p-2 mb-1 border border-gray-200"
                  >
                    <p class="font-medium text-gray-700">{scenario.name}</p>
                    <div :if={scenario.given != []} class="mt-1">
                      <span class="text-gray-400">Given:</span>
                      <span :for={g <- scenario.given} class="ml-1 text-orange-600">{g.label}</span>
                    </div>
                    <div class="mt-0.5">
                      <span class="text-gray-400">When:</span>
                      <span :for={w <- scenario.when_clause} class="ml-1 text-blue-600">
                        {w.label}
                      </span>
                    </div>
                    <div :if={scenario.then_clause != []} class="mt-0.5">
                      <span class="text-gray-400">Then:</span>
                      <span :for={t <- scenario.then_clause} class="ml-1 text-green-600">
                        {t.label}
                      </span>
                    </div>
                  </div>
                </div>

                <div :if={slice.tests == nil or slice.tests == []}>
                  <p class="text-xs text-gray-400 italic">No scenarios yet.</p>
                </div>
              </div>
            </div>

            <%!-- Inline label editor --%>
            <div :if={@editing_element} class="mt-4 bg-gray-50 rounded p-3">
              <h3 class="text-xs font-semibold text-gray-500 mb-2">Edit Label</h3>
              <form phx-submit="edit_label">
                <input type="hidden" name="element_id" value={@editing_element} />
                <input
                  type="text"
                  name="label"
                  class="w-full text-sm border border-gray-300 rounded px-2 py-1"
                  autofocus
                />
                <button
                  type="submit"
                  class="mt-2 w-full bg-blue-600 text-white px-2 py-1 rounded text-sm"
                >
                  Update
                </button>
              </form>
            </div>

            <div :if={@prd.overview} class="mt-6">
              <h2 class="text-sm font-semibold text-gray-700 mb-2">Overview</h2>
              <p class="text-xs text-gray-500">{String.slice(@prd.overview || "", 0..200)}</p>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp type_label(:command), do: "Command"
  defp type_label(:event), do: "Event"
  defp type_label(:view), do: "View"
  defp type_label(:trigger), do: "Trigger"
  defp type_label(:exception), do: "Exception"
  defp type_label(:automation), do: "Automation"
  defp type_label(_), do: ""
end
