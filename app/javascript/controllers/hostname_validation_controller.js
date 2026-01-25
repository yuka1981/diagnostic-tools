import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="hostname-validation"
// Validates hostname and IP inputs in real-time, preventing localhost entries and invalid IPs
// Also performs server-side validation for hostname uniqueness via API
export default class extends Controller {
  static targets = ["input", "error", "ipInput", "ipError", "submit"]
  static values = {
    nodeId: { type: String, default: "" },
    localhostMessage: { type: String, default: "Localhost is not allowed. Please use a remote hostname or IP address." },
    ipLocalhostMessage: { type: String, default: "Localhost IP addresses (127.0.0.1, ::1) are not allowed." },
    ipInvalidMessage: { type: String, default: "Please enter a valid IPv4 or IPv6 address." }
  }

  // IPv4 pattern: 0-255 for each octet
  static IPV4_PATTERN = /^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/

  // IPv6 pattern: supports full, compressed, and mixed formats
  static IPV6_PATTERN = /^(?:(?:[0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}|(?:[0-9a-fA-F]{1,4}:){1,7}:|(?:[0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|(?:[0-9a-fA-F]{1,4}:){1,5}(?::[0-9a-fA-F]{1,4}){1,2}|(?:[0-9a-fA-F]{1,4}:){1,4}(?::[0-9a-fA-F]{1,4}){1,3}|(?:[0-9a-fA-F]{1,4}:){1,3}(?::[0-9a-fA-F]{1,4}){1,4}|(?:[0-9a-fA-F]{1,4}:){1,2}(?::[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:(?::[0-9a-fA-F]{1,4}){1,6}|:(?::[0-9a-fA-F]{1,4}){1,7}|::)$/

  // Debounce delay in milliseconds
  static DEBOUNCE_DELAY = 300

  connect() {
    this.debounceTimer = null
    this.abortController = null
    this.validate()
  }

  disconnect() {
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer)
    }
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
      this.showHostnameError(this.localhostMessageValue)
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

  // Called on blur of hostname field - triggers server-side validation with debounce
  validateHostnameOnBlur() {
    // Clear any pending debounce timer
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer)
    }

    // Set up debounced API call
    this.debounceTimer = setTimeout(() => {
      this.performServerValidation()
    }, this.constructor.DEBOUNCE_DELAY)
  }

  // Performs server-side hostname validation via API
  async performServerValidation() {
    const hostnameValue = this.hasInputTarget ? this.inputTarget.value.trim() : ""

    // Skip validation if hostname is empty or is localhost (already handled client-side)
    if (!hostnameValue || this.isLocalhost(hostnameValue.toLowerCase())) {
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
          hostname: hostnameValue
        }
      }

      // Include node ID for edit mode to exclude self from uniqueness check
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
        console.error("Hostname validation API error:", response.status)
        return
      }

      const data = await response.json()

      if (!data.valid && data.errors?.hostname) {
        this.showHostnameError(data.errors.hostname.join(", "))
        this.disableSubmit()
      } else {
        // Only clear error if there's no client-side localhost error
        const currentHostname = this.hasInputTarget ? this.inputTarget.value.trim().toLowerCase() : ""
        if (!this.isLocalhost(currentHostname)) {
          this.hideHostnameError()
          // Re-run full validation to check IP field state before enabling submit
          this.updateSubmitState()
        }
      }
    } catch (error) {
      if (error.name !== 'AbortError') {
        console.error("Server-side hostname validation failed:", error)
      }
    }
  }

  // Updates submit button state based on current validation state
  updateSubmitState() {
    const hostnameValue = this.hasInputTarget ? this.inputTarget.value.trim().toLowerCase() : ""
    const ipValue = this.hasIpInputTarget ? this.ipInputTarget.value.trim() : ""
    const ipIsLocalhost = this.isLocalhost(ipValue.toLowerCase())
    const ipIsInvalid = ipValue !== "" && !this.isValidIp(ipValue)

    // Check if there's a visible hostname error
    const hasHostnameError = this.hasErrorTarget && !this.errorTarget.classList.contains("hidden")

    if (this.isLocalhost(hostnameValue) || ipIsLocalhost || ipIsInvalid || hasHostnameError) {
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

  showHostnameError(message) {
    if (this.hasErrorTarget) {
      this.errorTarget.textContent = message
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
    field.classList.add("border-error-5", "focus:border-error-5", "focus:ring-error-5")
    field.classList.remove("border-neutral-15", "focus:border-primary-5", "focus:ring-primary-5")
  }

  clearFieldError(field) {
    field.classList.remove("border-error-5", "focus:border-error-5", "focus:ring-error-5")
    field.classList.add("border-neutral-15", "focus:border-primary-5", "focus:ring-primary-5")
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
