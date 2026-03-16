defmodule EventModeler.BoardTest do
  use ExUnit.Case, async: false

  alias EventModeler.{Board, Workspace}

  @test_dir Path.join(
              System.tmp_dir!(),
              "event_modeler_board_test_#{:erlang.unique_integer([:positive])}"
            )

  setup do
    # Ensure the application services are running
    ensure_registry_alive()

    # Clean up any leftover state from previous test
    File.rm_rf!(@test_dir)
    File.mkdir_p!(@test_dir)

    {:ok, path} = Workspace.create_event_model(@test_dir, "Board Test")

    on_exit(fn ->
      try do
        case Registry.lookup(EventModeler.Board.Registry, path) do
          [{pid, _}] -> GenServer.stop(pid, :normal)
          [] -> :ok
        end
      rescue
        _ -> :ok
      catch
        _, _ -> :ok
      end

      File.rm_rf!(@test_dir)
    end)

    %{path: path}
  end

  defp ensure_registry_alive do
    ensure_registry_alive(10)
  end

  defp ensure_registry_alive(0), do: raise("Board.Registry failed to start after retries")

  defp ensure_registry_alive(retries) do
    case Process.whereis(EventModeler.Board.Registry) do
      nil ->
        Application.stop(:event_modeler)
        Application.ensure_all_started(:event_modeler)
        Process.sleep(200)
        ensure_registry_alive(retries - 1)

      pid when is_pid(pid) ->
        # Verify the registry is actually responsive
        try do
          Registry.lookup(EventModeler.Board.Registry, "__health_check__")
          :ok
        rescue
          ArgumentError ->
            Process.sleep(100)
            ensure_registry_alive(retries - 1)
        end
    end
  end

  test "opens a board from file", %{path: path} do
    assert {:ok, _pid} = Board.open(path)
    assert {:ok, state} = Board.get_state(path)
    assert state.event_model.title == "Board Test"
    assert state.dirty == false
  end

  test "opening same path returns same pid", %{path: path} do
    {:ok, pid1} = Board.open(path)
    {:ok, pid2} = Board.open(path)
    assert pid1 == pid2
  end

  test "save writes state to file", %{path: path} do
    {:ok, _pid} = Board.open(path)
    assert :ok = Board.save(path)

    {:ok, event_model} = Workspace.read_event_model(path)
    assert event_model.title == "Board Test"
  end

  test "get_state returns error for unopened board" do
    assert {:error, :not_open} = Board.get_state("/nonexistent/board.md")
  end

  test "place_element adds element and marks dirty", %{path: path} do
    {:ok, _pid} = Board.open(path)

    assert {:ok, element_id} = Board.place_element(path, :command, "DoThing")
    assert is_binary(element_id)

    {:ok, state} = Board.get_state(path)
    assert state.dirty == true

    # Element should be in the event model
    all_elements =
      Enum.flat_map(state.event_model.slices, & &1.steps)

    assert Enum.any?(all_elements, &(&1.label == "DoThing"))
  end

  test "edit_element updates label", %{path: path} do
    {:ok, _pid} = Board.open(path)
    {:ok, element_id} = Board.place_element(path, :event, "OldLabel")

    :ok = Board.edit_element(path, element_id, %{"label" => "NewLabel"})

    {:ok, state} = Board.get_state(path)
    all_elements = Enum.flat_map(state.event_model.slices, & &1.steps)
    edited = Enum.find(all_elements, &(&1.id == element_id))
    assert edited.label == "NewLabel"
  end

  test "connect_elements validates connection rules", %{path: path} do
    {:ok, _pid} = Board.open(path)
    {:ok, cmd_id} = Board.place_element(path, :command, "Cmd")
    {:ok, view_id} = Board.place_element(path, :view, "View")
    {:ok, evt_id} = Board.place_element(path, :event, "Evt")

    # command -> view is invalid
    assert {:error, reason} = Board.connect_elements(path, cmd_id, view_id)
    assert reason =~ "Command"
    assert reason =~ "View"

    # command -> event is valid
    assert :ok = Board.connect_elements(path, cmd_id, evt_id)
  end

  test "remove_element removes from event model", %{path: path} do
    {:ok, _pid} = Board.open(path)
    {:ok, element_id} = Board.place_element(path, :event, "ToRemove")

    :ok = Board.remove_element(path, element_id)

    {:ok, state} = Board.get_state(path)
    all_elements = Enum.flat_map(state.event_model.slices, & &1.steps)
    refute Enum.any?(all_elements, &(&1.id == element_id))
  end

  test "mutations append event stream entries", %{path: path} do
    {:ok, _pid} = Board.open(path)

    {:ok, state_before} = Board.get_state(path)
    stream_count_before = length(state_before.event_model.event_stream)

    {:ok, _} = Board.place_element(path, :command, "Test")

    {:ok, state_after} = Board.get_state(path)
    assert length(state_after.event_model.event_stream) > stream_count_before
  end

  test "define_slice groups elements into a named slice", %{path: path} do
    {:ok, _pid} = Board.open(path)
    {:ok, cmd_id} = Board.place_element(path, :command, "RegisterUser")
    {:ok, evt_id} = Board.place_element(path, :event, "UserRegistered")

    assert :ok = Board.define_slice(path, "RegisterUser", [cmd_id, evt_id])

    {:ok, state} = Board.get_state(path)
    slice = Enum.find(state.event_model.slices, &(&1.name == "RegisterUser"))
    assert slice != nil
    assert length(slice.steps) == 2
    assert Enum.any?(slice.steps, &(&1.label == "RegisterUser"))
    assert Enum.any?(slice.steps, &(&1.label == "UserRegistered"))
  end

  test "define_slice returns error for no matching elements", %{path: path} do
    {:ok, _pid} = Board.open(path)

    assert {:error, "No matching elements found"} =
             Board.define_slice(path, "Empty", ["nonexistent"])
  end

  test "rename_slice updates slice name", %{path: path} do
    {:ok, _pid} = Board.open(path)
    {:ok, cmd_id} = Board.place_element(path, :command, "DoThing")
    :ok = Board.define_slice(path, "OldName", [cmd_id])

    :ok = Board.rename_slice(path, "OldName", "NewName")

    {:ok, state} = Board.get_state(path)
    assert Enum.any?(state.event_model.slices, &(&1.name == "NewName"))
    refute Enum.any?(state.event_model.slices, &(&1.name == "OldName"))
  end

  test "generate_scenarios creates GWT scenarios for a slice", %{path: path} do
    {:ok, _pid} = Board.open(path)
    {:ok, cmd_id} = Board.place_element(path, :command, "CreateBoard")
    {:ok, evt_id} = Board.place_element(path, :event, "BoardCreated")
    :ok = Board.define_slice(path, "CreateBoard", [cmd_id, evt_id])

    assert {:ok, scenarios} = Board.generate_scenarios(path, "CreateBoard")
    assert length(scenarios) == 1

    [scenario] = scenarios
    assert scenario.name == "CreateBoardHappyPath"
    assert scenario.auto_generated == true
    assert length(scenario.when_clause) == 1
    assert hd(scenario.when_clause).label == "Processing/CreateBoard"
  end

  test "generate_scenarios returns error for unknown slice", %{path: path} do
    {:ok, _pid} = Board.open(path)

    assert {:error, "Slice not found"} =
             Board.generate_scenarios(path, "NonexistentSlice")
  end

  test "generate_scenarios stores scenarios in slice tests", %{path: path} do
    {:ok, _pid} = Board.open(path)
    {:ok, cmd_id} = Board.place_element(path, :command, "Login")
    {:ok, evt_id} = Board.place_element(path, :event, "LoggedIn")
    :ok = Board.define_slice(path, "Login", [cmd_id, evt_id])

    {:ok, _scenarios} = Board.generate_scenarios(path, "Login")

    {:ok, state} = Board.get_state(path)
    slice = Enum.find(state.event_model.slices, &(&1.name == "Login"))
    assert slice.tests != nil
    assert length(slice.tests) == 1
  end

  test "connect_elements rejects self-connection", %{path: path} do
    {:ok, _pid} = Board.open(path)
    {:ok, cmd_id} = Board.place_element(path, :command, "Cmd")

    assert {:error, reason} = Board.connect_elements(path, cmd_id, cmd_id)
    assert reason =~ "itself"
  end

  test "connect_elements rejects duplicate connection", %{path: path} do
    {:ok, _pid} = Board.open(path)
    {:ok, cmd_id} = Board.place_element(path, :command, "Cmd")
    {:ok, evt_id} = Board.place_element(path, :event, "Evt")

    assert :ok = Board.connect_elements(path, cmd_id, evt_id)
    assert {:error, reason} = Board.connect_elements(path, cmd_id, evt_id)
    assert reason =~ "already connected"
  end

  test "remove_element cleans up connections", %{path: path} do
    {:ok, _pid} = Board.open(path)
    {:ok, cmd_id} = Board.place_element(path, :command, "Cmd")
    {:ok, evt_id} = Board.place_element(path, :event, "Evt")

    :ok = Board.connect_elements(path, cmd_id, evt_id)
    :ok = Board.remove_element(path, cmd_id)

    # After removing cmd, a new command should be able to connect to the same event
    {:ok, cmd_id2} = Board.place_element(path, :command, "Cmd2")
    assert :ok = Board.connect_elements(path, cmd_id2, evt_id)
  end

  # Disconnect elements

  test "disconnect_elements removes a connection", %{path: path} do
    {:ok, _pid} = Board.open(path)
    {:ok, cmd_id} = Board.place_element(path, :command, "Cmd")
    {:ok, evt_id} = Board.place_element(path, :event, "Evt")

    :ok = Board.connect_elements(path, cmd_id, evt_id)
    assert :ok = Board.disconnect_elements(path, cmd_id, evt_id)

    # Should be able to reconnect after disconnect
    assert :ok = Board.connect_elements(path, cmd_id, evt_id)
  end

  test "disconnect_elements returns informative error for structural connection", %{path: path} do
    {:ok, _pid} = Board.open(path)
    {:ok, cmd_id} = Board.place_element(path, :command, "Cmd")
    {:ok, evt_id} = Board.place_element(path, :event, "Evt")

    # These elements are consecutive in a slice, so they have a structural connection
    assert {:error, msg} = Board.disconnect_elements(path, cmd_id, evt_id)
    assert msg =~ "slice connection"
  end

  test "disconnect_elements returns error for nonexistent connection", %{path: path} do
    {:ok, _pid} = Board.open(path)

    assert {:error, "Connection not found"} =
             Board.disconnect_elements(path, "nonexistent_a", "nonexistent_b")
  end

  test "disconnect persists through save", %{path: path} do
    {:ok, _pid} = Board.open(path)
    {:ok, cmd_id} = Board.place_element(path, :command, "Cmd")
    {:ok, evt_id} = Board.place_element(path, :event, "Evt")

    :ok = Board.connect_elements(path, cmd_id, evt_id)
    :ok = Board.disconnect_elements(path, cmd_id, evt_id)
    :ok = Board.save(path)

    # Verify the saved file contains the ElementsDisconnected event
    content = File.read!(path)
    assert content =~ "ElementsDisconnected"

    # Verify connection is gone from state
    {:ok, state} = Board.get_state(path)
    refute {cmd_id, evt_id} in state.connections
  end

  # Slice removal

  test "remove_slice moves elements to Unassigned", %{path: path} do
    {:ok, _pid} = Board.open(path)
    {:ok, cmd_id} = Board.place_element(path, :command, "Cmd")
    {:ok, evt_id} = Board.place_element(path, :event, "Evt")
    :ok = Board.define_slice(path, "MySlice", [cmd_id, evt_id])

    assert :ok = Board.remove_slice(path, "MySlice")

    {:ok, state} = Board.get_state(path)
    refute Enum.any?(state.event_model.slices, &(&1.name == "MySlice"))

    # Elements should be in Unassigned
    unassigned = Enum.find(state.event_model.slices, &(&1.name == "Unassigned"))
    assert unassigned != nil
    assert length(unassigned.steps) == 2
  end

  test "remove_slice returns error for nonexistent slice", %{path: path} do
    {:ok, _pid} = Board.open(path)
    assert {:error, "Slice not found"} = Board.remove_slice(path, "Nope")
  end

  # Remove element from slice

  test "remove_element_from_slice moves element to Unassigned", %{path: path} do
    {:ok, _pid} = Board.open(path)
    {:ok, cmd_id} = Board.place_element(path, :command, "Cmd")
    {:ok, evt_id} = Board.place_element(path, :event, "Evt")
    :ok = Board.define_slice(path, "MySlice", [cmd_id, evt_id])

    assert :ok = Board.remove_element_from_slice(path, "MySlice", cmd_id)

    {:ok, state} = Board.get_state(path)
    slice = Enum.find(state.event_model.slices, &(&1.name == "MySlice"))
    assert length(slice.steps) == 1
    refute Enum.any?(slice.steps, &(&1.id == cmd_id))

    # Element should be in Unassigned
    unassigned = Enum.find(state.event_model.slices, &(&1.name == "Unassigned"))
    assert unassigned != nil
    assert Enum.any?(unassigned.steps, &(&1.id == cmd_id))
  end

  test "remove_element_from_slice returns error for wrong element", %{path: path} do
    {:ok, _pid} = Board.open(path)
    {:ok, cmd_id} = Board.place_element(path, :command, "Cmd")
    :ok = Board.define_slice(path, "MySlice", [cmd_id])

    assert {:error, "Element not found in slice"} =
             Board.remove_element_from_slice(path, "MySlice", "nonexistent")
  end

  # Scenario management

  test "remove_scenario deletes a scenario from a slice", %{path: path} do
    {:ok, _pid} = Board.open(path)
    {:ok, cmd_id} = Board.place_element(path, :command, "DoIt")
    {:ok, evt_id} = Board.place_element(path, :event, "Done")
    :ok = Board.define_slice(path, "DoSlice", [cmd_id, evt_id])
    {:ok, _} = Board.generate_scenarios(path, "DoSlice")

    assert :ok = Board.remove_scenario(path, "DoSlice", "DoSliceHappyPath")

    {:ok, state} = Board.get_state(path)
    slice = Enum.find(state.event_model.slices, &(&1.name == "DoSlice"))
    assert slice.tests == []
  end

  test "remove_scenario returns error for nonexistent scenario", %{path: path} do
    {:ok, _pid} = Board.open(path)
    {:ok, cmd_id} = Board.place_element(path, :command, "DoIt")
    :ok = Board.define_slice(path, "DoSlice", [cmd_id])

    assert {:error, "Scenario not found"} =
             Board.remove_scenario(path, "DoSlice", "NonexistentScenario")
  end

  test "update_scenario changes scenario name and clears auto_generated", %{path: path} do
    {:ok, _pid} = Board.open(path)
    {:ok, cmd_id} = Board.place_element(path, :command, "DoIt")
    {:ok, evt_id} = Board.place_element(path, :event, "Done")
    :ok = Board.define_slice(path, "DoSlice", [cmd_id, evt_id])
    {:ok, _} = Board.generate_scenarios(path, "DoSlice")

    assert :ok =
             Board.update_scenario(path, "DoSlice", "DoSliceHappyPath", %{
               "name" => "DoSliceEdgeCase"
             })

    {:ok, state} = Board.get_state(path)
    slice = Enum.find(state.event_model.slices, &(&1.name == "DoSlice"))
    scenario = hd(slice.tests)
    assert scenario.name == "DoSliceEdgeCase"
    assert scenario.auto_generated == false
  end

  test "add_scenario adds a manual scenario to a slice", %{path: path} do
    {:ok, _pid} = Board.open(path)
    {:ok, cmd_id} = Board.place_element(path, :command, "DoIt")
    :ok = Board.define_slice(path, "DoSlice", [cmd_id])

    assert :ok =
             Board.add_scenario(path, "DoSlice", %{
               "name" => "ManualScenario",
               "given" => [%{type: "e", label: "SomethingHappened", props: %{}}],
               "when_clause" => [%{type: "c", label: "DoIt", props: %{}}],
               "then_clause" => [%{type: "e", label: "ItWasDone", props: %{}}]
             })

    {:ok, state} = Board.get_state(path)
    slice = Enum.find(state.event_model.slices, &(&1.name == "DoSlice"))
    assert length(slice.tests) == 1
    scenario = hd(slice.tests)
    assert scenario.name == "ManualScenario"
    assert scenario.auto_generated == false
  end

  # Slice reordering

  test "reorder_slice moves slice up", %{path: path} do
    {:ok, _pid} = Board.open(path)
    {:ok, cmd1} = Board.place_element(path, :command, "Cmd1")
    {:ok, cmd2} = Board.place_element(path, :command, "Cmd2")
    :ok = Board.define_slice(path, "SliceA", [cmd1])
    :ok = Board.define_slice(path, "SliceB", [cmd2])

    {:ok, state_before} = Board.get_state(path)
    names_before = Enum.map(state_before.event_model.slices, & &1.name)
    idx_a = Enum.find_index(names_before, &(&1 == "SliceA"))
    idx_b = Enum.find_index(names_before, &(&1 == "SliceB"))
    assert idx_b > idx_a

    :ok = Board.reorder_slice(path, "SliceB", :up)

    {:ok, state_after} = Board.get_state(path)
    names_after = Enum.map(state_after.event_model.slices, & &1.name)
    new_idx_a = Enum.find_index(names_after, &(&1 == "SliceA"))
    new_idx_b = Enum.find_index(names_after, &(&1 == "SliceB"))
    assert new_idx_b < new_idx_a
  end

  test "reorder_slice returns error at boundary", %{path: path} do
    {:ok, _pid} = Board.open(path)
    {:ok, cmd1} = Board.place_element(path, :command, "Cmd1")
    :ok = Board.define_slice(path, "SliceA", [cmd1])

    {:ok, state} = Board.get_state(path)
    first_name = hd(state.event_model.slices).name
    assert {:error, _} = Board.reorder_slice(path, first_name, :up)
  end

  # Set slice order

  test "set_slice_order reorders slices by name list", %{path: path} do
    {:ok, _pid} = Board.open(path)
    {:ok, cmd1} = Board.place_element(path, :command, "Cmd1")
    {:ok, cmd2} = Board.place_element(path, :command, "Cmd2")
    {:ok, cmd3} = Board.place_element(path, :command, "Cmd3")
    :ok = Board.define_slice(path, "Alpha", [cmd1])
    :ok = Board.define_slice(path, "Beta", [cmd2])
    :ok = Board.define_slice(path, "Gamma", [cmd3])

    {:ok, state_before} = Board.get_state(path)
    current_names = Enum.map(state_before.event_model.slices, & &1.name)
    reversed = Enum.reverse(current_names)

    :ok = Board.set_slice_order(path, reversed)

    {:ok, state} = Board.get_state(path)
    names = Enum.map(state.event_model.slices, & &1.name)
    assert names == reversed
  end

  # Undo/Redo

  test "undo reverses last mutation", %{path: path} do
    {:ok, _pid} = Board.open(path)

    {:ok, state_before} = Board.get_state(path)

    elem_count_before =
      Enum.flat_map(state_before.event_model.slices, & &1.steps) |> length()

    {:ok, _id} = Board.place_element(path, :command, "ToUndo")

    {:ok, state_mid} = Board.get_state(path)

    elem_count_mid =
      Enum.flat_map(state_mid.event_model.slices, & &1.steps) |> length()

    assert elem_count_mid == elem_count_before + 1

    :ok = Board.undo(path)

    {:ok, state_after} = Board.get_state(path)

    elem_count_after =
      Enum.flat_map(state_after.event_model.slices, & &1.steps) |> length()

    assert elem_count_after == elem_count_before
  end

  test "redo restores undone mutation", %{path: path} do
    {:ok, _pid} = Board.open(path)
    {:ok, _id} = Board.place_element(path, :command, "ToRedo")

    {:ok, state_mid} = Board.get_state(path)

    elem_count_mid =
      Enum.flat_map(state_mid.event_model.slices, & &1.steps) |> length()

    :ok = Board.undo(path)
    :ok = Board.redo(path)

    {:ok, state_after} = Board.get_state(path)

    elem_count_after =
      Enum.flat_map(state_after.event_model.slices, & &1.steps) |> length()

    assert elem_count_after == elem_count_mid
  end

  test "undo on empty stack returns error", %{path: path} do
    {:ok, _pid} = Board.open(path)
    assert {:error, "Nothing to undo"} = Board.undo(path)
  end

  test "redo on empty stack returns error", %{path: path} do
    {:ok, _pid} = Board.open(path)
    assert {:error, "Nothing to redo"} = Board.redo(path)
  end

  test "new mutation clears redo stack", %{path: path} do
    {:ok, _pid} = Board.open(path)
    {:ok, _id} = Board.place_element(path, :command, "First")
    :ok = Board.undo(path)

    # Redo should work now
    {:ok, {_, can_redo}} = Board.can_undo_redo(path)
    assert can_redo

    # New mutation clears redo stack
    {:ok, _id2} = Board.place_element(path, :event, "Second")

    {:ok, {_, can_redo_after}} = Board.can_undo_redo(path)
    refute can_redo_after
  end

  test "can_undo_redo reports correct state", %{path: path} do
    {:ok, _pid} = Board.open(path)

    assert {:ok, {false, false}} = Board.can_undo_redo(path)

    {:ok, _id} = Board.place_element(path, :command, "Test")
    assert {:ok, {true, false}} = Board.can_undo_redo(path)

    :ok = Board.undo(path)
    assert {:ok, {false, true}} = Board.can_undo_redo(path)
  end
end
