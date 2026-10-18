# Static pages. Their text lives in locale-specific templates (privacy.vi.html.slim, privacy.en.html.slim).
class PagesController < ApplicationController
  def privacy
    @venue = Venue.main
  end
end
