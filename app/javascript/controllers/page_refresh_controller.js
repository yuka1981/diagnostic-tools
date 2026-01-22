import { Controller } from "@hotwired/stimulus"

// Triggers a full page refresh when connected to the DOM
// Used after form submissions that require a complete page reload
export default class extends Controller {
  connect() {
    // Use Turbo.visit to refresh the current page
    Turbo.visit(window.location.href, { action: "replace" })
  }
}
