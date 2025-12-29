import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="heatmap"
// Handles node heatmap grid interactions with click filtering
export default class extends Controller {
  static targets = ["cell", "clearButton", "selectedLabel"]
  static values = {
    selectedNodeId: { type: Number, default: 0 },
    runsFrameId: { type: String, default: "filtered_runs" }
  }

  connect() {
    this.updateUI()
  }

  filter(event) {
    const nodeId = parseInt(event.currentTarget.dataset.nodeId, 10)
    
    // Toggle selection if clicking the same node
    if (this.selectedNodeIdValue === nodeId) {
      this.clearSelection()
      return
    }

    this.selectedNodeIdValue = nodeId
    this.updateUI()
    this.updateRunsFrame(nodeId)
  }

  clearSelection() {
    this.selectedNodeIdValue = 0
    this.updateUI()
    this.updateRunsFrame(null)
  }

  updateUI() {
    const selectedId = this.selectedNodeIdValue

    // Update cell selection states
    this.cellTargets.forEach(cell => {
      const cellNodeId = parseInt(cell.dataset.nodeId, 10)
      if (selectedId && cellNodeId === selectedId) {
        cell.classList.add("ring-2", "ring-cyan-500", "ring-offset-2", "dark:ring-offset-slate-900")
        cell.classList.remove("hover:scale-105")
      } else {
        cell.classList.remove("ring-2", "ring-cyan-500", "ring-offset-2", "dark:ring-offset-slate-900")
        cell.classList.add("hover:scale-105")
      }
    })

    // Update clear button visibility (toggle both hidden and inline-flex to avoid CSS conflicts)
    if (this.hasClearButtonTarget) {
      if (selectedId) {
        this.clearButtonTarget.classList.remove("hidden")
        this.clearButtonTarget.classList.add("inline-flex")
      } else {
        this.clearButtonTarget.classList.add("hidden")
        this.clearButtonTarget.classList.remove("inline-flex")
      }
    }

    // Update selected label
    if (this.hasSelectedLabelTarget) {
      if (selectedId) {
        const selectedCell = this.cellTargets.find(c => parseInt(c.dataset.nodeId, 10) === selectedId)
        const hostname = selectedCell?.dataset.hostname || `Node #${selectedId}`
        this.selectedLabelTarget.textContent = `Filtered by: ${hostname}`
        this.selectedLabelTarget.classList.remove("hidden")
      } else {
        this.selectedLabelTarget.classList.add("hidden")
      }
    }
  }

  updateRunsFrame(nodeId) {
    const frame = document.getElementById(this.runsFrameIdValue)
    if (!frame) return

    // Build URL with optional node_id filter
    const url = new URL(window.location.href)
    if (nodeId) {
      url.searchParams.set("node_id", nodeId)
    } else {
      url.searchParams.delete("node_id")
    }

    // Update the Turbo Frame src to reload with filter
    frame.src = url.toString()
  }
}

