import { Controller } from "@hotwired/stimulus"

// Simple collapsible controller for toggling content visibility
export default class extends Controller {
  static targets = ["content", "icon"]
  static values = { open: { type: Boolean, default: false } }

  connect() {
    this.updateVisibility()
  }

  toggle() {
    this.openValue = !this.openValue
    this.updateVisibility()
  }

  updateVisibility() {
    if (this.hasContentTarget) {
      this.contentTarget.classList.toggle("hidden", !this.openValue)
    }

    if (this.hasIconTarget) {
      this.iconTarget.classList.toggle("rotate-180", this.openValue)
    }
  }
}
