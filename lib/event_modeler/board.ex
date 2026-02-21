defmodule EventModeler.Board do
  @moduledoc """
  GenServer managing an open board backed by a PRD file.

  Each open board has its own GenServer process, started via DynamicSupervisor
  and registered via Registry keyed by file path.
  """

  use GenServer

  alias EventModeler.Prd
  alias EventModeler.Prd.{Element, Slice, EventStreamWriter}
  alias EventModeler.Canvas.{Layout, HtmlRenderer, ConnectionRules}
  alias EventModeler.Workshop.ScenarioGenerator
  alias EventModeler.Workspace

  defstruct [:file_path, :prd, :layout, :canvas_data, dirty: false, connections: []]

  @type t :: %__MODULE__{
          file_path: String.t(),
          prd: Prd.t(),
          layout: map(),
          canvas_data: map(),
          dirty: boolean(),
          connections: [{String.t(), String.t()}]
        }

  @inactivity_timeout :timer.minutes(30)

  # Client API

  @doc """
  Opens a board for the given file path. Starts a new GenServer if not already running.
  """
  @spec open(String.t()) :: {:ok, pid()} | {:error, term()}
  def open(file_path) do
    case Registry.lookup(EventModeler.Board.Registry, file_path) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        DynamicSupervisor.start_child(
          EventModeler.Board.Supervisor,
          {__MODULE__, file_path}
        )
    end
  rescue
    ArgumentError -> {:error, :registry_unavailable}
  end

  @spec get_state(String.t()) :: {:ok, t()} | {:error, term()}
  def get_state(file_path), do: call(file_path, :get_state)

  @spec save(String.t()) :: :ok | {:error, term()}
  def save(file_path), do: call(file_path, :save)

  @spec place_element(String.t(), atom(), String.t(), String.t() | nil) ::
          {:ok, String.t()} | {:error, term()}
  def place_element(file_path, type, label, swimlane \\ nil) do
    call(file_path, {:place_element, type, label, swimlane})
  end

  @spec move_element(String.t(), String.t(), number(), number()) :: :ok | {:error, term()}
  def move_element(file_path, element_id, x, y) do
    call(file_path, {:move_element, element_id, x, y})
  end

  @spec edit_element(String.t(), String.t(), map()) :: :ok | {:error, term()}
  def edit_element(file_path, element_id, changes) do
    call(file_path, {:edit_element, element_id, changes})
  end

  @spec connect_elements(String.t(), String.t(), String.t()) :: :ok | {:error, String.t()}
  def connect_elements(file_path, from_id, to_id) do
    call(file_path, {:connect_elements, from_id, to_id})
  end

  @spec remove_element(String.t(), String.t()) :: :ok | {:error, term()}
  def remove_element(file_path, element_id) do
    call(file_path, {:remove_element, element_id})
  end

  @spec define_slice(String.t(), String.t(), [String.t()]) :: :ok | {:error, term()}
  def define_slice(file_path, name, element_ids) do
    call(file_path, {:define_slice, name, element_ids})
  end

  @spec rename_slice(String.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def rename_slice(file_path, old_name, new_name) do
    call(file_path, {:rename_slice, old_name, new_name})
  end

  @spec generate_scenarios(String.t(), String.t()) :: {:ok, [map()]} | {:error, term()}
  def generate_scenarios(file_path, slice_name) do
    call(file_path, {:generate_scenarios, slice_name})
  end

  defp call(file_path, message) do
    case Registry.lookup(EventModeler.Board.Registry, file_path) do
      [{pid, _}] -> GenServer.call(pid, message)
      [] -> {:error, :not_open}
    end
  rescue
    ArgumentError -> {:error, :not_open}
  end

  # Server

  def start_link(file_path) do
    GenServer.start_link(__MODULE__, file_path,
      name: {:via, Registry, {EventModeler.Board.Registry, file_path}}
    )
  end

  @impl true
  def init(file_path) do
    case Workspace.read_prd(file_path) do
      {:ok, prd} ->
        connections = extract_connections(prd.event_stream)

        state =
          recompute_layout(%__MODULE__{
            file_path: file_path,
            prd: prd,
            dirty: false,
            connections: connections
          })

        {:ok, state, @inactivity_timeout}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, state, @inactivity_timeout}
  end

  def handle_call(:save, _from, state) do
    case Workspace.write_prd(state.file_path, state.prd) do
      :ok -> {:reply, :ok, %{state | dirty: false}, @inactivity_timeout}
      {:error, _} = error -> {:reply, error, state, @inactivity_timeout}
    end
  end

  def handle_call({:place_element, type, label, swimlane}, _from, state) do
    element = %Element{
      id: generate_id(),
      type: type,
      label: label,
      swimlane: swimlane,
      props: %{}
    }

    # Add element to the first slice, or create a default "Unassigned" slice
    prd = add_element_to_prd(state.prd, element)

    prd =
      EventStreamWriter.append(prd, "ElementAdded", "user", %{
        "elementId" => element.id,
        "type" => to_string(type),
        "label" => label
      })

    state =
      %{state | prd: prd, dirty: true}
      |> recompute_layout()

    {:reply, {:ok, element.id}, state, @inactivity_timeout}
  end

  def handle_call({:move_element, element_id, _x, _y}, _from, state) do
    # Position tracking is handled by the layout engine, not stored in PRD
    # Just record the event
    prd =
      EventStreamWriter.append(state.prd, "ElementMoved", "user", %{
        "elementId" => element_id
      })

    state = %{state | prd: prd, dirty: true}
    {:reply, :ok, state, @inactivity_timeout}
  end

  def handle_call({:edit_element, element_id, changes}, _from, state) do
    prd = update_element_in_prd(state.prd, element_id, changes)

    prd =
      EventStreamWriter.append(prd, "ElementModified", "user", %{
        "elementId" => element_id,
        "changes" => inspect(changes)
      })

    state =
      %{state | prd: prd, dirty: true}
      |> recompute_layout()

    {:reply, :ok, state, @inactivity_timeout}
  end

  def handle_call({:connect_elements, from_id, to_id}, _from, state) do
    cond do
      from_id == to_id ->
        {:reply, {:error, "Cannot connect an element to itself"}, state, @inactivity_timeout}

      {from_id, to_id} in state.connections ->
        {:reply, {:error, "These elements are already connected"}, state, @inactivity_timeout}

      true ->
        from_elem = find_element(state.prd, from_id)
        to_elem = find_element(state.prd, to_id)

        cond do
          is_nil(from_elem) ->
            {:reply, {:error, "Source element not found"}, state, @inactivity_timeout}

          is_nil(to_elem) ->
            {:reply, {:error, "Target element not found"}, state, @inactivity_timeout}

          true ->
            case ConnectionRules.rejection_reason(from_elem.type, to_elem.type) do
              nil ->
                prd =
                  EventStreamWriter.append(state.prd, "ElementsConnected", "user", %{
                    "fromId" => from_id,
                    "toId" => to_id
                  })

                connections = [{from_id, to_id} | state.connections]
                state = %{state | prd: prd, dirty: true, connections: connections}
                {:reply, :ok, state, @inactivity_timeout}

              reason ->
                {:reply, {:error, reason}, state, @inactivity_timeout}
            end
        end
    end
  end

  def handle_call({:remove_element, element_id}, _from, state) do
    prd = remove_element_from_prd(state.prd, element_id)

    prd =
      EventStreamWriter.append(prd, "ElementRemoved", "user", %{
        "elementId" => element_id
      })

    connections =
      Enum.reject(state.connections, fn {from, to} ->
        from == element_id or to == element_id
      end)

    state =
      %{state | prd: prd, dirty: true, connections: connections}
      |> recompute_layout()

    {:reply, :ok, state, @inactivity_timeout}
  end

  def handle_call({:define_slice, name, element_ids}, _from, state) do
    # Collect elements matching the given IDs
    all_elements = Enum.flat_map(state.prd.slices, & &1.steps)
    selected = Enum.filter(all_elements, &(&1.id in element_ids))

    if selected == [] do
      {:reply, {:error, "No matching elements found"}, state, @inactivity_timeout}
    else
      # Create new slice, remove elements from their current slices
      new_slice = %Slice{name: name, steps: selected, tests: []}

      updated_slices =
        state.prd.slices
        |> Enum.map(fn slice ->
          %{slice | steps: Enum.reject(slice.steps, &(&1.id in element_ids))}
        end)
        |> Enum.reject(fn s -> s.steps == [] and s.name == "Unassigned" end)

      prd = %{state.prd | slices: updated_slices ++ [new_slice]}

      prd =
        EventStreamWriter.append(prd, "SliceAdded", "user", %{
          "sliceName" => name,
          "elementCount" => length(selected)
        })

      state =
        %{state | prd: prd, dirty: true}
        |> recompute_layout()

      {:reply, :ok, state, @inactivity_timeout}
    end
  end

  def handle_call({:rename_slice, old_name, new_name}, _from, state) do
    updated_slices =
      Enum.map(state.prd.slices, fn slice ->
        if slice.name == old_name, do: %{slice | name: new_name}, else: slice
      end)

    prd = %{state.prd | slices: updated_slices}

    prd =
      EventStreamWriter.append(prd, "SliceRenamed", "user", %{
        "oldName" => old_name,
        "newName" => new_name
      })

    state = %{state | prd: prd, dirty: true}
    {:reply, :ok, state, @inactivity_timeout}
  end

  def handle_call({:generate_scenarios, slice_name}, _from, state) do
    case Enum.find(state.prd.slices, &(&1.name == slice_name)) do
      nil ->
        {:reply, {:error, "Slice not found"}, state, @inactivity_timeout}

      slice ->
        scenarios = ScenarioGenerator.generate(slice)

        updated_slices =
          Enum.map(state.prd.slices, fn s ->
            if s.name == slice_name, do: %{s | tests: scenarios}, else: s
          end)

        prd = %{state.prd | slices: updated_slices}

        prd =
          EventStreamWriter.append(prd, "ScenarioAdded", "user", %{
            "sliceName" => slice_name,
            "count" => length(scenarios)
          })

        state =
          %{state | prd: prd, dirty: true}
          |> recompute_layout()

        {:reply, {:ok, scenarios}, state, @inactivity_timeout}
    end
  end

  @impl true
  def handle_info(:timeout, state) do
    {:stop, :normal, state}
  end

  # Private helpers

  defp recompute_layout(state) do
    layout = Layout.compute(state.prd)
    canvas_data = HtmlRenderer.render(layout)
    %{state | layout: layout, canvas_data: canvas_data}
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end

  defp add_element_to_prd(%Prd{slices: slices} = prd, element) do
    case slices do
      [] ->
        # Create a default slice
        slice = %Prd.Slice{name: "Unassigned", steps: [element]}
        %{prd | slices: [slice]}

      [first | rest] ->
        # Add to the first slice
        updated = %{first | steps: first.steps ++ [element]}
        %{prd | slices: [updated | rest]}
    end
  end

  defp update_element_in_prd(%Prd{slices: slices} = prd, element_id, changes) do
    updated_slices =
      Enum.map(slices, fn slice ->
        updated_steps =
          Enum.map(slice.steps, fn step ->
            if step.id == element_id do
              step
              |> maybe_update(:label, changes["label"])
              |> maybe_update(:swimlane, changes["swimlane"])
              |> maybe_update_props(changes["props"])
            else
              step
            end
          end)

        %{slice | steps: updated_steps}
      end)

    %{prd | slices: updated_slices}
  end

  defp maybe_update(struct, _key, nil), do: struct
  defp maybe_update(struct, key, value), do: Map.put(struct, key, value)

  defp maybe_update_props(struct, nil), do: struct
  defp maybe_update_props(struct, props), do: %{struct | props: Map.merge(struct.props, props)}

  defp remove_element_from_prd(%Prd{slices: slices} = prd, element_id) do
    updated_slices =
      slices
      |> Enum.map(fn slice ->
        %{slice | steps: Enum.reject(slice.steps, &(&1.id == element_id))}
      end)
      |> Enum.reject(fn slice -> slice.steps == [] and slice.name == "Unassigned" end)

    %{prd | slices: updated_slices}
  end

  defp find_element(%Prd{slices: slices}, element_id) do
    Enum.find_value(slices, fn slice ->
      Enum.find(slice.steps, &(&1.id == element_id))
    end)
  end

  defp extract_connections(event_stream) do
    event_stream
    |> Enum.filter(fn entry -> entry.type == "ElementsConnected" end)
    |> Enum.map(fn entry -> {entry.data["fromId"], entry.data["toId"]} end)
  end
end
