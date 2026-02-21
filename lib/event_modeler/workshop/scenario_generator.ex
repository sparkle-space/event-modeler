defmodule EventModeler.Workshop.ScenarioGenerator do
  @moduledoc """
  Generates Given/When/Then scenarios from a slice's elements and connections.

  Analyzes the element graph within a slice:
  - The command element = When
  - Events preceding the command (via views) = Given preconditions
  - Events and views produced by the command = Then outcomes
  """

  alias EventModeler.Prd.Slice

  @doc """
  Generates GWT scenarios from a slice's elements.

  Returns a list of scenario maps with `:name`, `:given`, `:when_clause`, `:then_clause`,
  and `:auto_generated` fields.
  """
  @spec generate(%Slice{}) :: [map()]
  def generate(%Slice{steps: steps, name: slice_name}) do
    # Find the command element(s)
    commands = Enum.filter(steps, &(&1.type == :command))

    if commands == [] do
      []
    else
      Enum.map(commands, fn command ->
        generate_for_command(command, steps, slice_name)
      end)
    end
  end

  defp generate_for_command(command, steps, slice_name) do
    # Given: events/views that appear BEFORE the command in step order
    # (these represent preconditions)
    cmd_index = Enum.find_index(steps, &(&1.id == command.id))

    before_command = Enum.take(steps, cmd_index || 0)

    given_events =
      before_command
      |> Enum.filter(&(&1.type == :event))
      |> Enum.map(fn evt ->
        %{type: "e", label: format_label(evt), props: evt.props}
      end)

    # When: the command itself
    when_clause = [
      %{type: "c", label: format_label(command), props: command.props}
    ]

    # Then: events and views that appear AFTER the command
    after_command = Enum.drop(steps, (cmd_index || 0) + 1)

    then_events =
      after_command
      |> Enum.filter(&(&1.type in [:event, :view]))
      |> Enum.map(fn elem ->
        prefix = if elem.type == :event, do: "e", else: "v"
        %{type: prefix, label: format_label(elem), props: elem.props}
      end)

    # Also check for exception elements after the command
    then_exceptions =
      after_command
      |> Enum.filter(&(&1.type == :exception))
      |> Enum.map(fn elem ->
        %{type: "x", label: format_label(elem), props: elem.props}
      end)

    then_clause = then_events ++ then_exceptions

    %{
      name: "#{slice_name}HappyPath",
      given: given_events,
      when_clause: when_clause,
      then_clause: then_clause,
      auto_generated: true
    }
  end

  defp format_label(element) do
    if element.swimlane do
      "#{element.swimlane}/#{element.label}"
    else
      element.label
    end
  end
end
