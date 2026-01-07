import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

export default class extends Controller {
  static values = { nodeId: Number }
  static targets = ["output"]

  connect() {
    this.subscription = consumer.subscriptions.create(
      { channel: "NodeLogChannel", node_id: this.nodeIdValue },
      {
        received: (data) => this.appendLog(data)
      }
    )
  }

  disconnect() {
    this.subscription.unsubscribe()
  }

  appendLog(data) {
    const { log, stream } = data
    const span = document.createElement("span")
    span.textContent = log
    if (stream === "stderr") {
      span.classList.add("text-red-500")
    } else {
      span.classList.add("text-gray-300")
    }
    this.outputTarget.appendChild(span)
    
    // Auto-scroll
    this.outputTarget.scrollTop = this.outputTarget.scrollHeight
  }
}
