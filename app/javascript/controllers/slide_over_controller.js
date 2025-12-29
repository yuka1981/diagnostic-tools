import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="slide-over"
// Handles slide-over panel behavior with CSS transitions and accessibility
export default class extends Controller {
  static targets = ["panel", "backdrop", "content"]
  static values = {
    open: { type: Boolean, default: false }
  }

  connect() {
    // Bind keyboard handler for escape key
    this.boundHandleKeydown = this.handleKeydown.bind(this)
    document.addEventListener("keydown", this.boundHandleKeydown)
    
    // Initialize panel state
    if (this.openValue) {
      this.show()
    }
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundHandleKeydown)
  }

  open(event) {
    // Note: Don't call preventDefault() here to allow Turbo Frame navigation to proceed
    this.openValue = true
    this.show()
  }

  close(event) {
    event?.preventDefault()
    this.openValue = false
    this.hide()
  }

  toggle(event) {
    if (this.openValue) {
      this.close(event)
    } else {
      this.open(event)
    }
  }

  show() {
    // Show backdrop with fade-in
    if (this.hasBackdropTarget) {
      this.backdropTarget.classList.remove("hidden", "opacity-0")
      // Use requestAnimationFrame to ensure the hidden class is removed before adding opacity
      requestAnimationFrame(() => {
        this.backdropTarget.classList.add("opacity-100")
      })
    }

    // Slide panel in from right
    if (this.hasPanelTarget) {
      this.panelTarget.classList.remove("hidden", "translate-x-full")
      requestAnimationFrame(() => {
        this.panelTarget.classList.add("translate-x-0")
      })
    }

    // Prevent body scroll
    document.body.classList.add("overflow-hidden")
  }

  hide() {
    // Fade out backdrop
    if (this.hasBackdropTarget) {
      this.backdropTarget.classList.remove("opacity-100")
      this.backdropTarget.classList.add("opacity-0")
      // Hide completely after transition
      setTimeout(() => {
        if (!this.openValue) {
          this.backdropTarget.classList.add("hidden")
        }
      }, 300)
    }

    // Slide panel out to right
    if (this.hasPanelTarget) {
      this.panelTarget.classList.remove("translate-x-0")
      this.panelTarget.classList.add("translate-x-full")
      // Hide completely after transition
      setTimeout(() => {
        if (!this.openValue) {
          this.panelTarget.classList.add("hidden")
        }
      }, 300)
    }

    // Re-enable body scroll
    document.body.classList.remove("overflow-hidden")
  }

  handleKeydown(event) {
    if (event.key === "Escape" && this.openValue) {
      this.close(event)
    }
  }

  // Handle clicking on backdrop
  backdropClick(event) {
    if (event.target === this.backdropTarget) {
      this.close(event)
    }
  }
}

