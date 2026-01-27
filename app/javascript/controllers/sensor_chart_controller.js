import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["chart", "rangeButton"]
  static values = { range: { type: String, default: "24h" } }

  connect() {
    // Charts are rendered server-side via Chartkick
    // This controller handles any client-side interactions
  }

  selectRange(event) {
    event.preventDefault()
    const range = event.currentTarget.dataset.range
    this.rangeValue = range

    // Update button states
    this.rangeButtonTargets.forEach(btn => {
      const isActive = btn.dataset.range === range
      btn.classList.toggle("bg-primary-6", isActive)
      btn.classList.toggle("text-white", isActive)
      btn.classList.toggle("bg-neutral-4", !isActive)
      btn.classList.toggle("text-neutral-45", !isActive)
    })
  }
}
