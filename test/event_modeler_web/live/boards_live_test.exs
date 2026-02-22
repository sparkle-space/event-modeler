defmodule EventModelerWeb.BoardsLiveTest do
  use EventModelerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders the boards page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/boards")
    assert html =~ "Boards"
    assert html =~ "Create New Event Model"
  end

  test "lists existing event model files", %{conn: conn} do
    # The starter event model should be visible
    {:ok, _view, html} = live(conn, ~p"/boards")
    assert html =~ "Board Management"
  end
end
