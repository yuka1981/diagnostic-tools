import * as fabric from "fabric"

export class RackDiagram {
  constructor(canvasElement, options) {
    this.options = {
      rackHeight: 42,
      descUnits: false,
      nodes: [],
      readonly: false,
      onSelect: () => {},
      onChange: () => {},
      ...options
    }

    this.nodeObjects = new Map()
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

    this.initCanvas(canvasElement)
    this.render()
  }

  initCanvas(element) {
    const containerWidth = element.parentElement.clientWidth
    const ruHeight = 20
    const labelWidth = 40
    const rackWidth = containerWidth - labelWidth - 20
    const canvasHeight = this.options.rackHeight * ruHeight + 40

    this.ruHeight = ruHeight
    this.labelWidth = labelWidth
    this.rackWidth = rackWidth
    this.rackX = labelWidth + 10
    this.rackY = 20

    element.width = containerWidth
    element.height = canvasHeight

    this.canvas = new fabric.Canvas(element, {
      selection: false,
      backgroundColor: "#f8fafc"
    })

    this.canvas.on("mouse:down", this.handleMouseDown.bind(this))
  }

  render() {
    this.canvas.clear()
    this.drawRackFrame()
    this.drawRULabels()
    this.drawNodes()
    this.canvas.renderAll()
  }

  drawRackFrame() {
    const height = this.options.rackHeight * this.ruHeight

    const frame = new fabric.Rect({
      left: this.rackX,
      top: this.rackY,
      width: this.rackWidth,
      height: height,
      fill: "#e2e8f0",
      stroke: "#94a3b8",
      strokeWidth: 2,
      selectable: false,
      evented: false
    })
    this.canvas.add(frame)

    // RU grid lines
    for (let i = 1; i < this.options.rackHeight; i++) {
      const y = this.rackY + i * this.ruHeight
      const line = new fabric.Line(
        [this.rackX, y, this.rackX + this.rackWidth, y],
        {
          stroke: "#cbd5e1",
          strokeWidth: 1,
          selectable: false,
          evented: false
        }
      )
      this.canvas.add(line)
    }
  }

  drawRULabels() {
    for (let i = 1; i <= this.options.rackHeight; i++) {
      const ruNumber = this.options.descUnits ? i : this.options.rackHeight - i + 1
      const y = this.rackY + (i - 1) * this.ruHeight + this.ruHeight / 2

      const label = new fabric.FabricText(ruNumber.toString(), {
        left: this.labelWidth / 2,
        top: y,
        fontSize: 10,
        fontFamily: "system-ui",
        fill: "#64748b",
        originX: "center",
        originY: "center",
        selectable: false,
        evented: false
      })
      this.canvas.add(label)
    }
  }

  drawNodes() {
    this.nodeObjects.clear()

    this.options.nodes.forEach(node => {
      const pos = this.positions.get(node.id)
      if (!pos || !pos.rack_position) return

      const ruFromTop = this.options.descUnits
        ? pos.rack_position - 1
        : this.options.rackHeight - pos.rack_position - pos.rack_height + 1

      const y = this.rackY + ruFromTop * this.ruHeight
      const height = pos.rack_height * this.ruHeight

      // Determine color based on status
      const fillColor = node.status === "Online" ? "#14b8a6" : "#94a3b8"
      const strokeColor = node.status === "Online" ? "#0d9488" : "#64748b"

      const rect = new fabric.Rect({
        left: this.rackX + 4,
        top: y + 2,
        width: this.rackWidth - 8,
        height: height - 4,
        fill: fillColor,
        stroke: strokeColor,
        strokeWidth: 1,
        rx: 4,
        ry: 4,
        selectable: !this.options.readonly,
        hasControls: false,
        hasBorders: false,
        lockMovementX: true,
        lockScalingX: true,
        lockScalingY: true,
        lockRotation: true,
        data: { ...node, ...pos }
      })

      const text = new fabric.FabricText(node.hostname, {
        left: this.rackX + this.rackWidth / 2,
        top: y + height / 2,
        fontSize: 12,
        fontFamily: "system-ui",
        fontWeight: "bold",
        fill: "#ffffff",
        originX: "center",
        originY: "center",
        selectable: false,
        evented: false
      })

      const group = new fabric.Group([rect, text], {
        left: this.rackX + 4,
        top: y + 2,
        selectable: !this.options.readonly,
        hasControls: false,
        hasBorders: true,
        borderColor: "#0f766e",
        lockMovementX: true,
        lockScalingX: true,
        lockScalingY: true,
        lockRotation: true,
        data: { ...node, ...pos }
      })

      if (!this.options.readonly) {
        group.on("moving", this.handleNodeMove.bind(this, node.id))
        group.on("modified", this.handleNodeMoveEnd.bind(this, node.id))
      }

      this.canvas.add(group)
      this.nodeObjects.set(node.id, group)
    })
  }

  handleMouseDown(event) {
    const target = event.target

    if (target && target.data) {
      this.selectNode(target.data)
    } else {
      this.selectNode(null)
    }
  }

  selectNode(nodeData) {
    this.nodeObjects.forEach(obj => {
      obj.set({ borderColor: "#0f766e" })
    })

    if (nodeData) {
      const obj = this.nodeObjects.get(nodeData.id)
      if (obj) {
        obj.set({ borderColor: "#f59e0b" })
      }
      this.selectedNode = nodeData
    } else {
      this.selectedNode = null
    }

    this.canvas.renderAll()
    this.options.onSelect(this.selectedNode)
  }

  handleNodeMove(nodeId, event) {
    const obj = event.target
    const pos = this.positions.get(nodeId)
    const height = pos.rack_height

    let y = obj.top
    y = Math.max(this.rackY + 2, y)
    y = Math.min(this.rackY + (this.options.rackHeight - height) * this.ruHeight + 2, y)

    const ruFromTop = Math.round((y - this.rackY - 2) / this.ruHeight)
    y = this.rackY + ruFromTop * this.ruHeight + 2

    obj.set({ top: y, left: this.rackX + 4 })
  }

  handleNodeMoveEnd(nodeId, event) {
    const obj = event.target
    const pos = this.positions.get(nodeId)
    const height = pos.rack_height

    const ruFromTop = Math.round((obj.top - this.rackY - 2) / this.ruHeight)
    const newPosition = this.options.descUnits
      ? ruFromTop + 1
      : this.options.rackHeight - ruFromTop - height + 1

    if (this.wouldOverlap(nodeId, newPosition, height)) {
      this.render()
      return
    }

    this.positions.set(nodeId, {
      node_id: nodeId,
      rack_position: newPosition,
      rack_height: height
    })

    if (this.selectedNode && this.selectedNode.id === nodeId) {
      this.selectedNode.position = newPosition
      this.options.onSelect(this.selectedNode)
    }

    this.options.onChange()
    this.render()
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
    this.canvas.dispose()
  }
}
