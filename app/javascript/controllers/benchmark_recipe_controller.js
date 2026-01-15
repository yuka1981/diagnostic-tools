import { Controller } from "@hotwired/stimulus"

// Controller for benchmark recipe selection in the run form
// Shows recipe default profile and optionally populates argument overrides
export default class extends Controller {
  static targets = ["select", "defaults", "defaultsContent", "overrides"]
  static values = {
    recipes: { type: Object, default: {} }
  }

  connect() {
    // Initial update if a recipe is already selected
    if (this.hasSelectTarget && this.selectTarget.value) {
      this.showDefaults()
    }
  }

  showDefaults() {
    const recipeId = this.selectTarget.value

    if (!recipeId) {
      this.hideDefaults()
      return
    }

    const recipe = this.recipesValue[recipeId]

    if (recipe && recipe.default_profile) {
      // Show the defaults section
      if (this.hasDefaultsTarget) {
        this.defaultsTarget.classList.remove("hidden")
      }

      // Display the default profile as formatted JSON
      if (this.hasDefaultsContentTarget) {
        const formatted = JSON.stringify(recipe.default_profile, null, 2)
        this.defaultsContentTarget.textContent = formatted
      }
    } else {
      this.hideDefaults()
    }
  }

  hideDefaults() {
    if (this.hasDefaultsTarget) {
      this.defaultsTarget.classList.add("hidden")
    }
  }

  // Optional: Populate overrides textarea with recipe defaults for easy editing
  populateOverrides() {
    const recipeId = this.selectTarget.value

    if (!recipeId || !this.hasOverridesTarget) {
      return
    }

    const recipe = this.recipesValue[recipeId]

    if (recipe && recipe.default_profile) {
      // Only populate if the textarea is empty
      if (!this.overridesTarget.value.trim()) {
        const formatted = JSON.stringify(recipe.default_profile, null, 2)
        this.overridesTarget.value = formatted
      }
    }
  }
}
