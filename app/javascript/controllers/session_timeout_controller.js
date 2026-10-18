import { Controller } from "@hotwired/stimulus"

// Signed-in pages reload themselves once the session has timed out (Devise :timeoutable), so the server
// signs the user out and shows the sign-in page instead of leaving stale data on screen.
// The clock restarts with every request the user makes; live background refreshes do not count.
export default class extends Controller {
  static values = { seconds: Number }

  connect() {
    this.activity = (event) => {
      if (event.detail?.fetchOptions?.headers?.["X-Background-Refresh"]) return
      this.restart()
    }
    document.addEventListener("turbo:before-fetch-request", this.activity)
    this.restart()
  }

  disconnect() {
    document.removeEventListener("turbo:before-fetch-request", this.activity)
    clearTimeout(this.timer)
  }

  restart() {
    clearTimeout(this.timer)
    // A few seconds late, so the server sees the session as expired.
    this.timer = setTimeout(() => window.location.reload(), (this.secondsValue + 5) * 1000)
  }
}
