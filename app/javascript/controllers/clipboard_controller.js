import { Controller } from "@hotwired/stimulus"

// Clipboard controller for copying text to clipboard
// Usage:
//   <div data-controller="clipboard">
//     <span data-clipboard-target="source" class="hidden">full text to copy</span>
//     <button data-action="click->clipboard#copy">
//       <svg data-clipboard-target="icon">...</svg>
//       <svg data-clipboard-target="success" class="hidden">...</svg>
//     </button>
//   </div>
export default class extends Controller {
  static targets = ["source", "icon", "success"]
  static values = {
    resetDelay: { type: Number, default: 2000 }
  }

  async copy(event) {
    event.preventDefault()

    const text = this.sourceTarget.textContent.trim()

    try {
      await navigator.clipboard.writeText(text)
      this.showSuccess()
    } catch (err) {
      // Fallback for older browsers or when clipboard API fails
      this.fallbackCopy(text)
    }
  }

  fallbackCopy(text) {
    const textArea = document.createElement("textarea")
    textArea.value = text
    textArea.style.position = "fixed"
    textArea.style.left = "-9999px"
    document.body.appendChild(textArea)
    textArea.select()

    try {
      document.execCommand("copy")
      this.showSuccess()
    } catch (err) {
      console.error("Failed to copy text:", err)
    }

    document.body.removeChild(textArea)
  }

  showSuccess() {
    // Hide copy icon, show success icon
    if (this.hasIconTarget) {
      this.iconTarget.classList.add("hidden")
    }
    if (this.hasSuccessTarget) {
      this.successTarget.classList.remove("hidden")
    }

    // Reset after delay
    setTimeout(() => {
      this.resetState()
    }, this.resetDelayValue)
  }

  resetState() {
    if (this.hasIconTarget) {
      this.iconTarget.classList.remove("hidden")
    }
    if (this.hasSuccessTarget) {
      this.successTarget.classList.add("hidden")
    }
  }
}
