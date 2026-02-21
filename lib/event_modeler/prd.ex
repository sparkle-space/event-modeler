defmodule EventModeler.Prd do
  @moduledoc """
  Core structs representing a parsed PRD (Product Requirements Document).
  """

  defstruct [
    :title,
    :status,
    :domain,
    :version,
    :created,
    :updated,
    :dependencies,
    :tags,
    :overview,
    :key_ideas,
    :slices,
    :scenarios,
    :data_flows,
    :prd_dependencies,
    :sources,
    :event_stream,
    :raw_markdown,
    sections: %{}
  ]

  @type t :: %__MODULE__{
          title: String.t() | nil,
          status: String.t() | nil,
          domain: String.t() | nil,
          version: integer() | nil,
          created: String.t() | nil,
          updated: String.t() | nil,
          dependencies: [String.t()],
          tags: [String.t()],
          overview: String.t() | nil,
          key_ideas: [String.t()],
          slices: [EventModeler.Prd.Slice.t()],
          scenarios: [map()],
          data_flows: String.t() | nil,
          prd_dependencies: String.t() | nil,
          sources: String.t() | nil,
          event_stream: [EventModeler.Prd.EventEntry.t()],
          raw_markdown: String.t() | nil,
          sections: map()
        }
end
