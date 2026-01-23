import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="ssh-override"
// Shows/hides SSH override fields based on checkbox state
// When checkbox is checked, the corresponding field is shown (node-level override)
// When checkbox is unchecked, the field is hidden (uses global default)
export default class extends Controller {
  static targets = ["checkbox", "field"]
  static values = { fieldName: String }

  connect() {
    this.toggle()
  }

  toggle() {
    if (!this.hasCheckboxTarget || !this.hasFieldTarget) return

    const isOverride = this.checkboxTarget.checked

    if (isOverride) {
      this.fieldTarget.classList.remove("hidden")
    } else {
      this.fieldTarget.classList.add("hidden")
    }
  }
}
