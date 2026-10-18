module ApplicationHelper
  # The venue whose contact channels the layout shows (none yet on a fresh install).
  def contact_venue
    return @contact_venue if defined?(@contact_venue)

    @contact_venue = Venue.active.order(:id).first
  end
end
