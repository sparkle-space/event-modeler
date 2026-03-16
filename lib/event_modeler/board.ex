defmodule EventModeler.Board do
  @moduledoc """
  GenServer managing an open board backed by an Event Model file.

  Each open board has its own GenServer process, started via DynamicSupervisor
  and registered via Registry keyed by file path.
  """

  use GenServer

  alias EventModeler.EventModel
  alias EventModeler.EventModel.{Element, Slice, EventStreamWriter}
  alias EventModeler.Canvas.{Layout, HtmlRenderer, ConnectionRules, CompletenessChecker, Swimlane}
  alias EventModeler.Workshop.ScenarioGenerator
  alias EventModeler.Workspace

  defstruct [
    :file_path,
    :event_model,
    :layout,
    :canvas_data,
    dirty: false,
    view_mode: :compact,
    connections: [],
    undo_stack: [],
    redo_stack: []
  ]

  @type view_mode :: :compact | :detailed

  @type t :: %__MODULE__{
          file_path: String.t(),
          event_model: EventModel.t(),
          layout: map(),
          canvas_data: map(),
          dirty: boolean(),
          view_mode: view_mode(),
          connections: [{String.t(), String.t()}],
          undo_stack: list(),
          redo_stack: list()
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
        case DynamicSupervisor.start_child(
               EventModeler.Board.Supervisor,
               {__MODULE__, file_path}
             ) do
          {:error, {:already_started, pid}} -> {:ok, pid}
          other -> other
        end
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

  @spec reorder_slice(String.t(), String.t(), :up | :down) :: :ok | {:error, term()}
  def reorder_slice(file_path, slice_name, direction) do
    call(file_path, {:reorder_slice, slice_name, direction})
  end

  @spec set_slice_order(String.t(), [String.t()]) :: :ok | {:error, term()}
  def set_slice_order(file_path, ordered_names) do
    call(file_path, {:set_slice_order, ordered_names})
  end

  @spec undo(String.t()) :: :ok | {:error, term()}
  def undo(file_path), do: call(file_path, :undo)

  @spec redo(String.t()) :: :ok | {:error, term()}
  def redo(file_path), do: call(file_path, :redo)

  @spec can_undo_redo(String.t()) :: {:ok, {boolean(), boolean()}} | {:error, term()}
  def can_undo_redo(file_path), do: call(file_path, :can_undo_redo)

  @spec toggle_view_mode(String.t()) :: {:ok, view_mode()} | {:error, term()}
  def toggle_view_mode(file_path), do: call(file_path, :toggle_view_mode)

  @spec get_view_mode(String.t()) :: {:ok, view_mode()} | {:error, term()}
  def get_view_mode(file_path), do: call(file_path, :get_view_mode)

  @spec check_completeness(String.t()) :: {:ok, list()} | {:error, term()}
  def check_completeness(file_path), do: call(file_path, :check_completeness)

  @doc """
  Copies fields from source element to target element (forward: Command -> Event).
  Only copies fields not already present on the target.
  """
  @spec copy_fields_forward(String.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def copy_fields_forward(file_path, from_id, to_id) do
    call(file_path, {:copy_fields, from_id, to_id, :forward})
  end

  @doc """
  Copies fields from target element back to source element (backward: Event -> Command).
  Only copies fields not already present on the source.
  """
  @spec copy_fields_backward(String.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def copy_fields_backward(file_path, from_id, to_id) do
    call(file_path, {:copy_fields, from_id, to_id, :backward})
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
    state = push_undo(state)

    resolved_swimlane =
      swimlane || Swimlane.default_name(Swimlane.type_for_element(type))

    element = %Element{
      id: generate_id(),
      type: type,
      label: label,
      swimlane: resolved_swimlane,
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

  def handle_call({:move_element, element_id, x, y}, _from, state) do
    state = push_undo(state)

    # Find the element's base position from layout (without current offsets)
    base_elem = Enum.find(state.layout.elements, &(&1.id == element_id))

    if base_elem do
      # Current offsets (already applied in layout)
      current_offset_x = find_element_prop(state.event_model, element_id, "position_offset_x", 0)
      current_offset_y = find_element_prop(state.event_model, element_id, "position_offset_y", 0)

      # Base position = rendered position minus current offsets
      base_x = base_elem.x - current_offset_x
      base_y = base_elem.y - current_offset_y

      # New offset = target position minus base position
      offset_x = x - base_x
      offset_y = y - base_y

      event_model =
        update_element_in_event_model(state.event_model, element_id, %{
          "props" => %{"position_offset_x" => offset_x, "position_offset_y" => offset_y}
        })

      event_model =
        EventStreamWriter.append(event_model, "ElementMoved", "user", %{
          "elementId" => element_id,
          "offsetX" => offset_x,
          "offsetY" => offset_y
        })

      state =
        %{state | event_model: event_model, dirty: true}
        |> recompute_layout()

      {:reply, :ok, state, @inactivity_timeout}
    else
      {:reply, {:error, "Element not found"}, state, @inactivity_timeout}
    end
  end

  def handle_call({:edit_element, element_id, changes}, _from, state) do
    state = push_undo(state)
    elem = find_element(state.event_model, element_id)

    if elem && changes["swimlane"] do
      target_type = Swimlane.type_for_element(elem.type)
      # Validate: the swimlane name is compatible if it already exists as a different type
      existing_swimlane =
        state
        |> recompute_layout()
        |> Map.get(:canvas_data)
        |> Map.get(:swimlanes)
        |> Enum.find(fn sl -> sl.name == changes["swimlane"] end)

      if existing_swimlane && existing_swimlane.type != target_type do
        {:reply, {:error, "Cannot place #{elem.type} in a #{existing_swimlane.type} swimlane"},
         state, @inactivity_timeout}
      else
        do_edit_element(state, element_id, changes)
      end
    else
      do_edit_element(state, element_id, changes)
    end
  end

  def handle_call({:connect_elements, from_id, to_id}, _from, state) do
    state = push_undo(state)

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
    state = push_undo(state)
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
    state = push_undo(state)
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
    state = push_undo(state)

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
    state = push_undo(state)

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
    state = push_undo(state)

    cond do
      {from_id, to_id} in state.connections ->
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

      layout_connection?(state.layout, from_id, to_id) ->
        {:reply, {:error, "This is a slice connection. Edit the slice to change element order."},
         state, @inactivity_timeout}

      true ->
        {:reply, {:error, "Connection not found"}, state, @inactivity_timeout}
    end
  end

  def handle_call({:remove_slice, slice_name}, _from, state) do
    state = push_undo(state)

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
    state = push_undo(state)

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
    state = push_undo(state)

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
    state = push_undo(state)

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
    state = push_undo(state)

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

  def handle_call(:can_undo_redo, _from, state) do
    {:reply, {:ok, {state.undo_stack != [], state.redo_stack != []}}, state, @inactivity_timeout}
  end

  def handle_call(:toggle_view_mode, _from, state) do
    new_mode = if state.view_mode == :compact, do: :detailed, else: :compact
    state = %{state | view_mode: new_mode} |> recompute_layout()
    {:reply, {:ok, new_mode}, state, @inactivity_timeout}
  end

  def handle_call(:get_view_mode, _from, state) do
    {:reply, {:ok, state.view_mode}, state, @inactivity_timeout}
  end

  def handle_call(:check_completeness, _from, state) do
    results = CompletenessChecker.check(state.event_model)
    {:reply, {:ok, results}, state, @inactivity_timeout}
  end

  def handle_call({:copy_fields, from_id, to_id, direction}, _from, state) do
    from_elem = find_element(state.event_model, from_id)
    to_elem = find_element(state.event_model, to_id)

    cond do
      is_nil(from_elem) ->
        {:reply, {:error, "Source element not found"}, state, @inactivity_timeout}

      is_nil(to_elem) ->
        {:reply, {:error, "Target element not found"}, state, @inactivity_timeout}

      true ->
        state = push_undo(state)

        {source, target_id} =
          case direction do
            :forward -> {from_elem, to_id}
            :backward -> {to_elem, from_id}
          end

        source_fields = source.fields || []
        target = if direction == :forward, do: to_elem, else: from_elem
        existing_names = MapSet.new(target.fields || [], & &1.name)

        new_fields =
          Enum.reject(source_fields, fn f -> MapSet.member?(existing_names, f.name) end)

        if new_fields == [] do
          {:reply, :ok, state, @inactivity_timeout}
        else
          merged = (target.fields || []) ++ new_fields

          event_model =
            update_element_fields_in_event_model(state.event_model, target_id, merged)

          event_model =
            EventStreamWriter.append(event_model, "FieldsCopied", "user", %{
              "fromId" => from_id,
              "toId" => to_id,
              "direction" => to_string(direction),
              "fieldCount" => length(new_fields)
            })

          state =
            %{state | event_model: event_model, dirty: true}
            |> recompute_layout()

          {:reply, :ok, state, @inactivity_timeout}
        end
    end
  end

  def handle_call(:undo, _from, state) do
    case state.undo_stack do
      [] ->
        {:reply, {:error, "Nothing to undo"}, state, @inactivity_timeout}

      [{event_model, connections} | rest] ->
        redo_snapshot = {state.event_model, state.connections}

        event_model =
          EventStreamWriter.append(event_model, "UndoPerformed", "user", %{})

        state =
          %{
            state
            | event_model: event_model,
              connections: connections,
              dirty: true,
              undo_stack: rest,
              redo_stack: [redo_snapshot | state.redo_stack]
          }
          |> recompute_layout()

        {:reply, :ok, state, @inactivity_timeout}
    end
  end

  def handle_call(:redo, _from, state) do
    case state.redo_stack do
      [] ->
        {:reply, {:error, "Nothing to redo"}, state, @inactivity_timeout}

      [{event_model, connections} | rest] ->
        undo_snapshot = {state.event_model, state.connections}

        event_model =
          EventStreamWriter.append(event_model, "RedoPerformed", "user", %{})

        state =
          %{
            state
            | event_model: event_model,
              connections: connections,
              dirty: true,
              undo_stack: [undo_snapshot | state.undo_stack],
              redo_stack: rest
          }
          |> recompute_layout()

        {:reply, :ok, state, @inactivity_timeout}
    end
  end

  def handle_call({:set_slice_order, ordered_names}, _from, state) do
    state = push_undo(state)
    slices = state.event_model.slices
    slice_map = Map.new(slices, fn s -> {s.name, s} end)

    # Reorder slices to match provided order, keeping any unmentioned slices at the end
    ordered =
      ordered_names
      |> Enum.filter(&Map.has_key?(slice_map, &1))
      |> Enum.map(&Map.fetch!(slice_map, &1))

    remaining =
      Enum.reject(slices, fn s -> s.name in ordered_names end)

    updated_slices = ordered ++ remaining
    event_model = %{state.event_model | slices: updated_slices}

    event_model =
      EventStreamWriter.append(event_model, "SlicesReordered", "user", %{
        "order" => ordered_names
      })

    state =
      %{state | event_model: event_model, dirty: true}
      |> recompute_layout()

    {:reply, :ok, state, @inactivity_timeout}
  end

  def handle_call({:reorder_slice, slice_name, direction}, _from, state) do
    state = push_undo(state)
    slices = state.event_model.slices
    idx = Enum.find_index(slices, &(&1.name == slice_name))

    cond do
      is_nil(idx) ->
        {:reply, {:error, "Slice not found"}, state, @inactivity_timeout}

      direction == :up and idx == 0 ->
        {:reply, {:error, "Already first"}, state, @inactivity_timeout}

      direction == :down and idx == length(slices) - 1 ->
        {:reply, {:error, "Already last"}, state, @inactivity_timeout}

      true ->
        target_idx = if direction == :up, do: idx - 1, else: idx + 1

        updated_slices =
          slices
          |> List.replace_at(idx, Enum.at(slices, target_idx))
          |> List.replace_at(target_idx, Enum.at(slices, idx))

        event_model = %{state.event_model | slices: updated_slices}

        event_model =
          EventStreamWriter.append(event_model, "SliceReordered", "user", %{
            "sliceName" => slice_name,
            "direction" => to_string(direction)
          })

        state =
          %{state | event_model: event_model, dirty: true}
          |> recompute_layout()

        {:reply, :ok, state, @inactivity_timeout}
    end
  end

  @impl true
  def handle_info(:timeout, state) do
    {:stop, :normal, state}
  end

  # Private helpers

  @max_undo_depth 50

  defp push_undo(state) do
    snapshot = {state.event_model, state.connections}
    stack = [snapshot | state.undo_stack] |> Enum.take(@max_undo_depth)
    %{state | undo_stack: stack, redo_stack: []}
  end

  defp do_edit_element(state, element_id, changes) do
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

  defp recompute_layout(state) do
    layout = Layout.compute(state.event_model, view_mode: state.view_mode)
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

  defp find_element_prop(%EventModel{} = event_model, element_id, key, default) do
    case find_element(event_model, element_id) do
      nil -> default
      elem -> Map.get(elem.props, key, default)
    end
  end

  defp find_element(%EventModel{slices: slices}, element_id) do
    Enum.find_value(slices, fn slice ->
      Enum.find(slice.steps, &(&1.id == element_id))
    end)
  end

  defp update_element_fields_in_event_model(
         %EventModel{slices: slices} = event_model,
         element_id,
         fields
       ) do
    updated_slices =
      Enum.map(slices, fn slice ->
        updated_steps =
          Enum.map(slice.steps, fn step ->
            if step.id == element_id do
              %{step | fields: fields}
            else
              step
            end
          end)

        %{slice | steps: updated_steps}
      end)

    %{event_model | slices: updated_slices}
  end

  defp layout_connection?(layout, from_id, to_id) do
    Enum.any?(layout.connections, fn conn ->
      conn.from_id == from_id and conn.to_id == to_id
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
