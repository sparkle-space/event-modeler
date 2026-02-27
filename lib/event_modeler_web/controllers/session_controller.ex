defmodule EventModelerWeb.SessionController do
  use EventModelerWeb, :controller

  def new(conn, _params) do
    if get_session(conn, :authenticated) do
      redirect(conn, to: ~p"/")
    else
      render(conn, :new, error: nil, layout: false)
    end
  end

  def create(conn, %{"password" => password}) do
    expected = Application.get_env(:event_modeler, :auth_password)

    if Plug.Crypto.secure_compare(password, expected) do
      conn
      |> put_session(:authenticated, true)
      |> redirect(to: ~p"/")
    else
      render(conn, :new, error: "Invalid password", layout: false)
    end
  end

  def delete(conn, _params) do
    conn
    |> clear_session()
    |> redirect(to: ~p"/login")
  end
end
