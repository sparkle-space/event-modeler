/**
 * SliceReorder hook — drag-to-reorder slice items in a list.
 *
 * Uses HTML5 drag-and-drop on child elements with [data-slice-name].
 * On drop, pushes "reorder_slices" event with the new ordered list.
 */
const SliceReorder = {
  mounted() {
    this.el.addEventListener("dragstart", (e) => {
      const item = e.target.closest("[data-slice-name]")
      if (!item) return
      e.dataTransfer.effectAllowed = "move"
      e.dataTransfer.setData("text/plain", item.dataset.sliceName)
      item.classList.add("opacity-50")
      this.draggedItem = item
    })

    this.el.addEventListener("dragend", (e) => {
      const item = e.target.closest("[data-slice-name]")
      if (item) item.classList.remove("opacity-50")
      this.clearDropIndicators()
      this.draggedItem = null
    })

    this.el.addEventListener("dragover", (e) => {
      e.preventDefault()
      e.dataTransfer.dropEffect = "move"

      const target = e.target.closest("[data-slice-name]")
      this.clearDropIndicators()
      if (target && target !== this.draggedItem) {
        target.classList.add("border-t-2", "border-primary")
      }
    })

    this.el.addEventListener("dragleave", (e) => {
      const target = e.target.closest("[data-slice-name]")
      if (target) {
        target.classList.remove("border-t-2", "border-primary")
      }
    })

    this.el.addEventListener("drop", (e) => {
      e.preventDefault()
      this.clearDropIndicators()

      const items = [...this.el.querySelectorAll("[data-slice-name]")]
      const orderedNames = items.map((el) => el.dataset.sliceName)

      const draggedName = e.dataTransfer.getData("text/plain")
      const target = e.target.closest("[data-slice-name]")
      if (!target || !draggedName) return

      const targetName = target.dataset.sliceName
      if (draggedName === targetName) return

      // Remove dragged from list and insert before target
      const filtered = orderedNames.filter((n) => n !== draggedName)
      const targetIdx = filtered.indexOf(targetName)
      filtered.splice(targetIdx, 0, draggedName)

      this.pushEvent("set_slice_order", { ordered_names: filtered })
    })
  },

  clearDropIndicators() {
    this.el
      .querySelectorAll(".border-t-2")
      .forEach((el) => el.classList.remove("border-t-2", "border-primary"))
  },
}

export default SliceReorder
