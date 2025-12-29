import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="tabs"
// Handles tab navigation with ARIA support
export default class extends Controller {
  static targets = ["tab", "panel"]
  static values = {
    activeIndex: { type: Number, default: 0 }
  }

  connect() {
    this.showTab(this.activeIndexValue)
  }

  select(event) {
    event.preventDefault()
    const index = this.tabTargets.indexOf(event.currentTarget)
    if (index !== -1) {
      this.activeIndexValue = index
      this.showTab(index)
    }
  }

  showTab(index) {
    // Update tab states
    this.tabTargets.forEach((tab, i) => {
      const isActive = i === index
      tab.setAttribute("aria-selected", isActive)
      tab.setAttribute("tabindex", isActive ? "0" : "-1")
      
      if (isActive) {
        tab.classList.add("border-cyan-500", "text-cyan-600", "dark:text-cyan-400")
        tab.classList.remove("border-transparent", "text-gray-500", "dark:text-slate-400")
      } else {
        tab.classList.remove("border-cyan-500", "text-cyan-600", "dark:text-cyan-400")
        tab.classList.add("border-transparent", "text-gray-500", "dark:text-slate-400")
      }
    })

    // Update panel visibility
    this.panelTargets.forEach((panel, i) => {
      if (i === index) {
        panel.classList.remove("hidden")
        panel.setAttribute("aria-hidden", "false")
      } else {
        panel.classList.add("hidden")
        panel.setAttribute("aria-hidden", "true")
      }
    })
  }

  // Keyboard navigation
  handleKeydown(event) {
    const currentIndex = this.activeIndexValue
    let newIndex = currentIndex

    switch (event.key) {
      case "ArrowRight":
        newIndex = (currentIndex + 1) % this.tabTargets.length
        break
      case "ArrowLeft":
        newIndex = (currentIndex - 1 + this.tabTargets.length) % this.tabTargets.length
        break
      case "Home":
        newIndex = 0
        break
      case "End":
        newIndex = this.tabTargets.length - 1
        break
      default:
        return
    }

    event.preventDefault()
    this.activeIndexValue = newIndex
    this.showTab(newIndex)
    this.tabTargets[newIndex].focus()
  }
}

