import { Controller } from "@hotwired/stimulus"

// Toast notification controller
// Displays temporary notification messages that auto-dismiss
//
// Usage from other controllers:
//   this.dispatch("show", { detail: { message: "Field cleared", type: "info" } })
//
// Or directly via custom event:
//   window.dispatchEvent(new CustomEvent("toast:show", { detail: { message: "...", type: "info" } }))
//
// Types: "success", "info", "warning", "error"
export default class extends Controller {
  static targets = ["container"]
  static values = {
    duration: { type: Number, default: 3000 }
  }

  connect() {
    // Register global toast function for use from other controllers
    window.showToast = this.show.bind(this)
    // Also listen for custom events
    this.boundShow = this.show.bind(this)
    window.addEventListener("toast:show", this.boundShow)
  }

  disconnect() {
    window.removeEventListener("toast:show", this.boundShow)
    delete window.showToast
  }

  show(event) {
    // Handle both direct calls and custom events
    const detail = event?.detail || event
    const { message, type = "info" } = detail

    if (!this.hasContainerTarget) {
      console.error("[Toast] Container target not found!")
      return
    }

    const toast = this.createToast(message, type)
    this.containerTarget.appendChild(toast)

    // Trigger enter animation
    requestAnimationFrame(() => {
      toast.classList.remove("translate-y-2", "opacity-0")
      toast.classList.add("translate-y-0", "opacity-100")
    })

    // Auto-dismiss
    setTimeout(() => this.dismiss(toast), this.durationValue)
  }

  dismiss(toast) {
    toast.classList.remove("translate-y-0", "opacity-100")
    toast.classList.add("translate-y-2", "opacity-0")

    setTimeout(() => toast.remove(), 150)
  }

  createToast(message, type) {
    const toast = document.createElement("div")
    toast.className = `flex items-center gap-3 px-4 py-3 rounded-md shadow-lg transform transition-all duration-150 translate-y-2 opacity-0 ${this.typeStyles(type)}`

    toast.innerHTML = `
      ${this.typeIcon(type)}
      <p class="text-sm font-medium">${this.escapeHtml(message)}</p>
      <button type="button" class="ml-auto -mr-1 p-1 rounded hover:bg-black/10" data-action="click->toast#dismissClick">
        <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
        </svg>
      </button>
    `

    return toast
  }

  dismissClick(event) {
    // Find the toast element (parent of the close button)
    const toast = event.target.closest(".flex.items-center.gap-3")
    if (toast) this.dismiss(toast)
  }

  typeStyles(type) {
    switch (type) {
      case "success":
        return "bg-emerald-50 text-emerald-800 border border-emerald-200"
      case "warning":
        return "bg-amber-50 text-amber-800 border border-amber-200"
      case "error":
        return "bg-red-50 text-red-800 border border-red-200"
      case "info":
      default:
        return "bg-blue-50 text-blue-800 border border-blue-200"
    }
  }

  typeIcon(type) {
    switch (type) {
      case "success":
        return '<svg class="h-5 w-5 text-emerald-500" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" /></svg>'
      case "warning":
        return '<svg class="h-5 w-5 text-amber-500" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" /></svg>'
      case "error":
        return '<svg class="h-5 w-5 text-red-500" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z" /></svg>'
      case "info":
      default:
        return '<svg class="h-5 w-5 text-blue-500" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" /></svg>'
    }
  }

  escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }
}
