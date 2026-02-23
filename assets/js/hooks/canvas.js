/**
 * EventModelerCanvas hook - handles canvas interactions
 *
 * Provides:
 * - Pan: mousedown+mousemove on background, or scroll wheel -> CSS transform translate
 * - Zoom: Ctrl/Cmd+scroll or trackpad pinch -> CSS transform scale (cursor-centered)
 * - Select: click element -> pushEvent (handled by phx-click)
 * - Connect: shift+click source, shift+click target -> pushEvent
 * - Delete: Delete/Backspace -> pushEvent for selected element
 * - Viewport save/restore for element edit zoom
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
    this.savedViewport = null

    this.viewport.addEventListener("mousedown", (e) => this.onMouseDown(e))
    this.viewport.addEventListener("mousemove", (e) => this.onMouseMove(e))
    this.viewport.addEventListener("mouseup", () => this.onMouseUp())
    this.viewport.addEventListener("wheel", (e) => this.onWheel(e), {
      passive: false,
    })

    // Double-click on empty canvas to zoom in (element edit is now single-click)
    this.viewport.addEventListener("dblclick", (e) => {
      const elem = e.target.closest("[data-element-id]")
      if (!elem) {
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
        e.target.tagName !== "TEXTAREA" &&
        e.target.tagName !== "SELECT"
      ) {
        this.onDelete()
      }
    })

    // Listen for server-pushed events
    this.handleEvent("pan_to_slice", (payload) => {
      this.panToSlice(
        payload.x,
        payload.y,
        payload.width,
        payload.height,
        payload.bottom_offset || 0
      )
    })

    this.handleEvent("save_viewport", () => {
      this.savedViewport = {
        translateX: this.translateX,
        translateY: this.translateY,
        scale: this.scale,
      }
      this.pushEvent("viewport_saved", {
        translateX: this.translateX,
        translateY: this.translateY,
        scale: this.scale,
      })
    })

    this.handleEvent("zoom_to_element", (payload) => {
      this.zoomToElement(
        payload.x,
        payload.y,
        payload.width,
        payload.height,
        payload.panel_width || 0
      )
    })

    this.handleEvent("restore_viewport", (payload) => {
      this.translateX = payload.translateX || 0
      this.translateY = payload.translateY || 0
      this.scale = payload.scale || 1
      this.savedViewport = null
      this.world.style.transition = "transform 0.3s ease-out"
      this.applyTransform()
      setTimeout(() => {
        this.world.style.transition = ""
      }, 300)
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

  panToSlice(sliceX, sliceY, sliceWidth, sliceHeight, bottomOffset = 0) {
    const vp = this.viewport.getBoundingClientRect()
    const padding = 80
    // Account for bottom sheet overlay when calculating available space
    const availableHeight = vp.height - bottomOffset

    // Calculate scale to fit the slice bounding box in the visible area
    const scaleX = vp.width / (sliceWidth + padding)
    const scaleY = availableHeight / (sliceHeight + padding)
    const fitScale = Math.min(scaleX, scaleY)

    // Clamp: minimum zoom floor for readability, cap at MAX_SCALE
    const MIN_FIT_SCALE = 0.3
    this.scale = Math.max(MIN_FIT_SCALE, Math.min(fitScale, MAX_SCALE))

    // Center the bounding box in the visible area (above bottom sheet)
    const centerX = sliceX + sliceWidth / 2
    const centerY = sliceY + sliceHeight / 2
    this.translateX = vp.width / 2 - centerX * this.scale
    this.translateY = availableHeight / 2 - centerY * this.scale

    // Smooth transition, then remove so manual pan stays responsive
    this.world.style.transition = "transform 0.3s ease-out"
    this.applyTransform()
    setTimeout(() => {
      this.world.style.transition = ""
    }, 300)
  },

  zoomToElement(elemX, elemY, elemWidth, elemHeight, panelWidth) {
    const vp = this.viewport.getBoundingClientRect()
    // Available canvas width accounts for the right panel that will appear
    const availableWidth = vp.width - panelWidth
    const padding = 120

    // Calculate scale to fit element comfortably
    const scaleX = availableWidth / (elemWidth + padding * 2)
    const scaleY = vp.height / (elemHeight + padding * 2)
    const fitScale = Math.min(scaleX, scaleY, 2.5) // Cap at 2.5x

    this.scale = Math.max(0.5, fitScale)

    // Center the element in the available canvas area (not the full viewport)
    const centerX = elemX + elemWidth / 2
    const centerY = elemY + elemHeight / 2
    this.translateX = availableWidth / 2 - centerX * this.scale
    this.translateY = vp.height / 2 - centerY * this.scale

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

      // Notify server that background was clicked (clears editing state)
      this.pushEvent("canvas_background_clicked", {})

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
