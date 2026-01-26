import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="file-drop"
// Handles drag-and-drop file upload with visual feedback
export default class extends Controller {
  static targets = ["zone", "input", "label"]

  dragOver(event) {
    event.preventDefault()
    this.highlight()
  }

  dragEnter(event) {
    event.preventDefault()
    this.highlight()
  }

  dragLeave(event) {
    event.preventDefault()
    this.unhighlight()
  }

  drop(event) {
    event.preventDefault()
    this.unhighlight()

    const files = event.dataTransfer.files
    if (files.length > 0) {
      this.inputTarget.files = files
      this.updateLabel(files[0])
    }
  }

  fileSelected(event) {
    const files = event.target.files
    if (files.length > 0) {
      this.updateLabel(files[0])
    }
  }

  highlight() {
    this.zoneTarget.classList.add("border-success-4", "bg-success-1", "dark:border-success-5/50", "dark:bg-success-5/10")
    this.zoneTarget.classList.remove("border-neutral-15", "bg-neutral-2", "dark:border-white/10", "dark:bg-white/5")
  }

  unhighlight() {
    this.zoneTarget.classList.remove("border-success-4", "bg-success-1", "dark:border-success-5/50", "dark:bg-success-5/10")
    this.zoneTarget.classList.add("border-neutral-15", "bg-neutral-2", "dark:border-white/10", "dark:bg-white/5")
  }

  updateLabel(file) {
    if (this.hasLabelTarget) {
      this.labelTarget.innerHTML = "" // Clear existing content

      const nameSpan = document.createElement("span")
      nameSpan.className = "text-success-6 dark:text-success-4"
      nameSpan.textContent = file.name

      const sizeSpan = document.createElement("span")
      sizeSpan.className = "text-neutral-25 dark:text-neutral-45"
      sizeSpan.textContent = ` (${this.formatFileSize(file.size)})`

      this.labelTarget.appendChild(nameSpan)
      this.labelTarget.appendChild(sizeSpan)
    }
  }

  formatFileSize(bytes) {
    if (bytes === 0) return "0 Bytes"
    const k = 1024
    const sizes = ["Bytes", "KB", "MB", "GB"]
    const i = Math.floor(Math.log(bytes) / Math.log(k))
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + " " + sizes[i]
  }
}

