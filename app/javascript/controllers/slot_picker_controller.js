import { Controller } from "@hotwired/stimulus"

// Picks a range of consecutive free 30-minute slots on one court of the schedule grid.
// Click a free slot to start, click a later (or earlier) free slot on the same court to extend,
// click inside the selection to start over from that slot, click a lone selected slot to clear.
export default class extends Controller {
  static targets = ["summary", "summaryText", "hint", "continue"]
  static values = {
    newUrl: String,
    minMinutes: Number,
    maxMinutes: Number,
    currency: String,  // e.g. "%{amount}đ"
    locale: String,    // number formatting locale, e.g. "vi-VN"
    tooShort: String,
    tooLong: String
  }

  connect() {
    this.clear()
  }

  select(event) {
    const cell = event.currentTarget
    const court = cell.dataset.courtId
    const index = Number(cell.dataset.index)
    let hint = ""

    if (court !== this.court) {
      this.startAt(court, index)
    } else if (index > this.end || index < this.start) {
      const [from, to] = index > this.end ? [this.start, index] : [index, this.end]
      if (!this.allFree(court, from, to)) {
        this.startAt(court, index)
      } else if ((to - from + 1) * 30 > this.maxMinutesValue) {
        hint = this.tooLongValue
      } else {
        this.start = from
        this.end = to
      }
    } else if (this.start === this.end) {
      this.clear()
    } else {
      this.startAt(court, index)
    }

    this.render(hint)
  }

  // private

  startAt(court, index) {
    this.court = court
    this.start = index
    this.end = index
  }

  clear() {
    this.court = null
    this.start = null
    this.end = null
    this.render("")
  }

  cells(court) {
    return [...this.element.querySelectorAll(`[data-court-id="${court}"][data-index]`)]
      .sort((a, b) => Number(a.dataset.index) - Number(b.dataset.index))
  }

  allFree(court, from, to) {
    return this.cells(court)
      .filter((cell) => Number(cell.dataset.index) >= from && Number(cell.dataset.index) <= to)
      .every((cell) => cell.dataset.available === "true")
  }

  render(hint) {
    this.element.querySelectorAll('[data-available="true"]').forEach((cell) => {
      const index = Number(cell.dataset.index)
      const selected = this.court !== null && cell.dataset.courtId === this.court && index >= this.start && index <= this.end
      cell.setAttribute("aria-pressed", selected)
    })

    if (this.court === null) {
      this.summaryTarget.hidden = true
      return
    }

    const range = this.cells(this.court).filter((cell) => {
      const index = Number(cell.dataset.index)
      return index >= this.start && index <= this.end
    })
    const first = range[0]
    const last = range[range.length - 1]
    const minutes = range.length * 30
    const total = range.reduce((sum, cell) => sum + Number(cell.dataset.price), 0)
    const amount = new Intl.NumberFormat(this.localeValue).format(total)

    this.summaryTextTarget.textContent =
      `${first.dataset.courtName} · ${first.dataset.startsLabel} – ${last.dataset.endsLabel} · ${this.currencyValue.replace("%{amount}", amount)}`

    if (!hint && minutes < this.minMinutesValue) hint = this.tooShortValue
    this.hintTarget.textContent = hint

    const tooShort = minutes < this.minMinutesValue
    const url = new URL(this.newUrlValue, window.location.origin)
    url.searchParams.set("court_id", this.court)
    url.searchParams.set("starts_at", first.dataset.startsAt)
    url.searchParams.set("ends_at", last.dataset.endsAt)
    this.continueTarget.href = url.pathname + url.search
    this.continueTarget.setAttribute("aria-disabled", tooShort)
    this.summaryTarget.hidden = false
  }
}
