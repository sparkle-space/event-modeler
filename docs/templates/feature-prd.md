---
title: "Board Management"
status: draft
domain: "Board"
version: 1
created: "2026-02-21"
updated: "2026-02-21"
dependencies: []
tags:
  - event-modeling
  - board
---

# Board Management

## Overview

Board Management provides the core workflow for creating and managing event modeling boards in EventModeler. Users create boards from the dashboard, import PRDs into boards for visualization, and manage board lifecycle. This is the foundational feature that all other modeling capabilities build upon.

## Key Ideas

- **Board creation** -- Users create named boards as containers for event models. Each board is backed by a PRD file on disk.
- **PRD import** -- Existing markdown PRDs can be imported into a board, parsing their structure into visual elements on the canvas.
- **Canvas visualization** -- Imported or manually created elements render on an SVG canvas with proper Event Modeling visual conventions.

## Slices

Slices are derived from the event model. Each slice is a vertical unit of work defined in emlang notation.

### Slice: CreateBoard

**Wireframe:** Dashboard page with board list and "New Board" button

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

**Wireframe:** Import dialog with file picker and paste area

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
      WithValidContent:
        when:
          - c: ImportPrd
            props:
              markdownContent: "valid PRD content"
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

### Slice: VisualizeModel

**Wireframe:** Read-only canvas rendering of an event model

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

## Scenarios

### Scenario: Create and Populate Board

- **Given** no boards exist for the current user
- **When** user clicks "New Board" and enters title "My Event Model"
- **Then** a new board appears in the dashboard list and opens with an empty canvas

### Scenario: Import PRD into Board

- **Given** a board "My Event Model" exists
- **When** user opens import dialog and pastes a valid PRD markdown
- **Then** the canvas shows elements parsed from the PRD with proper colors and connections

### Scenario: Import Invalid PRD

- **Given** a board "My Event Model" exists
- **When** user imports an empty string as PRD content
- **Then** an error message "Invalid PRD content" is displayed

## Data Flows

| Source | Enters as | Transforms via | Exits as |
|--------|-----------|---------------|----------|
| Dashboard UI | `CreateBoard` command | `BoardCreated` event | `BoardCanvas` view |
| Import dialog | `ImportPrd` command | `PrdImported` event | `BoardCanvasWithElements` view |
| PRD file | `LoadModel` command | `ModelLoaded` event | `ReadOnlyCanvas` view |

## Dependencies

None -- this is a foundational feature.

## Sources

- [EventModeler Product Specification](../product-spec.md)
- [EventModeler Technical Design](../technical-design.md)
- [PRD Format Specification](../prd-format-spec.md)

<!-- event-stream -->
## Event Stream

```eventstream
seq: 1
ts: "2026-02-21T10:00:00Z"
type: PrdCreated
actor: system
data:
  title: "Board Management"
  status: draft
```

```eventstream
seq: 2
ts: "2026-02-21T10:01:00Z"
type: SliceAdded
actor: system
session: "initial-modeling"
data:
  sliceName: CreateBoard
  elements: [DashboardPage, CreateBoard, BoardCreated, BoardCanvas]
```

```eventstream
seq: 3
ts: "2026-02-21T10:02:00Z"
type: SliceAdded
actor: system
session: "initial-modeling"
data:
  sliceName: ImportPrd
  elements: [ImportDialog, ImportPrd, PrdImported, BoardCanvasWithElements]
```

```eventstream
seq: 4
ts: "2026-02-21T10:03:00Z"
type: SliceAdded
actor: system
session: "initial-modeling"
data:
  sliceName: VisualizeModel
  elements: [PrdFile, LoadModel, ModelLoaded, ReadOnlyCanvas]
```
