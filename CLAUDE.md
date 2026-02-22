# EventModeler

## Project Overview

EventModeler is a purpose-built collaborative canvas for designing information systems using Event Modeling. The core loop: **Event Model in → Event Model → Refined Event Model out**.

Users import an Event Model, collaboratively build an event model on a visual canvas, then export a refined Event Model enriched with slices, scenarios, and data flows.

## Architecture

Standalone Phoenix/LiveView application, event-sourced with Commanded + EventStore (PostgreSQL).

| Layer | Technology |
|-------|------------|
| Language | Elixir |
| Web framework | Phoenix + LiveView |
| Database | PostgreSQL |
| Event sourcing | Commanded + EventStore |
| Real-time | Phoenix Channels + Presence |
| Canvas | SVG via LiveView + JS hooks |

**Future:** The reusable core will be extracted into a hex package (`event_modeler`) once the API surface is stable.

## Repository Structure

```
event_modeler/
├── lib/
│   ├── event_modeler/
│   │   ├── board.ex              # Board GenServer — state machine per board session
│   │   ├── workspace.ex          # Board discovery — lists available Event Model files
│   │   ├── canvas/               # Layout engine, HTML/SVG renderers, swimlane logic
│   │   ├── event_model/          # Parser, serializer, emlang, event stream
│   │   ├── event_model.ex        # Core EventModel struct
│   │   └── workshop/             # Scenario generator (AI-assisted)
│   ├── event_modeler_web/
│   │   ├── live/                 # LiveViews (BoardLive, DashboardLive)
│   │   ├── components/           # Phoenix components
│   │   └── router.ex
│   └── event_modeler.ex
├── assets/js/hooks/              # JS hooks (canvas pan/zoom/select, theme)
├── priv/event_models/            # Sample Event Model markdown files
├── test/
├── config/
├── docs/
│   ├── product-spec.md           # Product specification
│   └── technical-design.md       # Technical design
├── mise.toml                     # Tool versions (Elixir, Erlang, Node, CLI tools)
├── mix.exs
└── CLAUDE.md
```

## Development Setup

Prerequisites (install via [mise](https://mise.jdx.dev/)):

```bash
mise install elixir erlang node
```

External tools (Python CLIs, npm CLIs) are installed locally via `mise use` into `mise.toml` — never via `brew`, global `pip`, or global `npm install -g`.

Database (via Docker):

```bash
docker compose up -d  # PostgreSQL
mix deps.get
mix ecto.setup
mix phx.server        # localhost:4000
```

## Commands

```bash
mix phx.server                    # Dev server on localhost:4000
mix test                          # Run all tests
mix test path/to/test.exs:42      # Run single test at line
mix format                        # Auto-format all Elixir files
mix format --check-formatted      # Check formatting (CI)
mix compile --warnings-as-errors  # Strict compilation (CI)
mix deps.get                      # Install dependencies
```

## Git Workflow

- Feature branch off `main` → PR → merge
- Branch naming: `feature/`, `fix/`, `docs/`, `refactor/`
- Pre-commit checks: `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix test`

## Documentation Conventions

### Event Model Format

Markdown with YAML frontmatter. Sections: Overview, Key Ideas, Slices (emlang blocks), Scenarios, Data Flows, Dependencies, Sources, Event Stream.

See `docs/product-spec.md` for the full format definition.

### Emlang Notation

Slices use [emlang](https://github.com/emlang-project/spec) v1.0.0 — a YAML DSL for event model slices. Embedded in Event Models as fenced `` ```emlang `` code blocks.

### Event Stream

Append-only event log at the bottom of Event Model files. Fenced `` ```eventstream `` YAML blocks with `seq`, `ts`, `type`, `actor`, `data` fields. Sentinel: `<!-- event-stream -->`.

## Key Concepts

- **Event Modeling** — A methodology for designing information systems around events. 7-step workshop: Brainstorm → Plot → Storyboard → Inputs → Outputs → Organize → Elaborate.
- **Slice** — A vertical unit of work: Trigger → Command → Event → View. Named, testable, deliverable.
- **Event Model lifecycle** — draft → modeling → refined → approved. Import starts modeling; export produces refined.
- **Two-level sync** — Ephemeral (GenServer + Channels for cursors/drags) + Persistent (event-sourced for model state).

## Code Patterns

- **Canvas layout is computed, not stored.** Element positions are calculated by `Layout.compute/1` from the `EventModel` struct on every change — no position data in the domain model.
- **Board GenServer caches layout.** `Board.recompute_layout/1` runs `Layout.compute` → `HtmlRenderer.render` and stores the result in GenServer state. The LiveView reads `canvas_data` from the Board.
- **Pan/zoom is client-side only.** CSS transforms (`translate` + `scale`) on `#canvas-world`, managed by the `EventModelerCanvas` JS hook. Server knows nothing about viewport state.
- **Server→client events via `push_event`.** E.g., `push_event(socket, "pan_to_slice", payload)` triggers `this.handleEvent("pan_to_slice", ...)` in the JS hook.

## Gotchas

- **Board GenServer caches stale data on code reload.** After changing layout/rendering code, the running Board GenServer still holds old `canvas_data`. Restart the server or navigate away and back to force a fresh mount.
- **`mix format` line length.** The Elixir formatter enforces line length. Long `push_event` calls with map payloads often need line-breaking. Always run `mix format` before committing.
- **CI runs format check.** PR checks include `mix format --check-formatted` — formatting failures block merge.

## Visual Web Inspection

Two CLI tools for token-efficient visual inspection of the running Phoenix app. Both installed locally via `mise` (see `mise.toml`).

### shot-scraper (quick visual checks)

Takes a screenshot and saves to disk. Zero tokens until you read the image.

```bash
shot-scraper http://localhost:4000 -o /tmp/page.png
# Then: Read /tmp/page.png  (Claude vision analyzes the image)
```

Options: `--width 1280 --height 800`, `--selector "#canvas"`, `--wait 2000` (ms).

### playwright-cli (interactive browser sessions)

Full browser interaction via CLI. Saves snapshots and screenshots to disk.

```bash
playwright-cli open http://localhost:4000
playwright-cli snapshot       # accessibility tree
playwright-cli screenshot     # save screenshot
playwright-cli click e21      # click element by ref
playwright-cli fill e35 "text" # fill form field
playwright-cli close
```

### When to use which

| Task | Tool |
|------|------|
| Quick visual check / screenshot | `shot-scraper` |
| Multi-step interaction (click, fill, navigate) | `playwright-cli` |
| Accessibility tree inspection | `playwright-cli snapshot` |

## Skills

| Skill | Description |
|-------|-------------|
| `/develop` | Core development patterns for Elixir/Phoenix/Commanded/LiveView |
| `/event-model-plan` | Event Modeling workshop guidance, Event Model format reference, emlang notation |
| `/research` | Web research and codebase analysis patterns |

## Agents

| Agent | Description |
|-------|-------------|
| `event-modeler` | Event Modeling design guidance (7-step workshop, slice definition, scenario generation) |
| `researcher` | Web research and information synthesis |
