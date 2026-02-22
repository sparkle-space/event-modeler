defmodule EventModeler.Canvas.LayoutTest do
  use ExUnit.Case, async: true

  alias EventModeler.Canvas.Layout
  alias EventModeler.EventModel
  alias EventModeler.EventModel.{Slice, Element}

  test "computes layout for empty event model" do
    event_model = %EventModel{slices: []}
    result = Layout.compute(event_model)

    assert result.elements == []
    assert result.connections == []
    assert result.width >= 800
    assert result.height >= 400
  end

  test "computes layout for single slice with 4 steps" do
    event_model = %EventModel{
      slices: [
        %Slice{
          name: "CreateBoard",
          steps: [
            %Element{id: "1", type: :wireframe, label: "DashboardPage", swimlane: "User"},
            %Element{id: "2", type: :command, label: "CreateBoard", swimlane: nil},
            %Element{id: "3", type: :event, label: "BoardCreated", swimlane: "Board"},
            %Element{id: "4", type: :view, label: "BoardCanvas", swimlane: nil}
          ]
        }
      ]
    }

    result = Layout.compute(event_model)

    assert length(result.elements) == 4
    assert length(result.connections) == 3

    # Elements should be positioned left-to-right
    xs = Enum.map(result.elements, & &1.x)
    assert xs == Enum.sort(xs)

    # All elements have positive dimensions
    Enum.each(result.elements, fn elem ->
      assert elem.width > 0
      assert elem.height > 0
      assert elem.x >= 0
      assert elem.y >= 0
    end)
  end

  test "computes connections between consecutive elements" do
    event_model = %EventModel{
      slices: [
        %Slice{
          name: "Test",
          steps: [
            %Element{id: "a", type: :command, label: "DoThing"},
            %Element{id: "b", type: :event, label: "ThingDone"},
            %Element{id: "c", type: :view, label: "Result"}
          ]
        }
      ]
    }

    result = Layout.compute(event_model)

    assert length(result.connections) == 2
    [conn1, conn2] = result.connections
    assert conn1.from_id == "a"
    assert conn1.to_id == "b"
    assert conn2.from_id == "b"
    assert conn2.to_id == "c"
  end

  test "assigns different swimlane rows by type" do
    event_model = %EventModel{
      slices: [
        %Slice{
          name: "Test",
          steps: [
            %Element{id: "1", type: :wireframe, label: "Form", swimlane: "User"},
            %Element{id: "2", type: :event, label: "Created", swimlane: "System"}
          ]
        }
      ]
    }

    result = Layout.compute(event_model)

    swimlane_names = Enum.map(result.swimlanes, & &1.name)
    assert "User" in swimlane_names
    assert "System" in swimlane_names

    # Elements in different swimlanes should have different y positions
    ys = result.elements |> Enum.map(& &1.y) |> Enum.uniq()
    assert length(ys) == 2
  end

  test "swimlanes include type field" do
    event_model = %EventModel{
      slices: [
        %Slice{
          name: "Test",
          steps: [
            %Element{id: "1", type: :wireframe, label: "Form", swimlane: "Triggers"},
            %Element{id: "2", type: :command, label: "DoThing", swimlane: "Processing"},
            %Element{id: "3", type: :event, label: "ThingDone", swimlane: "Events"}
          ]
        }
      ]
    }

    result = Layout.compute(event_model)

    trigger_sl = Enum.find(result.swimlanes, &(&1.name == "Triggers"))
    cmd_sl = Enum.find(result.swimlanes, &(&1.name == "Processing"))
    event_sl = Enum.find(result.swimlanes, &(&1.name == "Events"))

    assert trigger_sl.type == :trigger
    assert cmd_sl.type == :command_view
    assert event_sl.type == :event
  end

  test "swimlanes are ordered by type: trigger on top, events at bottom" do
    event_model = %EventModel{
      slices: [
        %Slice{
          name: "Test",
          steps: [
            # Insert in non-sorted order
            %Element{id: "1", type: :event, label: "ThingDone", swimlane: "Events"},
            %Element{id: "2", type: :wireframe, label: "Form", swimlane: "Triggers"},
            %Element{id: "3", type: :command, label: "DoThing", swimlane: "Processing"}
          ]
        }
      ]
    }

    result = Layout.compute(event_model)

    # Should be sorted: trigger first, command_view second, event third
    types = Enum.map(result.swimlanes, & &1.type)
    assert types == [:trigger, :command_view, :event]

    # Y positions should increase: trigger < command_view < event
    ys = Enum.map(result.swimlanes, & &1.y)
    assert ys == Enum.sort(ys)
  end

  test "elements without swimlane get typed default" do
    event_model = %EventModel{
      slices: [
        %Slice{
          name: "Test",
          steps: [
            %Element{id: "1", type: :wireframe, label: "Form"},
            %Element{id: "2", type: :command, label: "DoThing"},
            %Element{id: "3", type: :event, label: "ThingDone"}
          ]
        }
      ]
    }

    result = Layout.compute(event_model)

    wireframe = Enum.find(result.elements, &(&1.id == "1"))
    command = Enum.find(result.elements, &(&1.id == "2"))
    event = Enum.find(result.elements, &(&1.id == "3"))

    assert wireframe.swimlane == "Triggers"
    assert command.swimlane == "Processing"
    assert event.swimlane == "Events"
  end

  test "canvas width accommodates multi-element slices" do
    event_model = %EventModel{
      slices: [
        %Slice{
          name: "BigSlice",
          steps: [
            %Element{id: "1", type: :wireframe, label: "Screen"},
            %Element{id: "2", type: :command, label: "DoThing"},
            %Element{id: "3", type: :event, label: "ThingDone"},
            %Element{id: "4", type: :view, label: "Result"}
          ]
        }
      ]
    }

    result = Layout.compute(event_model)

    # The rightmost element's right edge should be within the canvas width
    rightmost = result.elements |> Enum.map(&(&1.x + &1.width)) |> Enum.max()
    assert result.width >= rightmost

    # Swimlane bands should have positive height
    Enum.each(result.swimlanes, fn sl ->
      assert sl.height > 0
    end)

    # Slice label width should span all elements in the slice
    [label] = result.slice_labels
    first_x = Enum.min_by(result.elements, & &1.x).x
    assert label.x == first_x
    assert label.width > 0
  end

  test "includes slice labels" do
    event_model = %EventModel{
      slices: [
        %Slice{
          name: "RegisterUser",
          steps: [%Element{id: "1", type: :command, label: "Register"}]
        }
      ]
    }

    result = Layout.compute(event_model)
    assert length(result.slice_labels) == 1
    assert hd(result.slice_labels).name == "RegisterUser"
  end
end
