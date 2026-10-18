module Api
  module V1
    # The customer's bookings: the list, one booking, booking (paid by transfer: Payment) and cancelling,
    # with the same rules as the web (BookingBatch, Booking#cancel!).
    class BookingsController < BaseController
      include Slots

      before_action :require_verified_email, only: :create

      def index
        bookings = current_user.bookings.kind_reservation.where.not(status: :pending).includes(:court, :payment)
        upcoming = bookings.where(status: ::BookingsController::UPCOMING_STATUSES).where(ends_at: Time.current..).order(:starts_at)
        awaiting = Payment.awaiting.where(user: current_user).where("expires_at > ?", Time.current).order(:expires_at)
        render json: {
          upcoming: upcoming.map { |booking| ApiJson.booking(booking) },
          past: bookings.where.not(id: upcoming).order(starts_at: :desc).limit(50).map { |booking| ApiJson.booking(booking) },
          awaiting_payments: awaiting.map { |payment| ApiJson.payment(payment, Venue.main) }
        }
      end

      def show
        render json: ApiJson.booking(current_user.bookings.kind_reservation.find_by!(code: params[:code]))
      end

      def create
        batch = BookingBatch.new(user: current_user, slots: slots_param, note: params[:note])
        return render_error(:payments_unavailable, [ t("bookings.create.payments_unavailable") ], status: :unprocessable_content) unless batch.venue.payments_enabled?

        if (payment = batch.reserve_for_payment)
          current_user.remember_locale(I18n.locale)
          render json: ApiJson.payment(payment, batch.venue), status: :created
        else
          render_error :not_bookable, ApiJson.errors(batch), status: :unprocessable_content
        end
      end

      def cancel
        booking = current_user.bookings.kind_reservation.find_by!(code: params[:code])
        booking.cancel!(by: current_user)
        current_user.remember_locale(I18n.locale)
        BookingMailer.with(booking: booking).cancelled.deliver_later
        render json: ApiJson.booking(booking)
      rescue ArgumentError
        render_error :not_allowed, [ t("bookings.cancel.not_allowed") ], status: :unprocessable_content
      rescue ActiveRecord::StaleObjectError
        render_error :changed_meanwhile, [ t("bookings.changed_meanwhile") ], status: :conflict
      end
    end
  end
end
