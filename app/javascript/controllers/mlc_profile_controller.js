import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="mlc-profile"
// Handles profile card selection in MLC benchmark form
export default class extends Controller {
  static targets = ["container"]

  select(event) {
    const key = event.params.key

    // Update radio buttons
    const radios = this.containerTarget.querySelectorAll("input[type='radio']")
    radios.forEach(radio => {
      radio.checked = radio.value === key
    })

    // Update card styling
    const cards = this.containerTarget.querySelectorAll("label")
    cards.forEach(card => {
      const cardKey = card.dataset.mlcProfileKeyParam
      const isSelected = cardKey === key

      // Remove all selection classes
      card.classList.remove("border-primary-5", "ring-2", "ring-primary-5", "bg-primary-1")
      card.classList.add("border-neutral-15", "bg-white")

      if (isSelected) {
        card.classList.remove("border-neutral-15", "bg-white")
        card.classList.add("border-primary-5", "ring-2", "ring-primary-5", "bg-primary-1")
      }

      // Toggle checkmark icon
      const checkIcon = card.querySelector("[data-check-icon]")
      if (checkIcon) {
        checkIcon.classList.toggle("hidden", !isSelected)
      }
    })
  }
}
