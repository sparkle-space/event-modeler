# EventModeler: Product Specification

**Status:** Concept
**Date:** 2026-02-17
**Depends on:** [Event Modeling](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/event-modeling.md), [Event Sourcing & CQRS](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/event-sourcing-cqrs.md), [Collaboration Architecture](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/collaboration-architecture.md)
**Companion:** [Technical Design](technical-design.md)

## Vision & Positioning

EventModeler is a purpose-built collaborative canvas for designing information systems using [Event Modeling](https://github.com/sparkle-space/masterplan/blob/main/01-concepts/technology/event-modeling.md). It targets mixed audiences — developers, domain experts, business analysts, and workshop facilitators — with a workflow centered on Product Requirements Documents (PRDs).

The core loop: **PRD in → Event Model → Refined PRD out**.

Users import a PRD, collaboratively build an event model from it on a visual canvas, then export a refined PRD enriched with slices, scenarios, and data flows derived from the model. Teams that start without a PRD still get one: the act of modeling generates a structured requirements document.

EventModeler ships as an **Elixir hex package** (`event_modeler`) that mounts into any Phoenix app, and as a **SaaS** (`eventmodeling.sparkle.space`) wrapping the same code with auth, billing, and multi-tenancy. sparkle.space itself includes the hex module — we dogfood our own tool to design our own system.

## Key Differentiators

| Differentiator | Why it matters |
|----------------|----------------|
| **PRD integration** | No existing tool connects requirements documents to visual event models bidirectionally. EventModeler treats the PRD as a first-class artifact — import it, model from it, export a refined version. |
| **Embeddable** | No competitor offers a library you drop into your own project. All are standalone SaaS. The hex module lives alongside the code it describes, making models living documentation. |
| **Non-technical accessibility** | Guided 7-step workshop facilitation mode designed for domain experts, not just developers. Enforces Event Modeling syntax (e.g., Commands cannot connect directly to Views) to prevent invalid models without requiring methodology expertise. |
| **Facilitation-to-delivery pipeline** | Full journey from PRD → event model → slices → Given/When/Then scenarios → exportable tickets. Most tools stop at the whiteboard. |
| **Test-case derivation** | Auto-generate Given/When/Then acceptance criteria from slices. The model is the test spec. |
| **Affordable** | Hex module is free and open-source. SaaS fills the gap below purpose-built tools (prooph board at EUR 250/month) and above generic whiteboards (Miro). |

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

### Hex Module Integration

The hex module (`event_modeler`) adds event modeling capability to any Phoenix app:

- Mountable routes via router macro
- Own Ecto migrations (boards, elements, slices, scenarios)
- Own LiveView modules, JS hooks, and CSS assets
- Configurable authentication adapter — host app provides user context
- Uses host app's Ecto Repo and PubSub

## Deferred Features (Post-MVP)

- **Code scaffolding** — Generate Elixir module stubs (aggregates, commands, events, projectors) from slices
- **Ticket integration** — Export slices to Jira or Linear as tickets
- **Version history** — Board versioning with visual model diffing
- **Template library** — Pre-built event model patterns (user registration, e-commerce checkout, etc.)
- **AI-assisted modeling** — Describe a business process in natural language, get a starting event model
- **SaaS billing & multi-tenancy** — Stripe integration, org management, usage-based pricing
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

- **vs. ONote/Evident Design:** Adds PRD integration, embeddable hex module, and scenario generation. Open-source core vs. closed SaaS.
- **vs. Miro:** Purpose-built with syntax enforcement, slice management, and structured export — not a generic canvas with templates.
- **vs. PlantUML/Mermaid:** Visual, collaborative, and interactive while still being embeddable in a codebase.
- **vs. all competitors:** Only tool that offers an embeddable library for dogfooding inside your own application.

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
