import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="filter-form"
export default class extends Controller {
  static targets = ["input", "clearButton"]
  static values = {
    clearUrl: String
  }

  connect() {
    this.updateClearButton()
  }

  updateClearButton() {
    const hasFilter = this.inputTargets.some(input => input.value.trim() !== "")
    
    if (hasFilter) {
      this.enableClearButton()
    } else {
      this.disableClearButton()
    }
  }

  enableClearButton() {
    this.clearButtonTarget.classList.remove("text-gray-400", "cursor-not-allowed", "pointer-events-none")
    this.clearButtonTarget.classList.add("text-gray-600", "hover:text-gray-900", "hover:bg-gray-100", "dark:text-slate-400", "dark:hover:text-white", "dark:hover:bg-white/10")
    if (!this.clearButtonTarget.getAttribute("href")) {
      this.clearButtonTarget.setAttribute("href", this.clearUrlValue)
    }
  }

  disableClearButton() {
    this.clearButtonTarget.classList.add("text-gray-400", "cursor-not-allowed", "pointer-events-none")
    this.clearButtonTarget.classList.remove("text-gray-600", "hover:text-gray-900", "hover:bg-gray-100", "dark:text-slate-400", "dark:hover:text-white", "dark:hover:bg-white/10")
    this.clearButtonTarget.removeAttribute("href")
  }
}
