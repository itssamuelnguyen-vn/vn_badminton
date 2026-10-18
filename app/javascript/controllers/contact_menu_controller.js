import { Controller } from "@hotwired/stimulus"

// The "Liên hệ" menu (a <details>) closes on a tap outside it or on Escape.
export default class extends Controller {
  closeOutside(event) {
    if (!this.element.contains(event.target)) this.close()
  }

  close() {
    this.element.open = false
  }
}
