/**
 * EventModelerCanvas hook - handles canvas interactions
 *
 * Provides:
 * - Pan: mousedown+mousemove on background, or scroll wheel -> CSS transform translate
 * - Zoom: Ctrl/Cmd+scroll or trackpad pinch -> CSS transform scale (cursor-centered)
 * - Select: click element -> pushEvent (handled by phx-click)
 * - Connect: shift+click source, shift+click target -> pushEvent
 * - Delete: Delete/Backspace -> pushEvent for selected element
 */
const MIN_SCALE = 0.1
const MAX_SCALE = 5

const EventModelerCanvas = {
  mounted() {
    this.viewport = this.el
    this.world = this.el.querySelector("#canvas-world")

    this.translateX = 0
    this.translateY = 0
    this.scale = 1

    this.isPanning = false
    this.panStart = null
    this.connectSource = null

    this.viewport.addEventListener("mousedown", (e) => this.onMouseDown(e))
    this.viewport.addEventListener("mousemove", (e) => this.onMouseMove(e))
    this.viewport.addEventListener("mouseup", () => this.onMouseUp())
    this.viewport.addEventListener("wheel", (e) => this.onWheel(e), {
      passive: false,
    })

    // Double-click on element to edit label, on empty canvas to zoom in
    this.viewport.addEventListener("dblclick", (e) => {
      const elem = e.target.closest("[data-element-id]")
      if (elem) {
        this.pushEvent("element_dblclick", {
          element_id: elem.dataset.elementId,
        })
      } else {
        const rect = this.viewport.getBoundingClientRect()
        const px = e.clientX - rect.left
        const py = e.clientY - rect.top
        this.zoomAtPoint(px, py, 1.5)
      }
    })

    // Escape key cancels connection mode
    document.addEventListener("keydown", (e) => {
      if (e.key === "Escape") {
        this.clearConnectSource()
      }

      if (
        (e.key === "Delete" || e.key === "Backspace") &&
        e.target.tagName !== "INPUT" &&
        e.target.tagName !== "TEXTAREA"
      ) {
        this.onDelete()
      }
    })

    // Listen for server-pushed pan_to_slice events
    this.handleEvent("pan_to_slice", (payload) => {
      this.panToSlice(payload.x, payload.width)
    })
  },

  updated() {
    this.world = this.el.querySelector("#canvas-world")
    this.applyTransform()
  },

  clearConnectSource() {
    if (this.connectSource) {
      const prev = this.viewport.querySelector(".connecting-source")
      if (prev) prev.classList.remove("connecting-source")
      this.connectSource = null
      this.viewport.style.cursor = ""
    }
  },

  setConnectSource(id) {
    this.connectSource = id
    const sourceEl = this.viewport.querySelector(
      `[data-element-id="${id}"]`
    )
    if (sourceEl) sourceEl.classList.add("connecting-source")
    this.viewport.style.cursor = "crosshair"
  },

  panToSlice(sliceX, sliceWidth) {
    const viewportWidth = this.viewport.getBoundingClientRect().width
    const sliceCenterX = sliceX + sliceWidth / 2

    // Center the slice horizontally: viewportCenter = translateX + sliceCenterX * scale
    this.translateX = viewportWidth / 2 - sliceCenterX * this.scale

    // Smooth transition, then remove so manual pan stays responsive
    this.world.style.transition = "transform 0.3s ease-out"
    this.applyTransform()
    setTimeout(() => {
      this.world.style.transition = ""
    }, 300)
  },

  applyTransform() {
    this.world.style.transform = `translate(${this.translateX}px, ${this.translateY}px) scale(${this.scale})`
  },

  zoomAtPoint(px, py, factor) {
    const newScale = this.scale * factor
    if (newScale < MIN_SCALE || newScale > MAX_SCALE) return
    this.translateX = px - factor * (px - this.translateX)
    this.translateY = py - factor * (py - this.translateY)
    this.scale = newScale
    this.applyTransform()
  },

  onMouseDown(e) {
    const elem = e.target.closest("[data-element-id]")

    if (elem && e.shiftKey) {
      // Connection mode
      const id = elem.dataset.elementId
      if (this.connectSource) {
        this.pushEvent("connect_elements", {
          from_id: this.connectSource,
          to_id: id,
        })
        this.clearConnectSource()
      } else {
        this.setConnectSource(id)
      }
    } else if (!elem) {
      // Click on empty canvas clears connection mode
      this.clearConnectSource()
      // Pan mode
      this.isPanning = true
      this.panStart = { x: e.clientX, y: e.clientY }
      this.viewport.style.cursor = "grabbing"
    }
  },

  onMouseMove(e) {
    if (!this.isPanning || !this.panStart) return

    this.translateX += e.clientX - this.panStart.x
    this.translateY += e.clientY - this.panStart.y
    this.panStart = { x: e.clientX, y: e.clientY }
    this.applyTransform()
  },

  onMouseUp() {
    if (this.isPanning) {
      this.isPanning = false
      this.panStart = null
      // Restore cursor based on connection mode state
      this.viewport.style.cursor = this.connectSource ? "crosshair" : ""
    }
  },

  onWheel(e) {
    e.preventDefault()

    if (e.ctrlKey || e.metaKey) {
      // Zoom toward cursor (Ctrl/Cmd+scroll or trackpad pinch)
      const factor = e.deltaY > 0 ? 0.95 : 1.05
      const rect = this.viewport.getBoundingClientRect()
      const px = e.clientX - rect.left
      const py = e.clientY - rect.top
      this.zoomAtPoint(px, py, factor)
    } else {
      // Pan
      this.translateX -= e.deltaX
      this.translateY -= e.deltaY
      this.applyTransform()
    }
  },

  onDelete() {
    const selected = this.viewport.querySelector("[data-selected='true']")
    if (selected) {
      this.pushEvent("remove_element", {
        element_id: selected.dataset.elementId,
      })
    }
  },
}

export default EventModelerCanvas
