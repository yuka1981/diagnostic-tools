import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="wizard"
// Manages multi-step wizard forms with step navigation, validation, and indicators
export default class extends Controller {
  static targets = ["step", "indicator", "backButton", "nextButton", "submitButton"]
  static values = {
    current: { type: Number, default: 1 },
    total: { type: Number, default: 3 }
  }

  connect() {
    this.showStep(this.currentValue)
  }

  next() {
    if (this.validateCurrentStep() && this.currentValue < this.totalValue) {
      this.currentValue++
      this.showStep(this.currentValue)
    }
  }

  back() {
    if (this.currentValue > 1) {
      this.currentValue--
      this.showStep(this.currentValue)
    }
  }

  goToStep(event) {
    const step = parseInt(event.currentTarget.dataset.step)
    // Only allow going backwards to completed steps
    if (step < this.currentValue) {
      this.currentValue = step
      this.showStep(this.currentValue)
    }
  }

  showStep(stepNumber) {
    // Hide all steps, show current
    this.stepTargets.forEach((step, index) => {
      step.classList.toggle("hidden", index + 1 !== stepNumber)
    })

    // Update indicators
    this.indicatorTargets.forEach((indicator, index) => {
      const stepNum = index + 1
      indicator.classList.remove("bg-teal-600", "bg-slate-300", "text-white", "text-slate-600")

      if (stepNum < stepNumber) {
        // Completed step - show checkmark
        indicator.classList.add("bg-teal-600", "text-white")
        indicator.innerHTML = `<svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd"/></svg>`
      } else if (stepNum === stepNumber) {
        // Current step - show number with teal background
        indicator.classList.add("bg-teal-600", "text-white")
        indicator.textContent = stepNum
      } else {
        // Future step - show number with slate background
        indicator.classList.add("bg-slate-300", "text-slate-600")
        indicator.textContent = stepNum
      }
    })

    // Update navigation buttons
    if (this.hasBackButtonTarget) {
      this.backButtonTarget.classList.toggle("hidden", stepNumber === 1)
    }
    if (this.hasNextButtonTarget) {
      this.nextButtonTarget.classList.toggle("hidden", stepNumber === this.totalValue)
    }
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.classList.toggle("hidden", stepNumber !== this.totalValue)
    }
  }

  validateCurrentStep() {
    const currentStep = this.stepTargets[this.currentValue - 1]
    const requiredFields = currentStep.querySelectorAll("[required]")
    let valid = true

    requiredFields.forEach(field => {
      // Find or create error message element
      let errorEl = field.parentElement.querySelector(".wizard-field-error")

      if (!field.value.trim()) {
        // Show error state
        field.classList.remove("border-slate-300")
        field.classList.add("border-red-500", "ring-1", "ring-red-500")

        // Show error message
        if (!errorEl) {
          errorEl = document.createElement("p")
          errorEl.className = "wizard-field-error mt-1 text-xs text-red-600 font-medium"
          field.parentElement.appendChild(errorEl)
        }
        errorEl.textContent = "This field is required"
        errorEl.classList.remove("hidden")

        valid = false
      } else {
        // Clear error state
        field.classList.remove("border-red-500", "ring-1", "ring-red-500")
        field.classList.add("border-slate-300")

        // Hide error message
        if (errorEl) {
          errorEl.classList.add("hidden")
        }
      }
    })

    // Focus first invalid field
    if (!valid) {
      const firstInvalid = currentStep.querySelector(".border-red-500")
      if (firstInvalid) {
        firstInvalid.focus()
      }
    }

    return valid
  }
}
