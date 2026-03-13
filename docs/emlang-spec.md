# Emlang Specification (Local Fork)

**Origin:** [emlang-project/spec](https://github.com/emlang-project/spec) v1.0.0
**Fork date:** 2026-03-13
**Purpose:** Local reference with sparklespace extensions

## Base Specification (v1.0.0)

Emlang is a YAML-based DSL for describing systems with Event Modeling patterns.

### Element Types

| Prefix | Type | Color | Description |
|--------|------|-------|-------------|
| `t:` | Trigger/Wireframe | -- | UI trigger or wireframe screen |
| `c:` | Command | Blue | Imperative action |
| `e:` | Event | Orange | Past-tense fact |
| `v:` | View | Green | Read model / query result |
| `x:` | Exception | Red | Error condition |

### Slice Forms

**Simple form** — steps only:

```yaml
slices:
  RegisterUser:
    steps:
      - t: RegistrationForm
      - c: RegisterUser
      - e: User/UserRegistered
      - v: RegistrationConfirmation
```

**Extended form** — steps with tests:

```yaml
slices:
  RegisterUser:
    steps:
      - t: RegistrationForm
      - c: RegisterUser
      - e: User/UserRegistered
    tests:
      HappyPath:
        when:
          - c: RegisterUser
        then:
          - e: User/UserRegistered
```

### Swimlane Prefixes

Element labels include a swimlane prefix separated by `/`:

```yaml
- e: User/UserRegistered    # Swimlane: "User", Label: "UserRegistered"
```

### Properties

Elements declare typed properties via `props:`:

```yaml
- c: RegisterUser
  props:
    email: string
    password: string
```

### Tests (GWT Scenarios)

Given/When/Then scenarios with optional `given`, required `when`, required `then`:

```yaml
tests:
  HappyPath:
    given:
      - e: SomePriorEvent
    when:
      - c: SomeCommand
    then:
      - e: SomeResultEvent
```

## Extensions

### `connections` block (sparklespace extension)

The `connections` block is an optional key in the extended slice form, alongside `steps` and `tests`. It documents how slices relate to each other — what events they depend on, what downstream slices or views they feed, and which stage gate conditions they participate in.

**Extended form with connections:**

```yaml
slices:
  EvaluateDimension:
    connections:
      consumes:
        - Forge/IdeaCreated
        - Forge/DimensionResearchCompleted
        - Forge/IntelligenceProductApplied
        - Forge/PrototypeResultReceived
      produces_for:
        - AdvanceIdeaStage
        - IdeaDashboardView
        - EvaluationDashboardView
      gates:
        - "draft→active: problem_clarity + strategic_fit evaluated"
        - "active→review: 5 dimensions evaluated"
        - "review→completed: all 7 at medium+ confidence"
    steps:
      - t: User/EvaluationDashboard
      - c: EvaluateDimension
      - e: Forge/DimensionEvaluated
    tests:
      SuccessfulEvaluation:
        when:
          - c: EvaluateDimension
        then:
          - e: Forge/DimensionEvaluated
```

**Schema:**

| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `consumes` | list of strings | no | Events or slices whose output this slice depends on |
| `produces_for` | list of strings | no | Slices or views that consume this slice's output events |
| `gates` | list of strings | no | Stage gate conditions this slice participates in (free-text) |

**Naming convention:**

- Same-context slices use bare names: `AdvanceIdeaStage`
- Cross-context events use `Context/EventName`: `Intelligence/IntelligenceProductPublished`
- Views use their view slice name: `IdeaDashboardView`

**Placement:**

`connections` appears after the slice name and before `steps`. The order within a slice definition is: `connections` → `steps` → `tests`.

**Notes:**

- `connections` is purely documentary — it has no effect on slice execution or validation
- It makes inter-slice dependencies explicit, enabling tooling to generate dependency graphs
- The `gates` field uses free-text descriptions since gate logic varies by domain
- When a slice both consumes events from and produces events for the same context, use bare slice names for same-context references
