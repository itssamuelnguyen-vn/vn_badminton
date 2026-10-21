module Api
  module V1
    # The customer's weekly bookings (BookingSeries, made by the venue) with each month's bill. The customer can
    # get a transfer code for a month still to pay, as the staff do on the web (CD-03).
    class SeriesController < BaseController
      def index
        venue = Venue.main
        render json: { series: BookingSeries.shown_to(current_user, venue.today).map { |one| ApiJson.series(one, venue) } }
      end

      # { month: "YYYY-MM" } -> payment (the one waiting already, or a new one for the amount due).
      def pay
        venue = Venue.main
        bill = BookingSeries.where(user: current_user).find(params[:id]).billing(Date.strptime(params.require(:month), "%Y-%m"))
        return render_error(:payments_unavailable, [ t("bookings.create.payments_unavailable") ], status: :unprocessable_content) unless venue.payments_enabled?
        return render_error(:not_allowed, [ t("api.series.nothing_due") ], status: :unprocessable_content) unless bill.payable?

        render json: ApiJson.payment(bill.request_payment!(by: current_user), venue)
      rescue Date::Error
        render_error :invalid, [], status: :unprocessable_content
      end
    end
  end
end
