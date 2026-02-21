defmodule EventModeler.Workshop.ScenarioGeneratorTest do
  use ExUnit.Case, async: true

  alias EventModeler.Workshop.ScenarioGenerator
  alias EventModeler.Prd.{Slice, Element}

  test "generates scenario from simple command-event slice" do
    slice = %Slice{
      name: "RegisterUser",
      steps: [
        %Element{id: "1", type: :command, label: "RegisterUser", props: %{"email" => "string"}},
        %Element{
          id: "2",
          type: :event,
          label: "UserRegistered",
          swimlane: "User",
          props: %{"userId" => "string"}
        }
      ]
    }

    scenarios = ScenarioGenerator.generate(slice)

    assert length(scenarios) == 1
    [scenario] = scenarios
    assert scenario.name == "RegisterUserHappyPath"
    assert scenario.auto_generated == true

    # When should be the command
    assert length(scenario.when_clause) == 1
    assert hd(scenario.when_clause).label == "RegisterUser"

    # Then should be the event
    assert length(scenario.then_clause) == 1
    assert hd(scenario.then_clause).label == "User/UserRegistered"
  end

  test "generates scenario with preconditions (given)" do
    slice = %Slice{
      name: "LoginUser",
      steps: [
        %Element{id: "1", type: :event, label: "UserRegistered", swimlane: "User", props: %{}},
        %Element{id: "2", type: :command, label: "LoginUser", props: %{"email" => "string"}},
        %Element{id: "3", type: :event, label: "UserLoggedIn", props: %{}}
      ]
    }

    scenarios = ScenarioGenerator.generate(slice)
    [scenario] = scenarios

    # Given should include the event before the command
    assert length(scenario.given) == 1
    assert hd(scenario.given).label == "User/UserRegistered"

    # Then should include the event after the command
    assert length(scenario.then_clause) == 1
  end

  test "generates scenario with view in then" do
    slice = %Slice{
      name: "CreateBoard",
      steps: [
        %Element{id: "1", type: :wireframe, label: "DashboardPage", swimlane: "User", props: %{}},
        %Element{id: "2", type: :command, label: "CreateBoard", props: %{"title" => "string"}},
        %Element{
          id: "3",
          type: :event,
          label: "BoardCreated",
          swimlane: "Board",
          props: %{}
        },
        %Element{id: "4", type: :view, label: "BoardCanvas", props: %{}}
      ]
    }

    scenarios = ScenarioGenerator.generate(slice)
    [scenario] = scenarios

    # Then should include both event and view
    assert length(scenario.then_clause) == 2
    types = Enum.map(scenario.then_clause, & &1.type)
    assert "e" in types
    assert "v" in types
  end

  test "returns empty list for slice with no commands" do
    slice = %Slice{
      name: "EventsOnly",
      steps: [
        %Element{id: "1", type: :event, label: "Something", props: %{}}
      ]
    }

    assert ScenarioGenerator.generate(slice) == []
  end

  test "includes element properties in scenario" do
    slice = %Slice{
      name: "Test",
      steps: [
        %Element{
          id: "1",
          type: :command,
          label: "DoThing",
          props: %{"name" => "string", "value" => "number"}
        },
        %Element{id: "2", type: :event, label: "ThingDone", props: %{}}
      ]
    }

    [scenario] = ScenarioGenerator.generate(slice)
    assert hd(scenario.when_clause).props == %{"name" => "string", "value" => "number"}
  end
end
