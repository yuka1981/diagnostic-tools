import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="modal"
// Handles modal close on escape key or backdrop click
export default class extends Controller {
  connect() {
    // Prevent body scroll when modal is open
    document.body.classList.add("overflow-hidden")
  }

  disconnect() {
    // Restore body scroll when modal closes
    document.body.classList.remove("overflow-hidden")
  }

  close(event) {
    // Navigate back to close the modal via turbo
    const frame = this.element.closest("turbo-frame")
    if (frame) {
      frame.innerHTML = ""
    }
    document.body.classList.remove("overflow-hidden")
  }
}

