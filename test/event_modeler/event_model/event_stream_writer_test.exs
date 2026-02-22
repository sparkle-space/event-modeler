defmodule EventModeler.EventModel.EventStreamWriterTest do
  use ExUnit.Case, async: true

  alias EventModeler.EventModel
  alias EventModeler.EventModel.{EventStreamWriter, EventEntry}

  test "appends event to empty stream" do
    event_model = %EventModel{event_stream: []}
    result = EventStreamWriter.append(event_model, "ElementAdded", "user", %{"label" => "Test"})

    assert length(result.event_stream) == 1
    [entry] = result.event_stream
    assert entry.seq == 1
    assert entry.type == "ElementAdded"
    assert entry.actor == "user"
    assert entry.data == %{"label" => "Test"}
  end

  test "auto-increments sequence number" do
    event_model = %EventModel{
      event_stream: [
        %EventEntry{
          seq: 1,
          ts: "2026-01-01T00:00:00Z",
          type: "EventModelCreated",
          actor: "system",
          data: %{}
        },
        %EventEntry{
          seq: 2,
          ts: "2026-01-01T00:01:00Z",
          type: "SliceAdded",
          actor: "system",
          data: %{}
        }
      ]
    }

    result = EventStreamWriter.append(event_model, "ElementAdded", "user", %{})
    assert List.last(result.event_stream).seq == 3
  end

  test "supports optional fields" do
    event_model = %EventModel{event_stream: []}

    result =
      EventStreamWriter.append(event_model, "SliceAdded", "user", %{"name" => "Test"},
        session: "workshop-1",
        ref: "slice-123",
        note: "First slice"
      )

    [entry] = result.event_stream
    assert entry.session == "workshop-1"
    assert entry.ref == "slice-123"
    assert entry.note == "First slice"
  end

  test "handles nil event_stream" do
    event_model = %EventModel{event_stream: nil}
    result = EventStreamWriter.append(event_model, "EventModelCreated", "system", %{})
    assert length(result.event_stream) == 1
    assert hd(result.event_stream).seq == 1
  end
end
