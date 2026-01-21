import interact from "interactjs"

export class RackDiagram {
  constructor(containerElement, options) {
    this.options = {
      rackHeight: 42,
      descUnits: false,
      nodes: [],
      readonly: false,
      onSelect: () => {},
      onChange: () => {},
      ...options
    }

    this.container = containerElement
    this.nodeElements = new Map()
    this.interactables = new Map()
    this.positions = new Map()
    this.selectedNode = null

    // Initialize positions from nodes
    this.options.nodes.forEach(node => {
      this.positions.set(node.id, {
        node_id: node.id,
        rack_position: node.position,
        rack_height: node.height
      })
    })

    this.initDimensions()
    this.render()
  }

  initDimensions() {
    const containerWidth = this.container.clientWidth || 400
    this.ruHeight = 20
    this.labelWidth = 40
    this.rackWidth = containerWidth - this.labelWidth - 20
    this.rackX = this.labelWidth + 10
    this.rackY = 20
    this.containerHeight = this.options.rackHeight * this.ruHeight + 40
  }

  render() {
    // Clear container
    this.container.innerHTML = ""
    this.nodeElements.clear()

    // Setup container styles
    this.container.style.position = "relative"
    this.container.style.height = `${this.containerHeight}px`
    this.container.style.backgroundColor = "#f8fafc"
    this.container.style.userSelect = "none"

    this.createRackFrame()
    this.createRULabels()
    this.createNodes()
  }

  createRackFrame() {
    const height = this.options.rackHeight * this.ruHeight

    // Rack frame container
    const frame = document.createElement("div")
    frame.style.position = "absolute"
    frame.style.left = `${this.rackX}px`
    frame.style.top = `${this.rackY}px`
    frame.style.width = `${this.rackWidth}px`
    frame.style.height = `${height}px`
    frame.style.backgroundColor = "#e2e8f0"
    frame.style.border = "2px solid #94a3b8"
    frame.style.boxSizing = "border-box"

    // Add click handler to deselect when clicking on empty rack space
    frame.addEventListener("click", (e) => {
      if (e.target === frame) {
        this.selectNode(null)
      }
    })

    this.rackFrame = frame
    this.container.appendChild(frame)

    // RU grid lines
    for (let i = 1; i < this.options.rackHeight; i++) {
      const line = document.createElement("div")
      line.style.position = "absolute"
      line.style.left = "0"
      line.style.top = `${i * this.ruHeight}px`
      line.style.width = "100%"
      line.style.height = "1px"
      line.style.backgroundColor = "#cbd5e1"
      line.style.pointerEvents = "none"
      frame.appendChild(line)
    }
  }

  createRULabels() {
    for (let i = 1; i <= this.options.rackHeight; i++) {
      const ruNumber = this.options.descUnits ? i : this.options.rackHeight - i + 1
      const y = this.rackY + (i - 1) * this.ruHeight + this.ruHeight / 2

      const label = document.createElement("div")
      label.textContent = ruNumber.toString()
      label.style.position = "absolute"
      label.style.left = `${this.labelWidth / 2}px`
      label.style.top = `${y}px`
      label.style.transform = "translate(-50%, -50%)"
      label.style.fontSize = "10px"
      label.style.fontFamily = "system-ui, sans-serif"
      label.style.color = "#64748b"
      label.style.pointerEvents = "none"

      this.container.appendChild(label)
    }
  }

  createNodes() {
    this.options.nodes.forEach(node => {
      const pos = this.positions.get(node.id)
      if (!pos || !pos.rack_position) return

      this.createNodeElement(node, pos)
    })
  }

  createNodeElement(node, pos) {
    const ruFromTop = this.options.descUnits
      ? pos.rack_position - 1
      : this.options.rackHeight - pos.rack_position - pos.rack_height + 1

    const y = ruFromTop * this.ruHeight
    const height = pos.rack_height * this.ruHeight

    // Determine color based on status
    const fillColor = node.status === "Online" ? "#14b8a6" : "#94a3b8"
    const borderColor = node.status === "Online" ? "#0d9488" : "#64748b"

    const nodeEl = document.createElement("div")
    nodeEl.className = "rack-node"
    nodeEl.dataset.nodeId = node.id
    nodeEl.style.position = "absolute"
    nodeEl.style.left = "4px"
    nodeEl.style.top = `${y + 2}px`
    nodeEl.style.width = `${this.rackWidth - 8}px`
    nodeEl.style.height = `${height - 4}px`
    nodeEl.style.backgroundColor = fillColor
    nodeEl.style.border = `1px solid ${borderColor}`
    nodeEl.style.borderRadius = "4px"
    nodeEl.style.display = "flex"
    nodeEl.style.alignItems = "center"
    nodeEl.style.justifyContent = "center"
    nodeEl.style.boxSizing = "border-box"
    nodeEl.style.cursor = this.options.readonly ? "default" : "grab"
    nodeEl.style.touchAction = "none" // Required for interact.js

    // Store node data
    nodeEl._nodeData = { ...node, ...pos }

    // Node label
    const label = document.createElement("span")
    label.textContent = node.hostname
    label.style.fontSize = "12px"
    label.style.fontFamily = "system-ui, sans-serif"
    label.style.fontWeight = "bold"
    label.style.color = "#ffffff"
    label.style.pointerEvents = "none"
    nodeEl.appendChild(label)

    // Click handler for selection
    nodeEl.addEventListener("click", (e) => {
      e.stopPropagation()
      this.selectNode(nodeEl._nodeData)
    })

    this.rackFrame.appendChild(nodeEl)
    this.nodeElements.set(node.id, nodeEl)

    // Setup draggable if not readonly
    if (!this.options.readonly) {
      this.setupDraggable(node.id, nodeEl, pos)
    }
  }

  setupDraggable(nodeId, nodeEl, pos) {
    const height = pos.rack_height
    const minY = 2
    const maxY = (this.options.rackHeight - height) * this.ruHeight + 2

    console.log("[RackDiagram] Setting up draggable for node:", nodeId, "height:", height, "maxY:", maxY)

    const interactable = interact(nodeEl).draggable({
      inertia: false,
      autoScroll: false,

      modifiers: [
        // Restrict vertical movement within rack bounds
        interact.modifiers.restrict({
          restriction: "parent",
          endOnly: false
        })
      ],

      listeners: {
        start: (event) => {
          console.log("[RackDiagram] Drag start:", nodeId)
          nodeEl.style.cursor = "grabbing"
          nodeEl.style.zIndex = "100"
          nodeEl.setAttribute("data-start-top", nodeEl.style.top)
        },
        move: (event) => {
          // Only move vertically
          const currentTop = parseFloat(nodeEl.style.top) || 0
          let newTop = currentTop + event.dy

          // Clamp to rack bounds
          newTop = Math.max(minY, Math.min(maxY, newTop))

          nodeEl.style.top = `${newTop}px`
        },
        end: (event) => {
          console.log("[RackDiagram] Drag end:", nodeId)
          nodeEl.style.cursor = "grab"
          nodeEl.style.zIndex = ""

          // Snap to nearest RU
          const currentTop = parseFloat(nodeEl.style.top) || 0
          const snappedRU = Math.round((currentTop - 2) / this.ruHeight)
          const snappedTop = snappedRU * this.ruHeight + 2
          nodeEl.style.top = `${Math.max(minY, Math.min(maxY, snappedTop))}px`

          this.handleNodeMoveEnd(nodeId, nodeEl)
        }
      }
    })

    this.interactables.set(nodeId, interactable)
    console.log("[RackDiagram] Draggable setup complete for node:", nodeId)
  }

  generateSnapTargets(nodeHeight) {
    const targets = []
    const maxRU = this.options.rackHeight - nodeHeight

    for (let i = 0; i <= maxRU; i++) {
      targets.push({ y: i * this.ruHeight + 2 })
    }

    return targets
  }

  selectNode(nodeData) {
    // Remove selection from all nodes
    this.nodeElements.forEach(el => {
      el.style.outline = "none"
      el.style.outlineOffset = "0"
    })

    if (nodeData) {
      const el = this.nodeElements.get(nodeData.id)
      if (el) {
        el.style.outline = "2px solid #f59e0b"
        el.style.outlineOffset = "1px"
      }
      this.selectedNode = nodeData
    } else {
      this.selectedNode = null
    }

    this.options.onSelect(this.selectedNode)
  }

  handleNodeMoveEnd(nodeId, nodeEl) {
    const pos = this.positions.get(nodeId)
    const height = pos.rack_height

    // Calculate RU from top based on current position
    const currentTop = parseFloat(nodeEl.style.top) - 2 // Subtract the 2px offset
    const ruFromTop = Math.round(currentTop / this.ruHeight)

    // Convert to rack position
    const newPosition = this.options.descUnits
      ? ruFromTop + 1
      : this.options.rackHeight - ruFromTop - height + 1

    // Check for overlap
    if (this.wouldOverlap(nodeId, newPosition, height)) {
      // Revert to original position
      const originalRuFromTop = this.options.descUnits
        ? pos.rack_position - 1
        : this.options.rackHeight - pos.rack_position - height + 1
      nodeEl.style.top = `${originalRuFromTop * this.ruHeight + 2}px`
      return
    }

    // Update position
    this.positions.set(nodeId, {
      node_id: nodeId,
      rack_position: newPosition,
      rack_height: height
    })

    // Update node data
    nodeEl._nodeData.rack_position = newPosition
    nodeEl._nodeData.position = newPosition

    // Update selected node if this is the one selected
    if (this.selectedNode && this.selectedNode.id === nodeId) {
      this.selectedNode.position = newPosition
      this.selectedNode.rack_position = newPosition
      this.options.onSelect(this.selectedNode)
    }

    this.options.onChange()
  }

  wouldOverlap(nodeId, position, height) {
    const nodeTop = position + height - 1

    for (const [id, pos] of this.positions) {
      if (id === nodeId || !pos.rack_position) continue

      const otherTop = pos.rack_position + pos.rack_height - 1
      if (position <= otherTop && pos.rack_position <= nodeTop) {
        return true
      }
    }

    return false
  }

  getPositions() {
    return Array.from(this.positions.values())
  }

  dispose() {
    // Clean up interact.js instances
    this.interactables.forEach(interactable => {
      interactable.unset()
    })
    this.interactables.clear()
    this.nodeElements.clear()

    // Clear container
    this.container.innerHTML = ""
  }
}
