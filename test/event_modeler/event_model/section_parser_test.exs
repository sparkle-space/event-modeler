defmodule EventModeler.EventModel.SectionParserTest do
  use ExUnit.Case, async: true

  alias EventModeler.EventModel.SectionParser

  test "parses known sections" do
    markdown = """
    ## Overview

    This is the overview section.

    ## Key Ideas

    - **Idea one** -- description one
    - **Idea two** -- description two

    ## Sources

    - [Link](http://example.com)
    """

    sections = SectionParser.parse(markdown)

    assert sections["Overview"] == "This is the overview section."
    assert String.contains?(sections["Key Ideas"], "Idea one")
    assert String.contains?(sections["Sources"], "Link")
  end

  test "ignores unknown sections" do
    markdown = """
    ## Overview

    Content.

    ## Random Section

    Should be ignored.
    """

    sections = SectionParser.parse(markdown)
    assert Map.has_key?(sections, "Overview")
    refute Map.has_key?(sections, "Random Section")
  end

  test "handles empty markdown" do
    assert SectionParser.parse("") == %{}
  end

  test "splits event stream content" do
    markdown = """
    ## Overview

    Content.

    <!-- event-stream -->
    ## Event Stream

    Stream content.
    """

    {before, event_part} = SectionParser.split_event_stream(markdown)
    assert String.contains?(before, "Content.")
    assert String.contains?(event_part, "Stream content.")
  end

  test "extracts key ideas from bullet list" do
    content = """
    - **Board creation** -- Users create named boards
    - **Event model import** -- Existing markdown event models can be imported
    """

    ideas = SectionParser.extract_key_ideas(content)
    assert length(ideas) == 2
    assert Enum.at(ideas, 0) =~ "Board creation"
    assert Enum.at(ideas, 1) =~ "Event model import"
  end

  test "extract_key_ideas returns empty list for nil" do
    assert SectionParser.extract_key_ideas(nil) == []
  end
end
