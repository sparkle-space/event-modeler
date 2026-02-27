defmodule EventModelerWeb.Plugs.Auth do
  @moduledoc """
  Plug that gates all routes behind a static password when AUTH_PASSWORD is set.

  If no password is configured, all requests pass through unchanged.
  """
  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    case Application.get_env(:event_modeler, :auth_password) do
      nil -> conn
      "" -> conn
      _password -> require_authentication(conn)
    end
  end

  defp require_authentication(conn) do
    if conn.request_path == "/login" do
      conn
    else
      if get_session(conn, :authenticated) do
        conn
      else
        conn
        |> redirect(to: "/login")
        |> halt()
      end
    end
  end
end
