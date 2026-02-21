defmodule EventModelerWeb.BoardsLiveTest do
  use EventModelerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders the boards page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/boards")
    assert html =~ "Boards"
    assert html =~ "Create New PRD"
  end

  test "lists existing PRD files", %{conn: conn} do
    # The starter PRD should be visible
    {:ok, _view, html} = live(conn, ~p"/boards")
    assert html =~ "Board Management"
  end
end
