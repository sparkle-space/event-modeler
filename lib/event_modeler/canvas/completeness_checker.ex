defmodule EventModeler.Canvas.CompletenessChecker do
  @moduledoc """
  DAG traversal right-to-left ensuring every View field traces back
  to a source Event.

  Checks field provenance: for each field on a View, traces backward
  through the connection chain (View <- Event <- Command) to verify
  the field has a source. Reports orphan fields (on Views with no
  matching Event field) and missing sources.
  """

  alias EventModeler.EventModel
  alias EventModeler.EventModel.Slice

  defmodule FieldTrace do
    @moduledoc false
    defstruct [:field_name, :element_label, :element_type, :status, :source]

    @type status :: :traced | :orphan | :missing_source
    @type t :: %__MODULE__{
            field_name: String.t(),
            element_label: String.t(),
            element_type: atom(),
            status: status(),
            source: String.t() | nil
          }
  end

  defmodule CheckResult do
    @moduledoc false
    defstruct [
      :slice_name,
      complete: true,
      traces: [],
      total_fields: 0,
      traced_fields: 0,
      orphan_fields: 0
    ]
  end

  @doc """
  Checks field completeness for all slices in an event model.
  Returns a list of `%CheckResult{}` per slice.
  """
  @spec check(%EventModel{}) :: [%CheckResult{}]
  def check(%EventModel{slices: slices}) when is_list(slices) do
    Enum.map(slices, &check_slice/1)
  end

  def check(_), do: []

  @doc """
  Checks completeness for a single slice.
  """
  @spec check_slice(Slice.t()) :: %CheckResult{}
  def check_slice(%Slice{} = slice) do
    steps = slice.steps || []

    views = Enum.filter(steps, &(&1.type == :view))
    events = Enum.filter(steps, &(&1.type == :event))
    commands = Enum.filter(steps, &(&1.type == :command))

    # Build field name sets for tracing
    event_field_names = collect_field_names(events)
    command_field_names = collect_field_names(commands)

    traces =
      Enum.flat_map(views, fn view ->
        view_fields = (view.fields || []) ++ props_as_fields(view.props)

        Enum.map(view_fields, fn field ->
          field_name = field_name(field)
          trace_field(field_name, view.label, event_field_names, command_field_names)
        end)
      end)

    total = length(traces)
    traced = Enum.count(traces, &(&1.status == :traced))
    orphan = Enum.count(traces, &(&1.status == :orphan))

    %CheckResult{
      slice_name: slice.name,
      complete: orphan == 0 and total > 0,
      traces: traces,
      total_fields: total,
      traced_fields: traced,
      orphan_fields: orphan
    }
  end

  defp trace_field(field_name, view_label, event_fields, command_fields) do
    downcased = String.downcase(field_name)

    event_source =
      Enum.find(event_fields, fn {name, _source} ->
        String.downcase(name) == downcased
      end)

    command_source =
      Enum.find(command_fields, fn {name, _source} ->
        String.downcase(name) == downcased
      end)

    cond do
      event_source ->
        {_, source} = event_source

        %FieldTrace{
          field_name: field_name,
          element_label: view_label,
          element_type: :view,
          status: :traced,
          source: source
        }

      command_source ->
        {_, source} = command_source

        %FieldTrace{
          field_name: field_name,
          element_label: view_label,
          element_type: :view,
          status: :traced,
          source: source
        }

      true ->
        %FieldTrace{
          field_name: field_name,
          element_label: view_label,
          element_type: :view,
          status: :orphan,
          source: nil
        }
    end
  end

  defp collect_field_names(elements) do
    Enum.flat_map(elements, fn elem ->
      fields = (elem.fields || []) ++ props_as_fields(elem.props)

      Enum.map(fields, fn field ->
        {field_name(field), elem.label}
      end)
    end)
  end

  defp field_name(%EventModeler.EventModel.Field{name: name}), do: name
  defp field_name(%{name: name}), do: name
  defp field_name(_), do: ""

  defp props_as_fields(nil), do: []
  defp props_as_fields(props) when props == %{}, do: []

  defp props_as_fields(props) when is_map(props) do
    Enum.map(props, fn {k, _v} ->
      %{name: k}
    end)
  end
end
