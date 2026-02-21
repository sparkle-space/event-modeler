# EventModeler

A purpose-built collaborative canvas for designing information systems using [Event Modeling](https://eventmodeling.org).

**PRD in → Event Model → Refined PRD out.**

## Documentation

- [Product Specification](docs/product-spec.md) — Feature set, PRD format, user stories, competitive landscape
- [Technical Design](docs/technical-design.md) — Architecture, data model, canvas, collaboration, workshop enforcement, scenario generation, completeness checking, wireframe handling

## Status

Pre-development — local server first. Product spec and technical design are complete. Next step: scaffold a standalone Phoenix/LiveView application.

**Development strategy:** Build a standalone Phoenix app with full event modeling capability. Extract the reusable hex module (`event_modeler`) once the core is mature and the API surface is stable.
