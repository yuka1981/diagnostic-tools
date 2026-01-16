import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="hostname-validation"
// Validates hostname and IP inputs in real-time, preventing localhost entries and invalid IPs
export default class extends Controller {
  static targets = ["input", "error", "ipInput", "ipError", "submit"]
  static values = {
    localhostMessage: { type: String, default: "Localhost is not allowed. Please use a remote hostname or IP address." },
    ipLocalhostMessage: { type: String, default: "Localhost IP addresses (127.0.0.1, ::1) are not allowed." },
    ipInvalidMessage: { type: String, default: "Please enter a valid IPv4 or IPv6 address." }
  }

  // IPv4 pattern: 0-255 for each octet
  static IPV4_PATTERN = /^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/

  // IPv6 pattern: supports full, compressed, and mixed formats
  static IPV6_PATTERN = /^(?:(?:[0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}|(?:[0-9a-fA-F]{1,4}:){1,7}:|(?:[0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|(?:[0-9a-fA-F]{1,4}:){1,5}(?::[0-9a-fA-F]{1,4}){1,2}|(?:[0-9a-fA-F]{1,4}:){1,4}(?::[0-9a-fA-F]{1,4}){1,3}|(?:[0-9a-fA-F]{1,4}:){1,3}(?::[0-9a-fA-F]{1,4}){1,4}|(?:[0-9a-fA-F]{1,4}:){1,2}(?::[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:(?::[0-9a-fA-F]{1,4}){1,6}|:(?::[0-9a-fA-F]{1,4}){1,7}|::)$/

  connect() {
    this.validate()
  }

  validate() {
    // Check hostname input
    const hostnameValue = this.hasInputTarget ? this.inputTarget.value.trim().toLowerCase() : ""
    const hostnameIsLocalhost = this.isLocalhost(hostnameValue)

    // Check IP input
    const ipValue = this.hasIpInputTarget ? this.ipInputTarget.value.trim() : ""
    const ipIsLocalhost = this.isLocalhost(ipValue.toLowerCase())
    const ipIsInvalid = ipValue !== "" && !this.isValidIp(ipValue)

    // Handle hostname validation
    if (hostnameIsLocalhost) {
      this.showHostnameError()
    } else {
      this.hideHostnameError()
    }

    // Handle IP validation - localhost takes priority over invalid format
    if (ipIsLocalhost) {
      this.showIpError(this.ipLocalhostMessageValue)
    } else if (ipIsInvalid) {
      this.showIpError(this.ipInvalidMessageValue)
    } else {
      this.hideIpError()
    }

    // Enable/disable submit based on all validations
    if (hostnameIsLocalhost || ipIsLocalhost || ipIsInvalid) {
      this.disableSubmit()
    } else {
      this.enableSubmit()
    }
  }

  isValidIp(value) {
    if (!value) return true // Empty is valid (field is optional)
    return this.constructor.IPV4_PATTERN.test(value) || this.constructor.IPV6_PATTERN.test(value)
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

  showIpError(message) {
    if (this.hasIpErrorTarget) {
      this.ipErrorTarget.textContent = message
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
