module Admin
  # Bookings taken by the owner (phone calls, walk-ins) and maintenance blocks, plus the day-to-day
  # actions on any booking: check-in, no-show, payment and cancellation.
  class BookingsController < BaseController
    before_action :set_booking, only: %i[show check_in no_show mark_paid cancel]

    def show
    end

    # Opened from an empty cell of the board: /admin/bookings/new?court_id=3&date=2026-10-20&start_minute=1080
    def new
      @form = BookingForm.new(venue: venue, attributes: params.permit(*BookingForm::FIELDS).to_h)
      @form.end_minute ||= @form.start_minute + venue.min_booking_minutes if @form.start_minute
    end

    def create
      @form = BookingForm.new(venue: venue, attributes: params.require(:booking).permit(*BookingForm::FIELDS).to_h)
      booking = @form.build(created_by: current_user)

      if booking.reserve
        BookingMailer.with(bookings: [ booking ]).confirmed.deliver_later if booking.user
        redirect_to admin_root_path(date: @form.date&.iso8601), notice: t(".success.#{booking.kind}", court: booking.court.display_name)
      else
        @booking = booking
        render :new, status: :unprocessable_content
      end
    end

    def check_in
      transition(:check_in!)
    end

    def no_show
      transition(:mark_no_show!)
    end

    def mark_paid
      transition(:mark_paid!)
    end

    def cancel
      @booking.cancel!(by: current_user)
      BookingMailer.with(booking: @booking).cancelled.deliver_later if @booking.user
      redirect_back_or_to admin_booking_path(@booking), notice: t(".success.#{@booking.kind}")
    rescue ArgumentError
      redirect_back_or_to admin_booking_path(@booking), alert: t("admin.bookings.not_allowed")
    rescue ActiveRecord::StaleObjectError
      redirect_back_or_to admin_booking_path(@booking), alert: t("bookings.changed_meanwhile")
    end

    private

    def set_booking
      @booking = Booking.find_by!(code: params[:code])
    end

    def transition(action)
      @booking.public_send(action)
      redirect_back_or_to admin_booking_path(@booking), notice: t(".success")
    rescue ArgumentError, ActiveRecord::RecordInvalid
      redirect_back_or_to admin_booking_path(@booking), alert: t("admin.bookings.not_allowed")
    # The booking changed since it was loaded (lock_version), e.g. the customer cancelled during the check-in.
    rescue ActiveRecord::StaleObjectError
      redirect_back_or_to admin_booking_path(@booking), alert: t("bookings.changed_meanwhile")
    end
  end
end
