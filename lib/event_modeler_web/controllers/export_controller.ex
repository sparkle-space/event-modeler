defmodule EventModelerWeb.ExportController do
  use EventModelerWeb, :controller

  alias EventModeler.Prd.Serializer
  alias EventModeler.Board

  def export(conn, %{"path" => encoded_path}) do
    with {:ok, file_path} <- Base.url_decode64(encoded_path, padding: false),
         {:ok, state} <- Board.get_state(file_path) do
      filename = Path.basename(file_path)
      content = Serializer.serialize(state.prd)

      conn
      |> put_resp_content_type("text/markdown")
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
      |> send_resp(200, content)
    else
      _ ->
        conn
        |> put_flash(:error, "Board not found or not open")
        |> redirect(to: ~p"/boards")
    end
  end
end
