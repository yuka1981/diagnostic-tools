import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="sidebar"
// Handles:
// - Mobile sidebar toggle
// - Desktop sidebar collapse/expand
// - State persistence via localStorage
export default class extends Controller {
  static targets = [
    "menu",
    "overlay",
    "content",
    "collapseIcon",
    "label",
    "sectionHeader",
    "brandText",
    "userInfo"
  ]

  static values = {
    collapsed: { type: Boolean, default: false }
  }

  connect() {
    this.loadState()
    this.applyState()
  }

  // Mobile toggle (existing functionality)
  toggle() {
    this.menuTarget.classList.toggle("translate-x-0")
    this.menuTarget.classList.toggle("-translate-x-full")
    this.overlayTarget.classList.toggle("hidden")
  }

  close() {
    this.menuTarget.classList.remove("translate-x-0")
    this.menuTarget.classList.add("-translate-x-full")
    this.overlayTarget.classList.add("hidden")
  }

  // Desktop collapse/expand
  toggleCollapse() {
    this.collapsedValue = !this.collapsedValue
    this.saveState()
    this.applyState()
  }

  // Load state from localStorage (with cookie fallback for collapsed state)
  loadState() {
    const collapsed = localStorage.getItem("sidebarCollapsed")

    if (collapsed !== null) {
      this.collapsedValue = collapsed === "true"
    } else {
      // Fall back to cookie if localStorage doesn't have the value
      const cookieMatch = document.cookie.match(/sidebar_collapsed=(\w+)/)
      if (cookieMatch) {
        this.collapsedValue = cookieMatch[1] === "true"
      }
    }
  }

  // Save state to localStorage and cookie (cookie enables server-side rendering)
  saveState() {
    localStorage.setItem("sidebarCollapsed", this.collapsedValue)
    // Set cookie for server-side rendering (prevents flash on page load)
    document.cookie = `sidebar_collapsed=${this.collapsedValue}; path=/; max-age=31536000`
  }

  // Apply collapsed/expanded state to UI
  applyState() {
    const menu = this.menuTarget

    if (this.collapsedValue) {
      // Collapse: w-16, hide labels
      menu.classList.remove("w-64")
      menu.classList.add("w-16")

      if (this.hasContentTarget) {
        this.contentTarget.classList.remove("lg:pl-64")
        this.contentTarget.classList.add("lg:pl-16")
      }

      // Hide text elements
      this.labelTargets.forEach(el => el.classList.add("hidden"))
      this.sectionHeaderTargets.forEach(el => el.classList.add("hidden"))
      if (this.hasBrandTextTarget) this.brandTextTarget.classList.add("hidden")
      if (this.hasUserInfoTarget) this.userInfoTarget.classList.add("hidden")

      // Update collapse icon to show expand arrow
      if (this.hasCollapseIconTarget) {
        this.collapseIconTarget.classList.add("rotate-180")
      }
    } else {
      // Expand: w-64, show labels
      menu.classList.remove("w-16")
      menu.classList.add("w-64")

      if (this.hasContentTarget) {
        this.contentTarget.classList.remove("lg:pl-16")
        this.contentTarget.classList.add("lg:pl-64")
      }

      // Show text elements
      this.labelTargets.forEach(el => el.classList.remove("hidden"))
      this.sectionHeaderTargets.forEach(el => el.classList.remove("hidden"))
      if (this.hasBrandTextTarget) this.brandTextTarget.classList.remove("hidden")
      if (this.hasUserInfoTarget) this.userInfoTarget.classList.remove("hidden")

      // Update collapse icon to show collapse arrow
      if (this.hasCollapseIconTarget) {
        this.collapseIconTarget.classList.remove("rotate-180")
      }
    }
  }
}
