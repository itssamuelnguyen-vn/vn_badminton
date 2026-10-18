import { Controller } from "@hotwired/stimulus"

// On the owner's booking form, hides the customer fields when the booking is a block
// (maintenance, private event) and switches the note's placeholder.
export default class extends Controller {
  static targets = ["customer", "note"]

  toggle(event) {
    const kind = event.target.value
    this.customerTarget.hidden = kind === "block"
    this.noteTarget.placeholder = this.noteTarget.dataset[kind === "block" ? "placeholderBlock" : "placeholderReservation"]
  }
}
