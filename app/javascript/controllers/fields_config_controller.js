import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="fields-config"
// Handles the configurable fields dropdown for node preview cards on the rack show page.
// - Opens/closes dropdown on gear icon click
// - Closes on click outside
// - Saves checkbox changes to user preferences via PATCH /users/preferences
// - Reloads page after save to update display
export default class extends Controller {
  static targets = ["dropdown", "checkbox"]
  static values = {
    open: { type: Boolean, default: false }
  }

  connect() {
    // Bind the outside click handler so we can add/remove it
    this.handleOutsideClick = this.handleOutsideClick.bind(this)
  }

  disconnect() {
    // Clean up the event listener if the controller is disconnected
    document.removeEventListener("click", this.handleOutsideClick)
  }

  toggle(event) {
    event.stopPropagation()
    this.openValue = !this.openValue
  }

  openValueChanged() {
    if (this.hasDropdownTarget) {
      if (this.openValue) {
        this.dropdownTarget.classList.remove("hidden")
        // Add click outside listener when opening
        // Use setTimeout to avoid the current click from triggering close
        setTimeout(() => {
          document.addEventListener("click", this.handleOutsideClick)
        }, 0)
      } else {
        this.dropdownTarget.classList.add("hidden")
        document.removeEventListener("click", this.handleOutsideClick)
      }
    }
  }

  handleOutsideClick(event) {
    // Close if click is outside the controller element
    if (!this.element.contains(event.target)) {
      this.openValue = false
    }
  }

  // Prevent dropdown clicks from closing the dropdown
  stopPropagation(event) {
    event.stopPropagation()
  }

  // Save preferences when a checkbox changes
  async save() {
    const selectedFields = this.checkboxTargets
      .filter(checkbox => checkbox.checked)
      .map(checkbox => checkbox.value)

    try {
      const response = await fetch("/users/preferences", {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": this.csrfToken
        },
        body: JSON.stringify({ rack_node_preview_fields: selectedFields })
      })

      if (response.ok) {
        // Reload the page to reflect the changes
        window.location.reload()
      } else {
        console.error("Failed to save preferences")
      }
    } catch (error) {
      console.error("Error saving preferences:", error)
    }
  }

  // Reset to default fields
  async resetToDefaults() {
    const defaultFields = ["cpu", "ram", "storage", "network"]

    // Update checkboxes to reflect defaults
    this.checkboxTargets.forEach(checkbox => {
      checkbox.checked = defaultFields.includes(checkbox.value)
    })

    try {
      const response = await fetch("/users/preferences", {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": this.csrfToken
        },
        body: JSON.stringify({ rack_node_preview_fields: defaultFields })
      })

      if (response.ok) {
        // Reload the page to reflect the changes
        window.location.reload()
      } else {
        console.error("Failed to reset preferences")
      }
    } catch (error) {
      console.error("Error resetting preferences:", error)
    }
  }

  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }
}
