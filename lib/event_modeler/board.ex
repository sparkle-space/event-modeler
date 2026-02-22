defmodule EventModeler.Board do
  @moduledoc """
  GenServer managing an open board backed by an Event Model file.

  Each open board has its own GenServer process, started via DynamicSupervisor
  and registered via Registry keyed by file path.
  """

  use GenServer

  alias EventModeler.EventModel
  alias EventModeler.EventModel.{Element, Slice, EventStreamWriter}
  alias EventModeler.Canvas.{Layout, HtmlRenderer, ConnectionRules}
  alias EventModeler.Workshop.ScenarioGenerator
  alias EventModeler.Workspace

  defstruct [:file_path, :event_model, :layout, :canvas_data, dirty: false, connections: []]

  @type t :: %__MODULE__{
          file_path: String.t(),
          event_model: EventModel.t(),
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

  @spec disconnect_elements(String.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def disconnect_elements(file_path, from_id, to_id) do
    call(file_path, {:disconnect_elements, from_id, to_id})
  end

  @spec remove_slice(String.t(), String.t()) :: :ok | {:error, term()}
  def remove_slice(file_path, slice_name) do
    call(file_path, {:remove_slice, slice_name})
  end

  @spec remove_element_from_slice(String.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def remove_element_from_slice(file_path, slice_name, element_id) do
    call(file_path, {:remove_element_from_slice, slice_name, element_id})
  end

  @spec remove_scenario(String.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def remove_scenario(file_path, slice_name, scenario_name) do
    call(file_path, {:remove_scenario, slice_name, scenario_name})
  end

  @spec update_scenario(String.t(), String.t(), String.t(), map()) :: :ok | {:error, term()}
  def update_scenario(file_path, slice_name, scenario_name, changes) do
    call(file_path, {:update_scenario, slice_name, scenario_name, changes})
  end

  @spec add_scenario(String.t(), String.t(), map()) :: :ok | {:error, term()}
  def add_scenario(file_path, slice_name, scenario) do
    call(file_path, {:add_scenario, slice_name, scenario})
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
    case Workspace.read_event_model(file_path) do
      {:ok, event_model} ->
        connections = extract_connections(event_model.event_stream)

        state =
          recompute_layout(%__MODULE__{
            file_path: file_path,
            event_model: event_model,
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
    case Workspace.write_event_model(state.file_path, state.event_model) do
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
    event_model = add_element_to_event_model(state.event_model, element)

    event_model =
      EventStreamWriter.append(event_model, "ElementAdded", "user", %{
        "elementId" => element.id,
        "type" => to_string(type),
        "label" => label
      })

    state =
      %{state | event_model: event_model, dirty: true}
      |> recompute_layout()

    {:reply, {:ok, element.id}, state, @inactivity_timeout}
  end

  def handle_call({:move_element, element_id, _x, _y}, _from, state) do
    # Position tracking is handled by the layout engine, not stored in Event Model
    # Just record the event
    event_model =
      EventStreamWriter.append(state.event_model, "ElementMoved", "user", %{
        "elementId" => element_id
      })

    state = %{state | event_model: event_model, dirty: true}
    {:reply, :ok, state, @inactivity_timeout}
  end

  def handle_call({:edit_element, element_id, changes}, _from, state) do
    event_model = update_element_in_event_model(state.event_model, element_id, changes)

    event_model =
      EventStreamWriter.append(event_model, "ElementModified", "user", %{
        "elementId" => element_id,
        "changes" => inspect(changes)
      })

    state =
      %{state | event_model: event_model, dirty: true}
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
        from_elem = find_element(state.event_model, from_id)
        to_elem = find_element(state.event_model, to_id)

        cond do
          is_nil(from_elem) ->
            {:reply, {:error, "Source element not found"}, state, @inactivity_timeout}

          is_nil(to_elem) ->
            {:reply, {:error, "Target element not found"}, state, @inactivity_timeout}

          true ->
            case ConnectionRules.rejection_reason(from_elem.type, to_elem.type) do
              nil ->
                event_model =
                  EventStreamWriter.append(state.event_model, "ElementsConnected", "user", %{
                    "fromId" => from_id,
                    "toId" => to_id
                  })

                connections = [{from_id, to_id} | state.connections]
                state = %{state | event_model: event_model, dirty: true, connections: connections}
                {:reply, :ok, state, @inactivity_timeout}

              reason ->
                {:reply, {:error, reason}, state, @inactivity_timeout}
            end
        end
    end
  end

  def handle_call({:remove_element, element_id}, _from, state) do
    event_model = remove_element_from_event_model(state.event_model, element_id)

    event_model =
      EventStreamWriter.append(event_model, "ElementRemoved", "user", %{
        "elementId" => element_id
      })

    connections =
      Enum.reject(state.connections, fn {from, to} ->
        from == element_id or to == element_id
      end)

    state =
      %{state | event_model: event_model, dirty: true, connections: connections}
      |> recompute_layout()

    {:reply, :ok, state, @inactivity_timeout}
  end

  def handle_call({:define_slice, name, element_ids}, _from, state) do
    # Collect elements matching the given IDs
    all_elements = Enum.flat_map(state.event_model.slices, & &1.steps)
    selected = Enum.filter(all_elements, &(&1.id in element_ids))

    if selected == [] do
      {:reply, {:error, "No matching elements found"}, state, @inactivity_timeout}
    else
      # Create new slice, remove elements from their current slices
      new_slice = %Slice{name: name, steps: selected, tests: []}

      updated_slices =
        state.event_model.slices
        |> Enum.map(fn slice ->
          %{slice | steps: Enum.reject(slice.steps, &(&1.id in element_ids))}
        end)
        |> Enum.reject(fn s -> s.steps == [] and s.name == "Unassigned" end)

      event_model = %{state.event_model | slices: updated_slices ++ [new_slice]}

      event_model =
        EventStreamWriter.append(event_model, "SliceAdded", "user", %{
          "sliceName" => name,
          "elementCount" => length(selected)
        })

      state =
        %{state | event_model: event_model, dirty: true}
        |> recompute_layout()

      {:reply, :ok, state, @inactivity_timeout}
    end
  end

  def handle_call({:rename_slice, old_name, new_name}, _from, state) do
    updated_slices =
      Enum.map(state.event_model.slices, fn slice ->
        if slice.name == old_name, do: %{slice | name: new_name}, else: slice
      end)

    event_model = %{state.event_model | slices: updated_slices}

    event_model =
      EventStreamWriter.append(event_model, "SliceRenamed", "user", %{
        "oldName" => old_name,
        "newName" => new_name
      })

    state = %{state | event_model: event_model, dirty: true}
    {:reply, :ok, state, @inactivity_timeout}
  end

  def handle_call({:generate_scenarios, slice_name}, _from, state) do
    case Enum.find(state.event_model.slices, &(&1.name == slice_name)) do
      nil ->
        {:reply, {:error, "Slice not found"}, state, @inactivity_timeout}

      slice ->
        scenarios = ScenarioGenerator.generate(slice)

        updated_slices =
          Enum.map(state.event_model.slices, fn s ->
            if s.name == slice_name, do: %{s | tests: scenarios}, else: s
          end)

        event_model = %{state.event_model | slices: updated_slices}

        event_model =
          EventStreamWriter.append(event_model, "ScenarioAdded", "user", %{
            "sliceName" => slice_name,
            "count" => length(scenarios)
          })

        state =
          %{state | event_model: event_model, dirty: true}
          |> recompute_layout()

        {:reply, {:ok, scenarios}, state, @inactivity_timeout}
    end
  end

  def handle_call({:disconnect_elements, from_id, to_id}, _from, state) do
    if {from_id, to_id} in state.connections do
      connections = List.delete(state.connections, {from_id, to_id})

      event_model =
        EventStreamWriter.append(state.event_model, "ElementsDisconnected", "user", %{
          "fromId" => from_id,
          "toId" => to_id
        })

      state =
        %{state | event_model: event_model, dirty: true, connections: connections}
        |> recompute_layout()

      {:reply, :ok, state, @inactivity_timeout}
    else
      {:reply, {:error, "Connection not found"}, state, @inactivity_timeout}
    end
  end

  def handle_call({:remove_slice, slice_name}, _from, state) do
    case Enum.find(state.event_model.slices, &(&1.name == slice_name)) do
      nil ->
        {:reply, {:error, "Slice not found"}, state, @inactivity_timeout}

      slice ->
        elements = slice.steps
        remaining = Enum.reject(state.event_model.slices, &(&1.name == slice_name))

        # Move elements to Unassigned slice
        updated_slices =
          if elements != [] do
            case Enum.find(remaining, &(&1.name == "Unassigned")) do
              nil ->
                remaining ++ [%Slice{name: "Unassigned", steps: elements, tests: []}]

              _unassigned ->
                Enum.map(remaining, fn s ->
                  if s.name == "Unassigned",
                    do: %{s | steps: s.steps ++ elements},
                    else: s
                end)
            end
          else
            remaining
          end

        event_model = %{state.event_model | slices: updated_slices}

        event_model =
          EventStreamWriter.append(event_model, "SliceRemoved", "user", %{
            "sliceName" => slice_name,
            "elementCount" => length(elements)
          })

        state =
          %{state | event_model: event_model, dirty: true}
          |> recompute_layout()

        {:reply, :ok, state, @inactivity_timeout}
    end
  end

  def handle_call({:remove_element_from_slice, slice_name, element_id}, _from, state) do
    case Enum.find(state.event_model.slices, &(&1.name == slice_name)) do
      nil ->
        {:reply, {:error, "Slice not found"}, state, @inactivity_timeout}

      slice ->
        element = Enum.find(slice.steps, &(&1.id == element_id))

        if element do
          # Remove from source slice
          updated_source = %{slice | steps: Enum.reject(slice.steps, &(&1.id == element_id))}

          updated_slices =
            Enum.map(state.event_model.slices, fn s ->
              if s.name == slice_name, do: updated_source, else: s
            end)

          # Add to Unassigned slice
          updated_slices =
            case Enum.find(updated_slices, &(&1.name == "Unassigned")) do
              nil ->
                updated_slices ++ [%Slice{name: "Unassigned", steps: [element], tests: []}]

              _unassigned ->
                Enum.map(updated_slices, fn s ->
                  if s.name == "Unassigned",
                    do: %{s | steps: s.steps ++ [element]},
                    else: s
                end)
            end

          # Remove empty source slice (unless it's Unassigned)
          updated_slices =
            Enum.reject(updated_slices, fn s ->
              s.steps == [] and s.name != "Unassigned" and s.name == slice_name
            end)

          event_model = %{state.event_model | slices: updated_slices}

          event_model =
            EventStreamWriter.append(event_model, "ElementRemovedFromSlice", "user", %{
              "sliceName" => slice_name,
              "elementId" => element_id
            })

          state =
            %{state | event_model: event_model, dirty: true}
            |> recompute_layout()

          {:reply, :ok, state, @inactivity_timeout}
        else
          {:reply, {:error, "Element not found in slice"}, state, @inactivity_timeout}
        end
    end
  end

  def handle_call({:remove_scenario, slice_name, scenario_name}, _from, state) do
    case Enum.find(state.event_model.slices, &(&1.name == slice_name)) do
      nil ->
        {:reply, {:error, "Slice not found"}, state, @inactivity_timeout}

      slice ->
        tests = slice.tests || []
        updated_tests = Enum.reject(tests, &(&1.name == scenario_name))

        if length(updated_tests) == length(tests) do
          {:reply, {:error, "Scenario not found"}, state, @inactivity_timeout}
        else
          updated_slices =
            Enum.map(state.event_model.slices, fn s ->
              if s.name == slice_name, do: %{s | tests: updated_tests}, else: s
            end)

          event_model = %{state.event_model | slices: updated_slices}

          event_model =
            EventStreamWriter.append(event_model, "ScenarioRemoved", "user", %{
              "sliceName" => slice_name,
              "scenarioName" => scenario_name
            })

          state = %{state | event_model: event_model, dirty: true}
          {:reply, :ok, state, @inactivity_timeout}
        end
    end
  end

  def handle_call({:update_scenario, slice_name, scenario_name, changes}, _from, state) do
    case Enum.find(state.event_model.slices, &(&1.name == slice_name)) do
      nil ->
        {:reply, {:error, "Slice not found"}, state, @inactivity_timeout}

      slice ->
        tests = slice.tests || []

        case Enum.find_index(tests, &(&1.name == scenario_name)) do
          nil ->
            {:reply, {:error, "Scenario not found"}, state, @inactivity_timeout}

          idx ->
            updated_scenario =
              Enum.at(tests, idx)
              |> maybe_update_scenario(:name, changes["name"])
              |> maybe_update_scenario(:given, changes["given"])
              |> maybe_update_scenario(:when_clause, changes["when_clause"])
              |> maybe_update_scenario(:then_clause, changes["then_clause"])
              |> Map.put(:auto_generated, false)

            updated_tests = List.replace_at(tests, idx, updated_scenario)

            updated_slices =
              Enum.map(state.event_model.slices, fn s ->
                if s.name == slice_name, do: %{s | tests: updated_tests}, else: s
              end)

            event_model = %{state.event_model | slices: updated_slices}

            event_model =
              EventStreamWriter.append(event_model, "ScenarioModified", "user", %{
                "sliceName" => slice_name,
                "scenarioName" => scenario_name
              })

            state = %{state | event_model: event_model, dirty: true}
            {:reply, :ok, state, @inactivity_timeout}
        end
    end
  end

  def handle_call({:add_scenario, slice_name, scenario}, _from, state) do
    case Enum.find(state.event_model.slices, &(&1.name == slice_name)) do
      nil ->
        {:reply, {:error, "Slice not found"}, state, @inactivity_timeout}

      slice ->
        new_scenario = %{
          name: scenario["name"] || "NewScenario",
          given: scenario["given"] || [],
          when_clause: scenario["when_clause"] || [],
          then_clause: scenario["then_clause"] || [],
          auto_generated: false
        }

        updated_tests = (slice.tests || []) ++ [new_scenario]

        updated_slices =
          Enum.map(state.event_model.slices, fn s ->
            if s.name == slice_name, do: %{s | tests: updated_tests}, else: s
          end)

        event_model = %{state.event_model | slices: updated_slices}

        event_model =
          EventStreamWriter.append(event_model, "ScenarioAdded", "user", %{
            "sliceName" => slice_name,
            "scenarioName" => new_scenario.name
          })

        state = %{state | event_model: event_model, dirty: true}
        {:reply, :ok, state, @inactivity_timeout}
    end
  end

  @impl true
  def handle_info(:timeout, state) do
    {:stop, :normal, state}
  end

  # Private helpers

  defp recompute_layout(state) do
    layout = Layout.compute(state.event_model)
    canvas_data = HtmlRenderer.render(layout)
    %{state | layout: layout, canvas_data: canvas_data}
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end

  defp add_element_to_event_model(%EventModel{slices: slices} = event_model, element) do
    case slices do
      [] ->
        # Create a default slice
        slice = %Slice{name: "Unassigned", steps: [element]}
        %{event_model | slices: [slice]}

      [first | rest] ->
        # Add to the first slice
        updated = %{first | steps: first.steps ++ [element]}
        %{event_model | slices: [updated | rest]}
    end
  end

  defp update_element_in_event_model(
         %EventModel{slices: slices} = event_model,
         element_id,
         changes
       ) do
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

    %{event_model | slices: updated_slices}
  end

  defp maybe_update(struct, _key, nil), do: struct
  defp maybe_update(struct, key, value), do: Map.put(struct, key, value)

  defp maybe_update_props(struct, nil), do: struct
  defp maybe_update_props(struct, props), do: %{struct | props: Map.merge(struct.props, props)}

  defp remove_element_from_event_model(%EventModel{slices: slices} = event_model, element_id) do
    updated_slices =
      slices
      |> Enum.map(fn slice ->
        %{slice | steps: Enum.reject(slice.steps, &(&1.id == element_id))}
      end)
      |> Enum.reject(fn slice -> slice.steps == [] and slice.name == "Unassigned" end)

    %{event_model | slices: updated_slices}
  end

  defp find_element(%EventModel{slices: slices}, element_id) do
    Enum.find_value(slices, fn slice ->
      Enum.find(slice.steps, &(&1.id == element_id))
    end)
  end

  defp extract_connections(event_stream) do
    connected =
      event_stream
      |> Enum.filter(fn entry -> entry.type == "ElementsConnected" end)
      |> Enum.map(fn entry -> {entry.data["fromId"], entry.data["toId"]} end)

    disconnected =
      event_stream
      |> Enum.filter(fn entry -> entry.type == "ElementsDisconnected" end)
      |> Enum.map(fn entry -> {entry.data["fromId"], entry.data["toId"]} end)

    connected -- disconnected
  end

  defp maybe_update_scenario(scenario, _key, nil), do: scenario
  defp maybe_update_scenario(scenario, key, value), do: Map.put(scenario, key, value)
end
