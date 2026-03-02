defmodule EventModeler.EventModel.SerializerTest do
  use ExUnit.Case, async: true

  alias EventModeler.EventModel
  alias EventModeler.EventModel.{Serializer, Parser, Slice, Element, EventEntry}

  test "serializes a minimal event model" do
    event_model = %EventModel{
      title: "Test",
      status: "draft",
      overview: "A test feature."
    }

    result = Serializer.serialize(event_model)
    assert result =~ "title:"
    assert result =~ "Test"
    assert result =~ "status:"
    assert result =~ "draft"
    assert result =~ "## Overview"
    assert result =~ "A test feature."
  end

  test "serializes slices as emlang blocks" do
    event_model = %EventModel{
      title: "Feature",
      status: "draft",
      slices: [
        %Slice{
          name: "DoThing",
          wireframe_description: "A form",
          steps: [
            %Element{type: :command, label: "DoThing", props: %{"name" => "string"}},
            %Element{type: :event, label: "ThingDone", swimlane: "Domain", props: %{}}
          ],
          tests: []
        }
      ]
    }

    result = Serializer.serialize(event_model)
    assert result =~ "## Slices"
    assert result =~ "### Slice: DoThing"
    assert result =~ "**Wireframe:** A form"
    assert result =~ "```yaml emlang"
    assert result =~ "c: DoThing"
    assert result =~ "e: Domain/ThingDone"
    assert result =~ "name: string"
  end

  test "serializes event stream entries" do
    event_model = %EventModel{
      title: "Test",
      status: "draft",
      event_stream: [
        %EventEntry{
          seq: 1,
          ts: "2026-02-21T10:00:00Z",
          type: "EventModelCreated",
          actor: "system",
          data: %{"title" => "Test", "status" => "draft"}
        }
      ]
    }

    result = Serializer.serialize(event_model)
    assert result =~ "<!-- event-stream -->"
    assert result =~ "## Event Stream"
    assert result =~ "```eventstream"
    assert result =~ "seq: 1"
    assert result =~ "EventModelCreated"
  end

  test "round-trip: parse -> serialize -> parse preserves data" do
    template = File.read!("docs/templates/feature-event-model.md")
    {:ok, event_model1} = Parser.parse(template)

    serialized = Serializer.serialize(event_model1)
    {:ok, event_model2} = Parser.parse(serialized)

    # Title, status, domain should survive round-trip
    assert event_model2.title == event_model1.title
    assert event_model2.status == event_model1.status
    assert event_model2.domain == event_model1.domain

    # Same number of slices
    assert length(event_model2.slices) == length(event_model1.slices)

    # Same slice names
    names1 = Enum.map(event_model1.slices, & &1.name) |> Enum.sort()
    names2 = Enum.map(event_model2.slices, & &1.name) |> Enum.sort()
    assert names2 == names1

    # Same number of event stream entries
    assert length(event_model2.event_stream) == length(event_model1.event_stream)
  end

  test "serializes frontmatter with lists" do
    event_model = %EventModel{
      title: "Test",
      status: "draft",
      dependencies: ["auth.md"],
      tags: ["event-modeling", "test"]
    }

    result = Serializer.serialize(event_model)
    assert result =~ "dependencies:"
    assert result =~ "auth.md"
    assert result =~ "tags:"
    assert result =~ "event-modeling"
  end

  test "serialize_for_save updates timestamp" do
    event_model = %EventModel{
      title: "Test",
      status: "draft",
      updated: "2026-01-01T00:00:00Z"
    }

    result = Serializer.serialize_for_save(event_model)
    # The updated timestamp should not be the old one
    refute result =~ "2026-01-01T00:00:00Z"
  end

  test "serialize_for_save promotes draft to refined when scenarios exist" do
    event_model = %EventModel{
      title: "Test",
      status: "draft",
      slices: [
        %Slice{
          name: "TestSlice",
          steps: [%Element{type: :command, label: "Cmd", props: %{}}],
          tests: [%{name: "TestHappyPath", given: [], when_clause: [], then_clause: []}]
        }
      ]
    }

    result = Serializer.serialize_for_save(event_model)
    assert result =~ "refined"
  end

  test "serialize_for_save keeps draft status when no scenarios" do
    event_model = %EventModel{
      title: "Test",
      status: "draft",
      slices: [
        %Slice{
          name: "TestSlice",
          steps: [%Element{type: :command, label: "Cmd", props: %{}}],
          tests: []
        }
      ]
    }

    result = Serializer.serialize_for_save(event_model)
    assert result =~ ~s(status: "draft")
  end

  test "generates data flows table from matching field names" do
    event_model = %EventModel{
      title: "Test",
      status: "draft",
      slices: [
        %Slice{
          name: "Register",
          steps: [
            %Element{type: :command, label: "Register", props: %{"email" => "string"}},
            %Element{type: :event, label: "Registered", props: %{"email" => "string"}},
            %Element{type: :view, label: "Profile", props: %{"email" => "string"}}
          ],
          tests: []
        }
      ]
    }

    result = Serializer.serialize(event_model)
    assert result =~ "## Data Flows"
    assert result =~ "| Register | email | Registered | email |"
    assert result =~ "| Registered | email | Profile | email |"
  end

  test "double round-trip preserves all data" do
    event_model1 = %EventModel{
      title: "Round Trip Test",
      status: "draft",
      domain: "testing",
      version: 1,
      created: "2026-01-01T00:00:00Z",
      updated: "2026-01-01T00:00:00Z",
      tags: ["test"],
      dependencies: [],
      overview: "Testing round-trip fidelity.",
      key_ideas: ["First idea", "Second idea"],
      slices: [
        %Slice{
          name: "DoThing",
          steps: [
            %Element{id: "1", type: :command, label: "DoThing", props: %{"name" => "string"}},
            %Element{id: "2", type: :event, label: "ThingDone", swimlane: "Domain", props: %{}}
          ],
          tests: [
            %{
              name: "DoThingHappyPath",
              given: [],
              when_clause: [%{type: "c", label: "DoThing", props: %{"name" => "string"}}],
              then_clause: [%{type: "e", label: "Domain/ThingDone", props: %{}}],
              auto_generated: true
            }
          ]
        }
      ],
      event_stream: [
        %EventEntry{
          seq: 1,
          ts: "2026-01-01T00:00:00Z",
          type: "EventModelCreated",
          actor: "system",
          data: %{"title" => "Round Trip Test"}
        }
      ]
    }

    serialized1 = Serializer.serialize(event_model1)
    {:ok, event_model2} = Parser.parse(serialized1)
    serialized2 = Serializer.serialize(event_model2)
    {:ok, event_model3} = Parser.parse(serialized2)

    # Structural equivalence after double round-trip
    assert event_model3.title == event_model1.title
    assert event_model3.status == event_model1.status
    assert event_model3.domain == event_model1.domain
    assert event_model3.overview == event_model1.overview
    assert length(event_model3.slices) == length(event_model1.slices)
    assert length(event_model3.event_stream) == length(event_model1.event_stream)

    # Slice details preserved
    [s1] = event_model1.slices
    [s3] = event_model3.slices
    assert s3.name == s1.name
    assert length(s3.steps) == length(s1.steps)
  end
end
