import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="slide-over"
// Handles slide-over panel behavior with CSS transitions and accessibility
export default class extends Controller {
  static targets = ["panel", "backdrop", "content", "closeButton", "modalContent"]
  static values = {
    open: { type: Boolean, default: false }
  }

  connect() {
    // Bind keyboard handler for escape key and focus trapping
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

    // Show modal with scale and fade-in animation
    if (this.hasPanelTarget) {
      this.panelTarget.classList.remove("hidden", "opacity-0", "scale-95")
      requestAnimationFrame(() => {
        this.panelTarget.classList.add("opacity-100", "scale-100")
      })
    }

    // Prevent body scroll
    document.body.classList.add("overflow-hidden")

    // Set initial focus on close button for accessibility
    requestAnimationFrame(() => {
      if (this.hasCloseButtonTarget) {
        this.closeButtonTarget.focus()
      }
    })
  }

  hide() {
    // Fade out backdrop
    if (this.hasBackdropTarget) {
      this.backdropTarget.classList.remove("opacity-100")
      this.backdropTarget.classList.add("opacity-0")
    }

    // Scale down and fade out modal, then hide after transition completes
    if (this.hasPanelTarget) {
      const onTransitionEnd = () => {
        if (!this.openValue) {
          this.panelTarget.classList.add("hidden")
          if (this.hasBackdropTarget) {
            this.backdropTarget.classList.add("hidden")
          }
        }
        this.panelTarget.removeEventListener("transitionend", onTransitionEnd)
      }
      this.panelTarget.addEventListener("transitionend", onTransitionEnd)

      this.panelTarget.classList.remove("opacity-100", "scale-100")
      this.panelTarget.classList.add("opacity-0", "scale-95")
    }

    // Re-enable body scroll
    document.body.classList.remove("overflow-hidden")
  }

  handleKeydown(event) {
    if (!this.openValue) return

    // Handle Escape key to close
    if (event.key === "Escape") {
      this.close(event)
      return
    }

    // Handle Tab key for focus trapping
    if (event.key === "Tab" && this.hasPanelTarget) {
      this.trapFocus(event)
    }
  }

  trapFocus(event) {
    const focusableElements = Array.from(
      this.panelTarget.querySelectorAll(
        'a[href], button:not([disabled]), textarea, input, select, [tabindex]:not([tabindex="-1"])'
      )
    )

    if (focusableElements.length === 0) return

    const firstElement = focusableElements[0]
    const lastElement = focusableElements[focusableElements.length - 1]

    if (event.shiftKey) {
      // Shift + Tab: if on first element, wrap to last
      if (document.activeElement === firstElement) {
        lastElement.focus()
        event.preventDefault()
      }
    } else {
      // Tab: if on last element, wrap to first
      if (document.activeElement === lastElement) {
        firstElement.focus()
        event.preventDefault()
      }
    }
  }

  // Handle clicking on backdrop
  backdropClick(event) {
    if (event.target === this.backdropTarget) {
      this.close(event)
    }
  }

  // Handle clicking on the panel wrapper (for centered modal)
  // Close if click is outside the modal content
  panelClick(event) {
    if (this.hasModalContentTarget && !this.modalContentTarget.contains(event.target)) {
      this.close(event)
    }
  }
}
