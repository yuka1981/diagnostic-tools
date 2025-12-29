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
    this.zoneTarget.classList.add("border-emerald-400", "bg-emerald-50", "dark:border-emerald-500/50", "dark:bg-emerald-500/10")
    this.zoneTarget.classList.remove("border-gray-300", "bg-gray-50", "dark:border-white/10", "dark:bg-white/5")
  }

  unhighlight() {
    this.zoneTarget.classList.remove("border-emerald-400", "bg-emerald-50", "dark:border-emerald-500/50", "dark:bg-emerald-500/10")
    this.zoneTarget.classList.add("border-gray-300", "bg-gray-50", "dark:border-white/10", "dark:bg-white/5")
  }

  updateLabel(file) {
    if (this.hasLabelTarget) {
      this.labelTarget.innerHTML = `
        <span class="text-emerald-600 dark:text-emerald-400">${file.name}</span>
        <span class="text-gray-400 dark:text-slate-500">(${this.formatFileSize(file.size)})</span>
      `
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

