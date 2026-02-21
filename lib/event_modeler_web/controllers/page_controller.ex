defmodule EventModelerWeb.PageController do
  use EventModelerWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
