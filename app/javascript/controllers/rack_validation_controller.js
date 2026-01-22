import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="rack-validation"
// Validates rack position and height on blur to check for overlaps with existing nodes
// Calls the server-side validation API with debouncing
export default class extends Controller {
  static targets = ["rackSelect", "positionInput", "heightInput", "error"]
  static values = {
    nodeId: { type: String, default: "" }
  }

  // Debounce delay in milliseconds
  static DEBOUNCE_DELAY = 300

  connect() {
    this.debounceTimer = null
    this.abortController = null
  }

  disconnect() {
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer)
    }
    if (this.abortController) {
      this.abortController.abort()
    }
  }

  // Called on blur or change of rack fields - triggers server-side validation with debounce
  validateOnBlur() {
    // Clear any pending debounce timer
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer)
    }

    // Set up debounced API call
    this.debounceTimer = setTimeout(() => {
      this.performServerValidation()
    }, this.constructor.DEBOUNCE_DELAY)
  }

  // Performs server-side rack position validation via API
  async performServerValidation() {
    const rackId = this.hasRackSelectTarget ? this.rackSelectTarget.value : ""
    const position = this.hasPositionInputTarget ? this.positionInputTarget.value : ""
    const height = this.hasHeightInputTarget ? this.heightInputTarget.value : ""

    // Skip validation if no rack is selected or position is empty
    if (!rackId || !position) {
      this.hideError()
      return
    }

    // Cancel any pending request
    if (this.abortController) {
      this.abortController.abort()
    }
    this.abortController = new AbortController()

    try {
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
      if (!csrfToken) {
        console.warn("CSRF token not found, skipping server validation")
        return
      }

      const body = {
        node: {
          rack_id: rackId,
          rack_position: position,
          rack_height: height || 1
        }
      }

      // Include node ID for edit mode to exclude self from overlap check
      if (this.nodeIdValue) {
        body.node.id = this.nodeIdValue
      }

      const response = await fetch("/api/nodes/validate", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken
        },
        body: JSON.stringify(body),
        signal: this.abortController.signal
      })

      if (!response.ok) {
        console.error("Rack validation API error:", response.status)
        return
      }

      const data = await response.json()

      // Check for base errors (overlap errors) or rack_position errors
      const baseErrors = data.errors?.base || []
      const positionErrors = data.errors?.rack_position || []
      const allErrors = [...baseErrors, ...positionErrors]

      if (!data.valid && allErrors.length > 0) {
        this.showError(allErrors.join(", "))
      } else {
        this.hideError()
      }
    } catch (error) {
      if (error.name !== 'AbortError') {
        console.error("Server-side rack validation failed:", error)
      }
    }
  }

  showError(message) {
    if (this.hasErrorTarget) {
      this.errorTarget.textContent = message
      this.errorTarget.classList.remove("hidden")
    }
    if (this.hasPositionInputTarget) {
      this.markFieldAsError(this.positionInputTarget)
    }
  }

  hideError() {
    if (this.hasErrorTarget) {
      this.errorTarget.textContent = ""
      this.errorTarget.classList.add("hidden")
    }
    if (this.hasPositionInputTarget) {
      this.clearFieldError(this.positionInputTarget)
    }
  }

  markFieldAsError(field) {
    field.classList.add("border-red-500", "focus:border-red-500", "focus:ring-red-500")
    field.classList.remove("border-slate-300", "focus:border-teal-500", "focus:ring-teal-500")
  }

  clearFieldError(field) {
    field.classList.remove("border-red-500", "focus:border-red-500", "focus:ring-red-500")
    field.classList.add("border-slate-300", "focus:border-teal-500", "focus:ring-teal-500")
  }
}
