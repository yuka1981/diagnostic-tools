import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "content", "button" ]
  static values = { visible: { type: Boolean, default: true } }

  connect() {
    this.updateVisibility()
  }

  toggle() {
    this.visibleValue = !this.visibleValue
  }

  visibleValueChanged() {
    this.updateVisibility()
  }

  updateVisibility() {
    if (this.hasContentTarget) {
      this.contentTarget.style.display = this.visibleValue ? "" : "none"
    }

    if (this.hasButtonTarget) {
      const dot = this.buttonTarget.querySelector("span")
      
      if (this.visibleValue) {
        this.buttonTarget.classList.remove("bg-neutral-8")
        this.buttonTarget.classList.add("bg-primary-6")
        this.buttonTarget.setAttribute("aria-checked", "true")
        if (dot) {
          dot.classList.remove("translate-x-0")
          dot.classList.add("translate-x-4")
        }
      } else {
        this.buttonTarget.classList.remove("bg-primary-6")
        this.buttonTarget.classList.add("bg-neutral-8")
        this.buttonTarget.setAttribute("aria-checked", "false")
        if (dot) {
          dot.classList.remove("translate-x-4")
          dot.classList.add("translate-x-0")
        }
      }
    }
  }
}
