# /event-model-plan — Event Modeling & Event Model Format

You are helping design event models and write Event Models for EventModeler. Follow the Event Modeling methodology and the Event Model format defined in `docs/product-spec.md`.

## Event Modeling Workshop (7 Steps)

1. **Brainstorm** — Capture all domain events (past-tense: UserRegistered, OrderPlaced)
2. **Plot** — Arrange events chronologically on a timeline (left to right)
3. **Storyboard** — Add wireframes above the timeline showing what users see
4. **Inputs** — Add Commands linking user actions to Events (RegisterUser → UserRegistered)
5. **Outputs** — Add Views showing what data users see after events (UserProfile, Dashboard)
6. **Organize** — Define swimlanes for actors and bounded contexts
7. **Elaborate** — Define Given/When/Then scenarios for complex business logic

## Slice Definition

A slice is a vertical unit of work: Trigger → Command → Event → View.

Use emlang notation:

```emlang
slices:
  SliceName:
    steps:
      - t: Actor/TriggerScreen       # Wireframe/trigger
      - c: CommandName                # Command
        props:
          field: type
      - e: Context/EventName          # Event
        props:
          field: type
      - v: ViewName                   # View/read model
    tests:
      HappyPath:
        when:
          - c: CommandName
            props:
              field: value
        then:
          - e: Context/EventName
      ErrorCase:
        given:
          - e: Context/SomeEvent
        when:
          - c: CommandName
        then:
          - x: ErrorName
```

## Event Model Format

### Structure

```markdown
---
title: "Feature Name"
status: draft | modeling | refined | approved
domain: "Bounded Context"
version: 1
---

# Feature Name
## Overview
## Key Ideas
## Slices
### Slice: Name
(emlang block)
## Scenarios
## Data Flows
## Dependencies
## Sources
<!-- event-stream -->
## Event Stream
(eventstream blocks)
```

### Event Stream

Append-only log at the bottom of Event Model files. Each event is a fenced `eventstream` block:

```eventstream
seq: 1
ts: "2026-02-21T10:00:00Z"
type: EventModelCreated
actor: user@example.com
data:
  title: "Feature Name"
  status: draft
```

### Key Rules

- Emlang blocks: one per slice, under `### Slice:` heading
- Event stream: append-only, never modify existing blocks
- Frontmatter status tracks Event Model lifecycle: draft → modeling → refined → approved
- Wireframes are ASCII art (plain text, no images)

## Guidance

When helping design event models:

1. Start with domain events — what happens in the business?
2. Group events into slices — each slice is a deliverable unit
3. Define commands — what action triggers each event?
4. Add views — what does the user see after each event?
5. Write scenarios — Given (preconditions) / When (command) / Then (outcomes)
6. Check completeness — every view field must trace back to an event field, which traces to a command field
