import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="ssh-profile-select"
// Shows/hides SSH configuration section based on profile selection
// When a profile is selected, SSH config is hidden (profile settings are used)
// When "Custom SSH Settings" is selected, SSH config is shown for manual entry
export default class extends Controller {
  static targets = ["select", "sshConfigSection"]

  connect() {
    this.toggleSshConfig()
  }

  toggleSshConfig() {
    const hasProfile = this.hasSelectTarget && this.selectTarget.value !== ""

    if (this.hasSshConfigSectionTarget) {
      if (hasProfile) {
        // Profile selected - hide SSH config section
        this.sshConfigSectionTarget.classList.add("hidden")
      } else {
        // Custom SSH Settings selected - show SSH config section
        this.sshConfigSectionTarget.classList.remove("hidden")
      }
    }
  }
}
