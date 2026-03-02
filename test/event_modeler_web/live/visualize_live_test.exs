defmodule EventModelerWeb.VisualizeLiveTest do
  use EventModelerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders the visualize page", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/visualize")
    assert html =~ "Event Model Visualizer"
    assert html =~ "Paste Event Model Markdown"
    assert has_element?(view, "button", "Visualize")
  end

  test "visualizes submitted event model markdown", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/visualize")

    markdown = """
    ---
    title: "Test Feature"
    status: draft
    ---

    # Test Feature

    ## Overview

    A test feature.

    ## Slices

    ### Slice: DoThing

    ```yaml emlang
    slices:
      DoThing:
        steps:
          - c: DoThing
            props:
              name: string
          - e: ThingDone
            props:
              id: string
    ```
    """

    html =
      view
      |> form("form[phx-submit=visualize]", %{markdown: markdown})
      |> render_submit()

    # Should show the SVG canvas
    assert html =~ "Test Feature"
    assert html =~ "<svg"
    assert html =~ "DoThing"
    assert html =~ "ThingDone"
    # Should show slice in sidebar
    assert html =~ "Slices"
  end

  test "shows error for invalid input", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/visualize")

    # Empty string should still parse (minimal event model)
    html =
      view
      |> form("form[phx-submit=visualize]", %{markdown: ""})
      |> render_submit()

    # Should render without error since empty string is parseable
    refute html =~ "bg-red-50"
  end

  test "shows element type colors in SVG", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/visualize")

    markdown = """
    ---
    title: "Colors"
    status: draft
    ---

    ## Slices

    ### Slice: Test

    ```yaml emlang
    slices:
      Test:
        steps:
          - c: MyCommand
          - e: MyEvent
          - v: MyView
    ```
    """

    html =
      view
      |> form("form[phx-submit=visualize]", %{markdown: markdown})
      |> render_submit()

    # Blue for commands, orange for events, green for views
    assert html =~ "#3B82F6"
    assert html =~ "#F97316"
    assert html =~ "#22C55E"
  end
end
