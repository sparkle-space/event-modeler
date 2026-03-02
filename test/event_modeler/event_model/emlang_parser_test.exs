defmodule EventModeler.EventModel.EmlangParserTest do
  use ExUnit.Case, async: true

  alias EventModeler.EventModel.EmlangParser

  test "parses a single slice with steps" do
    markdown = """
    ## Slices

    ### Slice: CreateBoard

    ```yaml emlang
    slices:
      CreateBoard:
        steps:
          - t: User/DashboardPage
          - c: CreateBoard
            props:
              title: string
              ownerId: string
          - e: Board/BoardCreated
            props:
              boardId: string
              title: string
          - v: BoardCanvas
    ```
    """

    assert {:ok, [slice]} = EmlangParser.parse(markdown)
    assert slice.name == "CreateBoard"
    assert length(slice.steps) == 4

    [trigger, command, event, view] = slice.steps
    assert trigger.type == :wireframe
    assert trigger.label == "DashboardPage"
    assert trigger.swimlane == "User"

    assert command.type == :command
    assert command.label == "CreateBoard"
    assert command.props == %{"title" => "string", "ownerId" => "string"}

    assert event.type == :event
    assert event.label == "BoardCreated"
    assert event.swimlane == "Board"

    assert view.type == :view
    assert view.label == "BoardCanvas"
    assert view.swimlane == nil
  end

  test "parses multiple slices from multiple blocks" do
    markdown = """
    ```yaml emlang
    slices:
      SliceOne:
        steps:
          - c: DoThing
          - e: ThingDone
    ```

    ```yaml emlang
    slices:
      SliceTwo:
        steps:
          - c: DoOther
          - e: OtherDone
    ```
    """

    assert {:ok, slices} = EmlangParser.parse(markdown)
    assert length(slices) == 2
    assert Enum.map(slices, & &1.name) == ["SliceOne", "SliceTwo"]
  end

  test "parses tests (GWT scenarios)" do
    markdown = """
    ```yaml emlang
    slices:
      RegisterUser:
        steps:
          - c: RegisterUser
          - e: User/UserRegistered
        tests:
          HappyPath:
            when:
              - c: RegisterUser
                props:
                  email: alice@example.com
            then:
              - e: User/UserRegistered
          DuplicateEmail:
            given:
              - e: User/UserRegistered
                props:
                  email: alice@example.com
            when:
              - c: RegisterUser
                props:
                  email: alice@example.com
            then:
              - x: EmailAlreadyInUse
    ```
    """

    assert {:ok, [slice]} = EmlangParser.parse(markdown)
    assert length(slice.tests) == 2

    happy = Enum.find(slice.tests, &(&1.name == "HappyPath"))
    assert happy.given == []
    assert length(happy.when_clause) == 1
    assert length(happy.then_clause) == 1

    duplicate = Enum.find(slice.tests, &(&1.name == "DuplicateEmail"))
    assert length(duplicate.given) == 1
  end

  test "handles markdown with no emlang blocks" do
    markdown = "# Just a regular document\n\nNo code blocks here."

    assert {:ok, []} = EmlangParser.parse(markdown)
  end

  test "parses multiple slices within one block" do
    markdown = """
    ```yaml emlang
    slices:
      PlaceElement:
        steps:
          - c: PlaceElement
          - e: Element/ElementPlaced
      ConnectElements:
        steps:
          - c: ConnectElements
          - e: Element/ElementsConnected
    ```
    """

    assert {:ok, slices} = EmlangParser.parse(markdown)
    assert length(slices) == 2
  end

  test "extracts raw emlang blocks" do
    markdown = """
    Some text

    ```yaml emlang
    slices:
      Test:
        steps:
          - c: Test
    ```

    More text
    """

    blocks = EmlangParser.extract_emlang_blocks(markdown)
    assert length(blocks) == 1
    assert hd(blocks) =~ "slices:"
  end
end
