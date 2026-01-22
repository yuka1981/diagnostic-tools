import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="ssh-profile-select"
// Manages SSH profile selection with override functionality
// Shows/hides manual SSH configuration fields based on profile selection and override checkbox
export default class extends Controller {
  static targets = ["select", "overrideSection", "overrideCheckbox", "manualFields"]

  connect() {
    // Initialize state based on current values
    this.profileChanged()
  }

  profileChanged() {
    const hasProfile = this.selectTarget.value !== ""

    if (this.hasOverrideSectionTarget) {
      this.overrideSectionTarget.classList.toggle("hidden", !hasProfile)
    }

    if (hasProfile && this.hasOverrideCheckboxTarget) {
      // When profile selected, hide manual fields unless override is checked
      const showManual = this.overrideCheckboxTarget.checked
      if (this.hasManualFieldsTarget) {
        this.manualFieldsTarget.classList.toggle("hidden", !showManual)
      }
    } else {
      // No profile - always show manual fields
      if (this.hasManualFieldsTarget) {
        this.manualFieldsTarget.classList.remove("hidden")
      }
    }
  }

  toggleOverride() {
    if (this.hasManualFieldsTarget && this.hasOverrideCheckboxTarget) {
      const showManual = this.overrideCheckboxTarget.checked || this.selectTarget.value === ""
      this.manualFieldsTarget.classList.toggle("hidden", !showManual)
    }
  }
}
