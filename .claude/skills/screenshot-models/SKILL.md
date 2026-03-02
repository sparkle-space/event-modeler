# /screenshot-models — Generate Event Models & Take Screenshots

Generate Event Model `.md` files from descriptions and take high-resolution screenshots of the rendered canvas.

## Workflow

### Phase 1: Generate Event Model Files

Create `.md` files in `priv/event_models/` following the Event Model format.

#### File Structure

```markdown
---
title: "Model Title"
status: draft
domain: "Context"
version: 1
created: "2026-01-01T00:00:00Z"
updated: "2026-01-01T00:00:00Z"
tags:
  - event-modeling
---

# Model Title

## Overview

Brief description of what this model represents.

## Key Ideas

- Key concept 1
- Key concept 2

## Slices

### Slice: SliceName

Description of the slice.

```yaml emlang
slices:
  SliceName:
    steps:
      - t: Actor/TriggerScreen
      - c: CommandName
      - e: Context/EventName
      - v: ViewName
```

<!-- event-stream -->

## Event Stream

```eventstream
seq: 1
ts: "2026-01-01T00:00:00Z"
type: EventModelCreated
actor: system
data:
  title: "Model Title"
  status: draft
```
```

#### Emlang Step Prefixes

| Prefix | Type | Swimlane | Description |
|--------|------|----------|-------------|
| `t:` | Wireframe | Top | UI screens, triggers |
| `c:` | Command | Middle | User actions/intents |
| `e:` | Event | Middle | Domain events (past tense) |
| `v:` | View | Bottom | Read models, projections |
| `a:` | Automation | Middle | System-triggered processes |
| `x:` | Exception | Middle | Error/failure events |

#### Layout Engine Constraints

- **Left-to-right order**: Steps render in the order listed. First step is leftmost.
- **Swimlanes via prefix**: Use `Actor/Label` format to assign swimlanes (e.g., `t: Guest/SearchForm`, `e: Booking/RoomBooked`).
- **Fan-in (multiple events → one view)**: Use separate slices. Each slice contributes events; the view appears in the slice that reads them.
- **Fan-out (one event → multiple views)**: Use separate slices. Repeat the event in each slice with a different view.
- **One emlang block per slice**: Each `### Slice:` heading gets exactly one fenced `emlang` block.
- **Workspace discovery**: Only reads top-level files in `priv/event_models/` — no subdirectories.

#### Props (Optional)

Add `props` to commands and events for field-level detail:

```yaml emlang
slices:
  BookRoom:
    steps:
      - t: Guest/BookingForm
      - c: BookRoom
        props:
          guest_id: string
          room_id: string
          check_in: date
          check_out: date
      - e: Booking/RoomBooked
        props:
          booking_id: string
          guest_id: string
          room_id: string
      - v: BookingConfirmation
```

### Phase 2: Verify

Run all three checks before proceeding to screenshots:

```bash
mix compile --warnings-as-errors
mix test
mix format --check-formatted
```

Fix any issues before continuing. Common problems:
- Parser errors from malformed emlang YAML (check indentation)
- Missing event stream sentinel (`<!-- event-stream -->`)
- Formatter violations in modified Elixir files

### Phase 3: Screenshot

#### Compute Board URLs

The board route is `/boards/:path` where `:path` is the base64url-encoded absolute file path (no padding).

In the dev environment, files live under `_build/dev/lib/event_modeler/priv/event_models/`. Compute the URL path:

```elixir
# For a file named "my-model.md":
path = "/Users/<user>/src/sparkle-space/event-modeler/_build/dev/lib/event_modeler/priv/event_models/my-model.md"
encoded = Base.url_encode64(path, padding: false)
url = "http://localhost:4000/boards/#{encoded}"
```

To get the actual `_build` path at runtime, use:

```bash
mix run -e 'IO.puts(Path.join(:code.priv_dir(:event_modeler) |> to_string(), "event_models"))'
```

#### Ensure Dev Server is Running

```bash
# Check if server is already running
curl -s -o /dev/null -w "%{http_code}" http://localhost:4000

# If not running, start it in the background
mix phx.server &
sleep 5  # Wait for startup
```

#### Take Screenshots with Zoom-to-Fit

Use `shot-scraper` with retina resolution and JavaScript zoom-to-fit:

```bash
shot-scraper "http://localhost:4000/boards/<encoded_path>" \
  -o screenshots/<model-name>.png \
  --width 1920 --height 1080 --retina --wait 3000 \
  --javascript "
var viewport = document.getElementById('canvas-viewport');
var world = document.getElementById('canvas-world');
var elements = world.querySelectorAll('[data-element-id]');
var maxX = 0, maxY = 0;
elements.forEach(function(el) {
  var x = parseFloat(el.style.left) + parseFloat(el.style.width);
  var y = parseFloat(el.style.top) + parseFloat(el.style.height);
  if (x > maxX) maxX = x;
  if (y > maxY) maxY = y;
});
var padding = 60;
var contentWidth = maxX + padding;
var contentHeight = maxY + padding;
var vw = viewport.clientWidth;
var vh = viewport.clientHeight - 50;
var scale = Math.min(vw / contentWidth, vh / contentHeight);
world.style.transform = 'scale(' + scale + ')';
world.style.height = contentHeight + 'px';
"
```

**Key flags:**
- `--width 1920 --height 1080`: Full HD viewport
- `--retina`: 2x pixel density for sharp text
- `--wait 3000`: Wait 3 seconds for LiveView to render and board to load
- `--javascript "..."`: Inject zoom-to-fit that measures actual element positions

**Output directory:** Save screenshots to `screenshots/` at the project root.

#### Batch Screenshot Script

For multiple models, loop over the files:

```bash
PRIV_DIR=$(mix run -e 'IO.puts(Path.join(:code.priv_dir(:event_modeler) |> to_string(), "event_models"))')
mkdir -p screenshots

for file in "$PRIV_DIR"/*.md; do
  name=$(basename "$file" .md)
  encoded=$(mix run -e "IO.puts(Base.url_encode64(\"$file\", padding: false))")
  shot-scraper "http://localhost:4000/boards/$encoded" \
    -o "screenshots/${name}.png" \
    --width 1920 --height 1080 --retina --wait 3000 \
    --javascript "
var viewport = document.getElementById('canvas-viewport');
var world = document.getElementById('canvas-world');
var elements = world.querySelectorAll('[data-element-id]');
var maxX = 0, maxY = 0;
elements.forEach(function(el) {
  var x = parseFloat(el.style.left) + parseFloat(el.style.width);
  var y = parseFloat(el.style.top) + parseFloat(el.style.height);
  if (x > maxX) maxX = x;
  if (y > maxY) maxY = y;
});
var padding = 60;
var contentWidth = maxX + padding;
var contentHeight = maxY + padding;
var vw = viewport.clientWidth;
var vh = viewport.clientHeight - 50;
var scale = Math.min(vw / contentWidth, vh / contentHeight);
world.style.transform = 'scale(' + scale + ')';
world.style.height = contentHeight + 'px';
"
  echo "Captured: ${name}.png"
done
```

## Reference Files

| File | Purpose |
|------|---------|
| `lib/event_modeler/event_model/emlang_parser.ex` | Parses emlang YAML blocks into slices |
| `lib/event_modeler/event_model/element.ex` | Element types and prefix mappings |
| `lib/event_modeler/workspace.ex` | Workspace discovery (top-level `priv/event_models/`) |
| `lib/event_modeler/canvas/layout.ex` | Layout engine (computes positions from model) |
| `lib/event_modeler_web/router.ex` | Board route: `/boards/:path` |
| `docs/product-spec.md` | Full Event Model format specification |
