defmodule EventModeler.EventModel.Pattern do
  @moduledoc """
  Detects architectural patterns from slice step composition.

  Four patterns recognized:
  - `:command` — Trigger -> Command -> Event(s): user-initiated write
  - `:view` — Event(s) -> View: read model projection
  - `:automation` — Event -> Processor -> Command: same-domain automation
  - `:translation` — Event -> Translator -> Command: cross-domain translation
  """

  alias EventModeler.EventModel.Slice

  @type pattern :: :command | :view | :automation | :translation | nil

  @doc """
  Detects the architectural pattern of a slice from its steps.

  Returns the explicit pattern if set, otherwise auto-detects from step types.
  """
  @spec detect(Slice.t()) :: pattern()
  def detect(%Slice{pattern: pattern}) when pattern != nil, do: pattern

  def detect(%Slice{steps: steps}) when is_list(steps) do
    types = Enum.map(steps, & &1.type)
    detect_from_types(types)
  end

  def detect(_), do: nil

  @doc """
  Returns a human-readable label for a pattern.
  """
  @spec label(pattern()) :: String.t()
  def label(:command), do: "Command"
  def label(:view), do: "View"
  def label(:automation), do: "Automation"
  def label(:translation), do: "Translation"
  def label(_), do: "Unknown"

  @doc """
  Returns a description of the pattern.
  """
  @spec description(pattern()) :: String.t()
  def description(:command), do: "Trigger -> Command -> Event(s)"
  def description(:view), do: "Event(s) -> View"
  def description(:automation), do: "Event -> Processor -> Command (same domain)"
  def description(:translation), do: "Event -> Translator -> Command (cross domain)"
  def description(_), do: ""

  @doc """
  Validates pattern constraints.

  Returns `{:ok, pattern}` or `{:error, reason}`.
  For example, translation pattern should cross domain boundaries.
  """
  @spec validate(Slice.t()) :: {:ok, pattern()} | {:error, String.t()}
  def validate(%Slice{} = slice) do
    pattern = detect(slice)

    case pattern do
      :translation ->
        # Translation should involve cross-domain elements
        has_translator = Enum.any?(slice.steps, &(&1.type == :translator))

        if has_translator do
          {:ok, :translation}
        else
          {:error, "Translation pattern should contain a Translator element"}
        end

      _ ->
        {:ok, pattern}
    end
  end

  # Auto-detection heuristics based on step type composition

  defp detect_from_types(types) do
    has_translator = :translator in types
    has_processor = :processor in types
    has_wireframe = :wireframe in types
    has_command = :command in types
    has_event = :event in types
    has_view = :view in types
    has_automation = :automation in types

    cond do
      has_translator and has_command ->
        :translation

      has_processor and has_command ->
        :automation

      has_automation and has_command ->
        :automation

      has_wireframe and has_command and has_event ->
        :command

      has_command and has_event and !has_view ->
        :command

      has_event and has_view and !has_command ->
        :view

      has_wireframe and has_command ->
        :command

      true ->
        nil
    end
  end
end
