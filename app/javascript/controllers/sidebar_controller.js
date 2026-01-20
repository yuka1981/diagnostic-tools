import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="sidebar"
// Handles:
// - Mobile sidebar toggle (existing)
// - Desktop sidebar collapse/expand (new)
// - Expandable sections like Rooms (new)
// - State persistence via localStorage (new)
export default class extends Controller {
  static targets = [
    "menu",
    "overlay",
    "content",
    "collapseIcon",
    "label",
    "sectionHeader",
    "roomsList",
    "roomsChevron",
    "brandText",
    "userInfo"
  ]

  static values = {
    collapsed: { type: Boolean, default: false },
    roomsExpanded: { type: Boolean, default: true },
    roomsUrl: { type: String, default: "/rooms" }
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
    // Reset rooms expanded when collapsing sidebar (without animation)
    if (this.collapsedValue && this.roomsExpandedValue) {
      this.roomsExpandedValue = false
      // Disable transition, reset chevron, re-enable (prevents animation)
      if (this.hasRoomsChevronTarget) {
        this.roomsChevronTarget.style.transition = 'none'
        this.roomsChevronTarget.classList.remove("rotate-90")
        // Force reflow to apply changes immediately
        this.roomsChevronTarget.offsetHeight
        // Restore transition for future animations
        this.roomsChevronTarget.style.transition = ''
      }
    }
    this.saveState()
    this.applyState()
  }

  // Rooms section expand/collapse
  toggleRooms() {
    if (this.collapsedValue) {
      // Disable transitions before navigating to prevent animation glitch
      this.menuTarget.style.transition = 'none'
      window.location.href = this.roomsUrlValue
      return
    }
    this.roomsExpandedValue = !this.roomsExpandedValue
    this.saveState()
    this.applyRoomsState()
  }

  // Load state from localStorage (with cookie fallback for collapsed state)
  loadState() {
    const collapsed = localStorage.getItem("sidebarCollapsed")
    const roomsExpanded = localStorage.getItem("sidebarRoomsExpanded")

    if (collapsed !== null) {
      this.collapsedValue = collapsed === "true"
    } else {
      // Fall back to cookie if localStorage doesn't have the value
      const cookieMatch = document.cookie.match(/sidebar_collapsed=(\w+)/)
      if (cookieMatch) {
        this.collapsedValue = cookieMatch[1] === "true"
      }
    }
    if (roomsExpanded !== null) {
      this.roomsExpandedValue = roomsExpanded === "true"
    }
  }

  // Save state to localStorage and cookie (cookie enables server-side rendering)
  saveState() {
    localStorage.setItem("sidebarCollapsed", this.collapsedValue)
    localStorage.setItem("sidebarRoomsExpanded", this.roomsExpandedValue)
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

      // Hide rooms list when collapsed
      if (this.hasRoomsListTarget) {
        this.roomsListTarget.classList.add("hidden")
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

      // Apply rooms state
      this.applyRoomsState()
    }
  }

  // Apply rooms section expanded/collapsed state
  applyRoomsState() {
    if (!this.hasRoomsListTarget || !this.hasRoomsChevronTarget) return

    if (this.roomsExpandedValue && !this.collapsedValue) {
      this.roomsListTarget.classList.remove("hidden")
      this.roomsChevronTarget.classList.add("rotate-90")
    } else {
      this.roomsListTarget.classList.add("hidden")
      this.roomsChevronTarget.classList.remove("rotate-90")
    }
  }
}
