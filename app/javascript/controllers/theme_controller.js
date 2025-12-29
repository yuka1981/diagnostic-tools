import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="theme"
// Handles dark mode toggle with localStorage persistence
export default class extends Controller {
  static targets = ["icon", "label"]

  connect() {
    this.applyStoredTheme()
  }

  toggle() {
    const isDark = document.documentElement.classList.toggle("dark")
    this.updateStorage(isDark)
    this.updateUI(isDark)
  }

  applyStoredTheme() {
    const stored = localStorage.getItem("theme")
    const prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches
    const isDark = stored === "dark" || (!stored && prefersDark)

    if (isDark) {
      document.documentElement.classList.add("dark")
    } else {
      document.documentElement.classList.remove("dark")
    }

    this.updateUI(isDark)
  }

  updateStorage(isDark) {
    localStorage.setItem("theme", isDark ? "dark" : "light")
  }

  updateUI(isDark) {
    if (this.hasIconTarget) {
      // Update icon based on current theme
      this.iconTarget.innerHTML = isDark ? this.sunIcon : this.moonIcon
    }

    if (this.hasLabelTarget) {
      this.labelTarget.textContent = isDark ? "Light Mode" : "Dark Mode"
    }
  }

  get sunIcon() {
    return `<svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" 
        d="M12 3v1m0 16v1m9-9h-1M4 12H3m15.364 6.364l-.707-.707M6.343 6.343l-.707-.707m12.728 0l-.707.707M6.343 17.657l-.707.707M16 12a4 4 0 11-8 0 4 4 0 018 0z" />
    </svg>`
  }

  get moonIcon() {
    return `<svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" 
        d="M20.354 15.354A9 9 0 018.646 3.646 9.003 9.003 0 0012 21a9.003 9.003 0 008.354-5.646z" />
    </svg>`
  }
}

