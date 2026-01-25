import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="hostname-autocomplete"
// Provides autocomplete suggestions for hostname input fields
// Supports both single hostname suggestions and bulk pattern validation
export default class extends Controller {
  static targets = ["input", "dropdown", "badge"]
  static values = {
    url: { type: String, default: "/api/nodes/hostname_suggestions" }
  }

  connect() {
    this.timeout = null
    this.abortController = null
  }

  disconnect() {
    if (this.timeout) clearTimeout(this.timeout)
    if (this.abortController) this.abortController.abort()
  }

  search() {
    if (this.timeout) clearTimeout(this.timeout)
    this.timeout = setTimeout(() => this.fetchSuggestions(), 300)
  }

  async fetchSuggestions() {
    const prefix = this.inputTarget.value.trim()

    if (prefix.length < 2) {
      this.hideDropdown()
      this.hideBadge()
      return
    }

    if (this.abortController) this.abortController.abort()
    this.abortController = new AbortController()

    try {
      const response = await fetch(`${this.urlValue}?prefix=${encodeURIComponent(prefix)}`, {
        signal: this.abortController.signal
      })
      const data = await response.json()

      if (data.bulk) {
        this.showBulkBadge(data)
        this.hideDropdown()
      } else {
        this.showDropdown(data)
        this.hideBadge()
      }
    } catch (e) {
      if (e.name !== "AbortError") console.error("Hostname autocomplete error:", e)
    }
  }

  showDropdown(data) {
    if (!this.hasDropdownTarget) return

    const { existing, suggestions } = data

    if (existing.length === 0 && suggestions.length === 0) {
      this.hideDropdown()
      return
    }

    let html = ""

    if (suggestions.length > 0) {
      html += '<div class="px-3 py-2 text-xs font-medium text-neutral-45 bg-neutral-2">Suggestions</div>'
      suggestions.forEach(hostname => {
        html += `<button type="button"
                         class="w-full px-3 py-2 text-left text-sm hover:bg-primary-1 text-primary-7 flex items-center justify-between"
                         data-action="click->hostname-autocomplete#select"
                         data-hostname="${this.escapeHtml(hostname)}">
                   ${this.escapeHtml(hostname)}
                   <span class="text-xs text-primary-5">(next available)</span>
                 </button>`
      })
    }

    if (existing.length > 0) {
      html += '<div class="px-3 py-2 text-xs font-medium text-neutral-45 bg-neutral-2 border-t">Existing (avoid duplicates)</div>'
      existing.forEach(hostname => {
        html += `<div class="px-3 py-2 text-sm text-neutral-25 flex items-center justify-between">
                   ${this.escapeHtml(hostname)}
                   <span class="text-xs">(exists)</span>
                 </div>`
      })
    }

    this.dropdownTarget.innerHTML = html
    this.dropdownTarget.classList.remove("hidden")
  }

  hideDropdown() {
    if (this.hasDropdownTarget) {
      this.dropdownTarget.classList.add("hidden")
    }
  }

  showBulkBadge(data) {
    if (!this.hasBadgeTarget) return

    const { hostnames, conflicts } = data
    const count = hostnames ? hostnames.length : 0
    const valid = !conflicts || conflicts.length === 0

    let html = `<span class="inline-flex items-center px-3 py-1 rounded-full text-sm font-medium ${valid ? "bg-primary-1 text-primary-8" : "bg-amber-100 text-amber-800"}">
                  ${count} node${count !== 1 ? "s" : ""} will be created`

    if (!valid && conflicts.length > 0) {
      const conflictList = conflicts.slice(0, 3).map(h => this.escapeHtml(h)).join(", ")
      const moreText = conflicts.length > 3 ? "..." : ""
      html += `<span class="ml-2">| ${conflicts.length} conflict${conflicts.length !== 1 ? "s" : ""}: ${conflictList}${moreText}</span>`
    }

    html += "</span>"

    this.badgeTarget.innerHTML = html
    this.badgeTarget.classList.remove("hidden")
  }

  hideBadge() {
    if (this.hasBadgeTarget) {
      this.badgeTarget.classList.add("hidden")
    }
  }

  select(event) {
    const hostname = event.currentTarget.dataset.hostname
    this.inputTarget.value = hostname
    this.hideDropdown()
    this.inputTarget.focus()
  }

  clickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.hideDropdown()
    }
  }

  escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }
}
