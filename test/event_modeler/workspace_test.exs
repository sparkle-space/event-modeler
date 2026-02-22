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

  test "list_event_models returns empty list for empty directory" do
    assert Workspace.list_event_models(@test_dir) == []
  end

  test "list_event_models returns empty for non-existent directory" do
    assert Workspace.list_event_models("/nonexistent/path") == []
  end

  test "create_event_model creates a new event model file" do
    assert {:ok, path} = Workspace.create_event_model(@test_dir, "Test Feature")
    assert File.exists?(path)
    assert String.ends_with?(path, "test-feature.md")

    {:ok, event_model} = Workspace.read_event_model(path)
    assert event_model.title == "Test Feature"
    assert event_model.status == "draft"
    assert length(event_model.event_stream) == 1
  end

  test "create_event_model rejects duplicate filenames" do
    {:ok, _} = Workspace.create_event_model(@test_dir, "Test Feature")
    assert {:error, _} = Workspace.create_event_model(@test_dir, "Test Feature")
  end

  test "list_event_models finds created files" do
    {:ok, _} = Workspace.create_event_model(@test_dir, "Feature One")
    {:ok, _} = Workspace.create_event_model(@test_dir, "Feature Two")

    event_models = Workspace.list_event_models(@test_dir)
    assert length(event_models) == 2
    titles = Enum.map(event_models, & &1.title)
    assert "Feature One" in titles
    assert "Feature Two" in titles
  end

  test "write_event_model and read_event_model round-trip" do
    {:ok, path} = Workspace.create_event_model(@test_dir, "Round Trip")
    {:ok, event_model1} = Workspace.read_event_model(path)

    # Modify and write back
    event_model2 = %{event_model1 | status: "modeling"}
    :ok = Workspace.write_event_model(path, event_model2)

    {:ok, event_model3} = Workspace.read_event_model(path)
    assert event_model3.status == "modeling"
    assert event_model3.title == "Round Trip"
  end
end
