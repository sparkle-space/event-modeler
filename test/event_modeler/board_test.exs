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

    {:ok, path} = Workspace.create_prd(@test_dir, "Board Test")

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
    case Process.whereis(EventModeler.Board.Registry) do
      nil ->
        # Registry died - restart the application
        Application.stop(:event_modeler)
        Application.ensure_all_started(:event_modeler)
        Process.sleep(100)

      _pid ->
        :ok
    end
  end

  test "opens a board from file", %{path: path} do
    assert {:ok, _pid} = Board.open(path)
    assert {:ok, state} = Board.get_state(path)
    assert state.prd.title == "Board Test"
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

    {:ok, prd} = Workspace.read_prd(path)
    assert prd.title == "Board Test"
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

    # Element should be in the PRD
    all_elements =
      Enum.flat_map(state.prd.slices, & &1.steps)

    assert Enum.any?(all_elements, &(&1.label == "DoThing"))
  end

  test "edit_element updates label", %{path: path} do
    {:ok, _pid} = Board.open(path)
    {:ok, element_id} = Board.place_element(path, :event, "OldLabel")

    :ok = Board.edit_element(path, element_id, %{"label" => "NewLabel"})

    {:ok, state} = Board.get_state(path)
    all_elements = Enum.flat_map(state.prd.slices, & &1.steps)
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

  test "remove_element removes from PRD", %{path: path} do
    {:ok, _pid} = Board.open(path)
    {:ok, element_id} = Board.place_element(path, :event, "ToRemove")

    :ok = Board.remove_element(path, element_id)

    {:ok, state} = Board.get_state(path)
    all_elements = Enum.flat_map(state.prd.slices, & &1.steps)
    refute Enum.any?(all_elements, &(&1.id == element_id))
  end

  test "mutations append event stream entries", %{path: path} do
    {:ok, _pid} = Board.open(path)

    {:ok, state_before} = Board.get_state(path)
    stream_count_before = length(state_before.prd.event_stream)

    {:ok, _} = Board.place_element(path, :command, "Test")

    {:ok, state_after} = Board.get_state(path)
    assert length(state_after.prd.event_stream) > stream_count_before
  end

  test "define_slice groups elements into a named slice", %{path: path} do
    {:ok, _pid} = Board.open(path)
    {:ok, cmd_id} = Board.place_element(path, :command, "RegisterUser")
    {:ok, evt_id} = Board.place_element(path, :event, "UserRegistered")

    assert :ok = Board.define_slice(path, "RegisterUser", [cmd_id, evt_id])

    {:ok, state} = Board.get_state(path)
    slice = Enum.find(state.prd.slices, &(&1.name == "RegisterUser"))
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
    assert Enum.any?(state.prd.slices, &(&1.name == "NewName"))
    refute Enum.any?(state.prd.slices, &(&1.name == "OldName"))
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
    assert hd(scenario.when_clause).label == "CreateBoard"
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
    slice = Enum.find(state.prd.slices, &(&1.name == "Login"))
    assert slice.tests != nil
    assert length(slice.tests) == 1
  end
end
