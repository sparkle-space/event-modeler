defmodule EventModeler.Workshop.ScenarioGenerator do
  @moduledoc """
  Generates Given/When/Then scenarios from a slice's elements and connections.

  Analyzes the element graph within a slice:
  - The command element = When
  - Events preceding the command (via views) = Given preconditions
  - Events and views produced by the command = Then outcomes

  When automations link multiple commands (event->automation->command), the algorithm
  generates chained scenarios where the Then of scenario N feeds the Given of scenario N+1.
  """

  alias EventModeler.EventModel.Slice

  @doc """
  Generates GWT scenarios from a slice's elements.

  Returns a list of scenario maps with `:name`, `:given`, `:when_clause`, `:then_clause`,
  and `:auto_generated` fields.
  """
  @spec generate(%Slice{}) :: [map()]
  def generate(%Slice{steps: steps, name: slice_name}) do
    commands = Enum.filter(steps, &(&1.type == :command))

    if commands == [] do
      []
    else
      has_automation = Enum.any?(steps, &(&1.type == :automation))

      if has_automation and length(commands) > 1 do
        generate_chained(steps, slice_name)
      else
        Enum.map(commands, fn command ->
          generate_for_command(command, steps, slice_name)
        end)
      end
    end
  end

  defp generate_chained(steps, slice_name) do
    # Split steps into segments at automation boundaries.
    # Pattern: [preconditions...] command [outcomes...] automation [preconditions...] command [outcomes...]
    # Each command gets its own scenario, with chaining from previous Then to next Given.
    commands_with_index =
      steps
      |> Enum.with_index()
      |> Enum.filter(fn {elem, _idx} -> elem.type == :command end)

    commands_with_index
    |> Enum.with_index()
    |> Enum.map(fn {{command, cmd_pos}, chain_idx} ->
      # Find the range for this command's segment
      # Given: elements before this command (after previous automation/command boundary)
      before_command = Enum.take(steps, cmd_pos)

      # For chained commands (not the first), only look back to the preceding automation
      given_elements =
        if chain_idx > 0 do
          # Find the automation before this command
          before_command
          |> Enum.reverse()
          |> Enum.take_while(&(&1.type != :automation))
          |> Enum.reverse()
          |> Enum.filter(&(&1.type == :event))
        else
          before_command
          |> Enum.filter(&(&1.type == :event))
        end

      given =
        Enum.map(given_elements, fn evt ->
          %{type: "e", label: format_label(evt), props: evt.props}
        end)

      # When: this command
      when_clause = [
        %{type: "c", label: format_label(command), props: command.props}
      ]

      # Then: elements after command until next command or end
      # Find next command position (or end of list)
      next_cmd_pos =
        case Enum.find(commands_with_index, fn {_cmd, pos} -> pos > cmd_pos end) do
          {_cmd, pos} -> pos
          nil -> length(steps)
        end

      after_command =
        steps
        |> Enum.drop(cmd_pos + 1)
        |> Enum.take(next_cmd_pos - cmd_pos - 1)
        |> Enum.reject(&(&1.type == :automation))

      then_events =
        after_command
        |> Enum.filter(&(&1.type in [:event, :view]))
        |> Enum.map(fn elem ->
          prefix = if elem.type == :event, do: "e", else: "v"
          %{type: prefix, label: format_label(elem), props: elem.props}
        end)

      then_exceptions =
        after_command
        |> Enum.filter(&(&1.type == :exception))
        |> Enum.map(fn elem ->
          %{type: "x", label: format_label(elem), props: elem.props}
        end)

      suffix =
        if length(commands_with_index) > 1,
          do: "Step#{chain_idx + 1}",
          else: "HappyPath"

      %{
        name: "#{slice_name}#{suffix}",
        given: given,
        when_clause: when_clause,
        then_clause: then_events ++ then_exceptions,
        auto_generated: true
      }
    end)
  end

  defp generate_for_command(command, steps, slice_name) do
    cmd_index = Enum.find_index(steps, &(&1.id == command.id))

    before_command = Enum.take(steps, cmd_index || 0)

    given_events =
      before_command
      |> Enum.filter(&(&1.type == :event))
      |> Enum.map(fn evt ->
        %{type: "e", label: format_label(evt), props: evt.props}
      end)

    when_clause = [
      %{type: "c", label: format_label(command), props: command.props}
    ]

    after_command = Enum.drop(steps, (cmd_index || 0) + 1)

    then_events =
      after_command
      |> Enum.filter(&(&1.type in [:event, :view]))
      |> Enum.map(fn elem ->
        prefix = if elem.type == :event, do: "e", else: "v"
        %{type: prefix, label: format_label(elem), props: elem.props}
      end)

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
