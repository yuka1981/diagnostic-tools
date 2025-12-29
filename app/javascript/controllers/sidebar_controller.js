import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="sidebar"
// Handles mobile sidebar toggle
export default class extends Controller {
  static targets = ["menu", "overlay"]
  static classes = ["open"]

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
}

