# /develop — Core Development Patterns

You are working on EventModeler, a standalone Phoenix/LiveView application for collaborative event modeling, event-sourced with Commanded.

## Stack

- **Elixir** with **Phoenix** and **LiveView**
- **Commanded** for event sourcing (aggregates, commands, events, projectors)
- **PostgreSQL** for event store and read models
- **SVG** canvas rendered via LiveView + JS hooks

## Code Organization

```
lib/event_modeler/           # Domain layer
  aggregates/                # Commanded aggregates (Board, Element, Slice, Prd)
  commands/                  # Command structs
  events/                    # Event structs
  projectors/                # Ecto projectors for read models
  collaboration/             # BoardSession GenServer, Presence
  workshop/                  # StepConfig, workshop constraints
  prd/                       # PRD parser, exporter, event stream handler

lib/event_modeler_web/       # Web layer
  live/                      # LiveView modules (Canvas, Board, Slice, Workshop)
  components/                # Phoenix components
  hooks/                     # JS hook modules

assets/                      # JS/CSS
  js/hooks/                  # Canvas interaction hooks (pan, zoom, drag)
  css/                       # Tailwind + element colors
```

## Patterns

### Commanded Aggregate

```elixir
defmodule EventModeler.Aggregates.Board do
  defstruct [:board_id, :title, :owner_id, :status, swimlanes: []]

  # Commands dispatch events
  def execute(%__MODULE__{board_id: nil}, %CreateBoard{} = cmd) do
    %BoardCreated{board_id: cmd.board_id, title: cmd.title, owner_id: cmd.owner_id}
  end

  # Events apply state
  def apply(%__MODULE__{} = board, %BoardCreated{} = evt) do
    %{board | board_id: evt.board_id, title: evt.title, owner_id: evt.owner_id}
  end
end
```

### LiveView + SVG Canvas

- SVG rendered server-side with element positions
- JS hook (`EventModelerCanvas`) handles pan/zoom/drag client-side
- Mutations go through `pushEvent` → Commanded command → event broadcast → LiveView diff

### Two-Level Sync

- **Ephemeral:** BoardSession GenServer holds drag positions, locks, cursors. No persistence.
- **Persistent:** Commanded events stored in PostgreSQL. Projectors build read models.

### Event Enrichment

Events carry enough data for independent projection. Include labels/names, not just IDs.

## Testing

```bash
mix test                          # All tests
mix test test/event_modeler/      # Domain tests
mix test test/event_modeler_web/  # Web tests
```

- Test aggregates by dispatching commands and asserting events
- Test projectors by applying events and querying read models
- Test LiveViews with `Phoenix.LiveViewTest`

## Formatting & Quality

```bash
mix format                        # Format code
mix compile --warnings-as-errors  # No warnings
mix credo                         # Static analysis
```
