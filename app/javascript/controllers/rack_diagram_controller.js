import { Controller } from "@hotwired/stimulus"
import { RackDiagram } from "lib/rack_diagram"

export default class extends Controller {
  static targets = ["container"]
  static values = {
    rackId: Number,
    rackHeight: Number,
    descUnits: Boolean,
    nodes: Array,
    readonly: Boolean
  }

  connect() {
    this.hasChanges = false

    this.diagram = new RackDiagram(this.containerTarget, {
      rackHeight: this.rackHeightValue,
      descUnits: this.descUnitsValue,
      nodes: this.nodesValue,
      readonly: this.readonlyValue,
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
        this.updateMountedNodesTable(positions)
      } else {
        this.showNotification(data.errors.join(", "), "error")
      }
    } catch (error) {
      this.showNotification("Failed to save layout", "error")
    }
  }

  updateMountedNodesTable(positions) {
    // Update position cells in the Mounted Nodes table
    positions.forEach(pos => {
      const row = document.querySelector(`tr[data-node-id="${pos.node_id}"]`)
      if (row) {
        const positionCell = row.querySelector("td[data-position]")
        if (positionCell) {
          positionCell.textContent = `U${pos.rack_position}`
        }
      }
    })

    // Re-sort table rows by position
    const tbody = document.querySelector("table tbody")
    if (tbody) {
      const rows = Array.from(tbody.querySelectorAll("tr[data-node-id]"))
      rows.sort((a, b) => {
        const posA = parseInt(a.querySelector("td[data-position]")?.textContent.replace("U", "") || 0)
        const posB = parseInt(b.querySelector("td[data-position]")?.textContent.replace("U", "") || 0)
        return posA - posB
      })
      rows.forEach(row => tbody.appendChild(row))
    }
  }

  showNotification(message, type) {
    const flash = document.getElementById("flash_messages")
    if (flash) {
      const alertClass = type === "success" ? "bg-success-1 text-success-8 border-success-2" : "bg-error-1 text-error-8 border-error-2"
      flash.innerHTML = `<div class="p-4 rounded-lg border ${alertClass}">${message}</div>`
      setTimeout(() => { flash.innerHTML = "" }, 3000)
    }
  }
}
