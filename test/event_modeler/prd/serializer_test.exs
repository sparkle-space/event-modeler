defmodule EventModeler.Prd.SerializerTest do
  use ExUnit.Case, async: true

  alias EventModeler.Prd
  alias EventModeler.Prd.{Serializer, Parser, Slice, Element, EventEntry}

  test "serializes a minimal PRD" do
    prd = %Prd{
      title: "Test",
      status: "draft",
      overview: "A test feature."
    }

    result = Serializer.serialize(prd)
    assert result =~ "title:"
    assert result =~ "Test"
    assert result =~ "status:"
    assert result =~ "draft"
    assert result =~ "## Overview"
    assert result =~ "A test feature."
  end

  test "serializes slices as emlang blocks" do
    prd = %Prd{
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

    result = Serializer.serialize(prd)
    assert result =~ "## Slices"
    assert result =~ "### Slice: DoThing"
    assert result =~ "**Wireframe:** A form"
    assert result =~ "```emlang"
    assert result =~ "c: DoThing"
    assert result =~ "e: Domain/ThingDone"
    assert result =~ "name: string"
  end

  test "serializes event stream entries" do
    prd = %Prd{
      title: "Test",
      status: "draft",
      event_stream: [
        %EventEntry{
          seq: 1,
          ts: "2026-02-21T10:00:00Z",
          type: "PrdCreated",
          actor: "system",
          data: %{"title" => "Test", "status" => "draft"}
        }
      ]
    }

    result = Serializer.serialize(prd)
    assert result =~ "<!-- event-stream -->"
    assert result =~ "## Event Stream"
    assert result =~ "```eventstream"
    assert result =~ "seq: 1"
    assert result =~ "PrdCreated"
  end

  test "round-trip: parse -> serialize -> parse preserves data" do
    template = File.read!("docs/templates/feature-prd.md")
    {:ok, prd1} = Parser.parse(template)

    serialized = Serializer.serialize(prd1)
    {:ok, prd2} = Parser.parse(serialized)

    # Title, status, domain should survive round-trip
    assert prd2.title == prd1.title
    assert prd2.status == prd1.status
    assert prd2.domain == prd1.domain

    # Same number of slices
    assert length(prd2.slices) == length(prd1.slices)

    # Same slice names
    names1 = Enum.map(prd1.slices, & &1.name) |> Enum.sort()
    names2 = Enum.map(prd2.slices, & &1.name) |> Enum.sort()
    assert names2 == names1

    # Same number of event stream entries
    assert length(prd2.event_stream) == length(prd1.event_stream)
  end

  test "serializes frontmatter with lists" do
    prd = %Prd{
      title: "Test",
      status: "draft",
      dependencies: ["auth.md"],
      tags: ["event-modeling", "test"]
    }

    result = Serializer.serialize(prd)
    assert result =~ "dependencies:"
    assert result =~ "auth.md"
    assert result =~ "tags:"
    assert result =~ "event-modeling"
  end

  test "serialize_for_save updates timestamp" do
    prd = %Prd{
      title: "Test",
      status: "draft",
      updated: "2026-01-01T00:00:00Z"
    }

    result = Serializer.serialize_for_save(prd)
    # The updated timestamp should not be the old one
    refute result =~ "2026-01-01T00:00:00Z"
  end

  test "serialize_for_save promotes draft to refined when scenarios exist" do
    prd = %Prd{
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

    result = Serializer.serialize_for_save(prd)
    assert result =~ "refined"
  end

  test "serialize_for_save keeps draft status when no scenarios" do
    prd = %Prd{
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

    result = Serializer.serialize_for_save(prd)
    assert result =~ ~s(status: "draft")
  end

  test "generates data flows table from matching field names" do
    prd = %Prd{
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

    result = Serializer.serialize(prd)
    assert result =~ "## Data Flows"
    assert result =~ "| Register | email | Registered | email |"
    assert result =~ "| Registered | email | Profile | email |"
  end

  test "double round-trip preserves all data" do
    prd1 = %Prd{
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
          type: "PrdCreated",
          actor: "system",
          data: %{"title" => "Round Trip Test"}
        }
      ]
    }

    serialized1 = Serializer.serialize(prd1)
    {:ok, prd2} = Parser.parse(serialized1)
    serialized2 = Serializer.serialize(prd2)
    {:ok, prd3} = Parser.parse(serialized2)

    # Structural equivalence after double round-trip
    assert prd3.title == prd1.title
    assert prd3.status == prd1.status
    assert prd3.domain == prd1.domain
    assert prd3.overview == prd1.overview
    assert length(prd3.slices) == length(prd1.slices)
    assert length(prd3.event_stream) == length(prd1.event_stream)

    # Slice details preserved
    [s1] = prd1.slices
    [s3] = prd3.slices
    assert s3.name == s1.name
    assert length(s3.steps) == length(s1.steps)
  end
end
