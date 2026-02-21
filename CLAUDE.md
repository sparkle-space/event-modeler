# EventModeler

## Project Overview

EventModeler is a purpose-built collaborative canvas for designing information systems using Event Modeling. The core loop: **PRD in → Event Model → Refined PRD out**.

Users import a Product Requirements Document (PRD), collaboratively build an event model on a visual canvas, then export a refined PRD enriched with slices, scenarios, and data flows.

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

Currently docs-only. Target structure when code exists:

```
event_modeler/
├── lib/
│   ├── event_modeler/          # Core domain (aggregates, projectors, collaboration)
│   ├── event_modeler_web/      # Phoenix web layer (LiveViews, hooks, assets)
│   └── event_modeler.ex
├── assets/                     # JS/CSS for SVG canvas
├── priv/repo/migrations/
├── test/
├── config/
├── docs/
│   ├── product-spec.md         # Product specification
│   └── technical-design.md     # Technical design
├── CLAUDE.md                   # This file
├── mix.exs
└── README.md
```

## Development Setup

Prerequisites (install via [mise](https://mise.jdx.dev/)):

```bash
mise install elixir erlang node
```

External tools (Python CLIs, npm CLIs) are installed locally via `mise use` into `mise.toml` — never via `brew`, global `pip`, or global `npm install -g`.

**Bash tool quirk:** mise shims aren't on PATH in Claude Code's Bash tool. Prefix commands with `eval "$(mise activate bash)" &&`.

Database (via Docker):

```bash
docker compose up -d  # PostgreSQL
mix deps.get
mix ecto.setup
mix phx.server        # localhost:4000
```

## Git Workflow

- Feature branch off `main` → PR → merge
- Branch naming: `feature/`, `fix/`, `docs/`, `refactor/`
- Pre-commit checks: `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix test`

## Documentation Conventions

### PRD Format

Markdown with YAML frontmatter. Sections: Overview, Key Ideas, Slices (emlang blocks), Scenarios, Data Flows, Dependencies, Sources, Event Stream.

See `docs/product-spec.md` for the full format definition.

### Emlang Notation

Slices use [emlang](https://github.com/emlang-project/spec) v1.0.0 — a YAML DSL for event model slices. Embedded in PRDs as fenced `` ```emlang `` code blocks.

### Event Stream

Append-only event log at the bottom of PRD files. Fenced `` ```eventstream `` YAML blocks with `seq`, `ts`, `type`, `actor`, `data` fields. Sentinel: `<!-- event-stream -->`.

## Key Concepts

- **Event Modeling** — A methodology for designing information systems around events. 7-step workshop: Brainstorm → Plot → Storyboard → Inputs → Outputs → Organize → Elaborate.
- **Slice** — A vertical unit of work: Trigger → Command → Event → View. Named, testable, deliverable.
- **PRD lifecycle** — draft → modeling → refined → approved. Import starts modeling; export produces refined.
- **Two-level sync** — Ephemeral (GenServer + Channels for cursors/drags) + Persistent (event-sourced for model state).

## Visual Web Inspection

Two CLI tools for token-efficient visual inspection of the running Phoenix app. Both installed locally via `mise` (see `mise.toml`).

### shot-scraper (quick visual checks)

Takes a screenshot and saves to disk. Zero tokens until you read the image.

```bash
eval "$(mise activate bash)" && shot-scraper http://localhost:4000 -o /tmp/page.png
# Then: Read /tmp/page.png  (Claude vision analyzes the image)
```

Options: `--width 1280 --height 800`, `--selector "#canvas"`, `--wait 2000` (ms).

### playwright-cli (interactive browser sessions)

Full browser interaction via CLI. Saves snapshots and screenshots to disk.

```bash
eval "$(mise activate bash)" && playwright-cli open http://localhost:4000
eval "$(mise activate bash)" && playwright-cli snapshot       # accessibility tree
eval "$(mise activate bash)" && playwright-cli screenshot     # save screenshot
eval "$(mise activate bash)" && playwright-cli click e21      # click element by ref
eval "$(mise activate bash)" && playwright-cli fill e35 "text" # fill form field
eval "$(mise activate bash)" && playwright-cli close
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
| `/prd-plan` | Event Modeling workshop guidance, PRD format reference, emlang notation |
| `/research` | Web research and codebase analysis patterns |

## Agents

| Agent | Description |
|-------|-------------|
| `event-modeler` | Event Modeling design guidance (7-step workshop, slice definition, scenario generation) |
| `researcher` | Web research and information synthesis |
