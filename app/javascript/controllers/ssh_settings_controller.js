import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["bastionFields"]

  connect() {
    this.toggle()
  }

  toggle(event) {
    const select = event ? event.target : this.element.querySelector("select[name*='ssh_connect_method']")
    if (!select) return

    const isCustomBastion = select.value === "custom_bastion"
    
    if (isCustomBastion) {
      this.bastionFieldsTarget.classList.remove("hidden")
    } else {
      this.bastionFieldsTarget.classList.add("hidden")
    }
  }
}
