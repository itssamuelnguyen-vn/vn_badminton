module Api
  module V1
    # The customer's weekly bookings (BookingSeries, made by the venue) with each month's bill. The customer can
    # get a transfer code for a month still to pay, as the staff do on the web (CD-03).
    class SeriesController < BaseController
      def index
        venue = Venue.main
        series = BookingSeries.where(user: current_user).where(ends_on: venue.today.beginning_of_month.prev_month..).order(:starts_on)
        render json: { series: series.map { |one| ApiJson.series(one, venue) } }
      end

      # { month: "YYYY-MM" } -> payment (the one waiting already, or a new one for the amount due).
      def pay
        venue = Venue.main
        series = BookingSeries.where(user: current_user).find(params[:id])
        month = Date.strptime(params.require(:month), "%Y-%m")
        bill = series.billing(month)
        return render_error(:payments_unavailable, [ t("bookings.create.payments_unavailable") ], status: :unprocessable_content) unless venue.payments_enabled?
        return render_error(:not_allowed, [ t("api.series.nothing_due") ], status: :unprocessable_content) if bill.paid? || bill.due_vnd <= 0 || !series.months.include?(month)

        payment = series.payments.awaiting.where(series_month: month).find_by(amount_vnd: bill.due_vnd)
        payment ||= Payment.transaction do
          series.payments.awaiting.where(series_month: month).find_each { |old| old.update!(status: :cancelled) }
          Payment.create!(purpose: :series_period, series: series, series_month: month, amount_vnd: bill.due_vnd, user: current_user, created_by: current_user)
        end
        render json: ApiJson.payment(payment, venue)
      rescue Date::Error
        render_error :invalid, [], status: :unprocessable_content
      end
    end
  end
end
