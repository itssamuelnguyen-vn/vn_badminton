import { Controller } from "@hotwired/stimulus"

// Opens and closes the month calendar of the schedule's date picker, and switches between months.
// The calendar itself (and which days can be picked) is rendered by the server.
export default class extends Controller {
  static targets = ["toggle", "panel", "month"]

  connect() {
    this.closeOnOutsideClick = (event) => { if (!this.element.contains(event.target)) this.close() }
    this.closeOnEscape = (event) => { if (event.key === "Escape") this.close({ focus: true }) }
  }

  disconnect() {
    this.close()
  }

  toggle() {
    this.panelTarget.hidden ? this.open() : this.close()
  }

  open() {
    this.panelTarget.hidden = false
    this.toggleTarget.setAttribute("aria-expanded", "true")
    document.addEventListener("click", this.closeOnOutsideClick)
    document.addEventListener("keydown", this.closeOnEscape)
  }

  close({ focus = false } = {}) {
    if (!this.hasPanelTarget || this.panelTarget.hidden) return

    this.panelTarget.hidden = true
    this.toggleTarget.setAttribute("aria-expanded", "false")
    document.removeEventListener("click", this.closeOnOutsideClick)
    document.removeEventListener("keydown", this.closeOnEscape)
    if (focus) this.toggleTarget.focus()
  }

  showMonth({ params: { index } }) {
    this.monthTargets.forEach((month, i) => { month.hidden = i !== index })
  }
}
