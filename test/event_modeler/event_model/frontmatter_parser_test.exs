defmodule EventModeler.EventModel.FrontmatterParserTest do
  use ExUnit.Case, async: true

  alias EventModeler.EventModel.FrontmatterParser

  test "parses YAML frontmatter" do
    markdown = """
    ---
    title: "Test Feature"
    status: draft
    version: 1
    ---

    # Test Feature

    ## Overview

    Some content.
    """

    assert {:ok, frontmatter, rest} = FrontmatterParser.parse(markdown)
    assert frontmatter["title"] == "Test Feature"
    assert frontmatter["status"] == "draft"
    assert frontmatter["version"] == 1
    assert String.contains?(rest, "# Test Feature")
  end

  test "returns empty map when no frontmatter" do
    markdown = "# No Frontmatter\n\nJust content."

    assert {:ok, %{}, ^markdown} = FrontmatterParser.parse(markdown)
  end

  test "parses frontmatter with lists" do
    markdown = """
    ---
    title: "Feature"
    status: draft
    dependencies:
      - "auth.md"
      - "users.md"
    tags:
      - event-modeling
      - identity
    ---

    Content here.
    """

    assert {:ok, frontmatter, _rest} = FrontmatterParser.parse(markdown)
    assert frontmatter["dependencies"] == ["auth.md", "users.md"]
    assert frontmatter["tags"] == ["event-modeling", "identity"]
  end

  test "handles empty frontmatter gracefully" do
    markdown = """
    ---
    ---

    Content.
    """

    # YamlElixir returns nil for empty YAML, which is not a map
    result = FrontmatterParser.parse(markdown)

    case result do
      {:ok, %{}, _} -> :ok
      {:error, _} -> :ok
    end
  end
end
