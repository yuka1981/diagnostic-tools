import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="bulk-review"
// Handles inline editing of nodes in bulk review mode
export default class extends Controller {
  static targets = ["row", "editForm", "displayRow", "overridesField"]
  static values = { overrides: { type: Object, default: {} } }

  connect() {
    this.editing = null
  }

  edit(event) {
    const hostname = event.currentTarget.dataset.hostname
    const row = this.rowTargets.find(r => r.dataset.hostname === hostname)

    if (!row) return

    // Close any existing edit
    if (this.editing) {
      this.cancelEdit({ currentTarget: { dataset: { hostname: this.editing } } })
    }

    // Show edit form, hide display
    const editForm = row.querySelector("[data-bulk-review-target='editForm']")
    const displayRow = row.querySelector("[data-bulk-review-target='displayRow']")

    if (editForm) editForm.classList.remove("hidden")
    if (displayRow) displayRow.classList.add("hidden")

    this.editing = hostname
  }

  saveEdit(event) {
    const hostname = event.currentTarget.dataset.hostname
    const row = this.rowTargets.find(r => r.dataset.hostname === hostname)

    if (!row) return

    // Collect form values
    const override = {}
    row.querySelectorAll("[data-override-field]").forEach(field => {
      const key = field.dataset.overrideField
      const value = field.value
      if (value) override[key] = value
    })

    // Store override
    this.overridesValue = { ...this.overridesValue, [hostname]: override }
    this.updateOverridesField()

    // Update display and close edit
    this.updateRowDisplay(row, override)
    this.cancelEdit(event)
  }

  cancelEdit(event) {
    const hostname = event.currentTarget.dataset.hostname
    const row = this.rowTargets.find(r => r.dataset.hostname === hostname)

    if (!row) return

    const editForm = row.querySelector("[data-bulk-review-target='editForm']")
    const displayRow = row.querySelector("[data-bulk-review-target='displayRow']")

    if (editForm) editForm.classList.add("hidden")
    if (displayRow) displayRow.classList.remove("hidden")

    this.editing = null
  }

  updateRowDisplay(row, override) {
    Object.entries(override).forEach(([key, value]) => {
      const cell = row.querySelector(`[data-display-field="${key}"]`)
      if (cell) cell.textContent = value
    })
  }

  updateOverridesField() {
    if (this.hasOverridesFieldTarget) {
      this.overridesFieldTarget.value = JSON.stringify(this.overridesValue)
    }
  }
}
