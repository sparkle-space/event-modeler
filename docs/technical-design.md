# EventModeler: Technical Design

**Status:** Concept
**Date:** 2026-02-17
**Depends on:** [Product Specification](product-spec.md), [Event Modeling](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/event-modeling.md), [Collaboration Architecture](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/collaboration-architecture.md)

## Overview

EventModeler is a standalone Phoenix/LiveView application for collaborative event modeling. This document describes the architecture, data model, canvas design, collaboration strategy, and Event Model import/export pipeline.

For the product vision, feature set, and Event Model format definition, see the [Product Specification](product-spec.md).

## Repository Structure

| Decision | Choice |
|----------|--------|
| **Repo/package name** | `event_modeler` |
| **Repo structure** | Standalone Phoenix application |
| **Licensing** | Start private. Open-source when hex module is extracted |
| **Docs strategy** | Masterplan keeps overview summary + link to repo. Repo gets detailed specs in `docs/` |

```
event_modeler/
├── lib/
│   ├── event_modeler/          # Core domain logic
│   ├── event_modeler_web/      # Phoenix web layer
│   └── event_modeler.ex
├── assets/                     # JS/CSS for canvas
├── priv/
│   └── event_models/          # Sample Event Model markdown files
├── test/
├── config/
├── docs/
│   ├── product-spec.md
│   └── technical-design.md
├── mix.exs
└── README.md
```

The application is a standard Phoenix project. Once the core is mature, the reusable domain logic (`lib/event_modeler/`) will be extracted into a publishable hex package.

## Future: Hex Module Extraction

When the standalone app is mature, the core will be extracted into a hex package following the Phoenix library pattern established by `phoenix_live_dashboard` and `live_storybook`: a self-contained package that brings its own routes, LiveView modules, JS hooks, and CSS. The host app would provide authentication, user context, and PubSub. No database required — persistence is file-based (Event Model markdown files).

The design below describes the target hex module architecture. During the standalone app phase, these same components exist but are not yet packaged for external consumption.

### Router Integration

The host app mounts EventModeler with a single line:

```elixir
# lib/my_app_web/router.ex
import EventModeler.Router

scope "/", MyAppWeb do
  pipe_through [:browser, :require_authenticated_user]

  event_modeler "/event-model",
    event_models_path: "priv/event_models",
    pubsub: MyApp.PubSub,
    auth: MyAppWeb.EventModelerAuth
end
```

`event_modeler/2` is a macro that generates routes for the board listing, board canvas, slice detail, Event Model import/export, and workshop mode LiveViews.

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
| `EventModeler.Live.*` | LiveView modules for board, canvas, slices, workshop, Event Model import/export |
| `EventModeler.Hooks` | Phoenix LiveView JS hooks for canvas interaction |
| `EventModeler.Assets` | CSS and JS bundles (served via `Plug.Static` or esbuild plugin) |
| `EventModeler.EventModel.*` | Parser, serializer, emlang, event stream — file-based persistence |
| `EventModeler.Collaboration.*` | GenServer sessions, Registry, Presence for real-time sync |

### What the Host App Provides

| Component | Description |
|-----------|-------------|
| PubSub | Phoenix PubSub instance for broadcasts |
| Auth adapter | User identity and authorization |
| Endpoint | WebSocket and HTTP serving |
| File system | Directory for Event Model markdown files |

## Stack

The technology choices align with the sparkle.space ecosystem:

| Layer | Technology | Reference |
|-------|------------|-----------|
| Language | Elixir | [Elixir/Phoenix/LiveView](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/elixir-phoenix-liveview.md) |
| Web framework | Phoenix + LiveView | [Elixir/Phoenix/LiveView](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/elixir-phoenix-liveview.md) |
| Persistence | File system (Event Model markdown) | — |
| State management | Board GenServer (in-memory during sessions) | — |
| Real-time | Phoenix Channels + Presence | [Collaboration Architecture](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/collaboration-architecture.md) |
| Canvas rendering | SVG (via LiveView + JS hooks) | — |

## Data Model

EventModeler uses file-based persistence. Event Models are stored as markdown files in the file system. During a modeling session, the Board GenServer loads the Event Model into memory, holds all state (elements, slices, scenarios, connections), and writes back to the file on save.

### In-Memory State (Board GenServer)

Each open board has a GenServer (`EventModeler.Board`) holding the complete session state:

```elixir
%{
  file_path: String.t(),          # Path to the Event Model markdown file
  event_model: %EventModel{},     # Parsed Event Model struct (slices, elements, scenarios, etc.)
  layout: %LayoutResult{},        # Computed element positions (pure function of event_model)
  canvas_data: map(),             # Rendered canvas data for LiveView
  connections: [{String.t(), String.t()}],  # Active connections [{from_id, to_id}]
  dirty: boolean()                # Whether unsaved changes exist
}
```

### Core Domain Structs

```elixir
%EventModel{title, status, domain, version, slices, scenarios, event_stream, sections, ...}
%Slice{name, steps: [%Element{}], tests: [...], raw_emlang}
%Element{id, type, label, swimlane, props: %{}}
%EventEntry{seq, ts, type, actor, data, session, ref, note}
```

### Persistence Flow

1. **Load:** `Workspace.read_event_model(path)` → `Parser.parse(markdown)` → `%EventModel{}`
2. **Edit:** Board GenServer mutates the in-memory `%EventModel{}` struct
3. **Save:** `Serializer.serialize_for_save(event_model)` → write markdown to file
4. **Layout:** `Layout.compute(event_model)` → `%LayoutResult{}` (pure computation, no persistence)

### Connection Validation

Connection rules are enforced in `ConnectionRules`:

| Connection | Valid | Meaning |
|------------|-------|---------|
| command → event | Yes | Command produces event |
| command → exception | Yes | Command may fail |
| event → view | Yes | Event updates read model |
| event → automation | Yes | Event triggers automation |
| automation → command | Yes | Automation dispatches command |
| wireframe → command | Yes | Screen submits command |
| wireframe → view | Yes | Screen displays view data |
| command → view | No | Commands don't connect directly to views |
| wireframe → event | No | Wireframes don't connect to events |

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
│  ┌─ Panels (contextual, not always visible) ──────────────┐  │
│  │  Left panel: Element palette (hidden by default)       │  │
│  │  Right panel: Element editor (1/3 width, on click)     │  │
│  │  Bottom sheet: Slice details (overlays canvas)         │  │
│  │  Modal: Event model description (overlay)              │  │
│  │  Top bar: Slice dropdown, description, add element     │  │
│  └────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

### Board Interaction Modes

The board uses implicit functional modes — the UI adapts based on user actions rather than explicit mode toggles. The canvas maximizes screen space by default and panels appear only when needed.

| Mode | Trigger | UI State |
|------|---------|----------|
| Overview/Browse | Default state | No panels visible. Canvas fills screen. Floating "+" button and top bar controls available. |
| Add Element | Click "+" button or top bar "+ Add" | Left palette slides in (192px). Element type buttons with colored indicators. Close to dismiss. |
| Description | Click "Description" in top bar | Modal overlay (70vw) shows full event model overview, key ideas, data flows, sources. Read-only. |
| Slice Navigation | Select slice from top bar dropdown | Bottom sheet slides up from canvas bottom. Shows elements list, scenarios, generate button. Canvas pans to slice. |
| Edit Element | Single-click an element | Right panel appears at 1/3 screen width. Canvas zooms to element. Previous viewport saved and restored on close. |

**Viewport preservation:** When entering Edit Element mode, the JS hook saves the current `translateX`, `translateY`, and `scale`. On exit (cancel, update, or background click), the viewport animates back to the saved state.

**Escape key unwinding:** Escape closes the topmost active mode in priority order: description modal → element editor → palette → slice details.

### JS Hook Responsibilities

The `EventModelerCanvas` hook handles interactions that require client-side responsiveness:

| Interaction | Handling |
|-------------|----------|
| Pan | Client-side viewBox transform; no server round-trip |
| Zoom | Client-side viewBox scaling; no server round-trip |
| Drag element | Client-side position during drag; `pushEvent("element_moved", ...)` on drop |
| Draw connection | Client-side rubber-band line; `pushEvent("elements_connected", ...)` on release |
| Select element | Single-click opens edit mode; `pushEvent("element_selected", ...)` triggers viewport save + zoom + right panel |
| Text editing | Client-side input; `pushEvent("element_edited", ...)` on blur |
| Viewport save/restore | `save_viewport` / `restore_viewport` server events; animates between edit and browse states |
| Zoom to element | `zoom_to_element` server event; centers element accounting for right panel width |

The server remains authoritative: every mutation is handled by the Board GenServer, which validates the action and updates the in-memory state. Changes are broadcast to connected users via PubSub. Client-side state is optimistic and reconciled on server confirmation.

### Rendering Flow

1. LiveView mounts, Board GenServer loads Event Model from file and computes layout
2. SVG is rendered server-side with all elements positioned
3. JS hook initializes pan/zoom and attaches drag listeners
4. User drags element → client moves SVG node → drop fires `pushEvent`
5. Board GenServer updates in-memory state, records event in event stream
6. State change broadcast via PubSub → all connected LiveViews update assigns
7. LiveView diffs → minimal SVG attribute updates sent to other clients

## Real-Time Collaboration

Adapted from the [Collaboration Architecture](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/collaboration-architecture.md) two-level sync model.

### Two-Level Sync

| Level | Purpose | Technology | Persistence |
|-------|---------|------------|-------------|
| **Ephemeral** | Real-time element dragging, cursor positions, selection state | GenServer per board + Phoenix Channels | None (in-memory only) |
| **Persistent** | Element placement, connections, slice definitions, scenarios | Event Model markdown file | File system |

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
- `handle_call(:drag_end, ...)` — Release lock, update Board GenServer state for persistence
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
| Concurrent slice definition | Both succeed — slices are independent units |
| Concurrent connection drawing | Both succeed if valid; Board GenServer rejects invalid connections |

### Optimistic UI Updates

Following the [tier system](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/optimistic-ui-updates.md):

| Action | Tier | Approach |
|--------|------|----------|
| Move element | 1 | Client-side drag + optimistic assign update |
| Edit element label | 1 | `%{element | label: new_label}` |
| Place new element | 2 | Construct element struct from params + returned ID |
| Remove element | 2 | `Enum.reject` from element list |
| Import Event Model | 3 | Loading state + PubSub reload when import completes |

## Event Model Import/Export Pipeline

### Import Flow

```
Markdown Event Model (input)
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
       ├──── ```yaml emlang``` blocks found? ────┐
       │  No                                │ Yes
       ▼                                    ▼
┌─────────────┐                    ┌─────────────┐
│ Suggest      │                    │ Parse Emlang │  Parse each ```yaml emlang``` block as YAML
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
│               │  ImportEventModel command → EventModelImported event
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
│ Board State  │  Load original Event Model if imported
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ Build Slice  │  For each slice: collect elements in connection order
│ Sections     │  (Trigger → Command → Event → View)
│ (emlang)     │  Format as emlang YAML steps: list with props:
│              │  Include scenarios as emlang tests: blocks
│              │  Wrap in ```yaml emlang fenced code block
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
│ Event Model  │  Preserved: Overview, Key Ideas, Sources (from import)
│              │  Generated: Slices (emlang), Scenarios, Data Flows
└──────┬──────┘
       │
       └──→ Markdown (.md) — with ```yaml emlang slice blocks
```

### Round-Trip Fidelity

When an Event Model is imported and then exported:

- **Preserved verbatim:** Overview, Key Ideas, Sources, Dependencies (from the original)
- **Added by model:** Slices section, Scenarios section, Data Flows section
- **Updated:** Frontmatter status changes from `draft` to `refined`
- **Re-importable:** The exported Event Model can be re-imported into a new board, with existing slices and scenarios restored

### Event Stream Parser/Writer

The Event Model event stream is an append-only log embedded at the bottom of the markdown file. The parser reads it on import; the writer appends to it during modeling sessions.

#### Parse Algorithm

1. **Locate sentinel** — scan for `<!-- event-stream -->` HTML comment
2. **Extract blocks** — find all fenced `` ```eventstream `` blocks after the sentinel
3. **Parse YAML** — each block is a single YAML document with `seq`, `ts`, `type`, `actor`, `data` (plus optional `session`, `ref`, `note`)
4. **Validate sequence** — verify `seq` values are monotonically increasing with no gaps
5. **Return** — list of parsed event structs, ordered by `seq`

If no sentinel is found, the event stream is empty (new Event Model).

#### Write Algorithm

1. **Check sentinel** — if `<!-- event-stream -->` is absent, append it plus `## Event Stream` heading
2. **Determine next seq** — read the last event's `seq` value, increment by 1 (or start at 1)
3. **Format block** — render the event as a fenced `` ```eventstream `` YAML block
4. **Append** — write the new block at the end of the file (after all existing event blocks)

During modeling sessions, events are held in-memory by the `BoardSession` GenServer. They are flushed to the Event Model file on save or session end, not on every individual action. This batches disk writes and keeps the append operation atomic.

## Workshop Step Enforcement

The 7-step workshop mode constrains available tools at each step to guide participants through the Event Modeling process. Enforcement is server-authoritative — the Board GenServer rejects disallowed actions based on the current step. The UI hides unavailable tools as a convenience, but the server is the gate.

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

Board mutations (place element, connect elements, define swimlane, define slice, add scenario) are validated against `StepConfig` when `workshop_step` is set. When `nil` (free mode), all actions are accepted.

The Board GenServer holds the current step and exposes:
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

Per-element and per-slice checking only. No cross-board tracing. No per-board overall score.

## Wireframe Handling

### Core Decision: ASCII Wireframes Only

Wireframes use plain ASCII art rather than images or visual editors. Three benefits:

1. **Keeps focus on event model design, not visual design** — wireframes in Event Modeling are low-fidelity sketches showing what data appears on screen, not pixel-perfect mockups.
2. **Zero storage overhead** — wireframe content is plain text in the element's `props` map. No binary storage, no file uploads, no external URLs.
3. **Makes Event Model files self-contained** — wireframes embed inline as text in the exported markdown.

### Data Model

Wireframes are elements with `type: :wireframe`. The wireframe content lives in the element's `props` map:

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

No special handling needed beyond the existing `place_element` and `edit_element` Board GenServer calls. Wireframe content is element data stored in `props`.

### Connection Rules

Wireframe connection rules (also reflected in the connection validation rules above):

| Connection | Valid | Meaning |
|------------|-------|---------|
| wireframe → command | Yes | "This screen submits this command" |
| wireframe → view | Yes | "This screen displays this view data" |
| wireframe → event | No | Wireframes don't connect directly to events |
| wireframe → automation | No | Wireframes don't connect to automations |

### Event Model Export

Wireframe ASCII art is included inline in the exported Event Model markdown as a fenced code block under each slice, making the Event Model a complete self-contained document:

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

The [DCB pattern](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/dcb-pattern.md) concept applies to constraints that span multiple boards:

- **Board name uniqueness:** The Workspace module checks for file name conflicts when creating new Event Model files.
- **Element reference integrity:** When an element is referenced across boards (linked models), validation ensures the referenced element still exists.

In the file-based architecture, these constraints are enforced by the Board GenServer and Workspace module rather than by event store conditional appends.

### Reservation Pattern — Concurrent Editing

The [Reservation pattern](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/reservation-pattern.md) concept applies to concurrent element editing:

- When a user starts editing an element, the Board GenServer locks it to that user (future: multi-user).
- Other users see the element as locked (visual indicator).
- On save or timeout, the lock is released.
- This prevents lost-update conflicts on element content without requiring full CRDT merging (element labels and descriptions are short text, not documents).

In the file-based architecture, locks are ephemeral GenServer state — not persisted to disk.

## Deployment

### Standalone Server

```bash
# Clone and setup
git clone <repo-url> && cd event_modeler
mix deps.get
mix phx.server     # Start at localhost:4000
```

Event Model files are stored in `priv/event_models/`. No database setup required.

For production, build a Phoenix release and deploy to the target infrastructure.

### Future: Hex Module Deployment

Once extracted, host apps will add the hex module as a dependency:

```bash
# mix.exs
{:event_modeler, "~> 0.1"}

# Terminal
mix deps.get
```

Host app adds the router mount, configures the Event Model directory path, and starts the supervision tree. EventModeler runs within the host app's BEAM node.

### Infrastructure

Standalone server deployment targets Kubernetes (see [Hosting Architecture](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/hosting/hosting-architecture.md)):

| Component | Configuration |
|-----------|---------------|
| App pods | Phoenix release |
| Persistence | File system (Event Model markdown files) |
| PubSub | Erlang distribution for cross-node PubSub (see [Erlang Clustering](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/hosting/erlang-clustering.md)) |
| Assets | Bundled JS/CSS served by Phoenix |

## References

- [Product Specification](product-spec.md) — Feature set and Event Model format
- [Event Modeling](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/event-modeling.md) — Core methodology
- [Collaboration Architecture](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/collaboration-architecture.md) — Two-level sync pattern (adapted)
- [Optimistic UI Updates](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/optimistic-ui-updates.md) — UI update tiers (applied)
- [DCB Pattern](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/dcb-pattern.md) — Cross-board constraints
- [Reservation Pattern](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/reservation-pattern.md) — Element locking
- [Elixir/Phoenix/LiveView](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/elixir-phoenix-liveview.md) — Stack rationale
- [Emlang spec v1.0.0](https://github.com/emlang-project/spec) — Slice notation DSL (used in Event Model import/export)
- [Emlang CLI](https://github.com/emlang-project/emlang) — Linting and diagram generation
