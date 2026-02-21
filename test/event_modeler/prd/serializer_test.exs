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
end
