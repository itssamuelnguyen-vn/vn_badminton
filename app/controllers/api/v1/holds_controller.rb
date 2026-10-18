module Api
  module V1
    # The confirmation step: picking slots holds them for Booking::HOLD_DURATION (BookingBatch#hold), as when
    # the web's confirmation page opens. slots: [{ court_id:, starts_at:, ends_at: }], one range per court.
    class HoldsController < BaseController
      include Slots

      rate_limit to: 30, within: 10.minutes, only: :create, by: -> { current_user.id }, store: RATE_LIMIT_STORE, with: -> { rate_limited }
      before_action :require_verified_email, only: :create

      def create
        batch = BookingBatch.new(user: current_user, slots: slots_param)
        if batch.hold
          render json: { held_until: batch.held_until.iso8601, amount_vnd: batch.total_amount_vnd,
                         bookings: batch.bookings.map { |booking| ApiJson.booking(booking) } }, status: :created
        else
          render_error :not_bookable, ApiJson.errors(batch), status: :unprocessable_content
        end
      end

      # "Pick another time": frees the held slots at once.
      def destroy
        Booking.delete_holds!(current_user.bookings)
        head :no_content
      end
    end
  end
end
