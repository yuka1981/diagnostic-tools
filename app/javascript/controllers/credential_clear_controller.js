import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="credential-clear"
// Handles clearing credential fields (passwords, SSH keys) with confirmation
// When the clear button is clicked:
// - Shows a confirmation dialog
// - Sets a hidden flag to mark the credential for deletion on save
// - Clears the field value and shows visual feedback
// - Shows a toast notification
export default class extends Controller {
  static targets = ["clearButton", "field", "clearedIndicator", "clearFlag"]
  static values = {
    confirmMessage: { type: String, default: "Are you sure you want to clear this credential?" },
    fieldName: { type: String, default: "Credential" }
  }

  clear(event) {
    event.preventDefault()

    if (!confirm(this.confirmMessageValue)) {
      return
    }

    // Set the hidden flag to mark credential for deletion
    if (this.hasClearFlagTarget) {
      this.clearFlagTarget.value = "1"
    }

    // Clear the actual field value
    if (this.hasFieldTarget) {
      this.fieldTarget.value = ""
      // For password fields, also clear the placeholder to indicate it's empty
      if (this.fieldTarget.type === "password") {
        this.fieldTarget.placeholder = ""
      }
      // Disable the field to prevent re-entry before save
      this.fieldTarget.disabled = true
      this.fieldTarget.classList.add("bg-slate-100", "cursor-not-allowed")
    }

    // Hide the clear button
    if (this.hasClearButtonTarget) {
      this.clearButtonTarget.classList.add("hidden")
    }

    // Show the cleared indicator
    if (this.hasClearedIndicatorTarget) {
      this.clearedIndicatorTarget.classList.remove("hidden")
    }

    // Show toast notification
    this.showToast(`${this.fieldNameValue} will be cleared on save`)
  }

  showToast(message) {
    // Try global function first (more reliable), fall back to custom event
    if (typeof window.showToast === "function") {
      window.showToast({ message: message, type: "info" })
    } else {
      window.dispatchEvent(new CustomEvent("toast:show", {
        detail: { message: message, type: "info" }
      }))
    }
  }

  // Allow resetting/undoing the clear action before save
  undo(event) {
    event.preventDefault()

    // Reset the hidden flag
    if (this.hasClearFlagTarget) {
      this.clearFlagTarget.value = ""
    }

    // Re-enable the field
    if (this.hasFieldTarget) {
      this.fieldTarget.disabled = false
      this.fieldTarget.classList.remove("bg-slate-100", "cursor-not-allowed")
    }

    // Show the clear button again
    if (this.hasClearButtonTarget) {
      this.clearButtonTarget.classList.remove("hidden")
    }

    // Hide the cleared indicator
    if (this.hasClearedIndicatorTarget) {
      this.clearedIndicatorTarget.classList.add("hidden")
    }
  }
}
