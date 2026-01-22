import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="ssh-profile-select"
// Shows/hides SSH configuration section based on profile selection with smooth animation
// When a profile is selected, SSH config collapses (profile settings are used)
// When "Custom SSH Settings" is selected, SSH config expands for manual entry
export default class extends Controller {
  static targets = ["select", "sshConfigSection"]

  connect() {
    // Set initial state without animation
    this.initializeState()
  }

  initializeState() {
    const hasProfile = this.hasSelectTarget && this.selectTarget.value !== ""

    if (this.hasSshConfigSectionTarget) {
      const section = this.sshConfigSectionTarget

      if (hasProfile) {
        // Profile selected - start fully hidden (takes no space)
        section.classList.add("hidden")
      } else {
        // Custom settings - start expanded
        section.classList.remove("hidden")
        section.style.maxHeight = "none"
        section.style.opacity = "1"
        section.style.overflow = "visible"
      }
    }
  }

  toggleSshConfig() {
    const hasProfile = this.hasSelectTarget && this.selectTarget.value !== ""

    if (this.hasSshConfigSectionTarget) {
      if (hasProfile) {
        this.collapse()
      } else {
        this.expand()
      }
    }
  }

  expand() {
    const section = this.sshConfigSectionTarget

    // Remove hidden class and prepare for animation
    section.classList.remove("hidden")
    section.style.overflow = "hidden"
    section.style.maxHeight = "0"
    section.style.opacity = "0"

    // Force reflow to ensure the initial state is applied
    section.offsetHeight

    // Get the full height
    const fullHeight = section.scrollHeight

    // Add transition and animate to full height
    section.style.transition = "max-height 0.3s ease-out, opacity 0.3s ease-out"
    section.style.maxHeight = fullHeight + "px"
    section.style.opacity = "1"

    // After animation, remove constraints
    setTimeout(() => {
      section.style.maxHeight = "none"
      section.style.overflow = "visible"
      section.style.transition = ""
    }, 300)
  }

  collapse() {
    const section = this.sshConfigSectionTarget

    // Set current height explicitly for animation
    const currentHeight = section.scrollHeight
    section.style.maxHeight = currentHeight + "px"
    section.style.overflow = "hidden"
    section.style.opacity = "1"

    // Force reflow
    section.offsetHeight

    // Add transition and animate to 0
    section.style.transition = "max-height 0.3s ease-out, opacity 0.3s ease-out"
    section.style.maxHeight = "0"
    section.style.opacity = "0"

    // After animation, fully hide the element
    setTimeout(() => {
      section.classList.add("hidden")
      section.style.maxHeight = ""
      section.style.opacity = ""
      section.style.overflow = ""
      section.style.transition = ""
    }, 300)
  }
}
