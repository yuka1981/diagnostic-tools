import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["details"]
  static values = { id: Number, expanded: Boolean, read: Boolean }

  toggle(event) {
    if (event.target.tagName === "A") return

    this.expandedValue = !this.expandedValue
    this.detailsTarget.classList.toggle("hidden", !this.expandedValue)

    if (this.expandedValue && !this.readValue) {
      this.markAsRead()
    }
  }

  markAsRead() {
    fetch(`/notifications/${this.idValue}/mark_read`, {
      method: "POST",
      headers: {
        "X-CSRF-Token": document.querySelector("[name='csrf-token']").content,
        "Accept": "text/vnd.turbo-stream.html"
      }
    }).then(() => {
      this.readValue = true
    })
  }
}
