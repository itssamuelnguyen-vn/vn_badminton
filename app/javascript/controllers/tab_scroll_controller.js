import { Controller } from "@hotwired/stimulus"

// Keeps the current tab in view when the tab bar scrolls sideways (phones): each visit renders a new bar
// scrolled to the start, which would hide a tab near the end.
export default class extends Controller {
  connect() {
    const current = this.element.querySelector("[aria-current=page]")
    if (!current || this.element.scrollWidth <= this.element.clientWidth) return

    this.element.scrollLeft = current.offsetLeft - (this.element.clientWidth - current.offsetWidth) / 2
  }
}
