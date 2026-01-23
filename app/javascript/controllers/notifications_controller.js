import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dropdown", "frame"]
  static values = { userId: Number, loaded: { type: Boolean, default: false } }

  connect() {
    this.boundCloseOnClickOutside = this.closeOnClickOutside.bind(this)
    document.addEventListener("click", this.boundCloseOnClickOutside)
  }

  disconnect() {
    document.removeEventListener("click", this.boundCloseOnClickOutside)
  }

  toggle(event) {
    event.stopPropagation()
    const isHidden = this.dropdownTarget.classList.toggle("hidden")

    // Lazy-load notifications on first open
    if (!isHidden && !this.loadedValue && this.hasFrameTarget) {
      this.loadNotifications()
    }
  }

  loadNotifications() {
    this.frameTarget.src = "/notifications/dropdown"
    this.loadedValue = true
  }

  // Reload notifications (e.g., after mark all read)
  reload() {
    if (this.hasFrameTarget) {
      this.frameTarget.src = "/notifications/dropdown"
    }
  }

  close() {
    this.dropdownTarget.classList.add("hidden")
  }

  closeOnClickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.close()
    }
  }

  markAllRead(event) {
    event.preventDefault()
    event.stopPropagation()

    fetch("/notifications/mark_all_read", {
      method: "POST",
      headers: {
        "X-CSRF-Token": document.querySelector("[name='csrf-token']").content,
        "Accept": "text/vnd.turbo-stream.html"
      }
    }).then(() => {
      // Reload the notifications list after marking all read
      this.reload()
    })
  }
}
