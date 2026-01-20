import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="node-preview"
// Shows a preview card on hover (desktop) or tap (touch devices) for nodes in rack elevation view
export default class extends Controller {
  static values = {
    hostname: String,
    position: String,
    height: String,
    cpu: String,
    ram: String,
    url: String
  }

  connect() {
    this.isTouch = "ontouchstart" in window
    this.hoverTimeout = null
    this.card = null
  }

  // Desktop: show on mouseenter after 200ms delay
  mouseEnter() {
    if (this.isTouch) return
    this.hoverTimeout = setTimeout(() => this.showCard(), 200)
  }

  mouseLeave() {
    clearTimeout(this.hoverTimeout)
    this.hideCard()
  }

  // Touch: show on click
  click(event) {
    if (!this.isTouch) return
    event.preventDefault()
    event.stopPropagation()
    this.showCard()
  }

  showCard() {
    // Remove any existing cards first
    this.hideCard()

    // Create card HTML
    const card = document.createElement("div")
    card.className = "node-preview-card absolute z-50 bg-white border border-slate-200 rounded-lg shadow-lg p-3 text-sm"
    card.style.width = "200px"

    card.innerHTML = `
      <div class="font-bold text-slate-900 mb-1">${this.hostnameValue}</div>
      <div class="text-xs text-slate-500 mb-2">${this.positionValue} (${this.heightValue})</div>
      ${this.cpuValue ? `<div class="text-xs text-slate-600 mb-1"><span class="font-medium">CPU</span> ${this.cpuValue}</div>` : ""}
      ${this.ramValue ? `<div class="text-xs text-slate-600 mb-1"><span class="font-medium">RAM</span> ${this.ramValue}</div>` : ""}
      ${this.urlValue ? `<a href="${this.urlValue}" class="inline-block mt-2 text-xs text-teal-600 hover:text-teal-700 font-medium">View Node →</a>` : ""}
      ${this.isTouch ? '<button type="button" class="absolute top-1 right-1 text-slate-400 hover:text-slate-600" data-action="click->node-preview#hideCard">×</button>' : ""}
    `

    // Position the card (to the right of the element, or left if near edge)
    const rect = this.element.getBoundingClientRect()

    card.style.position = "fixed"
    card.style.top = `${rect.top}px`

    // Check if we're near the right edge
    if (rect.right + 220 > window.innerWidth) {
      card.style.left = `${rect.left - 210}px`
    } else {
      card.style.left = `${rect.right + 10}px`
    }

    this.card = card
    document.body.appendChild(card)

    // For touch devices, add click-outside listener
    if (this.isTouch) {
      this.boundClickOutside = this.clickOutside.bind(this)
      document.addEventListener("click", this.boundClickOutside, true)
    }
  }

  hideCard() {
    if (this.card) {
      this.card.remove()
      this.card = null
    }
    if (this.boundClickOutside) {
      document.removeEventListener("click", this.boundClickOutside, true)
      this.boundClickOutside = null
    }
  }

  clickOutside(event) {
    if (this.card && !this.card.contains(event.target) && !this.element.contains(event.target)) {
      this.hideCard()
    }
  }

  disconnect() {
    this.hideCard()
    clearTimeout(this.hoverTimeout)
  }
}
