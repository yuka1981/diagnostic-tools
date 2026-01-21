// app/javascript/controllers/image_viewer_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["image"]

  show(event) {
    const index = parseInt(event.currentTarget.dataset.index, 10)
    this.imageTargets.forEach((img, i) => {
      img.classList.toggle("hidden", i !== index)
    })
  }
}
