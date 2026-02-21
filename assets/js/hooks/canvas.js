/**
 * EventModelerCanvas hook - handles canvas interactions
 *
 * Provides:
 * - Pan: mousedown+mousemove on background -> viewBox transform
 * - Zoom: wheel -> viewBox scale
 * - Drag: mousedown on element -> track -> pushEvent on mouseup
 * - Select: click element -> pushEvent
 * - Connect: shift+click source, shift+click target -> pushEvent
 */
const EventModelerCanvas = {
  mounted() {
    this.svg = this.el
    this.isPanning = false
    this.isDragging = false
    this.panStart = null
    this.dragTarget = null
    this.dragStartPos = null
    this.connectSource = null
    this.scale = 1
    this.translateX = 0
    this.translateY = 0

    // Parse initial viewBox
    const vb = this.svg.getAttribute("viewBox").split(" ").map(Number)
    this.viewBox = { x: vb[0], y: vb[1], w: vb[2], h: vb[3] }

    this.svg.addEventListener("mousedown", (e) => this.handleMouseDown(e))
    this.svg.addEventListener("mousemove", (e) => this.handleMouseMove(e))
    this.svg.addEventListener("mouseup", (e) => this.handleMouseUp(e))
    this.svg.addEventListener("wheel", (e) => this.handleWheel(e), { passive: false })
    this.svg.addEventListener("dblclick", (e) => this.handleDblClick(e))

    document.addEventListener("keydown", (e) => {
      if (e.key === "Delete" || e.key === "Backspace") {
        this.handleDelete(e)
      }
    })
  },

  handleMouseDown(e) {
    const element = e.target.closest("[data-element-id]")

    if (element) {
      if (e.shiftKey) {
        // Connection mode
        const elementId = element.dataset.elementId
        if (this.connectSource) {
          // Second click - complete connection
          this.pushEvent("connect_elements", {
            from_id: this.connectSource,
            to_id: elementId
          })
          this.connectSource = null
        } else {
          // First click - start connection
          this.connectSource = elementId
        }
      } else {
        // Drag mode
        this.isDragging = true
        this.dragTarget = element
        this.dragStartPos = this.getSVGPoint(e)
        this.connectSource = null
      }
    } else {
      // Pan mode
      this.isPanning = true
      this.panStart = { x: e.clientX, y: e.clientY }
      this.connectSource = null
    }
  },

  handleMouseMove(e) {
    if (this.isPanning && this.panStart) {
      const dx = (e.clientX - this.panStart.x) / this.scale
      const dy = (e.clientY - this.panStart.y) / this.scale
      this.viewBox.x -= dx
      this.viewBox.y -= dy
      this.updateViewBox()
      this.panStart = { x: e.clientX, y: e.clientY }
    }

    if (this.isDragging && this.dragTarget) {
      const pos = this.getSVGPoint(e)
      const dx = pos.x - this.dragStartPos.x
      const dy = pos.y - this.dragStartPos.y

      // Move the element group visually
      const group = this.dragTarget.closest("g")
      if (group) {
        const currentTransform = group.getAttribute("transform") || ""
        const match = currentTransform.match(/translate\(([-\d.]+),\s*([-\d.]+)\)/)
        const cx = match ? parseFloat(match[1]) : 0
        const cy = match ? parseFloat(match[2]) : 0
        group.setAttribute("transform", `translate(${cx + dx}, ${cy + dy})`)
      }

      this.dragStartPos = pos
    }
  },

  handleMouseUp(e) {
    if (this.isDragging && this.dragTarget) {
      const elementId = this.dragTarget.dataset.elementId
      const pos = this.getSVGPoint(e)
      if (elementId) {
        this.pushEvent("move_element", {
          element_id: elementId,
          x: Math.round(pos.x),
          y: Math.round(pos.y)
        })
      }
    }

    this.isPanning = false
    this.isDragging = false
    this.dragTarget = null
    this.panStart = null
  },

  handleWheel(e) {
    e.preventDefault()
    const scaleFactor = e.deltaY > 0 ? 1.1 : 0.9
    const point = this.getSVGPoint(e)

    this.viewBox.x = point.x - (point.x - this.viewBox.x) * scaleFactor
    this.viewBox.y = point.y - (point.y - this.viewBox.y) * scaleFactor
    this.viewBox.w *= scaleFactor
    this.viewBox.h *= scaleFactor
    this.scale /= scaleFactor

    this.updateViewBox()
  },

  handleDblClick(e) {
    const element = e.target.closest("[data-element-id]")
    if (element) {
      this.pushEvent("element_dblclick", {
        element_id: element.dataset.elementId
      })
    }
  },

  handleDelete(e) {
    // Only handle if not in an input/textarea
    if (e.target.tagName === "INPUT" || e.target.tagName === "TEXTAREA") return

    const selected = this.svg.querySelector("[data-selected='true']")
    if (selected) {
      const elementId = selected.dataset.elementId
      if (elementId) {
        this.pushEvent("remove_element", { element_id: elementId })
      }
    }
  },

  getSVGPoint(e) {
    const pt = this.svg.createSVGPoint()
    pt.x = e.clientX
    pt.y = e.clientY
    return pt.matrixTransform(this.svg.getScreenCTM().inverse())
  },

  updateViewBox() {
    this.svg.setAttribute("viewBox",
      `${this.viewBox.x} ${this.viewBox.y} ${this.viewBox.w} ${this.viewBox.h}`
    )
  }
}

export default EventModelerCanvas
