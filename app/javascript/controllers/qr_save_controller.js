import { Controller } from "@hotwired/stimulus"

// The "save the QR" link of the payment page: bank apps scan a QR code from a saved picture. iPhones keep
// downloads in Files, where bank apps do not look, so there the picture goes through the share sheet
// ("Save Image" puts it in Photos). Elsewhere, and if sharing is not possible, the link downloads it.
export default class extends Controller {
  static targets = ["link"]
  static values = { filename: String }

  connect() {
    if (!this.isIOS() || !navigator.canShare) return

    // Fetched beforehand: the share sheet only opens straight from the tap.
    fetch(this.linkTarget.href)
      .then((response) => (response.ok ? response.blob() : null))
      .then((blob) => {
        const file = blob && new File([blob], this.filenameValue, { type: "image/png" })
        if (file && navigator.canShare({ files: [file] })) this.file = file
      })
      .catch(() => {})
  }

  save(event) {
    if (!this.file) return

    event.preventDefault()
    navigator.share({ files: [this.file] }).catch((error) => {
      if (error.name !== "AbortError") window.location.href = this.linkTarget.href
    })
  }

  isIOS() {
    return /iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1)
  }
}
