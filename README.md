# EventModeler

A purpose-built collaborative canvas for designing information systems using [Event Modeling](https://eventmodeling.org).

**Event Model in → Event Model → Refined Event Model out.**

## Documentation

- [Product Specification](docs/product-spec.md) — Feature set, Event Model format, user stories, competitive landscape
- [Technical Design](docs/technical-design.md) — Architecture, data model, canvas, collaboration, workshop enforcement, scenario generation, completeness checking, wireframe handling
- [Event Model Format Specification](docs/event-model-format-spec.md) — Standalone format spec for Event Model files (frontmatter, sections, emlang notation, event stream)

## Development Setup

Prerequisites (install via [mise](https://mise.jdx.dev/)):

```bash
mise install        # Erlang, Elixir, Node
mix deps.get        # Elixir dependencies
mix phx.server      # Start dev server at localhost:4000
```

## Done

- **Event Model Format Spec + Template** — Standalone format specification and reusable template with emlang notation, event stream format, and validation rules
- **Event Model Parser** — Parses Event Model markdown into structured data: YAML frontmatter, emlang slice blocks, named sections, and event stream entries
- **Read-Only Visualization** — SVG canvas rendering at `/visualize` with element layout, swimlane rows, connection arrows, and color-coded element types
- **File Management + Board Model** — Workspace file operations, Event Model serializer for round-trip markdown, Board GenServer per open file with DynamicSupervisor + Registry
- **Interactive Canvas Editing** — Place, move, connect, edit, and delete elements on the canvas with JS hook for pan/zoom/drag, connection rule validation, and event stream audit log
- **Slices + Scenario Generation** — Define named slices from element groups, auto-generate Given/When/Then scenarios from slice element graphs, sidebar UI for slice management
- **Full Event Model Round-Trip** — Save updates frontmatter timestamps and status, auto-generates data flows table, export controller for file download, verified with integration tests

## TODO

- **Real-Time Collaboration** — Multiple users editing the same board simultaneously with cursor tracking, element locking, and Phoenix Presence
- **Workshop Mode** — Guided 7-step Event Modeling workshop with per-step element constraints and facilitator controls
- **Completeness Checking + Polish** — Field traceability (View → Event → Command), read-only sharing route, landing page navigation, dogfooding readiness

## License

MIT — see [LICENSE](LICENSE).
