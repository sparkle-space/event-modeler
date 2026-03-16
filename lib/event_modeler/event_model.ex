defmodule EventModeler.EventModel do
  @moduledoc """
  Core structs representing a parsed Event Model.
  """

  defstruct [
    :title,
    :status,
    :domain,
    :version,
    :created,
    :updated,
    :format,
    :dependencies,
    :tags,
    :overview,
    :key_ideas,
    :slices,
    :scenarios,
    :data_flows,
    :model_dependencies,
    :sources,
    :event_stream,
    :raw_markdown,
    domains: [],
    sections: %{}
  ]

  @type t :: %__MODULE__{
          title: String.t() | nil,
          status: String.t() | nil,
          domain: String.t() | nil,
          version: integer() | nil,
          created: String.t() | nil,
          updated: String.t() | nil,
          format: String.t() | nil,
          dependencies: [String.t()],
          tags: [String.t()],
          overview: String.t() | nil,
          key_ideas: [String.t()],
          slices: [EventModeler.EventModel.Slice.t()],
          scenarios: [map()],
          data_flows: String.t() | nil,
          model_dependencies: String.t() | nil,
          sources: String.t() | nil,
          event_stream: [EventModeler.EventModel.EventEntry.t()],
          raw_markdown: String.t() | nil,
          domains: [EventModeler.EventModel.Domain.t()],
          sections: map()
        }
end
