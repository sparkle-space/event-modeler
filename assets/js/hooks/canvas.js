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

    // Double-click on element to edit label
    this.viewport.addEventListener("dblclick", (e) => {
      const elem = e.target.closest("[data-element-id]")
      if (elem) {
        this.pushEvent("element_dblclick", {
          element_id: elem.dataset.elementId,
        })
      }
    })

    document.addEventListener("keydown", (e) => {
      if (
        (e.key === "Delete" || e.key === "Backspace") &&
        e.target.tagName !== "INPUT" &&
        e.target.tagName !== "TEXTAREA"
      ) {
        this.handleDelete()
      }
    })
  },

  applyTransform() {
    this.world.style.transform = `translate(${this.translateX}px, ${this.translateY}px) scale(${this.scale})`
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
        this.connectSource = null
      } else {
        this.connectSource = id
      }
    } else if (!elem) {
      // Pan mode
      this.isPanning = true
      this.panStart = { x: e.clientX, y: e.clientY }
      this.connectSource = null
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
      this.viewport.style.cursor = ""
    }
  },

  onWheel(e) {
    e.preventDefault()

    if (e.ctrlKey || e.metaKey) {
      // Zoom toward cursor (Ctrl/Cmd+scroll or trackpad pinch)
      const factor = e.deltaY > 0 ? 0.9 : 1.1
      const rect = this.viewport.getBoundingClientRect()
      const px = e.clientX - rect.left
      const py = e.clientY - rect.top
      this.translateX = px - factor * (px - this.translateX)
      this.translateY = py - factor * (py - this.translateY)
      this.scale *= factor
    } else {
      // Pan
      this.translateX -= e.deltaX
      this.translateY -= e.deltaY
    }

    this.applyTransform()
  },

  handleDelete() {
    const selected = this.viewport.querySelector("[data-selected='true']")
    if (selected) {
      this.pushEvent("remove_element", {
        element_id: selected.dataset.elementId,
      })
    }
  },
}

export default EventModelerCanvas
