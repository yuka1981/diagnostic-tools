import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="autosubmit"
// Submits the form when a child element triggers an action
export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}

