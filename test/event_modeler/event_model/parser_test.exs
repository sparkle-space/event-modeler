defmodule EventModeler.EventModel.ParserTest do
  use ExUnit.Case, async: true

  alias EventModeler.EventModel
  alias EventModeler.EventModel.Parser

  test "parses empty/minimal event model" do
    markdown = "# Minimal\n\n## Overview\n\nJust an overview."

    assert {:ok, %EventModel{} = event_model} = Parser.parse(markdown)
    assert event_model.title == nil
    assert event_model.overview == "Just an overview."
    assert event_model.slices == []
    assert event_model.event_stream == []
  end

  test "parses frontmatter-only event model" do
    markdown = """
    ---
    title: "Test"
    status: draft
    version: 1
    ---

    # Test
    """

    assert {:ok, %EventModel{} = event_model} = Parser.parse(markdown)
    assert event_model.title == "Test"
    assert event_model.status == "draft"
    assert event_model.version == 1
  end

  test "parses event model with emlang blocks" do
    markdown = """
    ---
    title: "Feature"
    status: modeling
    ---

    # Feature

    ## Overview

    A feature overview.

    ## Slices

    ### Slice: DoThing

    **Wireframe:** A form with input fields

    ```emlang
    slices:
      DoThing:
        steps:
          - t: User/FormPage
          - c: DoThing
            props:
              name: string
          - e: Domain/ThingDone
            props:
              id: string
              name: string
          - v: ConfirmationPage
        tests:
          HappyPath:
            when:
              - c: DoThing
                props:
                  name: "test"
            then:
              - e: Domain/ThingDone
    ```
    """

    assert {:ok, %EventModel{} = event_model} = Parser.parse(markdown)
    assert event_model.title == "Feature"
    assert event_model.status == "modeling"
    assert event_model.overview == "A feature overview."

    assert length(event_model.slices) == 1
    [slice] = event_model.slices
    assert slice.name == "DoThing"
    assert slice.wireframe_description == "A form with input fields"
    assert length(slice.steps) == 4
    assert length(slice.tests) == 1
  end

  test "parses event model with event stream" do
    markdown = """
    ---
    title: "Feature"
    status: draft
    ---

    # Feature

    ## Overview

    Overview.

    <!-- event-stream -->
    ## Event Stream

    ```eventstream
    seq: 1
    ts: "2026-02-21T10:00:00Z"
    type: EventModelCreated
    actor: system
    data:
      title: "Feature"
      status: draft
    ```
    """

    assert {:ok, %EventModel{} = event_model} = Parser.parse(markdown)
    assert length(event_model.event_stream) == 1
    assert hd(event_model.event_stream).type == "EventModelCreated"
  end

  test "parses full template event model" do
    template = File.read!("docs/templates/feature-event-model.md")

    assert {:ok, %EventModel{} = event_model} = Parser.parse(template)
    assert event_model.title == "Board Management"
    assert event_model.status == "draft"
    assert event_model.domain == "Board"
    assert event_model.version == 1
    assert event_model.overview != nil
    assert length(event_model.key_ideas) == 3
    assert length(event_model.slices) == 3
    assert length(event_model.event_stream) == 4

    slice_names = Enum.map(event_model.slices, & &1.name)
    assert "CreateBoard" in slice_names
    assert "ImportEventModel" in slice_names
    assert "VisualizeModel" in slice_names

    create_board = Enum.find(event_model.slices, &(&1.name == "CreateBoard"))
    assert length(create_board.steps) == 4
    assert length(create_board.tests) == 1
  end

  test "handles nil input" do
    assert {:error, _} = Parser.parse(nil)
  end

  test "handles non-string input" do
    assert {:error, _} = Parser.parse(42)
  end

  test "preserves raw_markdown" do
    markdown = "# Simple\n\n## Overview\n\nContent."

    assert {:ok, event_model} = Parser.parse(markdown)
    assert event_model.raw_markdown == markdown
  end

  test "parses scenarios section" do
    markdown = """
    ---
    title: "Test"
    status: draft
    ---

    # Test

    ## Scenarios

    ### Scenario: Happy Path Flow

    - **Given** a user exists
    - **When** user logs in
    - **Then** dashboard is shown
    """

    assert {:ok, event_model} = Parser.parse(markdown)
    assert length(event_model.scenarios) == 1

    [scenario] = event_model.scenarios
    assert scenario.name == "Happy Path Flow"
    assert scenario.given =~ "a user exists"
    assert scenario.when_clause =~ "user logs in"
    assert scenario.then_clause =~ "dashboard is shown"
  end
end
