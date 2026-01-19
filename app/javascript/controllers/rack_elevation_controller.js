import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="rack-elevation"
// Handles rack elevation interactions (face toggle is handled via Turbo Frames)
export default class extends Controller {
  connect() {
    // Component connected - Turbo Frame handles face switching
  }
}
