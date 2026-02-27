defmodule EventModelerWeb.AuthHook do
  @moduledoc """
  LiveView on_mount hook that checks authentication when AUTH_PASSWORD is configured.
  """
  import Phoenix.LiveView

  def on_mount(:default, _params, session, socket) do
    case Application.get_env(:event_modeler, :auth_password) do
      nil ->
        {:cont, socket}

      "" ->
        {:cont, socket}

      _password ->
        if session["authenticated"] do
          {:cont, socket}
        else
          {:halt, redirect(socket, to: "/login")}
        end
    end
  end
end
