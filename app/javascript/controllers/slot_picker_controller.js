import { Controller } from "@hotwired/stimulus"

// Picks consecutive free 30-minute slots on the schedule grid: one range per court.
// Click a free slot to start, click a later (or earlier) free slot on the same court to extend,
// click inside a range to start over from that slot, click a lone selected slot to clear it.
// With the "several courts" box ticked, each court keeps its own range; otherwise picking
// another court replaces the selection.
//
// The page refreshes live when others book (Turbo morph). Row indexes can change then (today's past rows
// disappear), so the selection is also kept by start time and mapped back onto the new grid; a range that
// is no longer free is dropped with a hint.
export default class extends Controller {
  static targets = ["summary", "summaryList", "total", "hint", "continue", "multiple"]
  static values = {
    newUrl: String,
    minMinutes: Number,
    maxMinutes: Number,
    currency: String,  // e.g. "%{amount}đ"
    locale: String,    // number formatting locale, e.g. "vi-VN"
    tooShort: String,
    tooLong: String,
    totalLabel: String, // e.g. "Tổng cộng: %{amount}"
    taken: String       // shown when a refresh finds a picked slot taken
  }

  connect() {
    this.ranges = new Map() // court id -> { start, end } (row indexes, inclusive)
    this.times = new Map()  // court id -> { from, to } (starts_at of the first and last picked slot)
    this.lastCourt = null
    this.restore = () => this.restoreAfterRefresh()
    document.addEventListener("turbo:morph", this.restore)
    this.render("")
  }

  disconnect() {
    document.removeEventListener("turbo:morph", this.restore)
  }

  select(event) {
    const cell = event.currentTarget
    const court = cell.dataset.courtId
    const index = Number(cell.dataset.index)
    const range = this.ranges.get(court)
    let hint = ""

    if (!this.multiple) {
      for (const other of [...this.ranges.keys()]) if (other !== court) this.ranges.delete(other)
    }

    if (!range) {
      this.ranges.set(court, { start: index, end: index })
    } else if (index > range.end || index < range.start) {
      const [from, to] = index > range.end ? [range.start, index] : [index, range.end]
      if (!this.allFree(court, from, to)) {
        this.ranges.set(court, { start: index, end: index })
      } else if ((to - from + 1) * 30 > this.maxMinutesValue) {
        hint = this.tooLongValue
      } else {
        this.ranges.set(court, { start: from, end: to })
      }
    } else if (range.start === range.end) {
      this.ranges.delete(court)
    } else {
      this.ranges.set(court, { start: index, end: index })
    }

    this.lastCourt = court
    this.render(hint)
  }

  // Unticking "several courts" keeps only the court picked last.
  toggleMultiple() {
    if (!this.multiple) {
      for (const court of [...this.ranges.keys()]) if (court !== this.lastCourt) this.ranges.delete(court)
    }
    this.render("")
  }

  // private

  // After a live refresh: find the picked times again; drop the courts where a slot got taken.
  restoreAfterRefresh() {
    let hint = ""
    this.ranges = new Map()
    for (const [court, { from, to }] of this.times) {
      const cells = [...this.element.querySelectorAll(`[data-court-id="${court}"][data-index]`)]
      const first = cells.find((cell) => cell.dataset.startsAt === from)
      const last = cells.find((cell) => cell.dataset.startsAt === to)
      const start = first && Number(first.dataset.index)
      const end = last && Number(last.dataset.index)
      if (first && last && this.allFree(court, start, end)) {
        this.ranges.set(court, { start, end })
      } else {
        hint = this.takenValue
      }
    }
    this.render(hint)
  }

  get multiple() {
    return this.hasMultipleTarget && this.multipleTarget.checked
  }

  cells(court, from, to) {
    return [...this.element.querySelectorAll(`[data-court-id="${court}"][data-index]`)]
      .filter((cell) => Number(cell.dataset.index) >= from && Number(cell.dataset.index) <= to)
      .sort((a, b) => Number(a.dataset.index) - Number(b.dataset.index))
  }

  allFree(court, from, to) {
    return this.cells(court, from, to).every((cell) => cell.dataset.available === "true")
  }

  formatPrice(amount) {
    return this.currencyValue.replace("%{amount}", new Intl.NumberFormat(this.localeValue).format(amount))
  }

  render(hint) {
    this.times = new Map([...this.ranges.entries()].map(([court, range]) => {
      const cells = this.cells(court, range.start, range.end)
      return [court, { from: cells[0].dataset.startsAt, to: cells[cells.length - 1].dataset.startsAt }]
    }))

    this.element.querySelectorAll('[data-available="true"]').forEach((cell) => {
      const range = this.ranges.get(cell.dataset.courtId)
      const index = Number(cell.dataset.index)
      cell.setAttribute("aria-pressed", Boolean(range && index >= range.start && index <= range.end))
    })

    if (this.ranges.size === 0) {
      this.summaryTarget.hidden = !hint
      this.summaryListTarget.replaceChildren()
      this.totalTarget.textContent = ""
      this.hintTarget.textContent = hint
      this.continueTarget.setAttribute("aria-disabled", true)
      return
    }

    // One line per court, in the grid's column order.
    const selections = [...this.ranges.entries()].map(([court, range]) => {
      const cells = this.cells(court, range.start, range.end)
      return {
        court,
        first: cells[0],
        last: cells[cells.length - 1],
        minutes: cells.length * 30,
        price: cells.reduce((sum, cell) => sum + Number(cell.dataset.price), 0)
      }
    }).sort((a, b) => a.first.dataset.courtName.localeCompare(b.first.dataset.courtName, undefined, { numeric: true }))

    this.summaryListTarget.replaceChildren(...selections.map((selection) => {
      const item = document.createElement("li")
      item.textContent = `${selection.first.dataset.courtName} · ${selection.first.dataset.startsLabel} – ${selection.last.dataset.endsLabel} · ${this.formatPrice(selection.price)}`
      return item
    }))
    const total = this.formatPrice(selections.reduce((sum, s) => sum + s.price, 0))
    this.totalTarget.textContent = selections.length > 1 ? this.totalLabelValue.replace("%{amount}", total) : ""

    const tooShort = selections.some((selection) => selection.minutes < this.minMinutesValue)
    this.hintTarget.textContent = hint || (tooShort ? this.tooShortValue : "")

    const url = new URL(this.newUrlValue, window.location.origin)
    selections.forEach((selection, i) => {
      url.searchParams.set(`slots[${i}][court_id]`, selection.court)
      url.searchParams.set(`slots[${i}][starts_at]`, selection.first.dataset.startsAt)
      url.searchParams.set(`slots[${i}][ends_at]`, selection.last.dataset.endsAt)
    })
    this.continueTarget.href = url.pathname + url.search
    this.continueTarget.setAttribute("aria-disabled", tooShort)
    this.summaryTarget.hidden = false
  }
}
