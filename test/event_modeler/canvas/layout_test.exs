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

  test "connection direction adjusts when target element has negative offset" do
    event_model = %EventModel{
      slices: [
        %Slice{
          name: "Test",
          steps: [
            %Element{id: "a", type: :command, label: "Cmd", props: %{}},
            %Element{
              id: "b",
              type: :event,
              label: "Evt",
              props: %{"position_offset_x" => -500}
            }
          ]
        }
      ]
    }

    result = Layout.compute(event_model)
    [conn] = result.connections

    elem_a = Enum.find(result.elements, &(&1.id == "a"))
    elem_b = Enum.find(result.elements, &(&1.id == "b"))

    # Element b is to the left of element a due to negative offset
    assert elem_b.x < elem_a.x

    # Connection always goes from right edge of source to left edge of target
    assert conn.from_x == elem_a.x + elem_a.width
    assert conn.to_x == elem_b.x
  end

  test "applies position offsets from element props" do
    event_model = %EventModel{
      slices: [
        %Slice{
          name: "Test",
          steps: [
            %Element{
              id: "1",
              type: :command,
              label: "Cmd",
              props: %{"position_offset_x" => 50, "position_offset_y" => -20}
            },
            %Element{id: "2", type: :event, label: "Evt", props: %{}}
          ]
        }
      ]
    }

    result = Layout.compute(event_model)

    cmd = Enum.find(result.elements, &(&1.id == "1"))
    evt = Enum.find(result.elements, &(&1.id == "2"))

    # The element without offsets should have normal position
    # The element with offsets should be displaced relative to where it would be
    # Compute what the base position would be (without offsets)
    base_model = %EventModel{
      slices: [
        %Slice{
          name: "Test",
          steps: [
            %Element{id: "1", type: :command, label: "Cmd", props: %{}},
            %Element{id: "2", type: :event, label: "Evt", props: %{}}
          ]
        }
      ]
    }

    base_result = Layout.compute(base_model)
    base_cmd = Enum.find(base_result.elements, &(&1.id == "1"))
    base_evt = Enum.find(base_result.elements, &(&1.id == "2"))

    # Element with offsets should be displaced
    assert cmd.x == base_cmd.x + 50
    assert cmd.y == base_cmd.y - 20

    # Element without offsets should be in the same position
    assert evt.x == base_evt.x
    assert evt.y == base_evt.y
  end

  describe "slice_connections" do
    test "computes slice connections from produces_for" do
      event_model = %EventModel{
        slices: [
          %Slice{
            name: "Producer",
            steps: [
              %Element{id: "1", type: :command, label: "Produce"},
              %Element{id: "2", type: :event, label: "Produced", swimlane: "Domain"}
            ],
            connections: %{
              consumes: [],
              produces_for: ["Consumer"],
              gates: []
            }
          },
          %Slice{
            name: "Consumer",
            steps: [
              %Element{id: "3", type: :command, label: "Consume"},
              %Element{id: "4", type: :event, label: "Consumed"}
            ]
          }
        ]
      }

      result = Layout.compute(event_model)
      assert length(result.slice_connections) == 1

      [conn] = result.slice_connections
      assert conn.from_slice == "Producer"
      assert conn.to_slice == "Consumer"
      assert conn.type == :produces_for
      assert conn.style == :solid
    end

    test "computes slice connections from consumes" do
      event_model = %EventModel{
        slices: [
          %Slice{
            name: "Producer",
            steps: [
              %Element{id: "1", type: :command, label: "Produce"},
              %Element{id: "2", type: :event, label: "Produced", swimlane: "Domain"}
            ]
          },
          %Slice{
            name: "Consumer",
            steps: [
              %Element{id: "3", type: :command, label: "Consume"},
              %Element{id: "4", type: :event, label: "Consumed"}
            ],
            connections: %{
              consumes: ["Domain/Produced"],
              produces_for: [],
              gates: []
            }
          }
        ]
      }

      result = Layout.compute(event_model)
      assert length(result.slice_connections) == 1

      [conn] = result.slice_connections
      assert conn.from_slice == "Producer"
      assert conn.to_slice == "Consumer"
      assert conn.type == :consumes
      assert conn.style == :solid
    end

    test "cross-context references without local match produce dashed style" do
      event_model = %EventModel{
        slices: [
          %Slice{
            name: "Consumer",
            steps: [
              %Element{id: "1", type: :command, label: "Consume"},
              %Element{id: "2", type: :event, label: "Consumed"}
            ],
            connections: %{
              consumes: ["External/SomethingHappened"],
              produces_for: [],
              gates: []
            }
          }
        ]
      }

      result = Layout.compute(event_model)
      assert length(result.slice_connections) == 1
      [conn] = result.slice_connections
      assert conn.style == :dashed
    end

    test "no connections when connections field is nil" do
      event_model = %EventModel{
        slices: [
          %Slice{
            name: "Simple",
            steps: [%Element{id: "1", type: :command, label: "Cmd"}]
          }
        ]
      }

      result = Layout.compute(event_model)
      assert result.slice_connections == []
    end

    test "deduplicates connections by from/to pair" do
      event_model = %EventModel{
        slices: [
          %Slice{
            name: "A",
            steps: [
              %Element{id: "1", type: :command, label: "Do"},
              %Element{id: "2", type: :event, label: "Done", swimlane: "X"}
            ],
            connections: %{
              consumes: [],
              produces_for: ["B"],
              gates: []
            }
          },
          %Slice{
            name: "B",
            steps: [
              %Element{id: "3", type: :command, label: "Handle"},
              %Element{id: "4", type: :event, label: "Handled"}
            ],
            connections: %{
              consumes: ["X/Done"],
              produces_for: [],
              gates: []
            }
          }
        ]
      }

      result = Layout.compute(event_model)
      # Both A->B from produces_for and A->B from consumes should deduplicate
      a_to_b =
        Enum.filter(result.slice_connections, fn c ->
          c.from_slice == "A" and c.to_slice == "B"
        end)

      assert length(a_to_b) == 1
    end
  end

  describe "compute_spec_cards/3" do
    test "returns empty for slice with no tests" do
      event_model = %EventModel{
        slices: [
          %Slice{
            name: "NoTests",
            steps: [%Element{id: "1", type: :command, label: "Cmd"}],
            tests: []
          }
        ]
      }

      layout = Layout.compute(event_model)
      {cards, indicator, extra} = Layout.compute_spec_cards(event_model.slices, "NoTests", layout)

      assert cards == []
      assert indicator == nil
      assert extra == 0
    end

    test "returns empty for nonexistent slice" do
      event_model = %EventModel{slices: []}
      layout = Layout.compute(event_model)

      {cards, indicator, extra} =
        Layout.compute_spec_cards(event_model.slices, "Missing", layout)

      assert cards == []
      assert indicator == nil
      assert extra == 0
    end

    test "computes indicator for slice with tests" do
      event_model = %EventModel{
        slices: [
          %Slice{
            name: "WithTests",
            steps: [
              %Element{id: "1", type: :command, label: "Register"},
              %Element{id: "2", type: :event, label: "Registered"}
            ],
            tests: [
              %{
                name: "HappyPath",
                given: [%{type: "e", label: "Existing"}],
                when_clause: [%{type: "c", label: "Register"}],
                then_clause: [%{type: "e", label: "Registered"}]
              }
            ]
          }
        ]
      }

      layout = Layout.compute(event_model)

      {_cards, indicator, _extra} =
        Layout.compute_spec_cards(event_model.slices, "WithTests", layout)

      assert indicator != nil
      assert indicator.slice_name == "WithTests"
      assert indicator.count == 1
      assert indicator.x > 0
      assert indicator.y > 0
    end

    test "positions spec cards below indicator" do
      event_model = %EventModel{
        slices: [
          %Slice{
            name: "WithTests",
            steps: [
              %Element{id: "1", type: :command, label: "Register"},
              %Element{id: "2", type: :event, label: "Registered"}
            ],
            tests: [
              %{
                name: "HappyPath",
                given: [%{type: "e", label: "Existing"}],
                when_clause: [%{type: "c", label: "Register"}],
                then_clause: [%{type: "e", label: "Registered"}]
              },
              %{
                name: "DuplicateEmail",
                given: [%{type: "e", label: "Existing"}],
                when_clause: [%{type: "c", label: "Register"}],
                then_clause: [%{type: "x", label: "DuplicateError"}]
              }
            ]
          }
        ]
      }

      layout = Layout.compute(event_model)

      {cards, indicator, extra} =
        Layout.compute_spec_cards(event_model.slices, "WithTests", layout)

      assert length(cards) == 2
      assert indicator.count == 2

      [card1, card2] = cards
      assert card1.name == "HappyPath"
      assert card2.name == "DuplicateEmail"
      assert card1.slice_name == "WithTests"

      # Cards should be below the indicator
      assert card1.y > indicator.y
      # Second card below first
      assert card2.y > card1.y

      # Cards share the slice's x position
      assert card1.x == indicator.x
      assert card2.x == indicator.x

      # Extra height should be positive since cards extend below layout
      assert extra >= 0

      # Cards carry their GWT data
      assert length(card1.given) == 1
      assert length(card1.when_clause) == 1
      assert length(card1.then_clause) == 1
    end
  end
end
