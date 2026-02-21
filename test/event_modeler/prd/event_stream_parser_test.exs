defmodule EventModeler.Prd.EventStreamParserTest do
  use ExUnit.Case, async: true

  alias EventModeler.Prd.EventStreamParser

  test "parses event stream entries" do
    markdown = """
    # Document

    ## Overview

    Content.

    <!-- event-stream -->
    ## Event Stream

    ```eventstream
    seq: 1
    ts: "2026-02-21T10:00:00Z"
    type: PrdCreated
    actor: facilitator@example.com
    data:
      title: "Test"
      status: draft
    ```

    ```eventstream
    seq: 2
    ts: "2026-02-21T10:05:00Z"
    type: SliceAdded
    actor: facilitator@example.com
    session: "workshop-1"
    data:
      sliceName: RegisterUser
    ```
    """

    assert {:ok, entries} = EventStreamParser.parse(markdown)
    assert length(entries) == 2

    [first, second] = entries
    assert first.seq == 1
    assert first.type == "PrdCreated"
    assert first.actor == "facilitator@example.com"
    assert first.data["title"] == "Test"
    assert first.session == nil

    assert second.seq == 2
    assert second.type == "SliceAdded"
    assert second.session == "workshop-1"
  end

  test "returns empty list when no sentinel" do
    markdown = "# Document\n\nNo event stream here."

    assert {:ok, []} = EventStreamParser.parse(markdown)
  end

  test "returns empty list when sentinel exists but no blocks" do
    markdown = """
    # Document

    <!-- event-stream -->
    ## Event Stream
    """

    assert {:ok, []} = EventStreamParser.parse(markdown)
  end

  test "extracts eventstream blocks" do
    content = """
    ## Event Stream

    ```eventstream
    seq: 1
    ts: "2026-02-21T10:00:00Z"
    type: PrdCreated
    actor: system
    data:
      title: Test
    ```
    """

    blocks = EventStreamParser.extract_eventstream_blocks(content)
    assert length(blocks) == 1
    assert hd(blocks) =~ "seq: 1"
  end

  test "parses optional fields" do
    markdown = """
    <!-- event-stream -->
    ## Event Stream

    ```eventstream
    seq: 1
    ts: "2026-02-21T10:00:00Z"
    type: PrdCreated
    actor: system
    data:
      title: Test
    session: "session-1"
    ref: "slice-123"
    note: "Initial creation"
    ```
    """

    assert {:ok, [entry]} = EventStreamParser.parse(markdown)
    assert entry.session == "session-1"
    assert entry.ref == "slice-123"
    assert entry.note == "Initial creation"
  end
end
