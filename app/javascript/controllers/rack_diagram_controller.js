import { Controller } from "@hotwired/stimulus"
import { RackDiagram } from "lib/rack_diagram"

export default class extends Controller {
  static targets = ["canvas", "details"]
  static values = {
    rackId: Number,
    rackHeight: Number,
    descUnits: Boolean,
    nodes: Array,
    readonly: Boolean
  }

  connect() {
    this.hasChanges = false
    this.diagram = new RackDiagram(this.canvasTarget, {
      rackHeight: this.rackHeightValue,
      descUnits: this.descUnitsValue,
      nodes: this.nodesValue,
      readonly: this.readonlyValue,
      onSelect: this.handleSelect.bind(this),
      onChange: this.handleChange.bind(this)
    })

    this.setupSaveButton()
    this.setupBeforeUnload()
  }

  disconnect() {
    if (this.diagram) {
      this.diagram.dispose()
    }
    if (this.saveButton && this.saveClickHandler) {
      this.saveButton.removeEventListener("click", this.saveClickHandler)
    }
    window.removeEventListener("beforeunload", this.beforeUnloadHandler)
  }

  handleSelect(node) {
    if (node) {
      this.detailsTarget.innerHTML = this.nodeDetailsHTML(node)
    } else {
      this.detailsTarget.innerHTML = this.detailsTarget.dataset.defaultContent || ""
    }
  }

  handleChange() {
    this.hasChanges = true
    this.showSaveButton()
  }

  setupSaveButton() {
    this.saveButton = document.getElementById("save-layout-btn")
    if (this.saveButton) {
      this.saveClickHandler = this.saveLayout.bind(this)
      this.saveButton.addEventListener("click", this.saveClickHandler)
    }
  }

  showSaveButton() {
    if (this.saveButton) {
      this.saveButton.classList.remove("hidden")
      this.saveButton.classList.add("animate-pulse")
    }
  }

  hideSaveButton() {
    if (this.saveButton) {
      this.saveButton.classList.add("hidden")
      this.saveButton.classList.remove("animate-pulse")
    }
  }

  setupBeforeUnload() {
    this.beforeUnloadHandler = (e) => {
      if (this.hasChanges) {
        e.preventDefault()
        e.returnValue = ""
      }
    }
    window.addEventListener("beforeunload", this.beforeUnloadHandler)
  }

  async saveLayout() {
    const positions = this.diagram.getPositions()
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    try {
      const response = await fetch(`/racks/${this.rackIdValue}/update_layout`, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken
        },
        body: JSON.stringify({ positions })
      })

      const data = await response.json()

      if (data.success) {
        this.hasChanges = false
        this.hideSaveButton()
        this.showNotification("Layout saved successfully", "success")
      } else {
        this.showNotification(data.errors.join(", "), "error")
      }
    } catch (error) {
      this.showNotification("Failed to save layout", "error")
    }
  }

  showNotification(message, type) {
    const flash = document.getElementById("flash_messages")
    if (flash) {
      const alertClass = type === "success" ? "bg-green-50 text-green-800 border-green-200" : "bg-red-50 text-red-800 border-red-200"
      flash.innerHTML = `<div class="p-4 rounded-lg border ${alertClass}">${message}</div>`
      setTimeout(() => { flash.innerHTML = "" }, 3000)
    }
  }

  escapeHTML(str) {
    const div = document.createElement("div")
    div.textContent = str
    return div.innerHTML
  }

  nodeDetailsHTML(node) {
    const statusClass = node.status === "Online"
      ? "bg-emerald-100 text-emerald-800 border-emerald-200"
      : "bg-slate-100 text-slate-600 border-slate-200"
    const hostname = this.escapeHTML(node.hostname)

    return `
      <dl class="space-y-3">
        <div>
          <dt class="text-sm text-slate-500">Hostname</dt>
          <dd class="text-sm font-medium text-slate-900">
            <a href="/nodes/${node.id}" class="text-teal-600 hover:text-teal-800">${hostname}</a>
          </dd>
        </div>
        <div>
          <dt class="text-sm text-slate-500">Position</dt>
          <dd class="text-sm font-medium text-slate-900">RU ${node.position}</dd>
        </div>
        <div>
          <dt class="text-sm text-slate-500">Height</dt>
          <dd class="text-sm font-medium text-slate-900">${node.height}U</dd>
        </div>
        <div>
          <dt class="text-sm text-slate-500">Status</dt>
          <dd class="inline-flex items-center rounded-sm px-2 py-0.5 text-xs font-medium ${statusClass} border">${node.status}</dd>
        </div>
      </dl>
    `
  }
}
