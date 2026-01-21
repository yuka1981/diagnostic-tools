import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["parent", "child"]
  static values = {
    url: { type: String, default: "/rooms/for_site" }
  }

  parentChanged() {
    const siteId = this.parentTarget.value

    if (!siteId) {
      // Reset to all rooms and submit
      this.element.submit()
      return
    }

    // Fetch rooms for site and update child select
    fetch(`${this.urlValue}?site_id=${siteId}`)
      .then(response => response.json())
      .then(rooms => {
        this.updateChildOptions(rooms)
        this.element.submit()
      })
  }

  updateChildOptions(rooms) {
    const child = this.childTarget
    const currentValue = child.value

    // Clear existing options except "All Rooms"
    while (child.options.length > 1) {
      child.remove(1)
    }

    // Add new options
    rooms.forEach(room => {
      const option = new Option(room.name, room.id)
      child.add(option)
    })

    // Restore selection if still valid
    if (rooms.some(r => r.id.toString() === currentValue)) {
      child.value = currentValue
    }
  }
}
