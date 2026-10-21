import { Controller } from "@hotwired/stimulus"

// A list with a checkbox per row, a "select all" box and a submit button that shows how many are ticked
// and stays disabled while none is.
export default class extends Controller {
  static targets = ["item", "all", "button", "count"]

  connect() {
    this.update()
  }

  toggleAll() {
    this.itemTargets.forEach((item) => { item.checked = this.allTarget.checked })
    this.update()
  }

  update() {
    const ticked = this.itemTargets.filter((item) => item.checked).length
    this.buttonTarget.disabled = ticked === 0
    this.countTarget.textContent = ticked > 0 ? ` (${ticked})` : ""
    if (this.hasAllTarget) {
      this.allTarget.checked = ticked > 0 && ticked === this.itemTargets.length
      this.allTarget.indeterminate = ticked > 0 && ticked < this.itemTargets.length
    }
  }
}
