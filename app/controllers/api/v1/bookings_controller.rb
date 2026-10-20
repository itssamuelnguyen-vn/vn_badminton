module Api
  module V1
    # The customer's bookings: the list, one booking, booking (paid by transfer: Payment) and cancelling,
    # with the same rules as the web (BookingBatch, Booking#cancel!).
    class BookingsController < BaseController
      include Slots

      before_action :require_verified_email, only: :create
      before_action :set_booking, only: %i[show cancel review_reschedule reschedule review]
      before_action :require_reschedulable, only: %i[review_reschedule reschedule]

      def index
        bookings = current_user.bookings.kind_reservation.where.not(status: :pending).includes(:court, :payment, :items, :review)
        upcoming = bookings.where(status: ::BookingsController::UPCOMING_STATUSES).where(ends_at: Time.current..).order(:starts_at)
        awaiting = Payment.awaiting.where(user: current_user).where("expires_at > ?", Time.current).order(:expires_at)
        render json: {
          upcoming: upcoming.map { |booking| ApiJson.booking(booking) },
          past: bookings.where.not(id: upcoming).order(starts_at: :desc).limit(50).map { |booking| ApiJson.booking(booking) },
          awaiting_payments: awaiting.map { |payment| ApiJson.payment(payment, Venue.main) }
        }
      end

      def show
        render json: ApiJson.booking(@booking)
      end

      def create
        batch = BookingBatch.new(user: current_user, slots: slots_param, note: params[:note], items: items_param)
        return render_error(:payments_unavailable, [ t("bookings.create.payments_unavailable") ], status: :unprocessable_content) unless batch.venue.payments_enabled?

        if (payment = batch.reserve_for_payment)
          current_user.remember_locale(I18n.locale)
          render json: ApiJson.payment(payment, batch.venue), status: :created
        else
          render_error :not_bookable, ApiJson.errors(batch), status: :unprocessable_content
        end
      end

      def cancel
        @booking.cancel!(by: current_user)
        current_user.remember_locale(I18n.locale)
        BookingMailer.with(booking: @booking).cancelled.deliver_later
        render json: ApiJson.booking(@booking)
      rescue ArgumentError
        render_error :not_allowed, [ t("bookings.cancel.not_allowed") ], status: :unprocessable_content
      rescue ActiveRecord::StaleObjectError
        render_error :changed_meanwhile, [ t("bookings.changed_meanwhile") ], status: :conflict
      end

      # The new slot (court_id, starts_at, ends_at) checked and priced without saving, as the web's review page:
      # { booking (with the new slot and price), valid, messages }.
      def review_reschedule
        @booking.price_cap_vnd = @booking.total_amount_vnd if @booking.payment_paid? # same rule as Booking#reschedule
        @booking.assign_attributes(new_slot)
        valid = @booking.validate
        render json: { booking: ApiJson.booking(@booking), valid: valid, messages: @booking.errors.full_messages }
      end

      def reschedule
        previous = @booking.attributes.slice("court_id", "starts_at", "ends_at")
        if @booking.reschedule(**new_slot, by: current_user)
          BookingMailer.with(booking: @booking, previous: previous).rescheduled.deliver_later
          render json: ApiJson.booking(@booking)
        else
          render_error :not_bookable, @booking.errors.full_messages, status: :unprocessable_content
        end
      rescue ActiveRecord::StaleObjectError
        render_error :changed_meanwhile, [ t("bookings.changed_meanwhile") ], status: :conflict
      end

      # Rating a session played (Review): { rating: 1..5, comment }.
      def review
        # Not build_review: on a has_one it would replace the existing review.
        review = Review.new(booking: @booking, user: current_user, rating: params.require(:rating), comment: params[:comment])
        if review.save
          render json: ApiJson.booking(@booking.reload), status: :created
        else
          render_error :invalid, review.errors.full_messages, status: :unprocessable_content
        end
      end

      private

      # items: [{ product_id, quantity }], the products picked with the booking.
      def items_param
        Array(params[:items]).map { |item| item.permit(:product_id, :quantity).to_h.symbolize_keys }
      end

      def set_booking
        @booking = current_user.bookings.kind_reservation.find_by!(code: params[:code])
      end

      def require_reschedulable
        render_error(:not_allowed, [ t("bookings.reschedule.not_allowed") ], status: :unprocessable_content) unless @booking.reschedulable_by_customer?
      end

      def new_slot
        { court: Venue.main.courts.active.find(params.require(:court_id)), starts_at: params.require(:starts_at), ends_at: params.require(:ends_at) }
      end
    end
  end
end
