import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="release-mode"
// Handles switching between upload and build modes for agent releases
export default class extends Controller {
  static targets = [
    "uploadRadio",
    "buildRadio",
    "uploadSection",
    "buildSection",
    "binaryField",
    "submitButton",
    "submitText"
  ]

  connect() {
    // Initialize based on current selection
    this.updateMode()
  }

  toggleMode() {
    this.updateMode()
  }

  updateMode() {
    const isUploadMode = this.uploadRadioTarget.checked

    if (isUploadMode) {
      this.showUploadMode()
    } else {
      this.showBuildMode()
    }
  }

  showUploadMode() {
    // Show upload section, hide build section
    this.uploadSectionTarget.classList.remove("hidden")
    this.buildSectionTarget.classList.add("hidden")

    // Update submit button text
    this.submitTextTarget.textContent = "Upload Release"

    // Make binary field required
    if (this.hasBinaryFieldTarget) {
      this.binaryFieldTarget.required = true
    }
  }

  showBuildMode() {
    // Show build section, hide upload section
    this.uploadSectionTarget.classList.add("hidden")
    this.buildSectionTarget.classList.remove("hidden")

    // Update submit button text
    this.submitTextTarget.textContent = "Build Release"

    // Make binary field not required (we're building from source)
    if (this.hasBinaryFieldTarget) {
      this.binaryFieldTarget.required = false
    }
  }
}
