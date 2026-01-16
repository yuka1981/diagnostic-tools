import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="hostname-validation"
// Validates hostname and IP inputs in real-time, preventing localhost entries
export default class extends Controller {
  static targets = ["input", "error", "ipInput", "ipError", "submit"]
  static values = {
    localhostMessage: { type: String, default: "Localhost is not allowed. Please use a remote hostname or IP address." },
    ipLocalhostMessage: { type: String, default: "Localhost IP addresses (127.0.0.1, ::1) are not allowed." }
  }

  connect() {
    this.validate()
  }

  validate() {
    // Check hostname input
    const hostnameValue = this.hasInputTarget ? this.inputTarget.value.trim().toLowerCase() : ""
    const hostnameIsLocalhost = this.isLocalhost(hostnameValue)

    // Check IP input
    const ipValue = this.hasIpInputTarget ? this.ipInputTarget.value.trim().toLowerCase() : ""
    const ipIsLocalhost = this.isLocalhost(ipValue)

    // Handle hostname validation
    if (hostnameIsLocalhost) {
      this.showHostnameError()
    } else {
      this.hideHostnameError()
    }

    // Handle IP validation
    if (ipIsLocalhost) {
      this.showIpError()
    } else {
      this.hideIpError()
    }

    // Enable/disable submit based on both validations
    if (hostnameIsLocalhost || ipIsLocalhost) {
      this.disableSubmit()
    } else {
      this.enableSubmit()
    }
  }

  isLocalhost(value) {
    if (!value) return false
    return value === "localhost" || value === "127.0.0.1" || value === "::1"
  }

  showHostnameError() {
    if (this.hasErrorTarget) {
      this.errorTarget.textContent = this.localhostMessageValue
      this.errorTarget.classList.remove("hidden")
    }
    if (this.hasInputTarget) {
      this.markFieldAsError(this.inputTarget)
    }
  }

  hideHostnameError() {
    if (this.hasErrorTarget) {
      this.errorTarget.textContent = ""
      this.errorTarget.classList.add("hidden")
    }
    if (this.hasInputTarget) {
      this.clearFieldError(this.inputTarget)
    }
  }

  showIpError() {
    if (this.hasIpErrorTarget) {
      this.ipErrorTarget.textContent = this.ipLocalhostMessageValue
      this.ipErrorTarget.classList.remove("hidden")
    }
    if (this.hasIpInputTarget) {
      this.markFieldAsError(this.ipInputTarget)
    }
  }

  hideIpError() {
    if (this.hasIpErrorTarget) {
      this.ipErrorTarget.textContent = ""
      this.ipErrorTarget.classList.add("hidden")
    }
    if (this.hasIpInputTarget) {
      this.clearFieldError(this.ipInputTarget)
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

  disableSubmit() {
    if (this.hasSubmitTarget) {
      this.submitTarget.disabled = true
      this.submitTarget.classList.add("opacity-50", "cursor-not-allowed")
    }
  }

  enableSubmit() {
    if (this.hasSubmitTarget) {
      this.submitTarget.disabled = false
      this.submitTarget.classList.remove("opacity-50", "cursor-not-allowed")
    }
  }
}
