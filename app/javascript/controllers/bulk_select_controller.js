import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="bulk-select"
// Handles multi-select functionality for table rows
export default class extends Controller {
  static targets = ["actionBar", "count", "checkbox", "selectAll", "form", "hiddenInputs"]

  connect() {
    this.selectedIds = new Set()
    this.updateUI()
  }

  toggle(event) {
    const checkbox = event.currentTarget
    const id = checkbox.value

    if (checkbox.checked) {
      this.selectedIds.add(id)
    } else {
      this.selectedIds.delete(id)
    }

    this.updateUI()
  }

  toggleAll(event) {
    const checked = event.currentTarget.checked

    this.checkboxTargets.forEach(checkbox => {
      checkbox.checked = checked
      if (checked) {
        this.selectedIds.add(checkbox.value)
      } else {
        this.selectedIds.delete(checkbox.value)
      }
    })

    this.updateUI()
  }

  clearAll() {
    this.selectedIds.clear()

    this.checkboxTargets.forEach(checkbox => {
      checkbox.checked = false
    })

    if (this.hasSelectAllTarget) {
      this.selectAllTarget.checked = false
      this.selectAllTarget.indeterminate = false
    }

    this.updateUI()
  }

  deleteSelected(event) {
    if (this.selectedIds.size === 0) {
      event.preventDefault()
      return
    }

    // Update confirm message with actual count
    const count = this.selectedIds.size
    const confirmMessage = `Are you sure you want to delete ${count} node(s)? This action cannot be undone.`
    this.formTarget.dataset.turboConfirm = confirmMessage

    // Populate hidden inputs
    this.hiddenInputsTarget.innerHTML = ""
    this.selectedIds.forEach(id => {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = "node_ids[]"
      input.value = id
      this.hiddenInputsTarget.appendChild(input)
    })
  }

  updateUI() {
    this.updateActionBar()
    this.updateCount()
    this.updateSelectAllState()
  }

  updateActionBar() {
    if (!this.hasActionBarTarget) return

    const expandedClasses = (this.actionBarTarget.dataset.expandedClass || "").split(" ").filter(Boolean)
    const collapsedClasses = (this.actionBarTarget.dataset.collapsedClass || "").split(" ").filter(Boolean)

    if (this.selectedIds.size > 0) {
      // Expand: remove collapsed classes, add expanded classes
      this.actionBarTarget.classList.remove(...collapsedClasses)
      this.actionBarTarget.classList.add(...expandedClasses)
    } else {
      // Collapse: remove expanded classes, add collapsed classes
      this.actionBarTarget.classList.remove(...expandedClasses)
      this.actionBarTarget.classList.add(...collapsedClasses)
    }
  }

  updateCount() {
    if (!this.hasCountTarget) return

    const count = this.selectedIds.size
    this.countTarget.textContent = `${count} node(s) selected`
  }

  updateSelectAllState() {
    if (!this.hasSelectAllTarget) return

    const totalCount = this.checkboxTargets.length
    const selectedCount = this.selectedIds.size

    if (selectedCount === 0) {
      this.selectAllTarget.checked = false
      this.selectAllTarget.indeterminate = false
    } else if (selectedCount === totalCount) {
      this.selectAllTarget.checked = true
      this.selectAllTarget.indeterminate = false
    } else {
      this.selectAllTarget.checked = false
      this.selectAllTarget.indeterminate = true
    }
  }
}
