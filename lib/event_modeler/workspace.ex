defmodule EventModeler.Workspace do
  @moduledoc """
  Module for file operations on Event Model files within a workspace directory.
  """

  alias EventModeler.EventModel
  alias EventModeler.EventModel.{Parser, Serializer, EventEntry}

  @doc """
  Returns the configured workspace directory.
  Defaults to `priv/event_models/` within the application.
  """
  @spec workspace_dir() :: String.t()
  def workspace_dir do
    Application.get_env(:event_modeler, :workspace_dir, default_workspace_dir())
  end

  defp default_workspace_dir do
    Path.join(:code.priv_dir(:event_modeler) |> to_string(), "event_models")
  end

  @doc """
  Lists Event Model files in the workspace directory.
  Returns a list of maps with path, title, and status from frontmatter.
  """
  @spec list_event_models() :: [map()]
  @spec list_event_models(String.t()) :: [map()]
  def list_event_models(dir \\ nil) do
    dir = dir || workspace_dir()

    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".md"))
        |> Enum.sort()
        |> Enum.map(fn filename ->
          path = Path.join(dir, filename)
          quick_parse(path, filename)
        end)

      {:error, _} ->
        []
    end
  end

  defp quick_parse(path, filename) do
    case File.read(path) do
      {:ok, content} ->
        case EventModel.FrontmatterParser.parse(content) do
          {:ok, fm, _rest} ->
            %{
              path: path,
              filename: filename,
              title: fm["title"] || Path.rootname(filename),
              status: fm["status"] || "unknown"
            }

          _ ->
            %{path: path, filename: filename, title: Path.rootname(filename), status: "unknown"}
        end

      {:error, _} ->
        %{path: path, filename: filename, title: Path.rootname(filename), status: "error"}
    end
  end

  @doc """
  Reads and fully parses an Event Model file.
  """
  @spec read_event_model(String.t()) :: {:ok, EventModel.t()} | {:error, String.t()}
  def read_event_model(path) do
    case File.read(path) do
      {:ok, content} -> Parser.parse(content)
      {:error, reason} -> {:error, "Cannot read file: #{reason}"}
    end
  end

  @doc """
  Serializes a `%EventModel{}` and writes it to disk.
  Updates frontmatter timestamps on save.
  """
  @spec write_event_model(String.t(), EventModel.t()) :: :ok | {:error, String.t()}
  def write_event_model(path, %EventModel{} = event_model) do
    content = Serializer.serialize_for_save(event_model)

    case File.write(path, content) do
      :ok -> :ok
      {:error, reason} -> {:error, "Cannot write file: #{reason}"}
    end
  end

  @doc """
  Creates a new Event Model file from the template with the given title.
  """
  @spec create_event_model(String.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def create_event_model(dir \\ nil, title) do
    dir = dir || workspace_dir()
    File.mkdir_p!(dir)

    filename = slugify(title) <> ".md"
    path = Path.join(dir, filename)

    if File.exists?(path) do
      {:error, "File already exists: #{filename}"}
    else
      now = DateTime.utc_now() |> DateTime.to_iso8601()

      event_model = %EventModel{
        title: title,
        status: "draft",
        version: 1,
        created: now,
        updated: now,
        dependencies: [],
        tags: ["event-modeling"],
        overview: "TODO: Describe the feature.",
        key_ideas: [],
        slices: [],
        scenarios: [],
        event_stream: [
          %EventEntry{
            seq: 1,
            ts: now,
            type: "EventModelCreated",
            actor: "system",
            data: %{"title" => title, "status" => "draft"}
          }
        ]
      }

      case write_event_model(path, event_model) do
        :ok -> {:ok, path}
        error -> error
      end
    end
  end

  defp slugify(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.trim("-")
  end
end
