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
                   save_message: nil,
                   error: nil
                 )}

              {:error, reason} ->
                {:ok, assign(socket, error: "Failed to load board: #{reason}")}
            end

          {:error, reason} ->
            {:ok, assign(socket, error: "Failed to open board: #{inspect(reason)}")}
        end

      :error ->
        {:ok, assign(socket, error: "Invalid board path")}
    end
  end

  @impl true
  def handle_event("save", _params, socket) do
    case Board.save(socket.assigns.file_path) do
      :ok ->
        {:noreply,
         assign(socket,
           dirty: false,
           save_message: "Saved successfully"
         )}

      {:error, reason} ->
        {:noreply, assign(socket, save_message: "Save failed: #{reason}")}
    end
  end

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
        <div class="bg-white border-b border-gray-200 px-4 py-3 flex items-center justify-between">
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
            <span :if={@dirty} class="text-xs text-amber-600 font-medium">
              Unsaved changes
            </span>
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

        <%!-- Main content --%>
        <div class="flex-1 flex overflow-hidden">
          <%!-- SVG Canvas --%>
          <div class="flex-1 overflow-auto p-4">
            <svg
              viewBox={@svg_data.viewbox}
              width={@svg_data.width}
              height={@svg_data.height}
              class="border border-gray-200 rounded bg-white"
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
              <g :for={elem <- @svg_data.elements}>
                <rect
                  x={elem.x}
                  y={elem.y}
                  width={elem.width}
                  height={elem.height}
                  rx={elem.rx}
                  fill={elem.fill}
                  stroke={elem.stroke}
                  stroke-width="2"
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

          <%!-- Sidebar --%>
          <div class="w-64 bg-white border-l border-gray-200 p-4 overflow-y-auto">
            <h2 class="text-sm font-semibold text-gray-700 mb-3">Slices</h2>
            <div :if={@slice_names == []} class="text-sm text-gray-400">
              No slices defined.
            </div>
            <ul class="space-y-1">
              <li :for={name <- @slice_names} class="text-sm text-gray-600 flex items-center gap-2">
                <span class="w-2 h-2 bg-blue-500 rounded-full"></span>
                {name}
              </li>
            </ul>

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
end
