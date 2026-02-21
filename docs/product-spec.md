# EventModeler: Product Specification

**Status:** Concept
**Date:** 2026-02-17
**Depends on:** [Event Modeling](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/event-modeling.md), [Event Sourcing & CQRS](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/event-sourcing-cqrs.md), [Collaboration Architecture](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/collaboration-architecture.md)
**Companion:** [Technical Design](technical-design.md)

## Vision & Positioning

EventModeler is a purpose-built collaborative canvas for designing information systems using [Event Modeling](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/event-modeling.md). It targets mixed audiences — developers, domain experts, business analysts, and workshop facilitators — with a workflow centered on Product Requirements Documents (PRDs).

The core loop: **PRD in → Event Model → Refined PRD out**.

Users import a PRD, collaboratively build an event model from it on a visual canvas, then export a refined PRD enriched with slices, scenarios, and data flows derived from the model. Teams that start without a PRD still get one: the act of modeling generates a structured requirements document.

EventModeler is built as a **standalone Phoenix/LiveView application** — a local server you run alongside your codebase. Once the core is mature and the API surface is stable, the reusable parts will be extracted into an **Elixir hex package** (`event_modeler`) that mounts into any Phoenix app. sparkle.space will dogfood the tool to design its own system.

## Development Strategy

1. **Local server** — Build a standalone Phoenix/LiveView application with full event modeling capability
2. **Hex module extraction** — Once the core is mature, extract the reusable library (`event_modeler`) as a publishable hex package
3. **Optional SaaS** — A hosted deployment (`eventmodeling.sparkle.space`) is a separate project that depends on the published hex module

## Key Differentiators

| Differentiator | Why it matters |
|----------------|----------------|
| **PRD integration** | No existing tool connects requirements documents to visual event models bidirectionally. EventModeler treats the PRD as a first-class artifact — import it, model from it, export a refined version. |
| **Embeddable** | Designed for eventual extraction as an embeddable hex module. The library will live alongside the code it describes, making models living documentation. No competitor offers this. |
| **Non-technical accessibility** | Guided 7-step workshop facilitation mode designed for domain experts, not just developers. Enforces Event Modeling syntax (e.g., Commands cannot connect directly to Views) to prevent invalid models without requiring methodology expertise. |
| **Facilitation-to-delivery pipeline** | Full journey from PRD → event model → slices → Given/When/Then scenarios → exportable tickets. Most tools stop at the whiteboard. |
| **Test-case derivation** | Auto-generate Given/When/Then acceptance criteria from slices. The model is the test spec. |
| **Affordable** | Open-source when the hex module is extracted. Purpose-built event modeling at zero cost, compared to prooph board (EUR 250/month) and generic whiteboards (Miro). |

## PRD Format Definition

EventModeler defines a structured PRD format in markdown with YAML frontmatter. The format is machine-readable enough for import/export and human-readable enough to review in a markdown editor or git diff.

### Slice Notation: Emlang

Slice definitions use [emlang](https://github.com/emlang-project/spec) (Event Modeling Language) v1.0.0, a YAML-based DSL for describing systems with Event Modeling patterns. Emlang provides:

- **Named slices** as first-class constructs, mapping directly to EventModeler's slice concept
- **Five element types:** trigger (`t:`), command (`c:`), event (`e:`), view (`v:`), exception (`x:`)
- **Swimlane prefixes** (e.g., `User/UserRegistered`) for bounded context grouping
- **Properties** (`props:`) on each element for field definitions
- **GWT tests** (`tests:`) attached to slices with given/when/then constraints
- **Linting** via the `emlang` CLI (10 rules enforcing Event Modeling best practices)

Slices are embedded in PRD markdown as fenced `` ```emlang `` code blocks -- one block per slice, directly beneath its `### Slice:` heading. This makes the blocks extractable for linting and diagram generation:

```bash
# Extract all emlang blocks from a PRD and lint them
awk '/^```emlang/{p=1; print "---"; next} /^```/{p=0; next} p' feature-prd.md | emlang lint -
```

For the full rationale and comparison with alternative DSLs, see the [emlang PRD format proposal](https://github.com/sparkle-space/masterplan/blob/main/00-scratchpad/emlang-prd-format/prd-format-proposal.md).

### Format

````markdown
---
title: "Feature Name"
status: draft | modeling | refined | approved
domain: "Bounded Context"
version: 1
dependencies:
  - "other-feature-prd.md"
tags:
  - event-modeling
  - domain-name
---

# Feature Name

## Overview

[1-3 paragraph description of the feature, its purpose, and who benefits.]

## Key Ideas

- **Idea name** -- description of the core concept and why it matters
- **Another idea** -- each idea is a candidate for one or more slices

## Slices

Slices are derived from the event model. Each slice is a vertical unit of work
defined in emlang notation.

### Slice: Register User

**Wireframe:** Registration form with email, password, display name

```emlang
slices:
  RegisterUser:
    steps:
      - t: Visitor/RegistrationForm
      - c: RegisterUser
        props:
          email: string
          password: string
      - e: User/UserRegistered
        props:
          userId: string
          email: string
      - v: RegistrationConfirmation
    tests:
      HappyPath:
        when:
          - c: RegisterUser
            props:
              email: alice@example.com
        then:
          - e: User/UserRegistered
      DuplicateEmail:
        given:
          - e: User/UserRegistered
            props:
              email: alice@example.com
        when:
          - c: RegisterUser
            props:
              email: alice@example.com
        then:
          - x: EmailAlreadyInUse
```

### Slice: [Next Slice]

...

## Scenarios

Additional Given/When/Then scenarios not covered by individual slices,
particularly cross-slice or edge-case scenarios.

### Scenario: End-to-End Registration Flow

- **Given** no user exists with email "alice@example.com"
- **When** user completes registration and then logs in
- **Then** Dashboard shows welcome message with user's display name

## Data Flows

What data enters, transforms within, and exits the system.

| Source | Enters as | Transforms via | Exits as |
|--------|-----------|---------------|----------|
| Registration form | `RegisterUser` command | `UserRegistered` event | `RegistrationConfirmation` view |

## Dependencies

- [Other PRD](other-feature-prd.md) -- depends on user authentication

## Sources

- [Requirements document or research](link)
- Stakeholder interviews (date)
````

### Relationship to Existing PRD Format

The existing format in `00-scratchpad/prd-ideas/` (Overview + Key Ideas + Sources) is the **input format** — the starting point before modeling. The extended format above is the **output format** — what EventModeler produces after a modeling session. The import pipeline accepts either format; the export pipeline always produces the extended format.

| Section | Input PRD | Output PRD |
|---------|-----------|------------|
| Frontmatter | Optional | Always present |
| Overview | Required | Preserved from input |
| Key Ideas | Required | Preserved, linked to slices |
| Slices (emlang blocks) | Absent or present (re-import) | Generated from model as `` ```emlang `` code blocks |
| Scenarios | Absent | Generated from model |
| Data Flows | Absent | Generated from model |
| Dependencies | Optional | Enriched from model |
| Sources | Optional | Preserved from input |
| Event Stream | Absent | Appended by modeling sessions |

### Event Stream

PRD files carry an append-only event stream that records every modeling action. This makes the PRD self-describing: it contains not just the current model, but the history of how the model was built.

**Placement:** Bottom of the PRD file, after all content sections. An HTML comment sentinel `<!-- event-stream -->` marks the start, followed by a `## Event Stream` heading.

**Format:** One fenced `` ```eventstream `` block per event (same pattern as `` ```emlang ``). Each block contains YAML with the following schema:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `seq` | integer | yes | Monotonically increasing sequence number |
| `ts` | ISO 8601 UTC | yes | Timestamp of the event |
| `type` | PascalCase string | yes | Event type name |
| `actor` | string | yes | Who or what caused the event |
| `data` | map | yes | Event-specific payload |
| `session` | string | no | Groups events from one modeling session |
| `ref` | string | no | Reference to related entity (e.g., slice ID) |
| `note` | string | no | Human-readable annotation |

**Append-only rule:** New events are appended as new fenced blocks. Existing blocks are never modified or removed.

**Event type catalog:**

| Category | Event Types |
|----------|-------------|
| PRD lifecycle | `PrdCreated`, `PrdStatusChanged`, `PrdMetadataUpdated`, `PrdExported` |
| Session | `SessionStarted`, `SessionEnded` |
| Slices | `SliceAdded`, `SliceRenamed`, `SliceRemoved`, `SliceReordered` |
| Elements | `ElementAdded`, `ElementModified`, `ElementRemoved`, `ElementsConnected` |
| Scenarios | `ScenarioAdded`, `ScenarioModified`, `ScenarioRemoved` |
| Swimlanes | `SwimlaneAdded`, `SwimlaneRemoved` |
| Data flows | `DataFlowAdded` |
| Annotations | `NoteAdded` |

**Extraction:** Same pattern as emlang blocks:

```bash
awk '/^```eventstream/{p=1; print "---"; next} /^```/{p=0; next} p' feature-prd.md
```

**Example:**

````markdown
<!-- event-stream -->
## Event Stream

```eventstream
seq: 1
ts: "2026-02-21T10:00:00Z"
type: PrdCreated
actor: facilitator@example.com
data:
  title: "User Registration"
  status: draft
```

```eventstream
seq: 2
ts: "2026-02-21T10:05:00Z"
type: SliceAdded
actor: facilitator@example.com
session: "workshop-2026-02-21"
data:
  sliceName: RegisterUser
  elements: [RegistrationForm, RegisterUser, UserRegistered, RegistrationConfirmation]
```
````

## EventModeler's Own Event Model

EventModeler models itself. The slices below describe the core workflows of the event_modeler application, defined in emlang notation. This serves as both documentation and a dogfood test of the PRD format.

### Slice: CreateBoard

User creates a new modeling board.

```emlang
slices:
  CreateBoard:
    steps:
      - t: User/DashboardPage
      - c: CreateBoard
        props:
          title: string
          ownerId: string
      - e: Board/BoardCreated
        props:
          boardId: string
          title: string
          ownerId: string
      - v: BoardCanvas
    tests:
      HappyPath:
        when:
          - c: CreateBoard
            props:
              title: "My Event Model"
        then:
          - e: Board/BoardCreated
```

### Slice: ImportPrd

User imports a markdown PRD into a board.

```emlang
slices:
  ImportPrd:
    steps:
      - t: User/ImportDialog
      - c: ImportPrd
        props:
          boardId: string
          markdownContent: string
      - e: Prd/PrdImported
        props:
          prdId: string
          boardId: string
          title: string
          overview: string
          keyIdeas: list
      - v: BoardCanvasWithElements
    tests:
      WithEmlangBlocks:
        when:
          - c: ImportPrd
            props:
              markdownContent: "---\ntitle: Feature\n---\n## Slices\n```emlang\nslices:\n  Register:\n    steps:\n      - c: Register\n```"
        then:
          - e: Prd/PrdImported
      EmptyPrd:
        when:
          - c: ImportPrd
            props:
              markdownContent: ""
        then:
          - x: InvalidPrdContent
```

### Slice: ModelOnCanvas

User places elements, connects them, and defines swimlanes on the modeling canvas.

```emlang
slices:
  PlaceElement:
    steps:
      - t: User/ElementPalette
      - c: PlaceElement
        props:
          elementId: string
          boardId: string
          type: string
          label: string
          x: number
          y: number
      - e: Element/ElementPlaced
        props:
          elementId: string
          boardId: string
          type: string
          label: string
      - v: BoardCanvas
  ConnectElements:
    steps:
      - t: User/BoardCanvas
      - c: ConnectElements
        props:
          elementId: string
          targetElementId: string
          connectionType: string
      - e: Element/ElementsConnected
        props:
          elementId: string
          targetElementId: string
      - v: BoardCanvas
    tests:
      ValidConnection:
        when:
          - c: ConnectElements
            props:
              connectionType: "command_to_event"
        then:
          - e: Element/ElementsConnected
      InvalidConnection:
        when:
          - c: ConnectElements
            props:
              connectionType: "command_to_view"
        then:
          - x: InvalidConnectionType
```

### Slice: DefineSlice

User groups elements into a named slice.

```emlang
slices:
  DefineSlice:
    steps:
      - t: User/BoardCanvas
      - c: DefineSlice
        props:
          sliceId: string
          boardId: string
          name: string
          elementIds: list
      - e: Slice/SliceDefined
        props:
          sliceId: string
          boardId: string
          name: string
          elementIds: list
      - v: SlicePanel
    tests:
      HappyPath:
        when:
          - c: DefineSlice
            props:
              name: "RegisterUser"
        then:
          - e: Slice/SliceDefined
```

### Slice: GenerateScenarios

Auto-generate Given/When/Then scenarios from a slice's element graph.

```emlang
slices:
  GenerateScenarios:
    steps:
      - t: User/SlicePanel
      - c: GenerateScenarios
        props:
          sliceId: string
      - e: Slice/ScenarioAdded
        props:
          scenarioId: string
          sliceId: string
          given: list
          whenClause: string
          thenClause: list
      - v: ScenarioList
    tests:
      FromSliceGraph:
        given:
          - e: Slice/SliceDefined
            props:
              name: "RegisterUser"
        when:
          - c: GenerateScenarios
        then:
          - e: Slice/ScenarioAdded
```

### Slice: ExportPrd

Export a refined PRD with slices, scenarios, data flows, and event stream.

```emlang
slices:
  ExportPrd:
    steps:
      - t: User/ExportDialog
      - c: ExportPrd
        props:
          prdId: string
          format: string
      - e: Prd/PrdExported
        props:
          prdId: string
          format: string
          exportedAt: string
      - v: ExportDownload
    tests:
      MarkdownExport:
        given:
          - e: Prd/PrdImported
        when:
          - c: ExportPrd
            props:
              format: "markdown"
        then:
          - e: Prd/PrdExported
```

### Slice: VisualizeModel

Read-only rendering of a PRD's event model — no editing, just visualization.

```emlang
slices:
  VisualizeModel:
    steps:
      - t: System/PrdFile
      - c: LoadModel
        props:
          prdId: string
          mode: string
      - e: Board/ModelLoaded
        props:
          boardId: string
          prdId: string
          elementCount: number
      - v: ReadOnlyCanvas
    tests:
      LoadAndRender:
        when:
          - c: LoadModel
            props:
              mode: "readonly"
        then:
          - e: Board/ModelLoaded
```

## MVP Feature Set

### PRD Import & Export

- **Import:** Parse markdown PRD (input format or extended format), extract key ideas, suggest initial element placement on the canvas
- **Export markdown:** Traverse the board, collect slices with their elements, generate structured PRD in the extended format
- **Export JSON:** Machine-readable export for integration with external tools
- **Round-trip fidelity:** Imported content (overview, key ideas, sources) is preserved in the export; model-derived sections (slices, scenarios, data flows) are added alongside

### Collaborative Canvas

- SVG-based modeling surface with pan, zoom, and drag-drop
- Real-time multi-user editing with cursor and selection presence
- Server-authoritative state (see [Collaboration Architecture](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/collaboration-architecture.md))
- Optimistic UI updates for drag, resize, and text editing (see [Optimistic UI Updates](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/optimistic-ui-updates.md))

### Event Modeling Building Blocks

Standard [Event Modeling](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/event-modeling.md) components:

| Element | Color | Shape | Content |
|---------|-------|-------|---------|
| Event | Orange | Rectangle | Past-tense name (e.g., `UserRegistered`) + data fields |
| Command | Blue | Rectangle | Imperative name (e.g., `RegisterUser`) + data fields |
| View | Green | Rectangle | Descriptive name (e.g., `UserProfile`) + data fields |
| Wireframe | — | Monospace text block | ASCII art UI sketch + extracted data fields. Plain text in `fields` jsonb — no images, no uploads |
| Automation | Gear icon | Circle | Trigger description (e.g., "When OrderPlaced, send confirmation") |

### Canvas Organization

- **Swimlanes:** Horizontal lanes for bounded contexts, actors, or subsystems
- **Timeline:** Horizontal chronological layout (left to right)
- **Connections:** Arrows linking Commands → Events → Views, with connection validation (e.g., Commands cannot connect directly to Views)

### Slice Management

- **Define slices:** Select a Command → Event → View chain and name it as a slice
- **Highlight:** Visual overlay showing which elements belong to a selected slice
- **Extract:** Export individual slices as work items with their scenarios
- **Ordering:** Slices can be prioritized and reordered for delivery planning

### Scenario Generation

- Auto-generate Given/When/Then from slices: Events become Givens, Commands become Whens, resulting Events/Views become Thens
- Manual scenario editing for edge cases and cross-slice scenarios
- Scenarios are attached to slices and exported in the PRD

### Workshop Mode

Guided 7-step facilitation flow following the [Event Modeling workshop process](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/event-modeling.md#the-7-step-workshop-process):

1. **Brainstorm** — Free-form event capture (orange stickies)
2. **Plot** — Arrange events on the timeline
3. **Storyboard** — Add wireframes above the timeline
4. **Inputs** — Add Commands linking UI actions to Events
5. **Outputs** — Add Views linking Events to the UI; completeness check
6. **Organize** — Define swimlanes for actors and bounded contexts
7. **Elaborate** — Define Given/When/Then scenarios for complex logic

Each step constrains available tools (server-enforced, not just UI) and validates completeness before advancing. The facilitator can skip steps or go back — elements from later steps are de-emphasized but never deleted. Workshop step state is ephemeral (GenServer only, not event-sourced); if the session restarts, the board returns to free mode where all tools are available. See [Technical Design — Workshop Step Enforcement](technical-design.md#workshop-step-enforcement) for the full constraint table.

### User Roles

| Role | Permissions |
|------|-------------|
| Facilitator | Full canvas control, manage workshop steps, invite participants, export |
| Participant | Add/edit/move elements, define slices, add scenarios |
| Viewer | Read-only canvas access, view slices and scenarios |

### Read-Only Visualization Mode

Render a PRD's event model as a non-editable canvas. The system loads a PRD (or board state), renders the canvas, and disables all editing controls.

- **Use cases:** Self-documentation in running systems, embedding model views in wikis/dashboards, sharing models with stakeholders who don't need editing access
- **Event stream replay:** "Time-travel" slider replays the event stream to show how the model evolved over time
- **Embeddable:** The read-only view is a standalone LiveView that can be mounted independently, making it suitable for embedding in other Phoenix apps or rendering as a static page

### Future: Hex Module Extraction

Once the standalone app is mature, the core will be extracted into a hex package (`event_modeler`) that adds event modeling capability to any Phoenix app:

- Mountable routes via router macro
- Own Ecto migrations (boards, elements, slices, scenarios)
- Own LiveView modules, JS hooks, and CSS assets
- Configurable authentication adapter — host app provides user context
- Uses host app's Ecto Repo and PubSub

This is the target architecture, not the initial one. The standalone app is built first; extraction happens when the API surface is stable.

## Deferred Features (Post-MVP)

- **Code scaffolding** — Generate Elixir module stubs (aggregates, commands, events, projectors) from slices
- **Ticket integration** — Export slices to Jira or Linear as tickets
- **Version history** — Board versioning with visual model diffing
- **Template library** — Pre-built event model patterns (user registration, e-commerce checkout, etc.)
- **LLM-assisted PRD generation** — LLMs generate PRDs externally; event_modeler imports and validates them. The verification loop: event_modeler checks completeness, LLM iterates based on feedback. Integration surface is PRD import/export — LLMs run external, not embedded. Keeping LLMs external preserves scope and avoids coupling; the PRD format IS the interface
- **Information completeness checker (full)** — Per-board aggregate score and cross-board tracing (per-element and per-slice checking is MVP)
- **Time collapsing** — Collapse regions of the timeline to manage large models

## User Stories

### Workshop Facilitator

As a facilitator, I want to guide my team through a structured Event Modeling workshop so that we produce a complete, validated event model from our requirements.

- I create a new board and import our PRD
- I step the team through the 7-step workshop process
- At each step, the tool shows what we should focus on and validates our progress
- After the workshop, I export the refined PRD with slices and scenarios

### Domain Expert (Non-Technical)

As a domain expert, I want to participate in an Event Modeling session and contribute my business knowledge without needing to understand the technical methodology.

- I join a board as a participant and see a clear, visual timeline
- The facilitator guides each step; I add events that describe what happens in my domain
- I validate that the wireframes match what I expect users to see
- I review the Given/When/Then scenarios to confirm they match business rules

### Developer

As a developer, I want to use the event model as a living specification so that I can implement features directly from slices.

- I open the event model embedded in our Phoenix app (via hex module)
- I select a slice and see its Command, Event, View, and scenarios
- I implement the slice knowing exactly what data enters, transforms, and exits
- The model stays synchronized with the codebase because it lives alongside it

### Product Owner

As a product owner, I want to import a PRD, model it with the team, and get back a refined PRD with concrete slices I can prioritize and schedule.

- I import our markdown PRD into a new board
- After the team models it, I review the slices derived from the model
- I prioritize and reorder slices for delivery planning
- I export the refined PRD with slices and scenarios for stakeholders

### System Architect

As an architect, I want to embed a read-only view of our event model in our internal docs so that the team always sees the current system design.

- I point the read-only visualization at our PRD file
- The model renders as an interactive (but non-editable) canvas
- When the model is updated, the visualization reflects the changes
- I can replay the event stream to show how the design evolved

## Competitive Landscape

### Purpose-Built Event Modeling Tools

| Tool | Strengths | Gaps |
|------|-----------|------|
| **ONote / Evident Design** | Browser-based, real-time collaboration, syntax enforcement (prevents invalid connections), "time collapsing" for large models | No PRD integration, no embeddable library, no code generation, pricing unclear |
| **Modellution** | Jira/ClickUp integration, code generation | Beta status, limited deployment examples |
| **Qlerify** | AI assistance for modeling | Limited feature information, no embeddable option |

### General-Purpose Platforms

| Tool | Strengths | Gaps |
|------|-----------|------|
| **Miro / Mural** | Widely adopted, familiar UX, community Event Modeling templates, Nebulit plugin adds code generation and completeness checking | Generic tool — no syntax enforcement, no slice management, no scenario generation, no PRD integration |
| **PlantUML / Mermaid** | Version-controlled alongside code, "docs-as-code" approach | Cannot capture full Event Model complexity (swimlanes, connections, wireframes), no collaboration |

### Open-Source

| Tool | Strengths | Gaps |
|------|-----------|------|
| **Event Modeling DSL** (VS Code extension) | Text-based modeling in IDE | Limited visual capability, no collaboration |
| **O-FISH (WildAid)** | Production reference implementation of Event Modeling | Not a modeling tool — it's a system built using Event Modeling |

### Where EventModeler Fits

EventModeler occupies a unique position:

- **vs. ONote/Evident Design:** Adds PRD integration, scenario generation, read-only visualization mode, and a path to an embeddable hex module.
- **vs. Miro:** Purpose-built with syntax enforcement, slice management, and structured export — not a generic canvas with templates.
- **vs. PlantUML/Mermaid:** Visual, collaborative, and interactive while still being embeddable in a codebase.
- **vs. all competitors:** Only tool designed for eventual extraction as an embeddable library for dogfooding inside your own application. Embeddable read-only visualization of event models — no competitor offers this.
- **Forward-looking:** LLM-ready PRD format enables external AI tools to generate and iterate on PRDs using event_modeler's import/export pipeline as the integration surface.

## References

- [Event Modeling](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/event-modeling.md) — Core methodology (not duplicated here)
- [Technical Design](technical-design.md) — Implementation architecture
- [Event Sourcing & CQRS](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/event-sourcing-cqrs.md) — Underlying architecture
- [Collaboration Architecture](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/collaboration-architecture.md) — Real-time collaboration patterns
- [Optimistic UI Updates](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/optimistic-ui-updates.md) — UI update tier system
- [Emlang spec v1.0.0](https://github.com/emlang-project/spec) — Slice notation DSL
- [Emlang CLI](https://github.com/emlang-project/emlang) — Linting and diagram generation
- [Emlang PRD format proposal](https://github.com/sparkle-space/masterplan/blob/main/00-scratchpad/emlang-prd-format/prd-format-proposal.md) — DSL comparison and format proposal
- `00-scratchpad/prd-ideas/` — Existing PRD format (input for format definition)
- `00-scratchpad/event-modelling/` — Competitive research
