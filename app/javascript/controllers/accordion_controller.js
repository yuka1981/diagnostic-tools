import { Controller } from "@hotwired/stimulus"

// Handles accordion row expansion in tables
// Usage:
//   <div data-controller="accordion">
//     <tr data-accordion-target="row" data-action="click->accordion#toggle">
//     <tr data-accordion-target="details" class="hidden">
export default class extends Controller {
  static targets = ["row", "details", "chevron"]
  static values = {
    open: { type: Boolean, default: false },
    exclusive: { type: Boolean, default: true }
  }

  toggle(event) {
    // Don't toggle if clicking on buttons or links
    if (event.target.closest("button, a, [data-no-toggle]")) {
      return
    }

    const row = event.currentTarget
    const index = this.rowTargets.indexOf(row)

    if (index === -1) return

    const details = this.detailsTargets[index]
    const chevron = this.chevronTargets[index]
    const gridWrapper = details.querySelector(".grid")
    const isCurrentlyOpen = gridWrapper?.classList.contains("grid-rows-[1fr]") ?? false

    // Close all if exclusive mode
    if (this.exclusiveValue && !isCurrentlyOpen) {
      this.closeAll()
    }

    // Toggle current
    if (gridWrapper) {
      gridWrapper.classList.toggle("grid-rows-[1fr]", !isCurrentlyOpen)
      gridWrapper.classList.toggle("grid-rows-[0fr]", isCurrentlyOpen)
    }
    if (chevron) {
      chevron.classList.toggle("rotate-90", !isCurrentlyOpen)
    }
    row.classList.toggle("bg-slate-50", !isCurrentlyOpen)
  }

  closeAll() {
    this.detailsTargets.forEach((details, index) => {
      const gridWrapper = details.querySelector(".grid")
      if (gridWrapper) {
        gridWrapper.classList.remove("grid-rows-[1fr]")
        gridWrapper.classList.add("grid-rows-[0fr]")
      }
      const chevron = this.chevronTargets[index]
      if (chevron) {
        chevron.classList.remove("rotate-90")
      }
      this.rowTargets[index]?.classList.remove("bg-slate-50")
    })
  }
}
