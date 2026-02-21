defmodule EventModeler.Workspace do
  @moduledoc """
  Module for file operations on PRD files within a workspace directory.
  """

  alias EventModeler.Prd
  alias EventModeler.Prd.{Parser, Serializer, EventEntry}

  @doc """
  Returns the configured workspace directory.
  Defaults to `priv/prds/` within the application.
  """
  @spec workspace_dir() :: String.t()
  def workspace_dir do
    Application.get_env(:event_modeler, :workspace_dir, default_workspace_dir())
  end

  defp default_workspace_dir do
    Path.join(:code.priv_dir(:event_modeler) |> to_string(), "prds")
  end

  @doc """
  Lists PRD files in the workspace directory.
  Returns a list of maps with path, title, and status from frontmatter.
  """
  @spec list_prds() :: [map()]
  @spec list_prds(String.t()) :: [map()]
  def list_prds(dir \\ nil) do
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
        case Prd.FrontmatterParser.parse(content) do
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
  Reads and fully parses a PRD file.
  """
  @spec read_prd(String.t()) :: {:ok, Prd.t()} | {:error, String.t()}
  def read_prd(path) do
    case File.read(path) do
      {:ok, content} -> Parser.parse(content)
      {:error, reason} -> {:error, "Cannot read file: #{reason}"}
    end
  end

  @doc """
  Serializes a `%Prd{}` and writes it to disk.
  Updates frontmatter timestamps on save.
  """
  @spec write_prd(String.t(), Prd.t()) :: :ok | {:error, String.t()}
  def write_prd(path, %Prd{} = prd) do
    content = Serializer.serialize_for_save(prd)

    case File.write(path, content) do
      :ok -> :ok
      {:error, reason} -> {:error, "Cannot write file: #{reason}"}
    end
  end

  @doc """
  Creates a new PRD file from the template with the given title.
  """
  @spec create_prd(String.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def create_prd(dir \\ nil, title) do
    dir = dir || workspace_dir()
    File.mkdir_p!(dir)

    filename = slugify(title) <> ".md"
    path = Path.join(dir, filename)

    if File.exists?(path) do
      {:error, "File already exists: #{filename}"}
    else
      now = DateTime.utc_now() |> DateTime.to_iso8601()

      prd = %Prd{
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
            type: "PrdCreated",
            actor: "system",
            data: %{"title" => title, "status" => "draft"}
          }
        ]
      }

      case write_prd(path, prd) do
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
