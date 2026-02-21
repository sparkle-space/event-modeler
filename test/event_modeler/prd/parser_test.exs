defmodule EventModeler.Prd.ParserTest do
  use ExUnit.Case, async: true

  alias EventModeler.Prd
  alias EventModeler.Prd.Parser

  test "parses empty/minimal PRD" do
    markdown = "# Minimal\n\n## Overview\n\nJust an overview."

    assert {:ok, %Prd{} = prd} = Parser.parse(markdown)
    assert prd.title == nil
    assert prd.overview == "Just an overview."
    assert prd.slices == []
    assert prd.event_stream == []
  end

  test "parses frontmatter-only PRD" do
    markdown = """
    ---
    title: "Test"
    status: draft
    version: 1
    ---

    # Test
    """

    assert {:ok, %Prd{} = prd} = Parser.parse(markdown)
    assert prd.title == "Test"
    assert prd.status == "draft"
    assert prd.version == 1
  end

  test "parses PRD with emlang blocks" do
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

    assert {:ok, %Prd{} = prd} = Parser.parse(markdown)
    assert prd.title == "Feature"
    assert prd.status == "modeling"
    assert prd.overview == "A feature overview."

    assert length(prd.slices) == 1
    [slice] = prd.slices
    assert slice.name == "DoThing"
    assert slice.wireframe_description == "A form with input fields"
    assert length(slice.steps) == 4
    assert length(slice.tests) == 1
  end

  test "parses PRD with event stream" do
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
    type: PrdCreated
    actor: system
    data:
      title: "Feature"
      status: draft
    ```
    """

    assert {:ok, %Prd{} = prd} = Parser.parse(markdown)
    assert length(prd.event_stream) == 1
    assert hd(prd.event_stream).type == "PrdCreated"
  end

  test "parses full template PRD" do
    template = File.read!("docs/templates/feature-prd.md")

    assert {:ok, %Prd{} = prd} = Parser.parse(template)
    assert prd.title == "Board Management"
    assert prd.status == "draft"
    assert prd.domain == "Board"
    assert prd.version == 1
    assert prd.overview != nil
    assert length(prd.key_ideas) == 3
    assert length(prd.slices) == 3
    assert length(prd.event_stream) == 4

    slice_names = Enum.map(prd.slices, & &1.name)
    assert "CreateBoard" in slice_names
    assert "ImportPrd" in slice_names
    assert "VisualizeModel" in slice_names

    create_board = Enum.find(prd.slices, &(&1.name == "CreateBoard"))
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

    assert {:ok, prd} = Parser.parse(markdown)
    assert prd.raw_markdown == markdown
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

    assert {:ok, prd} = Parser.parse(markdown)
    assert length(prd.scenarios) == 1

    [scenario] = prd.scenarios
    assert scenario.name == "Happy Path Flow"
    assert scenario.given =~ "a user exists"
    assert scenario.when_clause =~ "user logs in"
    assert scenario.then_clause =~ "dashboard is shown"
  end
end
