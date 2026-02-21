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
    <div class="min-h-screen bg-[var(--color-bg)]">
      <div class="max-w-4xl mx-auto px-4 py-6">
        <div class="flex items-center justify-between mb-6">
          <h1 class="text-2xl font-bold text-[var(--color-text-primary)]">Boards</h1>
          <Layouts.theme_toggle />
        </div>

        <%!-- New PRD form --%>
        <div class="bg-[var(--color-surface)] rounded-[var(--radius-card)] shadow-sm border border-[var(--color-border)] p-4 mb-6">
          <h2 class="text-sm font-semibold text-[var(--color-text-secondary)] mb-2">
            Create New PRD
          </h2>
          <form phx-submit="create_prd" class="flex gap-2">
            <input
              type="text"
              name="title"
              value={@new_title}
              placeholder="Feature name..."
              class="flex-1 border border-[var(--color-border)] rounded-[var(--radius-element)] px-3 py-2 bg-[var(--color-surface)] text-[var(--color-text-primary)] placeholder-[var(--color-text-secondary)]"
            />
            <button
              type="submit"
              class="bg-primary text-primary-content px-4 py-2 rounded-[var(--radius-element)] hover:opacity-90 transition-opacity font-medium"
            >
              New PRD
            </button>
          </form>
          <p :if={@create_error} class="text-sm text-error mt-2">{@create_error}</p>
        </div>

        <%!-- PRD list --%>
        <div class="bg-[var(--color-surface)] rounded-[var(--radius-card)] shadow-sm border border-[var(--color-border)]">
          <div :if={@prds == []} class="p-8 text-center text-[var(--color-text-secondary)]">
            No PRD files found. Create one to get started.
          </div>

          <ul :if={@prds != []} class="divide-y divide-[var(--color-border)]">
            <li :for={prd <- @prds} class="hover:bg-[var(--color-surface-alt)] transition-colors">
              <.link
                navigate={~p"/boards/#{Base.url_encode64(prd.path, padding: false)}"}
                class="block px-4 py-3"
              >
                <div class="flex items-center justify-between">
                  <div>
                    <p class="font-medium text-[var(--color-text-primary)]">{prd.title}</p>
                    <p class="text-sm text-[var(--color-text-secondary)]">{prd.filename}</p>
                  </div>
                  <span class={[
                    "text-xs px-2.5 py-0.5 rounded-full font-medium",
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

  defp status_class("draft"),
    do: "bg-[var(--color-surface-alt)] text-[var(--color-text-secondary)]"

  defp status_class("modeling"), do: "bg-info/10 text-info"
  defp status_class("refined"), do: "bg-success/10 text-success"
  defp status_class("approved"), do: "bg-primary/10 text-primary"
  defp status_class(_), do: "bg-[var(--color-surface-alt)] text-[var(--color-text-secondary)]"
end
