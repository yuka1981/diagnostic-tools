import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dropdown"]
  static values = { userId: Number }

  connect() {
    this.boundCloseOnClickOutside = this.closeOnClickOutside.bind(this)
    document.addEventListener("click", this.boundCloseOnClickOutside)
  }

  disconnect() {
    document.removeEventListener("click", this.boundCloseOnClickOutside)
  }

  toggle(event) {
    event.stopPropagation()
    this.dropdownTarget.classList.toggle("hidden")
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
    })
  }
}
