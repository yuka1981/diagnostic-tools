import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="theme"
// Handles dark mode toggle with localStorage persistence
export default class extends Controller {
  static targets = ["sunIcon", "moonIcon", "label"]

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
    // Toggle icon visibility using class (safer than innerHTML)
    if (this.hasSunIconTarget && this.hasMoonIconTarget) {
      if (isDark) {
        this.sunIconTarget.classList.remove("hidden")
        this.moonIconTarget.classList.add("hidden")
      } else {
        this.sunIconTarget.classList.add("hidden")
        this.moonIconTarget.classList.remove("hidden")
      }
    }

    if (this.hasLabelTarget) {
      this.labelTarget.textContent = isDark ? "Light Mode" : "Dark Mode"
    }
  }
}
