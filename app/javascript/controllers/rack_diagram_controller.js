import { Controller } from "@hotwired/stimulus"
import { RackDiagram } from "lib/rack_diagram"

export default class extends Controller {
  static targets = ["container", "details"]
  static values = {
    rackId: Number,
    rackHeight: Number,
    descUnits: Boolean,
    nodes: Array,
    readonly: Boolean
  }

  connect() {
    console.log("[RackDiagram] Connecting controller...")
    console.log("[RackDiagram] Container:", this.containerTarget)
    console.log("[RackDiagram] Container dimensions:", this.containerTarget.clientWidth, "x", this.containerTarget.clientHeight)
    console.log("[RackDiagram] Nodes:", this.nodesValue)

    this.hasChanges = false

    // Store initial details content for restoration when deselecting
    if (this.hasDetailsTarget) {
      this.defaultDetailsContent = this.detailsTarget.innerHTML
    }

    try {
      this.diagram = new RackDiagram(this.containerTarget, {
        rackHeight: this.rackHeightValue,
        descUnits: this.descUnitsValue,
        nodes: this.nodesValue,
        readonly: this.readonlyValue,
        onSelect: this.handleSelect.bind(this),
        onChange: this.handleChange.bind(this)
      })
      console.log("[RackDiagram] Diagram initialized successfully")
    } catch (error) {
      console.error("[RackDiagram] Failed to initialize diagram:", error)
    }

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
    if (!this.hasDetailsTarget) return

    if (node) {
      this.detailsTarget.innerHTML = this.nodeDetailsHTML(node)
    } else {
      this.detailsTarget.innerHTML = this.defaultDetailsContent || ""
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
