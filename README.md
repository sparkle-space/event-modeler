# EventModeler

A purpose-built collaborative canvas for designing information systems using [Event Modeling](https://eventmodeling.org).

**PRD in → Event Model → Refined PRD out.**

## Documentation

- [Product Specification](docs/product-spec.md) — Feature set, PRD format, user stories, competitive landscape
- [Technical Design](docs/technical-design.md) — Architecture, data model, canvas, collaboration, workshop enforcement, scenario generation, completeness checking, wireframe handling

## Development Setup

Prerequisites (install via [mise](https://mise.jdx.dev/)):

```bash
mise install        # Erlang, Elixir, Node
mix deps.get        # Elixir dependencies
mix phx.server      # Start dev server at localhost:4000
```

## Status

Early development — Phoenix scaffold with landing page. Product spec and technical design are complete.

**Development strategy:** Build a standalone Phoenix app with full event modeling capability. Extract the reusable hex module (`event_modeler`) once the core is mature and the API surface is stable.
