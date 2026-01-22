import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "hiddenField", "results", "preview", "rackHeight"]
  static values = {
    url: { type: String, default: "/api/server_products/search" }
  }

  connect() {
    this.debounceTimer = null
    this.initializePreview()
  }

  initializePreview() {
    // Show preview if there's an existing selection (editing an existing node)
    if (this.hasHiddenFieldTarget && this.hiddenFieldTarget.value && this.hasInputTarget && this.inputTarget.value) {
      const previewData = {
        name: this.inputTarget.value,
        formFactor: "",
        rackHeight: ""
      }
      this.showPreview(previewData)
    }
  }

  search() {
    const query = this.inputTarget.value
    if (query.length < 2) {
      this.hideResults()
      return
    }

    clearTimeout(this.debounceTimer)
    this.debounceTimer = setTimeout(() => this.fetchResults(query), 300)
  }

  async fetchResults(query) {
    try {
      const response = await fetch(`${this.urlValue}?q=${encodeURIComponent(query)}`)
      const products = await response.json()
      this.renderResults(products)
    } catch (error) {
      console.error("Search failed:", error)
      this.hideResults()
    }
  }

  renderResults(products) {
    if (products.length === 0) {
      this.hideResults()
      return
    }

    const html = products.map(p => `
      <button type="button"
              class="w-full px-3 py-2 text-left hover:bg-slate-100 flex items-center gap-3"
              data-action="click->server-product-search#select"
              data-id="${p.id}"
              data-name="${this.escapeHtml(p.name)}"
              data-rack-height="${p.rack_height}"
              data-form-factor="${p.form_factor || ''}"
              data-thumbnail-url="${p.thumbnail_url || ''}">
        ${p.thumbnail_url
          ? `<img src="${p.thumbnail_url}" class="w-10 h-8 object-contain rounded border" alt="" />`
          : `<div class="w-10 h-8 bg-slate-100 rounded border flex items-center justify-center">
              <svg class="w-4 h-4 text-slate-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 12h14M5 12a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v4a2 2 0 01-2 2M5 12a2 2 0 00-2 2v4a2 2 0 002 2h14a2 2 0 002-2v-4a2 2 0 00-2-2" />
              </svg>
            </div>`
        }
        <div class="flex-1 min-w-0">
          <p class="text-sm font-medium text-slate-900 truncate">${this.escapeHtml(p.name)}</p>
          <p class="text-xs text-slate-500">${p.form_factor || ''} • ${p.rack_height}U</p>
        </div>
      </button>
    `).join("")

    this.resultsTarget.innerHTML = html
    this.resultsTarget.classList.remove("hidden")
  }

  select(event) {
    event.preventDefault()
    const button = event.currentTarget
    const id = button.dataset.id
    const name = button.dataset.name
    const rackHeight = button.dataset.rackHeight

    // Update hidden field and display input
    this.hiddenFieldTarget.value = id
    this.inputTarget.value = name

    // Auto-fill rack_height
    if (this.hasRackHeightTarget && rackHeight) {
      this.rackHeightTarget.value = rackHeight
    } else {
      // Try to find rack_height field in the form
      const rackHeightField = document.querySelector('[name="node[rack_height]"]')
      if (rackHeightField && rackHeight) {
        rackHeightField.value = rackHeight
      }
    }

    // Show preview
    this.showPreview(button.dataset)

    // Hide results
    this.hideResults()
  }

  showPreview(data) {
    if (!this.hasPreviewTarget) return

    this.previewTarget.innerHTML = `
      <div class="flex items-center gap-4 p-3 bg-slate-50 rounded-lg border border-slate-200">
        ${data.thumbnailUrl
          ? `<img src="${data.thumbnailUrl}" class="w-16 h-12 object-contain rounded border" alt="" />`
          : `<div class="w-16 h-12 bg-slate-100 rounded border flex items-center justify-center">
              <svg class="w-6 h-6 text-slate-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 12h14M5 12a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v4a2 2 0 01-2 2M5 12a2 2 0 00-2 2v4a2 2 0 002 2h14a2 2 0 002-2v-4a2 2 0 00-2-2" />
              </svg>
            </div>`
        }
        <div class="flex-1">
          <p class="text-sm font-bold text-slate-900">${this.escapeHtml(data.name)}</p>
          <p class="text-xs text-slate-500">${data.formFactor || ''} • ${data.rackHeight}U</p>
        </div>
        <button type="button"
                class="text-slate-400 hover:text-red-600"
                data-action="click->server-product-search#clear">
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
      </div>
    `
    this.previewTarget.classList.remove("hidden")
  }

  clear(event) {
    event.preventDefault()
    this.hiddenFieldTarget.value = ""
    this.inputTarget.value = ""
    if (this.hasPreviewTarget) {
      this.previewTarget.innerHTML = ""
      this.previewTarget.classList.add("hidden")
    }
  }

  hideResults() {
    if (this.hasResultsTarget) {
      this.resultsTarget.classList.add("hidden")
      this.resultsTarget.innerHTML = ""
    }
  }

  escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }
}
