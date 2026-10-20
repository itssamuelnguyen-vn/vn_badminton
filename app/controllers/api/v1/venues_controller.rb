module Api
  module V1
    # The venue: courts, booking policy, price list and contact links. Public, so the app can show it signed out.
    class VenuesController < BaseController
      skip_before_action :authenticate!

      def show
        render json: ApiJson.venue(Venue.main)
      end
    end
  end
end
