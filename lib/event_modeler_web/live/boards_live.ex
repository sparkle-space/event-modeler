defmodule EventModelerWeb.BoardsLive do
  use EventModelerWeb, :live_view

  alias EventModeler.Workspace

  @impl true
  def mount(_params, _session, socket) do
    prds = Workspace.list_prds()

    {:ok,
     assign(socket,
       page_title: "Boards",
       prds: prds,
       new_title: "",
       create_error: nil
     )}
  end

  @impl true
  def handle_event("create_prd", %{"title" => title}, socket) do
    title = String.trim(title)

    if title == "" do
      {:noreply, assign(socket, create_error: "Title cannot be empty")}
    else
      case Workspace.create_prd(title) do
        {:ok, path} ->
          encoded = Base.url_encode64(path, padding: false)

          {:noreply,
           socket
           |> push_navigate(to: ~p"/boards/#{encoded}")}

        {:error, reason} ->
          {:noreply, assign(socket, create_error: reason)}
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <div class="max-w-4xl mx-auto px-4 py-6">
        <div class="flex items-center justify-between mb-6">
          <h1 class="text-2xl font-bold text-gray-900">Boards</h1>
        </div>

        <%!-- New PRD form --%>
        <div class="bg-white rounded-lg shadow p-4 mb-6">
          <h2 class="text-sm font-semibold text-gray-700 mb-2">Create New PRD</h2>
          <form phx-submit="create_prd" class="flex gap-2">
            <input
              type="text"
              name="title"
              value={@new_title}
              placeholder="Feature name..."
              class="flex-1 border border-gray-300 rounded px-3 py-2"
            />
            <button
              type="submit"
              class="bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700 font-medium"
            >
              New PRD
            </button>
          </form>
          <p :if={@create_error} class="text-sm text-red-600 mt-2">{@create_error}</p>
        </div>

        <%!-- PRD list --%>
        <div class="bg-white rounded-lg shadow">
          <div :if={@prds == []} class="p-8 text-center text-gray-400">
            No PRD files found. Create one to get started.
          </div>

          <ul :if={@prds != []} class="divide-y divide-gray-200">
            <li :for={prd <- @prds} class="hover:bg-gray-50">
              <.link
                navigate={~p"/boards/#{Base.url_encode64(prd.path, padding: false)}"}
                class="block px-4 py-3"
              >
                <div class="flex items-center justify-between">
                  <div>
                    <p class="font-medium text-gray-900">{prd.title}</p>
                    <p class="text-sm text-gray-500">{prd.filename}</p>
                  </div>
                  <span class={[
                    "text-xs px-2 py-0.5 rounded-full",
                    status_class(prd.status)
                  ]}>
                    {prd.status}
                  </span>
                </div>
              </.link>
            </li>
          </ul>
        </div>
      </div>
    </div>
    """
  end

  defp status_class("draft"), do: "bg-gray-100 text-gray-600"
  defp status_class("modeling"), do: "bg-blue-100 text-blue-700"
  defp status_class("refined"), do: "bg-green-100 text-green-700"
  defp status_class("approved"), do: "bg-purple-100 text-purple-700"
  defp status_class(_), do: "bg-gray-100 text-gray-600"
end
