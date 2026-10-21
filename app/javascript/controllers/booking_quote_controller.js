import { Controller } from "@hotwired/stimulus"

// The confirmation page's price box follows the extras picked and the voucher code: the form's slots, quantities
// and code are sent to BookingsController#quote, which re-renders the box (the "booking_quote" Turbo frame).
// The +/− buttons next to each extra change its quantity within 0..max.
export default class extends Controller {
  static values = { url: String }

  disconnect() {
    clearTimeout(this.timer)
  }

  step({ params: { input, delta } }) {
    const field = document.getElementById(input)
    const max = Number(field.max) || 20
    field.value = Math.min(max, Math.max(0, (parseInt(field.value, 10) || 0) + delta))
    this.refresh()
  }

  // Waits for a short pause in typing or clicking before asking for the new price.
  refresh() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.load(), 250)
  }

  load() {
    const query = new URLSearchParams()
    for (const [key, value] of new FormData(this.element)) {
      if (key.startsWith("booking[slots]") || key.startsWith("booking[quantities]") || key === "booking[voucher_code]") query.append(key, value)
    }
    const frame = document.getElementById("booking_quote")
    if (frame) frame.src = `${this.urlValue}?${query}`
  }
}
