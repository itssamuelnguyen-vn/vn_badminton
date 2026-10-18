// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

// Live refreshes of the schedule (a Turbo stream "refresh" sent by the server when someone books) are not
// user activity: the next request is marked so the session timeout ignores it (ApplicationController).
let backgroundRefresh = false
document.addEventListener("turbo:before-stream-render", (event) => {
  if (event.target.getAttribute("action") === "refresh") backgroundRefresh = true
})
document.addEventListener("turbo:before-fetch-request", (event) => {
  if (!backgroundRefresh) return
  event.detail.fetchOptions.headers["X-Background-Refresh"] = "1"
  backgroundRefresh = false
})
