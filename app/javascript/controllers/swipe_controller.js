import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="swipe"
// Handles mobile swipe navigation between views using CSS scroll-snap
// - Swipe left/right to switch between Elevation and Nodes views
// - Dot indicators show current view
// - Listens to rack-show controller's selectionChanged event to auto-swipe
export default class extends Controller {
  static targets = ["container", "view", "dot"]
  static values = {
    currentIndex: { type: Number, default: 0 }
  }

  connect() {
    // Set up scroll listener with debouncing for performance
    this.handleScroll = this.debounce(this.onScroll.bind(this), 50)
    this.containerTarget.addEventListener("scroll", this.handleScroll)

    // Listen for selection changes from rack-show controller
    this.boundHandleSelectionChanged = this.handleSelectionChanged.bind(this)
    document.addEventListener("rack-show:selectionChanged", this.boundHandleSelectionChanged)

    // Initialize dot state
    this.updateDots()
  }

  disconnect() {
    this.containerTarget.removeEventListener("scroll", this.handleScroll)
    document.removeEventListener("rack-show:selectionChanged", this.boundHandleSelectionChanged)
  }

  // Handle scroll events to update current view index
  onScroll() {
    const container = this.containerTarget
    const scrollLeft = container.scrollLeft
    const viewWidth = container.offsetWidth

    // Calculate which view is most visible
    const newIndex = Math.round(scrollLeft / viewWidth)

    if (newIndex !== this.currentIndexValue && newIndex >= 0 && newIndex < this.viewTargets.length) {
      this.currentIndexValue = newIndex
      this.updateDots()
    }
  }

  // Navigate to specific view by index (called from dot click)
  goToView(event) {
    event.preventDefault()
    const index = parseInt(event.currentTarget.dataset.index, 10)
    this.scrollToView(index)
  }

  // Smooth scroll to a specific view
  scrollToView(index) {
    if (index < 0 || index >= this.viewTargets.length) return

    const container = this.containerTarget
    const viewWidth = container.offsetWidth

    container.scrollTo({
      left: index * viewWidth,
      behavior: "smooth"
    })

    this.currentIndexValue = index
    this.updateDots()
  }

  // Update dot indicators to reflect current view
  updateDots() {
    this.dotTargets.forEach((dot, index) => {
      const isActive = index === this.currentIndexValue

      // Update visual state
      if (isActive) {
        dot.classList.add("bg-teal-600")
        dot.classList.remove("bg-slate-300")
        dot.setAttribute("aria-current", "true")
      } else {
        dot.classList.remove("bg-teal-600")
        dot.classList.add("bg-slate-300")
        dot.setAttribute("aria-current", "false")
      }
    })
  }

  // Handle selection changes from rack-show controller
  // When a node is selected in elevation, auto-swipe to nodes view
  handleSelectionChanged(event) {
    const { nodeId } = event.detail

    // If a node was selected (not deselected), swipe to nodes view (index 1)
    if (nodeId && nodeId > 0) {
      this.scrollToView(1)
    }
  }

  // Simple debounce utility
  debounce(func, wait) {
    let timeout
    return (...args) => {
      clearTimeout(timeout)
      timeout = setTimeout(() => func.apply(this, args), wait)
    }
  }

  // Value changed callback
  currentIndexValueChanged(newIndex, previousIndex) {
    if (newIndex !== previousIndex) {
      this.dispatch("viewChanged", {
        detail: { index: newIndex, previousIndex: previousIndex }
      })
    }
  }
}
