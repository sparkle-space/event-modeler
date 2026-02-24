# Gap Analysis: EventModeler — Planned vs. Implemented

*Generated: 2026-02-24*

## Context

This analysis compares the product spec (`docs/product-spec.md`) and technical design (`docs/technical-design.md`) against the current codebase to identify what remains to be implemented.

---

## Current State Summary

The project is a **working, file-based prototype** with a functional collaborative canvas, element CRUD, slice management, scenario generation, and markdown import/export. It uses GenServer + file I/O for persistence — no database, no event sourcing infrastructure.

---

## What IS Implemented (working)

- Markdown parsing pipeline (frontmatter, sections, emlang, event stream)
- Board GenServer with full element/slice/scenario CRUD
- Layout engine with computed positions and swimlane logic
- Connection validation per Event Modeling rules
- Interactive SVG canvas (pan, zoom, select, connect, delete)
- Element editing with right panel
- Slice management with bottom sheet
- Scenario auto-generation from slice structure
- Round-trip serialization (parse → edit → save → reload)
- Markdown export via ExportController
- Basic visualization view (VisualizeLive)
- Implicit interaction modes (palette, description, element editing)
- 22 test files with good domain and integration coverage
- CI pipeline (compile, format, tests)

---

## What's NOT Implemented — By Category

### 1. ~~Infrastructure — Event Sourcing & Database~~ NOT A GAP

**Decision:** File-based persistence is the intended architecture. No Commanded/EventStore/Ecto overhaul planned. The Board GenServer + markdown file I/O is the persistence layer by design. The technical design doc describes aspirational architecture that may need updating to reflect this decision.

### 2. Real-Time Collaboration

| Gap | Spec Reference |
|-----|---------------|
| No multi-user presence (cursors, selections) | Product Spec §Collaborative Canvas |
| No element locking / drag locks | Technical Design §Conflict Resolution |
| No Phoenix Presence integration | Technical Design §Ephemeral Sync |
| No conflict resolution (first-lock-wins, last-write-wins) | Technical Design §Conflict Resolution |
| No user sessions or identity | Product Spec §User Roles |

### 3. User Roles & Permissions

| Gap | Spec Reference |
|-----|---------------|
| No Facilitator / Participant / Viewer roles | Product Spec §User Roles |
| No authentication or authorization | Product Spec §User Roles |
| No invite / join flow | Product Spec §Workshop Mode |

### 4. Workshop Mode (7-Step Process)

| Gap | Spec Reference |
|-----|---------------|
| No workshop step tracking in GenServer | Product Spec §Workshop Mode |
| No step-specific UI constraints (e.g., only events in Brainstorm) | Product Spec §Workshop Mode |
| No facilitator step progression controls | Product Spec §Workshop Mode |
| No element de-emphasis for "future step" items | Product Spec §Workshop Mode |
| No progress indicators per step | Product Spec §Workshop Mode |

### 5. Import Flow Enhancements

| Gap | Spec Reference |
|-----|---------------|
| No heuristic element placement from Key Ideas | Product Spec §Import Flow |
| No Key Idea → Command + Event pair suggestion | Product Spec §Import Flow |
| No interactive review/adjust step after import | Product Spec §Import Flow |

### 6. Export Enhancements

| Gap | Spec Reference |
|-----|---------------|
| No data flow table generation (Source → Enters as → Transforms via → Exits as) | Product Spec §Data Flows |

**Decision:** JSON export is not needed. Markdown + emlang is the canonical format.

### 7. Information Completeness Checking

| Gap | Spec Reference |
|-----|---------------|
| No per-element completeness indicators (green/yellow/red) | Product Spec §Completeness |
| No field provenance tracing (View fields → source Events) | Product Spec §Completeness |
| No per-slice completeness score badges | Product Spec §Completeness |
| No orphan detection (disconnected elements, empty labels) | Product Spec §Completeness |

### 8. Read-Only Visualization Enhancements

| Gap | Spec Reference |
|-----|---------------|
| No event stream replay / time-travel slider | Product Spec §Visualization |
| No embeddable LiveView component | Product Spec §Visualization |
| Current VisualizeLive is basic markdown-in → SVG-out | — |

### 9. Canvas UX Refinements

| Gap | Spec Reference |
|-----|---------------|
| No drag-to-move elements on canvas | Product Spec §Canvas |
| No drag-to-reorder slices | Product Spec §Slice Management |
| No keyboard shortcuts beyond Delete | Product Spec §Canvas |
| No undo/redo | Common expectation |
| No minimap or overview navigation | Common expectation |

### 10. Element Types — Partial Coverage

| Element | Status |
|---------|--------|
| Events | Fully supported |
| Commands | Fully supported |
| Views | Fully supported |
| Exceptions | Supported in parser/layout, less exercised in UI |
| Wireframes | Parsed and rendered, but no ASCII art editor or field extraction |
| Automations | Parsed and rendered, but no special gear icon UI or trigger descriptions |

---

## Prioritized Recommendation

### Likely Next Steps (high value, builds on existing work)

1. **Drag-to-move elements** — the canvas supports click/select but not repositioning
2. **Data flow table generation** — extends export with field tracing
3. **Information completeness checking** — visual feedback on model quality
4. **Workshop mode** — step tracking in GenServer, UI step indicator
5. **Import heuristics** — auto-suggest elements from Key Ideas

### Larger Efforts (infrastructure changes)

6. **Real-time collaboration** — Phoenix Presence, element locking, cursor sharing
7. ~~**Event sourcing with Commanded**~~ — NOT PLANNED. File-based persistence is intentional.
8. **User authentication & roles** — identity, permissions, invite flow
9. **Event stream replay / time-travel** — can use markdown event stream entries

### Out of Scope

- Code scaffolding from slices
- Ticket integration (Jira/Linear)
- Template library

### Deferred by Design (post-MVP per spec)

- LLM-assisted generation
- Time collapsing

---

## Deep Dive: Real-Time Collaboration

### What the Spec Requires

The technical design defines a **two-level sync** model:

| Level | Purpose | Technology | Persistence |
|-------|---------|------------|-------------|
| Ephemeral | Dragging, cursors, selections, locks | GenServer + Phoenix Channels | None (in-memory) |
| Persistent | Element placement, connections, slices, scenarios | File-based (markdown) | Markdown files |

**BoardSession GenServer** (spec'd but not built):
```
%{
  board_id: String.t(),
  participants: MapSet.t(String.t()),
  element_locks: %{element_id => user_id},
  drag_positions: %{element_id => {x, y}},
  workshop_step: integer() | nil
}
```

**Presence metadata** (spec'd but not built):
```
%{
  user_id: String.t(),
  display_name: String.t(),
  color: String.t(),
  cursor: {x, y} | nil,
  selected_element: String.t() | nil
}
```

**Conflict resolution rules:**
- Two users drag same element → first lock wins, second sees it locked
- Concurrent text edits → last-write-wins on `ElementEdited`
- Concurrent slice definitions → both succeed (independent)
- Invalid connections → aggregate rejects

### What Already Exists

| Component | Status |
|-----------|--------|
| `Phoenix.PubSub` in supervision tree | Initialized but **never used** |
| `Registry` for Board lookup | Working |
| `DynamicSupervisor` for Board processes | Working |
| Board GenServer state management | Working, but **single-user only** |
| LiveView ↔ Board GenServer connection | Working, but **no broadcast/subscribe** |
| JS hook for canvas interaction | Working, but **no cursor/drag broadcasting** |

### What's Completely Missing

**Infrastructure:**
- No `Phoenix.Presence` module
- No PubSub subscriptions in BoardLive (it's initialized but unused)
- No user identity in session/socket (no `current_user`)
- No authentication pipeline in router

**Board GenServer gaps:**
- State struct has no `participants`, `element_locks`, `drag_positions`
- No `join/2`, `leave/2`, `drag_start/3`, `drag_move/2`, `drag_end/2` APIs
- Changes are not broadcast — only the calling LiveView sees updates

**LiveView gaps:**
- No `subscribe()` to board PubSub topic on mount
- No `handle_info` for broadcast messages (user joined, element locked, etc.)
- No presence tracking for cursor/selection sync
- No lock checks before mutations

**JS hook gaps:**
- No cursor position broadcasting on mousemove
- No drag position broadcasting during drag
- No remote cursor rendering
- No lock visualization (grayed-out elements)
- No incoming remote drag position updates

### Implementation Phases

**Phase 1 — User Context & PubSub (blocks everything)**
- Add user identity to session (even anonymous with random ID + color)
- Subscribe BoardLive to board PubSub topic on mount
- Broadcast board state changes from Board GenServer
- Handle incoming broadcasts in BoardLive to re-render

**Phase 2 — Element Locking & Drag Sync**
- Add `element_locks` and `drag_positions` to Board GenServer state
- Implement `drag_start/3` (acquire lock), `drag_move/2` (update position), `drag_end/2` (release lock)
- Broadcast lock/unlock events via PubSub
- JS hook: render lock indicators, receive remote drag positions

**Phase 3 — Cursor & Presence**
- Initialize Phoenix.Presence in supervision tree
- Track user presence with cursor position and selected element
- JS hook: broadcast cursor position on mousemove (throttled)
- Render remote cursors with assigned colors

**Phase 4 — Optimistic Updates & Conflict Handling**
- Client-side optimistic element positioning during drag
- Reconcile on server confirmation
- Handle lock conflicts gracefully (visual feedback)

**Phase 5 — Roles & Authorization**
- Add role to user context (Facilitator/Participant/Viewer)
- Server-side permission checks on mutations
- Hide/disable UI controls based on role

---

## Deep Dive: Drag-to-Move Elements

### Current State

**Partially wired:** The Board GenServer has `move_element/4`, BoardLive has `handle_event("move_element", ...)`, and the JS hook has element detection — but no actual drag logic connects them.

- `Board.move_element/4` **ignores x/y values** — only logs an event stream entry
- BoardLive handler calls Board then refreshes state — correct pattern
- JS hook detects element clicks for selection but has **no drag mode**
- Pan mode works (background drag) but element drag doesn't exist

### Core Architectural Tension

Layout positions are **computed, not stored**. `Layout.compute/1` is a pure function that calculates all positions from the EventModel struct. Dragging to a new position creates a conflict: where to store the user's override?

**Solution: Position offsets in Element.props**
- Layout computes base position as usual
- Element stores `position_offset_x` / `position_offset_y` in `props` map
- Layout applies offsets after computing base positions
- Offsets persist to markdown file via existing serialization
- "Reset layout" = delete offset props

### Changes Needed Per Layer

| Layer | Change | Complexity |
|-------|--------|-----------|
| `assets/js/hooks/canvas.js` | Add element drag mode (mousedown/move/up on elements), coordinate math with pan/zoom, pushEvent | **Medium** — coordinate math under transforms is tricky |
| `lib/event_modeler/board.ex` | Store x/y as offset in Element.props, recompute layout | **Low** — infrastructure exists |
| `lib/event_modeler/canvas/layout.ex` | Apply `position_offset_x/y` from props to computed positions | **Low** — ~5 lines in `layout_slice/3` |
| `lib/event_modeler_web/live/board_live.ex` | Already has handler — no change needed | **None** |
| Serialization | Props already serialize to markdown — no change | **None** |

### JS Hook Drag Algorithm

```
mousedown on element (non-shift):
  → record drag start position, element start position
  → enter drag mode

mousemove in drag mode:
  → compute delta / scale factor
  → apply CSS transform to element (visual feedback, no server call)

mouseup in drag mode:
  → compute final world-space position (accounting for pan + zoom)
  → pushEvent("move_element", {element_id, x, y})
  → clear CSS transform (server re-renders with actual position)
```

**Hardest part:** Coordinate math accounting for CSS transform (pan offset + zoom scale) on `#canvas-world`.

### What Already Works (reusable)

- `Board.move_element/4` API endpoint (just needs real implementation)
- `BoardLive.handle_event("move_element", ...)` handler
- `Element.props` free-form map for storing offsets
- `EventStreamWriter` for logging the move
- `HtmlRenderer` maps positions to inline styles
- JS hook already tracks `data-element-id` and `data-selected`
- `refresh_state/1` pattern for post-mutation re-render

---

## Deep Dive: Information Completeness Checking

### What the Spec Requires

Technical design (§641-675) defines a **three-tier completeness checker**:

**Field provenance tracing:**
```
View field → source Event field → source Command field → user input (terminal)
```

**Field matching rules:**
1. **Exact match** — field names match exactly
2. **System-generated** — regex `*_id`, `*_at`, `id`, `timestamp`, `version` (no source needed)
3. **Fuzzy match** — Jaro distance > 0.8, flags near-misses with suggested fixes

**Severity levels:**
| Level | Condition |
|-------|-----------|
| Error | Orphan view field, orphan event field, disconnected view/command |
| Warning | Empty element, field name mismatch, disconnected event |
| Info | View without wireframe |

**Presentation:** Per-element colored indicators (green/yellow/red), per-slice score badges, field provenance on hover. MVP = per-element + per-slice only.

### What Already Exists (reusable)

| Component | Location | How it helps |
|-----------|----------|-------------|
| `Element.props` map | `lib/event_modeler/event_model/element.ex` | Field storage — already populated, serialized, preserved through layout |
| Connection list `[{from_id, to_id}]` | `lib/event_modeler/board.ex:25` | Directed graph for traversal |
| Connection extraction from event stream | `board.ex:704-716` | Reconstructs graph from history |
| Graph walking in ScenarioGenerator | `lib/event_modeler/workshop/scenario_generator.ex:125-156` | Same pattern needed: walk before/after elements in slice |
| ConnectionRules valid sources/targets | `lib/event_modeler/canvas/connection_rules.ex` | Defines expected flow patterns |
| Layout preserves props | `lib/event_modeler/canvas/layout.ex:154` | Props available on positioned elements |

### What's Missing

**No implementation at all** — zero code for completeness checking exists.

**Needed modules:**

1. **`EventModeler.Canvas.GraphTraverser`** (new)
   - `connections_for_element/3` — find adjacent elements by direction
   - `trace_field_backward/4` — walk back from View field to source Command/Event
   - Extract and generalize the graph-walking pattern from ScenarioGenerator

2. **`EventModeler.Canvas.FieldMatcher`** (new)
   - `exact_match?/2`, `system_generated?/1`, `fuzzy_match/3`
   - Jaro distance from hex library or inline implementation

3. **`EventModeler.Canvas.CompletenessChecker`** (new)
   - `check_slice/2` — per-slice analysis returning score + field reports
   - `check_element/2` — per-element field tracing with severity classification

4. **Board integration** — `Board.check_completeness/1` public API (ephemeral, no persistence)

5. **UI layer** — colored indicators on elements, score badges on slices, hover tooltips

### Key Insight

The **infrastructure is ~80% ready**. Element props carry field data, connections form a queryable graph, and the ScenarioGenerator already demonstrates the graph-walking pattern needed. The gap is the algorithm implementation and UI integration.

---

## Deep Dive: Workshop Mode (7-Step Guided Process)

### What the Spec Requires

A facilitator-guided 7-step workflow that constrains which tools are available at each step:

| Step | Phase | Allowed Elements | Advance Criteria |
|------|-------|------------------|-----------------|
| 1 | Brainstorm | Event only | >= 1 event |
| 2 | Plot | Event only | >= 3 events |
| 3 | Storyboard | Wireframe, Event | >= 1 wireframe |
| 4 | Identify Inputs | Command, Event | >= 1 command + connection |
| 5 | Identify Outputs | View, Command, Event, Automation | >= 1 view + connection |
| 6 | Organize | All types | >= 1 swimlane |
| 7 | Elaborate | All types | Final step (slices/scenarios) |
| nil | Free Mode | All types | N/A (default) |

**Key design decisions from spec:**
- **Server-enforced** constraints (not just UI hiding)
- **Soft guidance** — facilitator can skip/go back; elements never deleted, just de-emphasized
- **Ephemeral** — workshop_step lives in GenServer only, not persisted. Session restart = free mode
- **Facilitator-only** step control

### What Exists Today

**Nothing workshop-specific.** The `workshop/` directory only contains `scenario_generator.ex`.

- Board GenServer state has no `workshop_step` field
- `place_element` does no type validation against step
- `connect_elements` validates connection rules but not step constraints
- Element palette always shows all 6 types
- No facilitator/participant role distinction
- No step indicator UI

### Where Workshop State Belongs

**In the Board GenServer** (not a separate process). Rationale:
- Workshop step directly affects which mutations are allowed
- Must be checked atomically with element placement/connection
- Existing Board GenServer already manages all board state

**Board struct additions needed:**
```elixir
defstruct [
  ...,
  workshop_step: nil,       # 1..7 | nil
  facilitator_id: nil,      # user_id (nil = no workshop)
]
```

### New Module: `EventModeler.Workshop.StepConfig`

Pure configuration module (no state) defining per-step constraints:
- `allowed_element_types(step)` → `[:event]` for step 1, all types for step 6-7
- `allowed_connections(step)` → `[]` for steps 1-3, `[{:command, :event}]` for step 4, etc.
- `allowed_actions(step)` → enables `:define_slice` only at step 7
- `advance_criteria(step)` → validation rules per step

### Changes Per Layer

| Layer | Change | Complexity |
|-------|--------|-----------|
| New `Workshop.StepConfig` | Pure config module for step constraints | **Low** |
| `board.ex` state | Add `workshop_step`, `facilitator_id` fields | **Low** |
| `board.ex` handlers | New: `start_workshop`, `advance_step`, `go_back`, `skip`, `end_workshop` | **Medium** |
| `board.ex` mutations | Gate `place_element`, `connect_elements`, `define_slice` by step | **Medium** |
| `board_live.ex` mount | Fetch + assign workshop state | **Low** |
| `board_live.ex` events | New handlers for step controls; filter palette by step | **Medium** |
| Template/UI | Step indicator bar, filtered palette, facilitator controls, de-emphasis | **Medium** |
| Error messages | Return blockers on invalid actions or advance attempts | **Low** |

### Element Palette Change

**Current:** Always shows all 6 types.
**New:** Filters to `StepConfig.allowed_element_types(@workshop_step)`. When `workshop_step` is nil (free mode), shows all.

### Key Dependencies

- **User identity** — needed to track facilitator role (blocked by no auth)
- **Swimlane management** — step 6 requires defining swimlanes, which needs first-class Board support (currently swimlanes only exist in the layout read model)

### Workaround for Auth Dependency

Workshop mode could work without full auth by using a simpler model:
- The user who calls `start_workshop` becomes the facilitator
- Track by LiveView socket/PID rather than authenticated user_id
- Single-user workshop is still useful for guided self-modeling

---

## Deep Dive: Read-Only Visualization & Event Replay

### What the Spec Requires

- Render Event Model as a **non-editable canvas** (VisualizeLive)
- **Event stream replay** with a time-travel slider showing model evolution
- **Embeddable LiveView** component mountable in host Phoenix apps
- Auto-update when underlying model file changes

### What Exists Today

**VisualizeLive** (`lib/event_modeler_web/live/visualize_live.ex`, 277 lines) is **functional for basic read-only viewing:**
- Paste markdown or load from file → parses → computes layout → renders SVG
- Non-editable (no place/move/connect handlers)
- Full page at `/visualize` route

**Event stream infrastructure exists:**
- `EventEntry` struct has `seq`, `ts`, `type`, `actor`, `data` fields
- `EventStreamParser` extracts and sorts entries from markdown
- `EventStreamWriter` appends events with auto-incrementing seq

**Pure rendering pipeline works:**
- `Parser.parse()` → `Layout.compute()` → `SvgRenderer.render()` — all pure functions, replayable

### What's Missing

| Feature | Status |
|---------|--------|
| Event replay / reconstruction at seq N | Missing — no `Replayer` module |
| Time-travel slider UI | Missing |
| Event details sidebar (type, actor, what changed) | Missing |
| Embeddable LiveComponent | Missing — VisualizeLive is a full page, not a component |
| Auto-update on file change | Missing |

### Core Challenge: Event Reconstruction

**Can events be replayed to reconstruct intermediate model state?**

The event stream records actions like `SliceAdded`, `ElementAdded`, `ElementMoved`, etc. Each entry has a `data` map with the transformation payload. However:
- **No reconstruction logic exists** — no module that applies events 1..N to build an intermediate `%EventModel{}`
- **Data adequacy is uncertain** — need to verify each event type carries enough data (does `ElementAdded` include full element properties or just an ID?)
- Would need a new `EventModeler.EventModel.Replayer` module

### Implementation Phases

**Phase 1: Replayer module** (foundation)
- `replay_events(event_stream, up_to_seq)` → intermediate `%EventModel{}`
- Handlers for each event type that modify the model
- Tests with sample event sequences

**Phase 2: Slider UI in VisualizeLive**
- Add range slider bound to event seq (1..max)
- On slider change: call Replayer → recompute layout → re-render SVG
- Show current event metadata (seq, type, actor, timestamp)

**Phase 3: Embeddable component**
- Extract VisualizeLive rendering into `VisualizerComponent` (LiveComponent)
- Accept `markdown` as prop, no page wrapper
- Mountable via `<.live_component module={VisualizerComponent} ...  />`

**Phase 4: Auto-update** (post-MVP)
- File watcher or polling to reload markdown on changes

---

## Deep Dive: Canvas UX Refinements

### Current Keyboard/Mouse Capabilities

| Interaction | Status |
|-------------|--------|
| Pan (drag background / scroll wheel) | Working |
| Zoom (Ctrl+scroll, trackpad pinch, cursor-centered) | Working |
| Delete (Delete/Backspace key) | Working |
| Connect (Shift+click source → Shift+click target) | Working |
| Select element (click → edit mode + zoom) | Working |
| Double-click canvas (zoom 1.5x) | Working |
| Escape (close topmost panel) | Working |
| Viewport save/restore (edit mode entry/exit) | Working |

### Missing Features

#### Keyboard Shortcuts — Quick Wins

| Shortcut | Action | Effort |
|----------|--------|--------|
| Ctrl/Cmd+S | Save board | ~10 LOC |
| +/- keys | Zoom in/out | ~20 LOC |
| Ctrl/Cmd+0 | Fit-to-window (zoom to show all) | ~30 LOC |
| ? key | Open shortcuts reference modal | ~80 LOC |

**Total for all basic shortcuts: ~150 LOC.** Add `phx-window-keydown` handlers in BoardLive, wire to existing functions.

#### Undo/Redo — Medium Effort

**The event stream is append-only by design** — it records facts, not reversions. Undo needs a **separate session-scoped state stack**, not the event stream.

**Approach:**
- Add `undo_stack` and `redo_stack` to Board GenServer state
- On each mutation: push current state snapshot before applying change
- On undo: pop from undo_stack, restore state, push to redo_stack
- Undo is **ephemeral** (session-only, not persisted, lost on GenServer restart)
- Event stream continues to record only forward-actions

**Effort:** ~300-500 LOC. Main concern: state snapshot cloning for large boards.

#### Slice Reordering

**Already possible in data model** — `EventModel.slices` is an ordered list, `Layout.compute` iterates in list order. Just need:
1. Board GenServer `reorder_slices/2` handler (~30 LOC)
2. BoardLive event handler + up/down arrows in bottom sheet (~70 LOC)

**No schema change needed** — slice order is implicit in list position.

#### Fit-to-Window

Calculate bounding box of all positioned elements from `Layout.compute` result, set canvas transform to fit. ~30 LOC in JS hook + a button in header.

#### Minimap — Higher Effort (Post-MVP)

Render a small SVG replica of the full canvas with a draggable viewport rectangle. ~400-600 LOC JavaScript + CSS. High value for large models (50+ elements) but not critical for MVP.

### Recommended MVP Additions

1. **Ctrl/Cmd+S** to save (trivial, expected behavior)
2. **Fit-to-window** button and Ctrl/Cmd+0 shortcut
3. **+/-** zoom shortcuts
4. **Slice reordering** via keyboard (arrow keys in bottom sheet)
5. **Undo/redo** (if feasible within timeline)

### Deferred to Post-MVP

- Canvas minimap
- Drag-to-reorder slices (vs. keyboard arrows)
- Keyboard shortcut reference modal
- Pan mode toggle (Space key)

---

## Not Yet Deep-Dived

The following gap areas were identified but not explored in detail:

- **Import flow heuristics** — auto-suggest elements from Key Ideas, interactive review/adjust
- **Export enhancements** — JSON format, data flow table generation
