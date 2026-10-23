import { Controller } from "@hotwired/stimulus"

// Google's "Sign in with Google" button (Google Identity Services) on the sign-in and sign-up pages. Google's
// script draws the button; the ID token it gives back is posted with the form around it, Rails' CSRF token
// included (Users::GoogleController#create). Without the script (blocked, offline) the section stays hidden.
const SCRIPT = "https://accounts.google.com/gsi/client"
let loading

function loadScript() {
  loading ||= new Promise((resolve, reject) => {
    const script = document.createElement("script")
    script.src = SCRIPT
    script.async = true
    script.onload = resolve
    script.onerror = () => {
      loading = null
      reject()
    }
    document.head.append(script)
  })
  return loading
}

export default class extends Controller {
  static targets = ["button", "credential"]
  static values = { clientId: String, locale: String }

  connect() {
    loadScript()
      .then(() => this.render())
      .catch(() => {})
  }

  render() {
    if (!this.element.isConnected) return

    google.accounts.id.initialize({
      client_id: this.clientIdValue,
      callback: ({ credential }) => {
        this.credentialTarget.value = credential
        this.element.requestSubmit()
      },
    })
    google.accounts.id.renderButton(this.buttonTarget, {
      theme: "outline",
      size: "large",
      shape: "pill",
      text: "continue_with",
      locale: this.localeValue,
      width: Math.min(400, this.buttonTarget.clientWidth || 320),
    })
    this.element.hidden = false
  }
}
