import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container", "rangeButton"]
  static values = {
    nodeId: Number,
    sensorType: String,
    range: { type: String, default: "24h" }
  }

  connect() {
    this.loadChartData()
  }

  changeRange(event) {
    event.preventDefault()
    this.rangeValue = event.currentTarget.dataset.range

    // Update active button styling
    this.rangeButtonTargets.forEach(btn => {
      btn.classList.remove("bg-primary-6", "text-white")
      btn.classList.add("bg-neutral-4", "text-neutral-65")
    })
    event.currentTarget.classList.remove("bg-neutral-4", "text-neutral-65")
    event.currentTarget.classList.add("bg-primary-6", "text-white")

    this.loadChartData()
  }

  async loadChartData() {
    try {
      const url = `/api/v1/bmc/sensors/${this.nodeIdValue}?sensor_type=${this.sensorTypeValue}&range=${this.rangeValue}`
      const response = await fetch(url, {
        headers: { "Accept": "application/json" }
      })
      if (!response.ok) return

      const data = await response.json()
      this.containerTarget.innerHTML = ""

      if (data.chart_data && data.chart_data.length > 0) {
        this.renderChartData(data.chart_data)
      } else {
        this.containerTarget.innerHTML = '<p class="text-sm text-neutral-45 py-4">No sensor data available for this time range.</p>'
      }
    } catch (error) {
      console.error("Failed to load chart data:", error)
    }
  }

  renderChartData(chartData) {
    const chartId = `chart-${this.sensorTypeValue}-${Date.now()}`
    const canvas = document.createElement("div")
    canvas.id = chartId
    this.containerTarget.appendChild(canvas)

    // Use Chartkick to render
    if (typeof Chartkick !== "undefined") {
      new Chartkick.LineChart(chartId, chartData, {
        xtitle: "Time",
        ytitle: this.sensorTypeValue,
        curve: true,
        points: false
      })
    }
  }
}
