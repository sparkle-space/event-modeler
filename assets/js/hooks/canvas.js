/**
 * EventModelerCanvas hook - handles canvas interactions
 *
 * Provides:
 * - Pan: mousedown+mousemove on background, or scroll wheel -> CSS transform translate
 * - Zoom: Ctrl/Cmd+scroll or trackpad pinch -> CSS transform scale (cursor-centered)
 * - Pan clamping: prevents panning beyond the world content bounds (with margin)
 * - Select: click element -> pushEvent (handled by phx-click)
 * - Connect: shift+click source, shift+click target -> pushEvent
 * - Delete: Delete/Backspace -> pushEvent for selected element
 * - Viewport save/restore for element edit zoom
 * - Minimap: overview panel with draggable viewport rectangle, auto-sized to world aspect ratio
 */
const MIN_SCALE = 0.1
const MAX_SCALE = 5

// How much visible margin (in viewport pixels) to keep when panning.
// The user can pan until only this many pixels of the world remain visible.
const PAN_MARGIN = 100

// Minimap config
const MINIMAP_MAX_WIDTH = 180
const MINIMAP_MAX_HEIGHT = 140
const MINIMAP_MARGIN = 12
const MINIMAP_PAD = 8

// Element type colors for minimap
const MINIMAP_COLORS = {
  command: "#3B82F6",
  event: "#F97316",
  view: "#22C55E",
  wireframe: "#9CA3AF",
  automation: "#8B5CF6",
  exception: "#EF4444",
}

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

    // Drag-to-move state
    this.isDragging = false
    this.dragElement = null
    this.dragStartClient = null
    this.dragStartPos = null
    this.dragThresholdMet = false
    this.suppressNextClick = false

    // Suppress the click event that fires after a drag to prevent
    // phx-click="element_selected" from re-selecting the dragged element.
    // Capture phase fires before LiveView's click handler.
    this.el.addEventListener("click", (e) => {
      if (this.suppressNextClick) {
        e.stopPropagation()
        e.preventDefault()
        this.suppressNextClick = false
      }
    }, true)
    this.pendingClickElement = null

    // Minimap state
    this.minimapDragging = false

    // Cache world dimensions
    this.worldWidth = parseInt(this.world.style.width) || 800
    this.worldHeight = parseInt(this.world.style.height) || 400

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

    // Keyboard shortcuts
    document.addEventListener("keydown", (e) => {
      if (e.key === "Escape") {
        this.clearConnectSource()
      }

      const isTyping =
        e.target.tagName === "INPUT" ||
        e.target.tagName === "TEXTAREA" ||
        e.target.tagName === "SELECT"

      if ((e.key === "Delete" || e.key === "Backspace") && !isTyping) {
        this.onDelete()
      }

      // Ctrl/Cmd+S: Save
      if ((e.ctrlKey || e.metaKey) && e.key === "s") {
        e.preventDefault()
        this.pushEvent("save", {})
      }

      // Ctrl/Cmd+0: Fit to window
      if ((e.ctrlKey || e.metaKey) && e.key === "0") {
        e.preventDefault()
        this.fitToWindow()
      }

      // +/= key: Zoom in (centered on viewport)
      if ((e.key === "+" || e.key === "=") && !e.ctrlKey && !e.metaKey && !isTyping) {
        e.preventDefault()
        const rect = this.viewport.getBoundingClientRect()
        this.zoomAtPoint(rect.width / 2, rect.height / 2, 1.2)
      }

      // - key: Zoom out (centered on viewport)
      if (e.key === "-" && !e.ctrlKey && !e.metaKey && !isTyping) {
        e.preventDefault()
        const rect = this.viewport.getBoundingClientRect()
        this.zoomAtPoint(rect.width / 2, rect.height / 2, 0.8)
      }

      // ? key: Toggle shortcuts reference
      if (e.key === "?" && !isTyping) {
        e.preventDefault()
        this.pushEvent("toggle_shortcuts_modal", {})
      }

      // Ctrl/Cmd+Z: Undo
      if ((e.ctrlKey || e.metaKey) && e.key === "z" && !e.shiftKey) {
        e.preventDefault()
        this.pushEvent("undo", {})
      }

      // Ctrl/Cmd+Shift+Z or Ctrl/Cmd+Y: Redo
      if ((e.ctrlKey || e.metaKey) && e.key === "z" && e.shiftKey) {
        e.preventDefault()
        this.pushEvent("redo", {})
      }
      if ((e.ctrlKey || e.metaKey) && e.key === "y") {
        e.preventDefault()
        this.pushEvent("redo", {})
      }

      // M key: Toggle minimap
      if (e.key === "m" && !isTyping) {
        this.toggleMinimap()
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
      this.zoomToElement(payload.x, payload.y, payload.width, payload.height)
    })

    this.handleEvent("restore_viewport", (payload) => {
      this.translateX = payload.translateX || 0
      this.translateY = payload.translateY || 0
      this.scale = payload.scale || 1
      this.savedViewport = null
      this.clampTranslate()
      this.world.style.transition = "transform 0.3s ease-out"
      this.applyTransform()
      setTimeout(() => {
        this.world.style.transition = ""
      }, 300)
    })

    this.handleEvent("fit_to_window", () => {
      this.fitToWindow()
    })

    // Create minimap
    this.createMinimap()
    this.renderMinimap()
  },

  updated() {
    this.world = this.el.querySelector("#canvas-world")
    this.updateWorldDimensions()
    this.clampTranslate()
    this.applyTransform()
    this.resizeMinimap()
    this.renderMinimap()
  },

  // --- World dimensions ---

  updateWorldDimensions() {
    this.worldWidth = parseInt(this.world.style.width) || 800
    this.worldHeight = parseInt(this.world.style.height) || 400
  },

  // --- Pan clamping ---
  // Ensures the viewport cannot pan so far that the world content
  // disappears from view. At least PAN_MARGIN pixels of scaled world
  // must remain visible on each edge.

  clampTranslate() {
    const vp = this.viewport.getBoundingClientRect()
    const scaledWidth = this.worldWidth * this.scale
    const scaledHeight = this.worldHeight * this.scale

    // Max translate: world's left edge can go at most PAN_MARGIN px
    // into the viewport from the right edge (so content stays visible)
    const maxTx = PAN_MARGIN
    // Min translate: world's right edge must stay at least PAN_MARGIN px
    // from the viewport's left edge
    const minTx = vp.width - scaledWidth - PAN_MARGIN

    const maxTy = PAN_MARGIN
    const minTy = vp.height - scaledHeight - PAN_MARGIN

    // If the world is smaller than the viewport, center it instead of clamping
    if (scaledWidth + PAN_MARGIN * 2 <= vp.width) {
      this.translateX = (vp.width - scaledWidth) / 2
    } else {
      this.translateX = Math.max(minTx, Math.min(maxTx, this.translateX))
    }

    if (scaledHeight + PAN_MARGIN * 2 <= vp.height) {
      this.translateY = (vp.height - scaledHeight) / 2
    } else {
      this.translateY = Math.max(minTy, Math.min(maxTy, this.translateY))
    }
  },

  // --- Minimap ---

  createMinimap() {
    const container = document.createElement("div")
    container.id = "canvas-minimap"

    // Compute initial minimap size from world aspect ratio
    const { width: mw, height: mh } = this.minimapSize()

    container.style.cssText = `
      position: absolute;
      bottom: ${MINIMAP_MARGIN}px;
      right: ${MINIMAP_MARGIN}px;
      width: ${mw}px;
      height: ${mh}px;
      background: var(--color-surface);
      border: 1px solid var(--color-border);
      border-radius: 8px;
      overflow: hidden;
      z-index: 15;
      opacity: 0.9;
      cursor: pointer;
      box-shadow: 0 2px 8px rgba(0,0,0,0.15);
    `

    const canvas = document.createElement("canvas")
    canvas.width = mw * 2 // 2x for retina
    canvas.height = mh * 2
    canvas.style.cssText = `width: ${mw}px; height: ${mh}px;`
    container.appendChild(canvas)

    // Minimap interactions
    container.addEventListener("mousedown", (e) => {
      e.stopPropagation()
      this.minimapDragging = true
      this.minimapNavigate(e)
    })

    container.addEventListener("mousemove", (e) => {
      if (this.minimapDragging) {
        e.stopPropagation()
        this.minimapNavigate(e)
      }
    })

    container.addEventListener("mouseup", (e) => {
      e.stopPropagation()
      this.minimapDragging = false
    })

    container.addEventListener("mouseleave", () => {
      this.minimapDragging = false
    })

    // Prevent wheel events from reaching the main canvas
    container.addEventListener("wheel", (e) => {
      e.stopPropagation()
    })

    this.viewport.appendChild(container)
    this.minimapContainer = container
    this.minimapCanvas = canvas
    this.minimapVisible = true
  },

  // Calculate minimap pixel size to match world aspect ratio,
  // fitting within MINIMAP_MAX_WIDTH x MINIMAP_MAX_HEIGHT.
  minimapSize() {
    const aspect = this.worldWidth / Math.max(this.worldHeight, 1)
    let w, h
    if (aspect >= MINIMAP_MAX_WIDTH / MINIMAP_MAX_HEIGHT) {
      // World is wider — fill width, shrink height
      w = MINIMAP_MAX_WIDTH
      h = Math.max(Math.round(w / aspect), 40) // min 40px tall
    } else {
      // World is taller — fill height, shrink width
      h = MINIMAP_MAX_HEIGHT
      w = Math.max(Math.round(h * aspect), 60) // min 60px wide
    }
    return { width: w, height: h }
  },

  // Resize minimap container + canvas when world dimensions change.
  resizeMinimap() {
    if (!this.minimapContainer || !this.minimapVisible) return

    const { width: mw, height: mh } = this.minimapSize()
    const currentW = parseInt(this.minimapContainer.style.width)
    const currentH = parseInt(this.minimapContainer.style.height)

    if (currentW === mw && currentH === mh) return

    this.minimapContainer.style.width = mw + "px"
    this.minimapContainer.style.height = mh + "px"
    this.minimapCanvas.width = mw * 2
    this.minimapCanvas.height = mh * 2
    this.minimapCanvas.style.width = mw + "px"
    this.minimapCanvas.style.height = mh + "px"
  },

  toggleMinimap() {
    this.minimapVisible = !this.minimapVisible
    this.minimapContainer.style.display = this.minimapVisible ? "block" : "none"
    if (this.minimapVisible) {
      this.resizeMinimap()
      this.renderMinimap()
    }
  },

  minimapNavigate(e) {
    const rect = this.minimapContainer.getBoundingClientRect()
    const mx = e.clientX - rect.left
    const my = e.clientY - rect.top

    const { width: mw, height: mh } = this.minimapSize()
    const miniScale = Math.min(
      (mw - MINIMAP_PAD * 2) / this.worldWidth,
      (mh - MINIMAP_PAD * 2) / this.worldHeight
    )

    // Convert minimap click position to world coordinates
    const worldX = (mx - MINIMAP_PAD) / miniScale
    const worldY = (my - MINIMAP_PAD) / miniScale

    // Center the viewport on that world position
    const vp = this.viewport.getBoundingClientRect()
    this.translateX = vp.width / 2 - worldX * this.scale
    this.translateY = vp.height / 2 - worldY * this.scale
    this.clampTranslate()
    this.applyTransform()
    this.renderMinimap()
  },

  renderMinimap() {
    if (!this.minimapCanvas || !this.minimapVisible) return

    const { width: mw, height: mh } = this.minimapSize()

    const ctx = this.minimapCanvas.getContext("2d")
    const dpr = 2
    ctx.clearRect(0, 0, mw * dpr, mh * dpr)
    ctx.scale(dpr, dpr)

    // Calculate scale to fit world in minimap
    const miniScale = Math.min(
      (mw - MINIMAP_PAD * 2) / this.worldWidth,
      (mh - MINIMAP_PAD * 2) / this.worldHeight
    )

    // Draw world background
    ctx.fillStyle = "#e5e7eb"
    ctx.globalAlpha = 0.3
    ctx.fillRect(
      MINIMAP_PAD,
      MINIMAP_PAD,
      this.worldWidth * miniScale,
      this.worldHeight * miniScale
    )
    ctx.globalAlpha = 1

    // Draw elements from DOM
    const elements = this.world.querySelectorAll("[data-element-id]")
    elements.forEach((el) => {
      const x = parseFloat(el.style.left) * miniScale + MINIMAP_PAD
      const y = parseFloat(el.style.top) * miniScale + MINIMAP_PAD
      const w = Math.max(parseFloat(el.style.width) * miniScale, 2)
      const h = Math.max(parseFloat(el.style.height) * miniScale, 2)

      // Determine color from element classes
      let color = "#9CA3AF"
      for (const [type, c] of Object.entries(MINIMAP_COLORS)) {
        if (el.classList.toString().includes(type) || el.querySelector(`.text-${type}`)) {
          color = c
          break
        }
      }

      // Try to detect type from the type label text
      const typeSpan = el.querySelector("span:last-child")
      if (typeSpan) {
        const typeText = typeSpan.textContent.trim().toLowerCase()
        if (MINIMAP_COLORS[typeText]) {
          color = MINIMAP_COLORS[typeText]
        }
      }

      ctx.fillStyle = color
      ctx.fillRect(x, y, w, h)
    })

    // Draw viewport rectangle
    const vp = this.viewport.getBoundingClientRect()
    const vpLeft = (-this.translateX / this.scale) * miniScale + MINIMAP_PAD
    const vpTop = (-this.translateY / this.scale) * miniScale + MINIMAP_PAD
    const vpWidth = (vp.width / this.scale) * miniScale
    const vpHeight = (vp.height / this.scale) * miniScale

    ctx.strokeStyle = "#3B82F6"
    ctx.lineWidth = 1.5
    ctx.strokeRect(vpLeft, vpTop, vpWidth, vpHeight)
    ctx.fillStyle = "rgba(59, 130, 246, 0.08)"
    ctx.fillRect(vpLeft, vpTop, vpWidth, vpHeight)

    // Reset scale for next frame
    ctx.setTransform(1, 0, 0, 1, 0, 0)
  },

  // --- Connection mode ---

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

  // --- Navigation ---

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

    this.clampTranslate()
    this.world.style.transition = "transform 0.3s ease-out"
    this.applyTransform()
    this.renderMinimap()
    setTimeout(() => {
      this.world.style.transition = ""
    }, 300)
  },

  zoomToElement(elemX, elemY, elemWidth, elemHeight) {
    const vp = this.viewport.getBoundingClientRect()
    const padding = 120

    // Calculate scale to fit element comfortably
    const scaleX = vp.width / (elemWidth + padding * 2)
    const scaleY = vp.height / (elemHeight + padding * 2)
    const fitScale = Math.min(scaleX, scaleY, 2.5) // Cap at 2.5x

    this.scale = Math.max(0.5, fitScale)

    // Center the element in the viewport (already resized by the right panel)
    const centerX = elemX + elemWidth / 2
    const centerY = elemY + elemHeight / 2
    this.translateX = vp.width / 2 - centerX * this.scale
    this.translateY = vp.height / 2 - centerY * this.scale

    // Note: intentionally NOT clamping here — zoom-to-element may need
    // to position outside normal bounds to center with the right panel open
    this.world.style.transition = "transform 0.3s ease-out"
    this.applyTransform()
    this.renderMinimap()
    setTimeout(() => {
      this.world.style.transition = ""
    }, 300)
  },

  fitToWindow() {
    const vp = this.viewport.getBoundingClientRect()
    const padding = 60

    const scaleX = vp.width / (this.worldWidth + padding * 2)
    const scaleY = vp.height / (this.worldHeight + padding * 2)
    const fitScale = Math.min(scaleX, scaleY, MAX_SCALE)
    this.scale = Math.max(MIN_SCALE, fitScale)

    this.translateX = (vp.width - this.worldWidth * this.scale) / 2
    this.translateY = (vp.height - this.worldHeight * this.scale) / 2

    // No clamping needed — fitToWindow always centers within bounds
    this.world.style.transition = "transform 0.3s ease-out"
    this.applyTransform()
    this.renderMinimap()
    setTimeout(() => {
      this.world.style.transition = ""
    }, 300)
  },

  // --- Transform ---

  applyTransform() {
    this.world.style.transform = `translate(${this.translateX}px, ${this.translateY}px) scale(${this.scale})`
  },

  zoomAtPoint(px, py, factor) {
    const newScale = this.scale * factor
    if (newScale < MIN_SCALE || newScale > MAX_SCALE) return
    this.translateX = px - factor * (px - this.translateX)
    this.translateY = py - factor * (py - this.translateY)
    this.scale = newScale
    this.clampTranslate()
    this.applyTransform()
    this.renderMinimap()
  },

  // --- Mouse handlers ---

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
    } else if (elem && !e.shiftKey) {
      // Potential drag-to-move — track start, wait for threshold
      this.pendingClickElement = elem
      this.dragStartClient = { x: e.clientX, y: e.clientY }
      this.dragStartPos = {
        x: parseInt(elem.style.left),
        y: parseInt(elem.style.top),
      }
      this.isDragging = true
      this.dragThresholdMet = false
      this.dragElement = elem
      e.preventDefault()
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
    // Element drag
    if (this.isDragging && this.dragElement) {
      const dx = e.clientX - this.dragStartClient.x
      const dy = e.clientY - this.dragStartClient.y

      if (!this.dragThresholdMet) {
        // Check 5px threshold before entering true drag mode
        if (Math.abs(dx) > 5 || Math.abs(dy) > 5) {
          this.dragThresholdMet = true
          this.viewport.style.cursor = "move"
        }
        return
      }

      // Apply position offset accounting for zoom scale
      const newX = this.dragStartPos.x + dx / this.scale
      const newY = this.dragStartPos.y + dy / this.scale
      this.dragElement.style.left = newX + "px"
      this.dragElement.style.top = newY + "px"
      return
    }

    // Canvas pan
    if (!this.isPanning || !this.panStart) return

    this.translateX += e.clientX - this.panStart.x
    this.translateY += e.clientY - this.panStart.y
    this.panStart = { x: e.clientX, y: e.clientY }
    this.clampTranslate()
    this.applyTransform()
    this.renderMinimap()
  },

  onMouseUp() {
    // Complete element drag
    if (this.isDragging && this.dragElement) {
      if (this.dragThresholdMet) {
        // Was a real drag — send final position to server
        const finalX = parseFloat(this.dragElement.style.left)
        const finalY = parseFloat(this.dragElement.style.top)
        this.pushEvent("move_element", {
          element_id: this.dragElement.dataset.elementId,
          x: finalX,
          y: finalY,
        })
        // Suppress the click event that fires after mouseup to prevent
        // phx-click="element_selected" from re-selecting the element
        this.suppressNextClick = true
      }
      // If threshold not met, it was a click — phx-click handles selection

      this.isDragging = false
      this.dragElement = null
      this.dragStartClient = null
      this.dragStartPos = null
      this.dragThresholdMet = false
      this.pendingClickElement = null
      this.viewport.style.cursor = this.connectSource ? "crosshair" : ""
      this.renderMinimap()
      return
    }

    // Complete canvas pan
    if (this.isPanning) {
      this.isPanning = false
      this.panStart = null
      // Restore cursor based on connection mode state
      this.viewport.style.cursor = this.connectSource ? "crosshair" : ""
      this.renderMinimap()
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
      this.clampTranslate()
      this.applyTransform()
      this.renderMinimap()
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
