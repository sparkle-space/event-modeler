# EventModeler: Technical Design

**Status:** Concept
**Date:** 2026-02-17
**Depends on:** [Product Specification](product-spec.md), [Event Modeling](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/event-modeling.md), [Event Sourcing & CQRS](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/event-sourcing-cqrs.md), [Collaboration Architecture](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/collaboration-architecture.md)

## Overview

EventModeler is an Elixir hex package (`event_modeler`) that adds event modeling capability to any Phoenix app, plus a thin SaaS wrapper for standalone deployment. This document describes the architecture, data model, canvas design, collaboration strategy, and PRD import/export pipeline.

For the product vision, feature set, and PRD format definition, see the [Product Specification](product-spec.md).

## Repository Structure

| Decision | Choice |
|----------|--------|
| **Repo/package name** | `event_modeler` |
| **Repo structure** | Mono-repo: hex module as core, SaaS as thin wrapper app |
| **Licensing** | Start private. SaaS hosted at sparkle.space. Hex module open-sourced later |
| **Docs strategy** | Masterplan keeps overview summary + link to repo. Repo gets detailed specs in `docs/` |

The mono-repo contains two Mix projects:

```
event_modeler/
├── lib/                        # Hex module (core)
│   └── event_modeler/
├── mix.exs                     # {:event_modeler, "~> 0.1"}
├── apps/
│   └── event_modeling_saas/    # SaaS wrapper (depends on core)
│       ├── lib/
│       └── mix.exs
├── docs/
│   ├── product-spec.md         # Detailed product specification
│   └── technical-design.md     # Detailed technical design
└── README.md
```

The hex module (`lib/`) is the publishable package. The SaaS app (`apps/event_modeling_saas/`) is a thin Phoenix wrapper that adds auth, billing, and multi-tenancy — it depends on the hex module via a path dependency. Both ship from the same repo, ensuring the SaaS always runs the same code as the open-source module.

## Hex Module Architecture

EventModeler follows the Phoenix library pattern established by `phoenix_live_dashboard` and `live_storybook`: a self-contained package that brings its own routes, LiveView modules, JS hooks, CSS, Ecto schemas, and migrations. The host app provides authentication, user context, Ecto Repo, and PubSub.

### Router Integration

The host app mounts EventModeler with a single line:

```elixir
# lib/my_app_web/router.ex
import EventModeler.Router

scope "/", MyAppWeb do
  pipe_through [:browser, :require_authenticated_user]

  event_modeler "/event-model",
    repo: MyApp.Repo,
    pubsub: MyApp.PubSub,
    auth: MyAppWeb.EventModelerAuth
end
```

`event_modeler/2` is a macro that generates routes for the board listing, board canvas, slice detail, PRD import/export, and workshop mode LiveViews.

### Authentication Adapter

The host app implements a behaviour to provide user context:

```elixir
defmodule EventModeler.Auth do
  @callback current_user(Plug.Conn.t() | Phoenix.LiveView.Socket.t()) ::
              %{id: String.t(), display_name: String.t(), role: atom()}
  @callback authorize(user :: map(), action :: atom(), resource :: map()) :: boolean()
end
```

```elixir
# lib/my_app_web/event_modeler_auth.ex
defmodule MyAppWeb.EventModelerAuth do
  @behaviour EventModeler.Auth

  @impl true
  def current_user(conn_or_socket) do
    user = conn_or_socket.assigns.current_user
    %{id: user.id, display_name: user.name, role: :participant}
  end

  @impl true
  def authorize(_user, _action, _resource), do: true
end
```

### What the Hex Module Brings

| Component | Description |
|-----------|-------------|
| `EventModeler.Router` | Router macro generating all routes |
| `EventModeler.Live.*` | LiveView modules for board, canvas, slices, workshop, PRD import/export |
| `EventModeler.Hooks` | Phoenix LiveView JS hooks for canvas interaction |
| `EventModeler.Assets` | CSS and JS bundles (served via `Plug.Static` or esbuild plugin) |
| `EventModeler.Ecto.Migrations` | Migration modules the host app runs via `mix ecto.migrate` |
| `EventModeler.Aggregates.*` | Commanded aggregates for Board, Element, Slice, PRD |
| `EventModeler.Projectors.*` | Ecto projectors for read models |
| `EventModeler.Collaboration.*` | GenServer sessions, Registry, Presence for real-time sync |

### What the Host App Provides

| Component | Description |
|-----------|-------------|
| Ecto Repo | Database access (PostgreSQL) |
| PubSub | Phoenix PubSub instance for broadcasts |
| Auth adapter | User identity and authorization |
| Endpoint | WebSocket and HTTP serving |

## Stack

The technology choices align with the existing sparkle.space stack:

| Layer | Technology | Reference |
|-------|------------|-----------|
| Language | Elixir | [Elixir/Phoenix/LiveView](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/elixir-phoenix-liveview.md) |
| Web framework | Phoenix + LiveView | [Elixir/Phoenix/LiveView](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/elixir-phoenix-liveview.md) |
| Database | PostgreSQL | [Hosting Architecture](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/hosting/hosting-architecture.md) |
| Event sourcing | Commanded + Eventstore | [Event Sourcing & CQRS](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/event-sourcing-cqrs.md) |
| Real-time | Phoenix Channels + Presence | [Collaboration Architecture](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/collaboration-architecture.md) |
| Canvas rendering | SVG (via LiveView + JS hooks) | — |

## Data Model

EventModeler is event-sourced using Commanded. The write model consists of aggregates; the read model consists of Ecto projections.

### Aggregates

#### Board Aggregate

The root aggregate representing an event modeling canvas.

```
Stream: EventModeler.BoardAggregate-{board_id}

Commands:
  CreateBoard {board_id, title, owner_id}
  RenameBoard {board_id, title}
  DefineSwimlane {board_id, swimlane_id, label, actor, position}
  ReorderSwimlanes {board_id, swimlane_ids}
  RemoveSwimlane {board_id, swimlane_id}
  ImportPrd {board_id, prd_id, markdown_content}
  ArchiveBoard {board_id}

Events:
  BoardCreated {board_id, title, owner_id, created_at}
  BoardRenamed {board_id, title}
  SwimlaneDefined {board_id, swimlane_id, label, actor, position}
  SwimlanesReordered {board_id, swimlane_ids}
  SwimlaneRemoved {board_id, swimlane_id}
  PrdImported {board_id, prd_id, title, overview, key_ideas}
  BoardArchived {board_id, archived_at}
```

#### Element Aggregate

Represents a single modeling element (Command, Event, View, Automation, Wireframe) on the canvas.

```
Stream: EventModeler.ElementAggregate-{element_id}

Commands:
  PlaceElement {element_id, board_id, type, label, x, y, swimlane_id}
  MoveElement {element_id, x, y, swimlane_id}
  EditElement {element_id, label, description, fields}
  ConnectElements {element_id, target_element_id, connection_type}
  DisconnectElements {element_id, target_element_id}
  RemoveElement {element_id}

Events:
  ElementPlaced {element_id, board_id, type, label, x, y, swimlane_id}
  ElementMoved {element_id, x, y, swimlane_id}
  ElementEdited {element_id, label, description, fields}
  ElementsConnected {element_id, target_element_id, connection_type}
  ElementsDisconnected {element_id, target_element_id}
  ElementRemoved {element_id}

Invariants:
  - type must be one of: :command, :event, :view, :automation, :wireframe
  - Connection validation:
      command→event (valid)
      event→view (valid)
      event→automation (valid)
      automation→command (valid)
      wireframe→command (valid: "this screen submits this command")
      wireframe→view (valid: "this screen displays this view data")
      command→view (rejected)
      wireframe→event (rejected)
      wireframe→automation (rejected)
      All other wireframe connections (rejected)
```

#### Slice Aggregate

A named vertical slice grouping Command → Event → View chains.

```
Stream: EventModeler.SliceAggregate-{slice_id}

Commands:
  DefineSlice {slice_id, board_id, name, element_ids}
  RenameSlice {slice_id, name}
  AddElementToSlice {slice_id, element_id}
  RemoveElementFromSlice {slice_id, element_id}
  AddScenario {slice_id, scenario_id, given, when_clause, then_clause}
  EditScenario {slice_id, scenario_id, given, when_clause, then_clause}
  RemoveScenario {slice_id, scenario_id}
  SetSlicePosition {slice_id, position}
  RemoveSlice {slice_id}

Events:
  SliceDefined {slice_id, board_id, name, element_ids}
  SliceRenamed {slice_id, name}
  ElementAddedToSlice {slice_id, element_id}
  ElementRemovedFromSlice {slice_id, element_id}
  ScenarioAdded {slice_id, scenario_id, given, when_clause, then_clause}
  ScenarioEdited {slice_id, scenario_id, given, when_clause, then_clause}
  ScenarioRemoved {slice_id, scenario_id}
  SlicePositionSet {slice_id, position}
  SliceRemoved {slice_id}
```

#### PRD Aggregate

Tracks an imported PRD and its refinement through the modeling process.

```
Stream: EventModeler.PrdAggregate-{prd_id}

Commands:
  ImportPrd {prd_id, board_id, markdown_content, frontmatter}
  RefinePrd {prd_id, refinements}
  ExportPrd {prd_id, format}

Events:
  PrdImported {prd_id, board_id, title, overview, key_ideas, raw_markdown}
  PrdRefined {prd_id, added_slices, added_scenarios, added_data_flows}
  PrdExported {prd_id, format, exported_at}
```

### Read Models (Projections)

```
boards
  id, title, owner_id, swimlanes (jsonb), prd_id, status, inserted_at, updated_at

elements
  id, board_id, type, label, description, fields (jsonb),
  x, y, swimlane_id, connections (jsonb), inserted_at, updated_at

slices
  id, board_id, name, element_ids (jsonb), position, inserted_at, updated_at

scenarios
  id, slice_id, given (jsonb), when_clause, then_clause (jsonb),
  auto_generated (boolean), inserted_at, updated_at

prds
  id, board_id, title, overview, key_ideas (jsonb), raw_markdown,
  status, exported_at, inserted_at, updated_at
```

## Canvas Architecture

### Why SVG Over HTML Canvas

The modeling surface uses SVG rather than HTML Canvas because event models are composed of labeled, connected shapes — not pixel-based graphics. SVG provides:

- DOM-based elements addressable by ID (for LiveView updates)
- Native text rendering and wrapping
- CSS styling for element types (orange events, blue commands, green views)
- Hit-testing and event handling per element
- Accessibility (screen readers can traverse SVG elements)
- Resolution independence (zoom without blur)

### Canvas Components

```
┌──────────────────────────────────────────────────────────────┐
│  LiveView (EventModeler.Live.Canvas)                         │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ SVG element (phx-hook="EventModelerCanvas")            │  │
│  │                                                        │  │
│  │  ┌─ Swimlane Layer ────────────────────────────────┐   │  │
│  │  │  Horizontal bands for actors/bounded contexts    │   │  │
│  │  └─────────────────────────────────────────────────┘   │  │
│  │                                                        │  │
│  │  ┌─ Element Layer ─────────────────────────────────┐   │  │
│  │  │  Rectangles (commands/events/views)              │   │  │
│  │  │  Circles (automations)                           │   │  │
│  │  │  Monospace blocks (ASCII wireframes)              │   │  │
│  │  └─────────────────────────────────────────────────┘   │  │
│  │                                                        │  │
│  │  ┌─ Connection Layer ──────────────────────────────┐   │  │
│  │  │  SVG paths with arrowheads between elements      │   │  │
│  │  └─────────────────────────────────────────────────┘   │  │
│  │                                                        │  │
│  │  ┌─ Presence Layer ────────────────────────────────┐   │  │
│  │  │  Remote cursors, selection highlights             │   │  │
│  │  └─────────────────────────────────────────────────┘   │  │
│  │                                                        │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌─ Sidebar ──────────────────────────────────────────────┐  │
│  │  Element palette, slice list, scenario editor,         │  │
│  │  PRD panel, workshop step indicator                    │  │
│  └────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

### JS Hook Responsibilities

The `EventModelerCanvas` hook handles interactions that require client-side responsiveness:

| Interaction | Handling |
|-------------|----------|
| Pan | Client-side viewBox transform; no server round-trip |
| Zoom | Client-side viewBox scaling; no server round-trip |
| Drag element | Client-side position during drag; `pushEvent("element_moved", ...)` on drop |
| Draw connection | Client-side rubber-band line; `pushEvent("elements_connected", ...)` on release |
| Select element | Client-side highlight; `pushEvent("element_selected", ...)` for sidebar update |
| Text editing | Client-side input; `pushEvent("element_edited", ...)` on blur |

The server remains authoritative: every mutation dispatches a Commanded command, and the resulting event is broadcast to all connected users. Client-side state is optimistic and reconciled on server confirmation.

### Rendering Flow

1. LiveView mounts, loads board read model (elements, connections, swimlanes)
2. SVG is rendered server-side with all elements positioned
3. JS hook initializes pan/zoom and attaches drag listeners
4. User drags element → client moves SVG node → drop fires `pushEvent`
5. Server dispatches `MoveElement` command → `ElementMoved` event
6. Event broadcast via PubSub → all connected LiveViews update assigns
7. LiveView diffs → minimal SVG attribute updates sent to other clients

## Real-Time Collaboration

Adapted from the [Collaboration Architecture](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/collaboration-architecture.md) two-level sync model.

### Two-Level Sync

| Level | Purpose | Technology | Persistence |
|-------|---------|------------|-------------|
| **Ephemeral** | Real-time element dragging, cursor positions, selection state | GenServer per board + Phoenix Channels | None (in-memory only) |
| **Persistent** | Element placement, connections, slice definitions, scenarios | Commanded event sourcing | PostgreSQL event store |

### BoardSession GenServer

Each active board has a GenServer (`EventModeler.Collaboration.BoardSession`) holding ephemeral state:

```elixir
%{
  board_id: String.t(),
  participants: MapSet.t(String.t()),         # connected user IDs
  element_locks: %{element_id => user_id},    # who is dragging what
  drag_positions: %{element_id => {x, y}},    # in-progress drag positions
  workshop_step: integer() | nil              # current workshop step (1-7)
}
```

**Key behaviors:**
- `handle_call(:drag_start, ...)` — Lock element to user, broadcast drag start
- `handle_call(:drag_move, ...)` — Update ephemeral position, broadcast to peers (throttled)
- `handle_call(:drag_end, ...)` — Release lock, dispatch `MoveElement` command for persistence
- `handle_call(:join, ...)` — Add participant, return current board state
- `handle_call(:leave, ...)` — Remove participant, release any held locks
- `handle_info(:timeout, ...)` — Shut down after all participants leave

### Presence

Phoenix Presence tracks per-board participant state:

```elixir
# Tracked metadata
%{
  user_id: String.t(),
  display_name: String.t(),
  color: String.t(),         # assigned on join for cursor rendering
  cursor: {x, y} | nil,      # canvas coordinates
  selected_element: String.t() | nil
}
```

### Conflict Resolution

| Conflict type | Resolution |
|---------------|------------|
| Two users drag same element | First lock wins; second user sees element locked |
| Concurrent element edits (text) | Last-write-wins on `ElementEdited` (short text fields; merge not needed) |
| Concurrent slice definition | Both succeed — slices are independent aggregates |
| Concurrent connection drawing | Both succeed if valid; aggregate rejects invalid connections |

### Optimistic UI Updates

Following the [tier system](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/optimistic-ui-updates.md):

| Action | Tier | Approach |
|--------|------|----------|
| Move element | 1 | Client-side drag + optimistic assign update |
| Edit element label | 1 | `%{element | label: new_label}` |
| Place new element | 2 | Construct element struct from params + returned ID |
| Remove element | 2 | `Enum.reject` from element list |
| Import PRD | 3 | Loading state + PubSub reload when import completes |

## PRD Import/Export Pipeline

### Import Flow

```
Markdown PRD (input)
      │
      ▼
┌─────────────┐
│ Parse        │  Split YAML frontmatter from markdown body
│ Frontmatter  │  Extract: title, status, domain, dependencies
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ Extract      │  Identify Overview section → board description
│ Sections     │  Identify Key Ideas → candidate elements
│              │  Identify existing Slices/Scenarios if present (re-import)
└──────┬──────┘
       │
       ├──── ```emlang``` blocks found? ────┐
       │  No                                │ Yes
       ▼                                    ▼
┌─────────────┐                    ┌─────────────┐
│ Suggest      │                    │ Parse Emlang │  Parse each ```emlang``` block as YAML
│ Placement    │                    │ Blocks       │  Extract: slice names, element types,
│ (heuristic)  │                    │              │  props, swimlanes, tests
│              │                    └──────┬──────┘
│ Key Idea →   │                           │
│ Command +    │                           ▼
│ Event pair   │                    ┌─────────────┐
│              │                    │ Map Elements │  t: → Wireframe, c: → Command,
└──────┬──────┘                    │              │  e: → Event, v: → View
       │                           │              │  x: → Scenario exception
       │                           │              │  Swimlane prefix → swimlane assignment
       │                           │              │  tests: → Scenario definitions
       │                           └──────┬──────┘
       │                                  │
       ▼                                  ▼
┌─────────────────────────────────────────────┐
│ Position &    │  Arrange elements on timeline (left to right)
│ Dispatch      │  Assign swimlanes from prefixes or defaults
│               │  ImportPrd command → PrdImported event
│               │  PlaceElement commands for each element
│               │  DefineSlice commands for each named slice
│               │  AddScenario commands for each test
│               │  User reviews and adjusts on canvas
└───────────────┘
```

The import produces **suggestions**, not final placements. Users review the suggested elements on the canvas and adjust, connect, and extend them during the modeling session.

The emlang path is more precise than the Key Ideas heuristic: it extracts exact element types, properties, swimlane assignments, and GWT tests directly from the structured YAML, rather than guessing Command + Event pairs from bullet-point text.

### Export Flow

```
Board (read model)
      │
      ▼
┌─────────────┐
│ Collect      │  Load all elements, connections, slices, scenarios
│ Board State  │  Load original PRD if imported
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ Build Slice  │  For each slice: collect elements in connection order
│ Sections     │  (Trigger → Command → Event → View)
│ (emlang)     │  Format as emlang YAML steps: list with props:
│              │  Include scenarios as emlang tests: blocks
│              │  Wrap in ```emlang fenced code block
│              │  Wireframe description as **Wireframe:** above block
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ Build Data   │  Trace element connections to build data flow table
│ Flow Table   │  Source → Enters as → Transforms via → Exits as
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ Assemble     │  YAML frontmatter (title, status: refined, domain)
│ PRD          │  Preserved: Overview, Key Ideas, Sources (from import)
│              │  Generated: Slices (emlang), Scenarios, Data Flows
└──────┬──────┘
       │
       ├──→ Markdown (.md) — with ```emlang slice blocks
       └──→ JSON (.json)
```

### Round-Trip Fidelity

When a PRD is imported and then exported:

- **Preserved verbatim:** Overview, Key Ideas, Sources, Dependencies (from the original)
- **Added by model:** Slices section, Scenarios section, Data Flows section
- **Updated:** Frontmatter status changes from `draft` to `refined`
- **Re-importable:** The exported PRD can be re-imported into a new board, with existing slices and scenarios restored

## Workshop Step Enforcement

The 7-step workshop mode constrains available tools at each step to guide participants through the Event Modeling process. Enforcement is server-authoritative — the `BoardSession` GenServer and Commanded aggregates reject disallowed actions. The UI hides unavailable tools as a convenience, but the server is the gate.

### Design Principles

- **Soft guidance, not hard walls** — the facilitator can skip steps or go back at any time. Elements created in later steps are never deleted when moving back; they are visually de-emphasized (lower opacity) to maintain focus.
- **Facilitator-only step control** — only the `facilitator` role can advance, go back, or skip steps. Participants work within whatever step the facilitator has set.
- **Workshop step is ephemeral** — the current step lives in the `BoardSession` GenServer only, not event-sourced. If the GenServer restarts, the board returns to free mode. This is intentional: workshop state is session-scoped, not a permanent property of the board.
- **Free mode vs workshop mode** — `workshop_step: nil` means all tools are available (the default for any board). The facilitator explicitly starts and ends workshop mode.

### Step Constraints

| Step | Create | Connect | Swimlane | Slice/Scenario | Advance When |
|------|--------|---------|----------|----------------|--------------|
| 1: Brainstorm Events | event | — | — | — | >= 1 event |
| 2: Plot Timeline | event | — | — | — | >= 3 events, arranged |
| 3: Storyboard | wireframe, event | — | — | — | >= 1 wireframe |
| 4: Identify Inputs | command, event | cmd→evt | — | — | >= 1 command + connection |
| 5: Identify Outputs | view, command, event, automation | all valid | — | — | >= 1 view + connection |
| 6: Organize | all | all valid | yes | — | >= 1 swimlane |
| 7: Elaborate | all | all valid | yes | yes | final step |
| nil (free mode) | all | all valid | yes | yes | N/A |

### Implementation

Step constraints are defined in a pure config module:

```elixir
defmodule EventModeler.Workshop.StepConfig do
  @type step :: 1..7 | nil

  @spec allowed_element_types(step()) :: list(atom())
  @spec allowed_connections(step()) :: list({atom(), atom()})
  @spec allowed_actions(step()) :: list(atom())
  @spec advance_criteria(step()) :: map()
end
```

Commands that carry board mutations (`PlaceElement`, `ConnectElements`, `DefineSwimlane`, `DefineSlice`, `AddScenario`) include an optional `workshop_step` field. When present, the aggregate validates the action against `StepConfig` before accepting the command. When `nil` (free mode), all actions are accepted.

The `BoardSession` GenServer holds the current step and exposes:
- `advance_step/2` — checks advance criteria, increments step (facilitator only)
- `go_back/2` — decrements step (facilitator only)
- `skip_step/2` — advances without checking criteria (facilitator only)
- `end_workshop/1` — sets step to `nil`, returning to free mode

## Scenario Auto-Generation Algorithm

Auto-generated Given/When/Then scenarios are derived from a slice's elements and their connections on the board. The algorithm builds a `SliceGraph` and walks it to produce structured scenarios.

### Algorithm

1. **Build SliceGraph** — collect all elements in the slice and their connections into a directed graph.
2. **Identify the command** — the entry point of the slice (the Command element).
3. **Derive Given (preconditions):**
   - Trace backwards from the command: find Views that connect to the command, then find Events that feed those Views.
   - These preceding Events become the Given clauses.
   - If no preceding Events exist (initial action), the Given is "no prior state exists."
4. **Derive When (action):**
   - The Command label + its fields with example values.
5. **Derive Then (outcomes):**
   - Events produced by the command (direct command→event connections).
   - Views fed by those Events (event→view connections).

### Chained Scenarios

When automations link multiple commands within a slice (event→automation→command), the algorithm generates chained scenarios — one per command in the chain. The Then clause of the first scenario feeds the Given of the next.

### Auto-Generation Metadata

Auto-generated scenarios carry `auto_generated: true` metadata:

- **Re-generated** when the slice's elements or connections change.
- **Preserved** if manually edited — the `auto_generated` flag is cleared on first manual edit, and subsequent slice changes do not overwrite the scenario.

### MVP Scope

- Direct connections only (one hop back for Given).
- Exact field name matching between connected elements.
- Manual re-generation trigger (button in slice panel) — not automatic on every change.

## Information Completeness Checking

The completeness checker validates that every field in the model is traceable to a source, catching gaps before they become implementation bugs.

### Core Rule

Every field in a View must be traceable to a source. The algorithm walks the connection graph backwards:

```
View field → source Event field → source Command field → user input (terminal)
```

### Field Matching

- **Exact match:** Field names match exactly between connected elements.
- **System-generated fields:** Fields matching `*_id`, `*_at`, `id`, `timestamp`, `version` are recognized via regex heuristic as system-generated and don't require a command source.
- **Fuzzy matching:** Jaro distance > 0.8 suggests fixes for near-miss field names (e.g., `user_name` vs `username`).

### Severity Levels

| Severity | Condition |
|----------|-----------|
| **Error** | Orphan view field (no traceable source), orphan event field (no source command), disconnected view (no incoming connections), disconnected command (no outgoing connections) |
| **Warning** | Empty element (no fields defined), field name mismatch (fuzzy match suggests fix), disconnected event (no connections) |
| **Info** | View without wireframe |

### Presentation

- **Per-element:** Colored indicator (green/yellow/red) on the element, with field provenance chain shown on hover or in sidebar.
- **Per-slice:** Score badge on the slice in the sidebar (e.g., "8/10 fields traced").
- **Per-board:** Overall completeness score in the board header (post-MVP).

### MVP Scope

Per-element and per-slice checking only. No cross-board tracing. No per-board aggregate score.

## Wireframe Handling

### Core Decision: ASCII Wireframes Only

Wireframes use plain ASCII art rather than images or visual editors. Three benefits:

1. **Keeps focus on event model design, not visual design** — wireframes in Event Modeling are low-fidelity sketches showing what data appears on screen, not pixel-perfect mockups.
2. **Zero storage overhead** — wireframe content is plain text in the `fields` jsonb column. No binary storage, no file uploads, no external URLs.
3. **Makes PRD files self-contained** — wireframes embed inline as text in the exported markdown.

### Data Model

Wireframes are elements with `type: :wireframe`. The wireframe content lives in `fields` as structured data:

```json
{
  "content": "+------------------+\n| Login            |\n|                  |\n| [email     ]     |\n| [password  ]     |\n|                  |\n| [ Sign In ]      |\n+------------------+",
  "fields": [
    {"name": "email", "type": "string"},
    {"name": "password", "type": "string"}
  ]
}
```

The `content` key holds the ASCII art. The `fields` array lists the data fields visible in the UI sketch, enabling the completeness checker to trace field provenance through wireframes.

### Canvas Rendering

The web canvas renders ASCII wireframes in a styled `<foreignObject>` block within SVG:

- Monospace font (`monospace` or `Courier New`)
- Background fill (light gray or white)
- Subtle border (1px solid, muted color)
- The underlying data is always plain ASCII text

### Editing

Inline monospace `<textarea>` on the canvas. No special drawing tools needed for MVP. The user types or pastes ASCII art directly.

### Commands

No new aggregate commands needed beyond the existing `PlaceElement` and `EditElement`. Wireframe content is element data edited via `EditElement`. This eliminates the need for `AttachWireframe`, `ReplaceWireframe`, `ResizeElement`, and the entire Storage behaviour dependency.

### Connection Rules

Wireframe connection rules (also reflected in the Element Aggregate invariants above):

| Connection | Valid | Meaning |
|------------|-------|---------|
| wireframe → command | Yes | "This screen submits this command" |
| wireframe → view | Yes | "This screen displays this view data" |
| wireframe → event | No | Wireframes don't connect directly to events |
| wireframe → automation | No | Wireframes don't connect to automations |

### PRD Export

Wireframe ASCII art is included inline in the exported PRD markdown as a fenced code block under each slice, making the PRD a complete self-contained document:

````markdown
### Slice: Register User

**Wireframe:**
```
+------------------+
| Registration     |
|                  |
| [email     ]     |
| [password  ]     |
| [name      ]     |
|                  |
| [ Sign Up ]      |
+------------------+
```

**Command:** `RegisterUser` (actor: Visitor)
...
````

## Key Patterns Applied

### DCB Pattern — Cross-Board Constraints

The [DCB pattern](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/dcb-pattern.md) handles constraints that span multiple boards:

- **Board name uniqueness per user:** Tag `BoardCreated` events with `owner_id` + `title`. Query by tag before creating. Conditional append rejects if a conflicting `BoardCreated` appeared.
- **Element reference integrity:** When an element is referenced across boards (linked models), DCB ensures the referenced element still exists at write time.

### Reservation Pattern — Concurrent Editing

The [Reservation pattern](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/reservation-pattern.md) manages concurrent element editing:

- When a user starts editing an element's text, a `ReserveElement` command locks it to that user.
- Other users see the element as locked (visual indicator).
- On save or timeout, a `ReleaseElement` command frees the lock.
- This prevents lost-update conflicts on element content without requiring full CRDT merging (element labels and descriptions are short text, not documents).

### TODO List Pattern — Async Export

The [TODO List pattern](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/todo-list-pattern.md) handles PRD export generation:

- `ExportPrd` command → `PrdExported` event
- Projector adds export request to `prd_export_todos` table
- Scheduler picks up the todo, assembles the PRD markdown/JSON from read models
- Worker dispatches `PrdExportCompleted` with the generated content
- Projector removes the todo and stores the export

This ensures export generation is crash-resilient and retryable.

### Event Enrichment — Projection Consistency

Following [Event Enrichment](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/event-enrichment.md), events carry enough data for projectors to operate independently:

- `ElementPlaced` includes the board title and swimlane label (not just IDs)
- `SliceDefined` includes element labels (not just element IDs)
- `ScenarioAdded` includes the slice name

This prevents cross-projector race conditions where one projector needs data from another's read model.

## Deployment

### Hex Module Deployment

```bash
# mix.exs
{:event_modeler, "~> 0.1"}

# Terminal
mix deps.get
mix ecto.migrate   # Runs EventModeler's migrations
```

Host app adds the router mount, auth adapter, and supervision tree entries. EventModeler runs within the host app's BEAM node.

### SaaS Deployment

`eventmodeling.sparkle.space` is a thin Phoenix app that wraps the hex module:

```
eventmodeling.sparkle.space/
├── lib/
│   ├── event_modeling_saas/
│   │   ├── accounts/          # User registration, auth (own aggregate)
│   │   ├── billing/           # Stripe integration (own aggregate)
│   │   └── tenancy/           # Org/team management (own aggregate)
│   └── event_modeling_saas_web/
│       └── router.ex          # Mounts event_modeler + auth + billing routes
├── mix.exs                    # Depends on {:event_modeler, path: "../.."}
└── config/
```

The SaaS app adds:
- User registration and authentication (not in the hex module)
- Stripe billing and subscription management
- Multi-tenancy: orgs, teams, per-org boards
- Landing page, onboarding flow, admin dashboard

The hex module code is identical in both deployments. The SaaS is the hex module + auth + billing + multi-tenancy.

### Infrastructure

Both deployments target Kubernetes (see [Hosting Architecture](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/hosting/hosting-architecture.md)):

| Component | Configuration |
|-----------|---------------|
| App pods | Phoenix release with EventModeler included |
| Database | PostgreSQL (event store + read models) |
| PubSub | Erlang distribution for cross-node PubSub (see [Erlang Clustering](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/hosting/erlang-clustering.md)) |
| Assets | CDN-served JS/CSS bundles from hex module |

## References

- [Product Specification](product-spec.md) — Feature set and PRD format
- [Event Modeling](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/event-modeling.md) — Core methodology
- [Event Sourcing & CQRS](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/event-sourcing-cqrs.md) — Architecture foundation
- [Collaboration Architecture](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/collaboration-architecture.md) — Two-level sync pattern (adapted)
- [Optimistic UI Updates](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/optimistic-ui-updates.md) — UI update tiers (applied)
- [DCB Pattern](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/dcb-pattern.md) — Cross-board constraints
- [Reservation Pattern](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/reservation-pattern.md) — Element locking
- [TODO List Pattern](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/todo-list-pattern.md) — Async export
- [Event Enrichment](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/event-enrichment.md) — Projection consistency
- [Elixir/Phoenix/LiveView](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/elixir-phoenix-liveview.md) — Stack rationale
- [Emlang spec v1.0.0](https://github.com/emlang-project/spec) — Slice notation DSL (used in PRD import/export)
- [Emlang CLI](https://github.com/emlang-project/emlang) — Linting and diagram generation
