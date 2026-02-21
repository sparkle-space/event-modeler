defmodule EventModeler.BoardTest do
  use ExUnit.Case, async: false

  alias EventModeler.{Board, Workspace}

  @test_dir Path.join(
              System.tmp_dir!(),
              "event_modeler_board_test_#{:erlang.unique_integer([:positive])}"
            )

  setup do
    File.mkdir_p!(@test_dir)

    {:ok, path} = Workspace.create_prd(@test_dir, "Board Test")

    on_exit(fn ->
      # Stop board if running
      case Registry.lookup(EventModeler.Board.Registry, path) do
        [{pid, _}] -> GenServer.stop(pid, :normal)
        [] -> :ok
      end

      File.rm_rf!(@test_dir)
    end)

    %{path: path}
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

    # Verify file was written
    {:ok, prd} = Workspace.read_prd(path)
    assert prd.title == "Board Test"
  end

  test "get_state returns error for unopened board" do
    assert {:error, :not_open} = Board.get_state("/nonexistent/board.md")
  end
end
