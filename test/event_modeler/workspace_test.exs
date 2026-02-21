defmodule EventModeler.WorkspaceTest do
  use ExUnit.Case, async: true

  alias EventModeler.Workspace

  @test_dir Path.join(
              System.tmp_dir!(),
              "event_modeler_test_#{:erlang.unique_integer([:positive])}"
            )

  setup do
    File.mkdir_p!(@test_dir)
    on_exit(fn -> File.rm_rf!(@test_dir) end)
    :ok
  end

  test "list_prds returns empty list for empty directory" do
    assert Workspace.list_prds(@test_dir) == []
  end

  test "list_prds returns empty for non-existent directory" do
    assert Workspace.list_prds("/nonexistent/path") == []
  end

  test "create_prd creates a new PRD file" do
    assert {:ok, path} = Workspace.create_prd(@test_dir, "Test Feature")
    assert File.exists?(path)
    assert String.ends_with?(path, "test-feature.md")

    {:ok, prd} = Workspace.read_prd(path)
    assert prd.title == "Test Feature"
    assert prd.status == "draft"
    assert length(prd.event_stream) == 1
  end

  test "create_prd rejects duplicate filenames" do
    {:ok, _} = Workspace.create_prd(@test_dir, "Test Feature")
    assert {:error, _} = Workspace.create_prd(@test_dir, "Test Feature")
  end

  test "list_prds finds created files" do
    {:ok, _} = Workspace.create_prd(@test_dir, "Feature One")
    {:ok, _} = Workspace.create_prd(@test_dir, "Feature Two")

    prds = Workspace.list_prds(@test_dir)
    assert length(prds) == 2
    titles = Enum.map(prds, & &1.title)
    assert "Feature One" in titles
    assert "Feature Two" in titles
  end

  test "write_prd and read_prd round-trip" do
    {:ok, path} = Workspace.create_prd(@test_dir, "Round Trip")
    {:ok, prd1} = Workspace.read_prd(path)

    # Modify and write back
    prd2 = %{prd1 | status: "modeling"}
    :ok = Workspace.write_prd(path, prd2)

    {:ok, prd3} = Workspace.read_prd(path)
    assert prd3.status == "modeling"
    assert prd3.title == "Round Trip"
  end
end
