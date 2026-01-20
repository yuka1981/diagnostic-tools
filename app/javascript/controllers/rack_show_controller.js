import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="rack-show"
// Handles selection sync between rack elevation diagram and nodes list
// - Clicking a node in elevation highlights it and scrolls to/expands the node card in the list
// - Clicking a node card in the list highlights it in elevation and expands the card
// - Clicking an already-expanded node collapses it and clears selection
export default class extends Controller {
  static targets = ["elevationNode", "nodeCard", "nodeCardContent"]
  static values = {
    selectedNodeId: { type: Number, default: 0 }
  }

  connect() {
    // Initialize with no selection
    this.selectedNodeIdValue = 0
  }

  disconnect() {
    this.clearSelection()
  }

  // Handle node selection from elevation diagram
  // Called via data-action="click->rack-show#selectFromElevation"
  selectFromElevation(event) {
    event.preventDefault()
    const nodeId = parseInt(event.currentTarget.dataset.nodeId, 10)

    if (!nodeId) return

    // If clicking the same node, toggle selection off
    if (this.selectedNodeIdValue === nodeId) {
      this.clearSelection()
      return
    }

    this.selectNode(nodeId)
    this.scrollToNodeCard(nodeId)
  }

  // Handle node selection from node card in list
  // Called via data-action="click->rack-show#selectFromCard"
  selectFromCard(event) {
    const nodeId = parseInt(event.currentTarget.dataset.nodeId, 10)

    if (!nodeId) return

    // If clicking the same node, toggle selection off
    if (this.selectedNodeIdValue === nodeId) {
      this.clearSelection()
      return
    }

    this.selectNode(nodeId)
  }

  // Select a node by ID - highlights in elevation and expands in list
  selectNode(nodeId) {
    // Clear previous selection first
    this.clearHighlights()
    this.collapseAllCards()

    // Update selected node ID
    this.selectedNodeIdValue = nodeId

    // Highlight in elevation
    this.highlightElevationNode(nodeId)

    // Expand the node card
    this.expandNodeCard(nodeId)
  }

  // Clear all selection state
  clearSelection() {
    this.selectedNodeIdValue = 0
    this.clearHighlights()
    this.collapseAllCards()
  }

  // Add selection styling to elevation node
  highlightElevationNode(nodeId) {
    const elevationNode = this.findElevationNode(nodeId)
    if (elevationNode) {
      elevationNode.classList.add("ring-2", "ring-teal-400", "ring-offset-1", "z-10")
      elevationNode.setAttribute("aria-selected", "true")
    }
  }

  // Remove selection styling from all elevation nodes
  clearHighlights() {
    this.elevationNodeTargets.forEach((node) => {
      node.classList.remove("ring-2", "ring-teal-400", "ring-offset-1", "z-10")
      node.setAttribute("aria-selected", "false")
    })
  }

  // Expand a specific node card
  expandNodeCard(nodeId) {
    const card = this.findNodeCard(nodeId)
    const content = this.findNodeCardContent(nodeId)

    if (card) {
      card.classList.add("bg-slate-50", "border-teal-500")
      card.setAttribute("aria-expanded", "true")
    }

    if (content) {
      content.classList.remove("hidden")
    }
  }

  // Collapse all node cards
  collapseAllCards() {
    this.nodeCardTargets.forEach((card) => {
      card.classList.remove("bg-slate-50", "border-teal-500")
      card.setAttribute("aria-expanded", "false")
    })

    this.nodeCardContentTargets.forEach((content) => {
      content.classList.add("hidden")
    })
  }

  // Smooth scroll to a node card in the list
  scrollToNodeCard(nodeId) {
    const card = this.findNodeCard(nodeId)
    if (card) {
      card.scrollIntoView({
        behavior: "smooth",
        block: "nearest"
      })
    }
  }

  // Helper: Find elevation node by ID
  findElevationNode(nodeId) {
    return this.elevationNodeTargets.find(
      (node) => parseInt(node.dataset.nodeId, 10) === nodeId
    )
  }

  // Helper: Find node card by ID
  findNodeCard(nodeId) {
    return this.nodeCardTargets.find(
      (card) => parseInt(card.dataset.nodeId, 10) === nodeId
    )
  }

  // Helper: Find node card content by ID
  findNodeCardContent(nodeId) {
    return this.nodeCardContentTargets.find(
      (content) => parseInt(content.dataset.nodeId, 10) === nodeId
    )
  }

  // Value changed callback - useful for debugging or future features
  selectedNodeIdValueChanged(newId, previousId) {
    // Dispatch custom event for other controllers that might need to know
    if (newId !== previousId) {
      this.dispatch("selectionChanged", {
        detail: { nodeId: newId, previousNodeId: previousId }
      })
    }
  }
}
