import { Controller } from "@hotwired/stimulus"

// Auto-refresh controller for Tasks page
// Usage:
//   <div data-controller="auto-refresh" data-auto-refresh-frame-value="tasks_list">
//     <select data-auto-refresh-target="select" data-action="change->auto-refresh#updateInterval">
export default class extends Controller {
  static targets = ["select", "countdown"]
  static values = {
    frame: String,
    interval: { type: Number, default: 0 }
  }

  connect() {
    this.timer = null
    this.countdownTimer = null
    this.remainingSeconds = 0
    this.startIfNeeded()

    // Pause when tab is hidden
    document.addEventListener("visibilitychange", this.handleVisibilityChange.bind(this))
  }

  disconnect() {
    this.stop()
    document.removeEventListener("visibilitychange", this.handleVisibilityChange.bind(this))
  }

  updateInterval(event) {
    this.intervalValue = parseInt(event.target.value, 10) || 0
    this.stop()
    this.startIfNeeded()
  }

  intervalValueChanged() {
    this.stop()
    this.startIfNeeded()
  }

  startIfNeeded() {
    if (this.intervalValue > 0 && !document.hidden) {
      this.remainingSeconds = this.intervalValue / 1000
      this.updateCountdown()
      this.startCountdown()
      this.timer = setTimeout(() => this.refresh(), this.intervalValue)
    }
  }

  stop() {
    if (this.timer) {
      clearTimeout(this.timer)
      this.timer = null
    }
    if (this.countdownTimer) {
      clearInterval(this.countdownTimer)
      this.countdownTimer = null
    }
    this.updateCountdown()
  }

  refresh() {
    const frame = document.getElementById(this.frameValue)
    if (frame) {
      frame.reload()
    }
    this.startIfNeeded()
  }

  startCountdown() {
    this.countdownTimer = setInterval(() => {
      this.remainingSeconds = Math.max(0, this.remainingSeconds - 1)
      this.updateCountdown()
    }, 1000)
  }

  updateCountdown() {
    if (!this.hasCountdownTarget) return

    if (this.intervalValue > 0 && this.remainingSeconds > 0) {
      this.countdownTarget.textContent = `${this.remainingSeconds}s`
      this.countdownTarget.classList.remove("hidden")
    } else {
      this.countdownTarget.classList.add("hidden")
    }
  }

  handleVisibilityChange() {
    if (document.hidden) {
      this.stop()
    } else {
      this.startIfNeeded()
    }
  }
}
