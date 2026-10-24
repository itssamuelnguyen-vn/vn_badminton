import { Controller } from "@hotwired/stimulus"

// A link to send to friends (a tournament's page, its organizer link): the phone's share sheet (Zalo, Messenger…)
// when there is one, else copied to the clipboard, the button saying so for a moment.
export default class extends Controller {
  static targets = ["button"]
  static values = { url: String, title: String, copied: String }

  async share() {
    if (navigator.share && /Android|iPhone|iPad/i.test(navigator.userAgent)) {
      try {
        await navigator.share({ title: this.titleValue, url: this.urlValue })
        return
      } catch (error) {
        if (error.name === "AbortError") return
      }
    }
    await navigator.clipboard.writeText(this.urlValue)
    const label = this.buttonTarget.textContent
    this.buttonTarget.textContent = this.copiedValue
    setTimeout(() => { this.buttonTarget.textContent = label }, 2000)
  }
}
