---
title: "Board Management"
status: "refined"
domain: "Board"
version: 1
created: "2026-02-21"
updated: "2026-02-21T16:28:55.223974Z"
tags:
  - "event-modeling"
  - "board"
---

# Board Management

## Overview

Board Management provides the core workflow for creating and managing event modeling boards in EventModeler. Users create boards from the dashboard, import Event Models into boards for visualization, and manage board lifecycle. This is the foundational feature that all other modeling capabilities build upon.

## Key Ideas

- **Board creation** -- Users create named boards as containers for event models. Each board is backed by an Event Model file on disk.
- **Event Model import** -- Existing markdown Event Models can be imported into a board, parsing their structure into visual elements on the canvas.
- **Canvas visualization** -- Imported or manually created elements render on an SVG canvas with proper Event Modeling visual conventions.

## Slices

### Slice: CreateBoard

**Wireframe:** Dashboard page with board list and "New Board" button

```emlang
slices:
  CreateBoard:
    steps:
      - t: User/DashboardPage
      - c: CreateBoard
        props:
          ownerId: string
          title: string
      - e: Board/BoardCreated
        props:
          boardId: string
          ownerId: string
          title: string
      - v: BoardCanvas
    tests:
      HappyPath:
        when:
          - c: CreateBoard
            props:
              title: My Event Model
        then:
          - e: Board/BoardCreated
```


### Slice: ImportEventModel

**Wireframe:** Import dialog with file picker and paste area

```emlang
slices:
  ImportEventModel:
    steps:
      - t: User/ImportDialog
      - c: ImportEventModel
        props:
          boardId: string
          markdownContent: string
      - e: EventModel/EventModelImported
        props:
          boardId: string
          keyIdeas: list
          overview: string
          eventModelId: string
          title: string
      - v: BoardCanvasWithElements
    tests:
      EmptyEventModel:
        when:
          - c: ImportEventModel
            props:
              markdownContent:
        then:
          - x: InvalidEventModelContent
      WithValidContent:
        when:
          - c: ImportEventModel
            props:
              markdownContent: valid Event Model content
        then:
          - e: EventModel/EventModelImported
```


### Slice: VisualizeModel

**Wireframe:** Read-only canvas rendering of an event model

```emlang
slices:
  VisualizeModel:
    steps:
      - t: System/EventModelFile
      - c: LoadModel
        props:
          mode: string
          eventModelId: string
      - e: Board/ModelLoaded
        props:
          boardId: string
          elementCount: number
          eventModelId: string
      - v: ReadOnlyCanvas
    tests:
      LoadAndRender:
        when:
          - c: LoadModel
            props:
              mode: readonly
        then:
          - e: Board/ModelLoaded
```


## Scenarios

### Scenario: Create and Populate Board

- **Given** no boards exist for the current user
- **When** user clicks "New Board" and enters title "My Event Model"
- **Then** a new board appears in the dashboard list and opens with an empty canvas

### Scenario: Import Event Model into Board

- **Given** a board "My Event Model" exists
- **When** user opens import dialog and pastes a valid Event Model markdown
- **Then** the canvas shows elements parsed from the Event Model with proper colors and connections

### Scenario: Import Invalid Event Model

- **Given** a board "My Event Model" exists
- **When** user imports an empty string as Event Model content
- **Then** an error message "Invalid Event Model content" is displayed

## Data Flows

| Source | Enters as | Transforms via | Exits as |
|--------|-----------|---------------|----------|
| Dashboard UI | `CreateBoard` command | `BoardCreated` event | `BoardCanvas` view |
| Import dialog | `ImportEventModel` command | `EventModelImported` event | `BoardCanvasWithElements` view |
| Event Model file | `LoadModel` command | `ModelLoaded` event | `ReadOnlyCanvas` view |

## Dependencies

None -- this is a foundational feature.

## Sources

- [EventModeler Product Specification](../product-spec.md)
- [EventModeler Technical Design](../technical-design.md)
- [Event Model Format Specification](../event-model-format-spec.md)

<!-- event-stream -->
## Event Stream

```eventstream
seq: 1
ts: "2026-02-21T10:00:00Z"
type: EventModelCreated
actor: system
data:
  status: "draft"
  title: "Board Management"
```

```eventstream
seq: 2
ts: "2026-02-21T10:01:00Z"
type: SliceAdded
actor: system
session: "initial-modeling"
data:
  elements: [DashboardPage, CreateBoard, BoardCreated, BoardCanvas]
  sliceName: "CreateBoard"
```

```eventstream
seq: 3
ts: "2026-02-21T10:02:00Z"
type: SliceAdded
actor: system
session: "initial-modeling"
data:
  elements: [ImportDialog, ImportEventModel, EventModelImported, BoardCanvasWithElements]
  sliceName: "ImportEventModel"
```

```eventstream
seq: 4
ts: "2026-02-21T10:03:00Z"
type: SliceAdded
actor: system
session: "initial-modeling"
data:
  elements: [EventModelFile, LoadModel, ModelLoaded, ReadOnlyCanvas]
  sliceName: "VisualizeModel"
```

```eventstream
seq: 5
ts: "2026-02-21T16:27:53.871576Z"
type: ElementMoved
actor: user
data:
  elementId: "QvNnj7rPYag"
```

```eventstream
seq: 6
ts: "2026-02-21T16:27:55.107989Z"
type: ElementMoved
actor: user
data:
  elementId: "MVeOJ5ewS0s"
```

```eventstream
seq: 7
ts: "2026-02-21T16:27:56.989685Z"
type: ElementMoved
actor: user
data:
  elementId: "dh18Ps5uB5U"
```

```eventstream
seq: 8
ts: "2026-02-21T16:27:57.824315Z"
type: ElementMoved
actor: user
data:
  elementId: "MVeOJ5ewS0s"
```

```eventstream
seq: 9
ts: "2026-02-21T16:28:00.790519Z"
type: ElementMoved
actor: user
data:
  elementId: "MVeOJ5ewS0s"
```

```eventstream
seq: 10
ts: "2026-02-21T16:28:01.057208Z"
type: ElementMoved
actor: user
data:
  elementId: "MVeOJ5ewS0s"
```

```eventstream
seq: 11
ts: "2026-02-21T16:28:01.789799Z"
type: ElementMoved
actor: user
data:
  elementId: "MVeOJ5ewS0s"
```

```eventstream
seq: 12
ts: "2026-02-21T16:28:02.740819Z"
type: ElementMoved
actor: user
data:
  elementId: "MVeOJ5ewS0s"
```

```eventstream
seq: 13
ts: "2026-02-21T16:28:03.557775Z"
type: ElementMoved
actor: user
data:
  elementId: "MVeOJ5ewS0s"
```

```eventstream
seq: 14
ts: "2026-02-21T16:28:03.774501Z"
type: ElementMoved
actor: user
data:
  elementId: "MVeOJ5ewS0s"
```

```eventstream
seq: 15
ts: "2026-02-21T16:28:26.492019Z"
type: ElementModified
actor: user
data:
  changes: "%{\"label\" => \"Create\"}"
  elementId: "MVeOJ5ewS0s"
```

```eventstream
seq: 16
ts: "2026-02-21T16:28:32.739811Z"
type: ElementMoved
actor: user
data:
  elementId: "MVeOJ5ewS0s"
```

```eventstream
seq: 17
ts: "2026-02-21T16:28:39.024506Z"
type: ElementMoved
actor: user
data:
  elementId: "MVeOJ5ewS0s"
```

```eventstream
seq: 18
ts: "2026-02-21T16:28:39.207298Z"
type: ElementMoved
actor: user
data:
  elementId: "MVeOJ5ewS0s"
```

```eventstream
seq: 19
ts: "2026-02-21T16:28:52.058066Z"
type: ElementModified
actor: user
data:
  changes: "%{\"label\" => \"CreateBoard\"}"
  elementId: "MVeOJ5ewS0s"
```
