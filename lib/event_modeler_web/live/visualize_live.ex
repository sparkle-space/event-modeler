defmodule EventModelerWeb.VisualizeLive do
  use EventModelerWeb, :live_view

  alias EventModeler.EventModel.Parser
  alias EventModeler.Canvas.{Layout, SvgRenderer}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Event Model Visualizer",
       markdown_input: "",
       file_path_input: "",
       svg_data: nil,
       parse_error: nil,
       event_model_title: nil,
       event_model_status: nil,
       slice_names: []
     )}
  end

  @impl true
  def handle_event("visualize", %{"markdown" => markdown}, socket) do
    socket = visualize_markdown(socket, markdown)
    {:noreply, socket}
  end

  def handle_event("load_file", %{"path" => path}, socket) do
    path = String.trim(path)

    case File.read(path) do
      {:ok, content} ->
        socket =
          socket
          |> assign(:markdown_input, content)
          |> visualize_markdown(content)

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, assign(socket, parse_error: "Cannot read file: #{reason}", svg_data: nil)}
    end
  end

  def handle_event("update_markdown", %{"markdown" => markdown}, socket) do
    {:noreply, assign(socket, markdown_input: markdown)}
  end

  defp visualize_markdown(socket, markdown) do
    case Parser.parse(markdown) do
      {:ok, event_model} ->
        layout = Layout.compute(event_model)
        svg_data = SvgRenderer.render(layout)

        assign(socket,
          svg_data: svg_data,
          parse_error: nil,
          event_model_title: event_model.title,
          event_model_status: event_model.status,
          slice_names: Enum.map(event_model.slices, & &1.name),
          markdown_input: markdown
        )

      {:error, reason} ->
        assign(socket, parse_error: reason, svg_data: nil)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <div class="max-w-7xl mx-auto px-4 py-6">
        <h1 class="text-2xl font-bold text-gray-900 mb-6">Event Model Visualizer</h1>

        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <%!-- Input panel --%>
          <div class="lg:col-span-1 space-y-4">
            <%!-- File loader --%>
            <div class="bg-white rounded-lg shadow p-4">
              <h2 class="text-sm font-semibold text-gray-700 mb-2">Load from File</h2>
              <form phx-submit="load_file" class="flex gap-2">
                <input
                  type="text"
                  name="path"
                  value={@file_path_input}
                  placeholder="Path to .md file"
                  class="flex-1 text-sm border border-gray-300 rounded px-2 py-1"
                />
                <button
                  type="submit"
                  class="text-sm bg-blue-600 text-white px-3 py-1 rounded hover:bg-blue-700"
                >
                  Load
                </button>
              </form>
            </div>

            <%!-- Paste markdown --%>
            <div class="bg-white rounded-lg shadow p-4">
              <h2 class="text-sm font-semibold text-gray-700 mb-2">Paste Event Model Markdown</h2>
              <form phx-submit="visualize">
                <textarea
                  name="markdown"
                  phx-change="update_markdown"
                  rows="16"
                  class="w-full text-xs font-mono border border-gray-300 rounded p-2 resize-y"
                  placeholder="Paste your Event Model markdown here..."
                >{@markdown_input}</textarea>
                <button
                  type="submit"
                  class="mt-2 w-full bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700 font-medium"
                >
                  Visualize
                </button>
              </form>
            </div>

            <%!-- Slice legend --%>
            <div :if={@slice_names != []} class="bg-white rounded-lg shadow p-4">
              <h2 class="text-sm font-semibold text-gray-700 mb-2">Slices</h2>
              <ul class="space-y-1">
                <li :for={name <- @slice_names} class="text-sm text-gray-600 flex items-center gap-2">
                  <span class="w-2 h-2 bg-blue-500 rounded-full"></span>
                  {name}
                </li>
              </ul>
            </div>
          </div>

          <%!-- Canvas panel --%>
          <div class="lg:col-span-2">
            <div :if={@parse_error} class="bg-red-50 border border-red-200 rounded-lg p-4 mb-4">
              <p class="text-sm text-red-700">{@parse_error}</p>
            </div>

            <div :if={@svg_data} class="bg-white rounded-lg shadow">
              <%!-- Header --%>
              <div class="px-4 py-3 border-b border-gray-200 flex items-center gap-4">
                <h2 :if={@event_model_title} class="font-semibold text-gray-900">
                  {@event_model_title}
                </h2>
                <span
                  :if={@event_model_status}
                  class="text-xs px-2 py-0.5 rounded-full bg-gray-100 text-gray-600"
                >
                  {@event_model_status}
                </span>
              </div>

              <%!-- SVG Canvas --%>
              <div class="overflow-auto p-4" style="max-height: 70vh;">
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
                      refX="0"
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

                  <%!-- Slice connection arcs --%>
                  <path
                    :for={sc <- @svg_data.slice_connections}
                    d={sc.path}
                    fill="none"
                    stroke={if(sc.style == :dashed, do: "#9CA3AF", else: "#8B5CF6")}
                    stroke-width="1.5"
                    stroke-dasharray={if(sc.style == :dashed, do: "6,4", else: "none")}
                    opacity="0.6"
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

                  <%!-- Slice labels at top --%>
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
            </div>

            <div
              :if={is_nil(@svg_data) and is_nil(@parse_error)}
              class="bg-white rounded-lg shadow p-12 text-center"
            >
              <p class="text-gray-400 text-lg">
                Paste an Event Model or load a file to visualize it.
              </p>
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
  defp type_label(:wireframe), do: "Wireframe"
  defp type_label(:exception), do: "Exception"
end
