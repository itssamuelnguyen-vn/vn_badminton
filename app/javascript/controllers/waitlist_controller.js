import { Controller } from "@hotwired/stimulus"

// "Báo khi có sân trống" on the schedule: clicking a taken slot opens the wait form with that time filled in,
// from the slot's start to one hour later (or the day's last slot), and brings it into view.
export default class extends Controller {
  static targets = ["panel", "from", "to"]

  pick(event) {
    if (!this.hasPanelTarget) return

    const startsAt = event.currentTarget.dataset.startsAt
    const fromIndex = [...this.fromTarget.options].findIndex((option) => option.value === startsAt)
    if (fromIndex < 0) return

    this.fromTarget.selectedIndex = fromIndex
    // The "to" options end one slot after the "from" options at the same index: one hour = two slots.
    this.toTarget.selectedIndex = Math.min(fromIndex + 1, this.toTarget.options.length - 1)
    this.panelTarget.open = true
    this.panelTarget.scrollIntoView({ behavior: "smooth", block: "center" })
    this.fromTarget.focus({ preventScroll: true })
  }
}
