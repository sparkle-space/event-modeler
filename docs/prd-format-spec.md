# PRD Format Specification

**Version:** 1.0
**Date:** 2026-02-21

This document defines the structured PRD (Product Requirements Document) format used by EventModeler. PRD files are self-contained markdown documents with YAML frontmatter, emlang slice definitions, and an append-only event stream.

## File Structure

A PRD file is a markdown document with this structure:

```
---
(YAML frontmatter)
---

# Title

## Overview
## Key Ideas
## Slices
## Scenarios
## Data Flows
## Dependencies
## Sources

<!-- event-stream -->
## Event Stream
```

All sections are optional except Overview when importing. The export pipeline always produces the full structure.

## YAML Frontmatter

The document begins with a YAML frontmatter block delimited by `---`:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `title` | string | yes | Human-readable feature/document name |
| `status` | enum | yes | One of: `draft`, `modeling`, `refined`, `approved` |
| `domain` | string | no | Bounded context name |
| `version` | integer | no | Document version number (starts at 1) |
| `created` | ISO 8601 date | no | Creation date |
| `updated` | ISO 8601 date | no | Last modification date |
| `dependencies` | list of strings | no | Paths to other PRD files this depends on |
| `tags` | list of strings | no | Categorization tags |

### Example

```yaml
---
title: "User Registration"
status: draft
domain: "Identity"
version: 1
created: "2026-02-21"
updated: "2026-02-21"
dependencies:
  - "email-verification-prd.md"
tags:
  - event-modeling
  - identity
---
```

### Status Lifecycle

- **draft** -- Initial state when a PRD is created or imported
- **modeling** -- Active modeling session in progress
- **refined** -- Modeling complete, slices and scenarios generated
- **approved** -- Stakeholder sign-off received

## Sections

### Overview

One to three paragraphs describing the feature, its purpose, and who benefits. Preserved verbatim on round-trip.

### Key Ideas

Bullet list of core concepts. Each idea is a candidate for one or more slices. Format:

```markdown
- **Idea name** -- description of the core concept and why it matters
```

### Slices

Slices are vertical units of work derived from the event model. Each slice has a `### Slice:` heading followed by an optional wireframe description and a fenced `emlang` code block.

```markdown
### Slice: Register User

**Wireframe:** Registration form with email, password, display name

\`\`\`emlang
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
\`\`\`
```

### Scenarios

Additional Given/When/Then scenarios not covered by individual slices, particularly cross-slice or edge-case scenarios.

```markdown
### Scenario: End-to-End Registration Flow

- **Given** no user exists with email "alice@example.com"
- **When** user completes registration and then logs in
- **Then** Dashboard shows welcome message with user's display name
```

### Data Flows

A table describing what data enters, transforms within, and exits the system.

```markdown
| Source | Enters as | Transforms via | Exits as |
|--------|-----------|---------------|----------|
| Registration form | `RegisterUser` command | `UserRegistered` event | `RegistrationConfirmation` view |
```

### Dependencies

Links to other PRD files this feature depends on.

### Sources

Links to requirements documents, research, stakeholder interviews, and other source material.

## Emlang Notation

Slices use [emlang](https://github.com/emlang-project/spec) v1.0.0, a YAML-based DSL for describing systems with Event Modeling patterns.

### Element Types

| Prefix | Type | Color | Description |
|--------|------|-------|-------------|
| `t:` | Trigger/Wireframe | -- | UI trigger or wireframe screen |
| `c:` | Command | Blue | Imperative action (e.g., `RegisterUser`) |
| `e:` | Event | Orange | Past-tense fact (e.g., `UserRegistered`) |
| `v:` | View | Green | Read model / query result |
| `x:` | Exception | Red | Error condition |

### Swimlane Prefixes

Element labels can include a swimlane prefix separated by `/`:

```yaml
- e: User/UserRegistered    # Swimlane: "User", Label: "UserRegistered"
- c: RegisterUser            # No swimlane (default)
```

### Properties

Elements can declare typed properties:

```yaml
- c: RegisterUser
  props:
    email: string
    password: string
    displayName: string
```

### Tests (GWT Scenarios)

Slices can embed Given/When/Then tests:

```yaml
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

Each test has a PascalCase name and optional `given`, required `when`, and required `then` clauses. Each clause is a list of elements with optional `props`.

### Extraction

Extract all emlang blocks from a PRD for linting or processing:

```bash
awk '/^```emlang/{p=1; print "---"; next} /^```/{p=0; next} p' feature-prd.md | emlang lint -
```

## Event Stream

The event stream is an append-only log embedded at the bottom of the PRD file. It records every modeling action, making the PRD self-describing.

### Placement

The event stream appears at the bottom of the file, after all content sections. An HTML comment sentinel `<!-- event-stream -->` marks the start, followed by a `## Event Stream` heading.

### Format

One fenced `eventstream` block per event. Each block contains YAML:

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

### Rules

- **Append-only:** New events are appended as new fenced blocks. Existing blocks are never modified or removed.
- **Monotonic sequence:** `seq` values must be monotonically increasing with no gaps.
- **UTC timestamps:** All `ts` values use ISO 8601 UTC format.

### Event Type Catalog

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

### Example

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

### Extraction

Extract all event stream entries from a PRD:

```bash
awk '/^```eventstream/{p=1; print "---"; next} /^```/{p=0; next} p' feature-prd.md
```

## Validation Rules

1. **Frontmatter required:** A valid PRD must have YAML frontmatter with at least `title` and `status`.
2. **Status values:** Must be one of `draft`, `modeling`, `refined`, `approved`.
3. **Emlang blocks:** Must be valid YAML. Each block must have a `slices:` top-level key.
4. **Step ordering:** Within a slice, steps should follow the logical flow: trigger -> command -> event -> view.
5. **Event stream integrity:** Sequence numbers must be monotonically increasing with no gaps.
6. **Sentinel required for stream:** If event stream entries exist, the `<!-- event-stream -->` sentinel must precede them.

## Input vs Output Format

| Section | Input PRD | Output PRD |
|---------|-----------|------------|
| Frontmatter | Optional | Always present |
| Overview | Required | Preserved from input |
| Key Ideas | Required | Preserved, linked to slices |
| Slices (emlang) | Absent or present (re-import) | Generated from model |
| Scenarios | Absent | Generated from model |
| Data Flows | Absent | Generated from model |
| Dependencies | Optional | Enriched from model |
| Sources | Optional | Preserved from input |
| Event Stream | Absent | Appended by modeling sessions |
