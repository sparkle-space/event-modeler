defmodule EventModeler.Board do
  @moduledoc """
  GenServer managing an open board backed by a PRD file.

  Each open board has its own GenServer process, started via DynamicSupervisor
  and registered via Registry keyed by file path.
  """

  use GenServer

  alias EventModeler.Prd
  alias EventModeler.Canvas.{Layout, SvgRenderer}
  alias EventModeler.Workspace

  defstruct [:file_path, :prd, :layout, :svg_data, dirty: false]

  @type t :: %__MODULE__{
          file_path: String.t(),
          prd: Prd.t(),
          layout: map(),
          svg_data: map(),
          dirty: boolean()
        }

  @inactivity_timeout :timer.minutes(30)

  # Client API

  @doc """
  Opens a board for the given file path. Starts a new GenServer if not already running.
  """
  @spec open(String.t()) :: {:ok, pid()} | {:error, term()}
  def open(file_path) do
    case Registry.lookup(EventModeler.Board.Registry, file_path) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        DynamicSupervisor.start_child(
          EventModeler.Board.Supervisor,
          {__MODULE__, file_path}
        )
    end
  end

  @doc """
  Gets the current board state.
  """
  @spec get_state(String.t()) :: {:ok, t()} | {:error, term()}
  def get_state(file_path) do
    call(file_path, :get_state)
  end

  @doc """
  Saves the board state back to the file.
  """
  @spec save(String.t()) :: :ok | {:error, term()}
  def save(file_path) do
    call(file_path, :save)
  end

  defp call(file_path, message) do
    case Registry.lookup(EventModeler.Board.Registry, file_path) do
      [{pid, _}] -> GenServer.call(pid, message)
      [] -> {:error, :not_open}
    end
  end

  # Server

  def start_link(file_path) do
    GenServer.start_link(__MODULE__, file_path,
      name: {:via, Registry, {EventModeler.Board.Registry, file_path}}
    )
  end

  @impl true
  def init(file_path) do
    case Workspace.read_prd(file_path) do
      {:ok, prd} ->
        layout = Layout.compute(prd)
        svg_data = SvgRenderer.render(layout)

        state = %__MODULE__{
          file_path: file_path,
          prd: prd,
          layout: layout,
          svg_data: svg_data,
          dirty: false
        }

        {:ok, state, @inactivity_timeout}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, state, @inactivity_timeout}
  end

  def handle_call(:save, _from, state) do
    case Workspace.write_prd(state.file_path, state.prd) do
      :ok ->
        {:reply, :ok, %{state | dirty: false}, @inactivity_timeout}

      {:error, _} = error ->
        {:reply, error, state, @inactivity_timeout}
    end
  end

  @impl true
  def handle_info(:timeout, state) do
    {:stop, :normal, state}
  end
end
