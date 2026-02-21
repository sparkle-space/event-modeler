defmodule EventModeler.IntegrationTest do
  use ExUnit.Case, async: false

  alias EventModeler.{Board, Workspace}
  alias EventModeler.Prd.Parser

  @test_dir Path.join(
              System.tmp_dir!(),
              "event_modeler_integration_test_#{:erlang.unique_integer([:positive])}"
            )

  setup do
    ensure_registry_alive()
    File.rm_rf!(@test_dir)
    File.mkdir_p!(@test_dir)

    {:ok, path} = Workspace.create_prd(@test_dir, "Integration Test")

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
        Application.stop(:event_modeler)
        Application.ensure_all_started(:event_modeler)
        Process.sleep(100)

      _pid ->
        :ok
    end
  end

  test "full round-trip: create -> edit -> slice -> scenarios -> save -> reload", %{path: path} do
    # Open the board
    {:ok, _pid} = Board.open(path)

    # Add elements
    {:ok, cmd_id} = Board.place_element(path, :command, "RegisterUser")
    {:ok, evt_id} = Board.place_element(path, :event, "UserRegistered", "User")
    {:ok, view_id} = Board.place_element(path, :view, "UserProfile")

    # Edit an element label
    :ok = Board.edit_element(path, cmd_id, %{"label" => "CreateAccount"})

    # Define a slice with the elements
    :ok = Board.define_slice(path, "CreateAccount", [cmd_id, evt_id, view_id])

    # Generate scenarios for the slice
    {:ok, scenarios} = Board.generate_scenarios(path, "CreateAccount")
    assert length(scenarios) == 1
    [scenario] = scenarios
    assert scenario.name == "CreateAccountHappyPath"
    assert scenario.auto_generated == true

    # Verify in-memory state
    {:ok, state} = Board.get_state(path)
    assert state.dirty == true
    slice = Enum.find(state.prd.slices, &(&1.name == "CreateAccount"))
    assert slice != nil
    assert length(slice.steps) == 3
    assert slice.tests != nil
    assert length(slice.tests) == 1

    # Save to disk
    :ok = Board.save(path)

    {:ok, state_after_save} = Board.get_state(path)
    assert state_after_save.dirty == false

    # Verify the saved file on disk is a valid, complete PRD
    {:ok, raw_content} = File.read(path)
    {:ok, parsed} = Parser.parse(raw_content)

    assert parsed.title == "Integration Test"

    # Slices should be preserved in the file
    assert length(parsed.slices) >= 1

    account_slice = Enum.find(parsed.slices, &(&1.name == "CreateAccount"))
    assert account_slice != nil
    assert length(account_slice.steps) == 3

    # Event stream should have entries in the file
    assert length(parsed.event_stream) > 0

    # Verify round-trip: parse the saved file, serialize it, parse again
    reserialized = EventModeler.Prd.Serializer.serialize(parsed)
    {:ok, reparsed} = Parser.parse(reserialized)
    assert reparsed.title == parsed.title
    assert length(reparsed.slices) == length(parsed.slices)
  end

  test "save updates frontmatter timestamp", %{path: path} do
    {:ok, _pid} = Board.open(path)

    {:ok, state_before} = Board.get_state(path)
    original_updated = state_before.prd.updated

    # Make a change and save
    {:ok, _} = Board.place_element(path, :command, "TestCmd")
    :ok = Board.save(path)

    # Read the file directly to check the updated timestamp
    {:ok, content} = File.read(path)
    {:ok, parsed} = Parser.parse(content)
    assert parsed.updated != original_updated
  end
end
