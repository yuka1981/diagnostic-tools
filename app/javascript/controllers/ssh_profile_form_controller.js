import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["connectionMethod", "bastionSection"]

  connect() {
    this.toggleBastion()
  }

  toggleBastion() {
    const select = this.hasConnectionMethodTarget
      ? this.connectionMethodTarget
      : this.element.querySelector("select[name*='ssh_connect_method']")

    if (!select) return

    const isCustomBastion = select.value === "custom_bastion"

    if (this.hasBastionSectionTarget) {
      if (isCustomBastion) {
        this.bastionSectionTarget.style.display = ""
      } else {
        this.bastionSectionTarget.style.display = "none"
      }
    }
  }
}
