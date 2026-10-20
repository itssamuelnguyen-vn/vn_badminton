module Api
  module V1
    # The owner's current news (Announcement), shown above the schedule. Public.
    class AnnouncementsController < BaseController
      skip_before_action :authenticate!

      def index
        venue = Venue.main
        render json: { announcements: venue.announcements.current(venue.today).map { |announcement| ApiJson.announcement(announcement) } }
      end
    end
  end
end
