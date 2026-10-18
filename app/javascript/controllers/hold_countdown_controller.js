import { Controller } from "@hotwired/stimulus"

// Counts down the time left to confirm the held slots on the confirmation page. The server decides what
// happens after it (the customer can still confirm if nobody took the slots); this only informs.
export default class extends Controller {
  static targets = ["clock", "running", "expired"]
  static values = { seconds: Number }

  connect() {
    this.deadline = Date.now() + this.secondsValue * 1000
    this.tick()
    this.timer = setInterval(() => this.tick(), 1000)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  tick() {
    const left = Math.max(0, Math.round((this.deadline - Date.now()) / 1000))
    this.clockTarget.textContent = `${Math.floor(left / 60)}:${String(left % 60).padStart(2, "0")}`
    if (left > 0) return

    clearInterval(this.timer)
    this.runningTarget.hidden = true
    this.expiredTarget.hidden = false
  }
}
