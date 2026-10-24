module Admin
  # Bookings taken by the owner (phone calls, walk-ins) and maintenance blocks, plus the day-to-day
  # actions on any booking: cash payment, cancellation, rescheduling. Check-ins and no-shows are not recorded:
  # bookings are paid before they are played (VH-04).
  class BookingsController < BaseController
    before_action :set_booking, only: %i[show mark_paid cancel undo_payment edit_schedule reschedule
                                         confirm_payment cancel_venue_fault mark_refunded]

    def show
    end

    # Opened from an empty cell of the board: /admin/bookings/new?court_id=3&date=2026-10-20&start_minute=1080
    def new
      @form = BookingForm.new(venue: venue, attributes: params.permit(*BookingForm::FIELDS).to_h)
      @form.end_minute ||= @form.start_minute + venue.min_booking_minutes if @form.start_minute
    end

    # Phone bookings are paid in full by transfer like online ones: held for Payment::WINDOW with a payment
    # code and link to send to the customer. Walk-ins pay cash at the counter and are confirmed at once.
    def create
      @form = BookingForm.new(venue: venue, attributes: params.require(:booking).permit(*BookingForm::FIELDS).to_h)
      booking = @form.build(created_by: current_user)
      transfer = booking.kind_reservation? && booking.source_phone?
      if transfer && !venue.payments_enabled?
        return redirect_to(edit_admin_settings_path, alert: t(".payments_unavailable"))
      end

      if transfer ? reserve_for_payment(booking) : booking.reserve
        if transfer
          redirect_to admin_booking_path(booking), notice: t(".awaiting_payment", court: booking.court.display_name)
        else
          if booking.user
            BookingMailer.with(bookings: [ booking ]).confirmed.deliver_later
            Push.booking_confirmed([ booking ])
          end
          redirect_to admin_root_path(date: @form.date&.iso8601), notice: t(".success.#{booking.kind}", court: booking.court.display_name)
        end
      else
        @booking = booking
        render :new, status: :unprocessable_content
      end
    end

    # The transfer was seen by the owner/staff (e.g. in the bank app) before or without the webhook.
    def confirm_payment
      if Payments::Confirm.call(@booking.payment, by: current_user)
        redirect_to admin_booking_path(@booking), notice: t(".success")
      else
        redirect_to admin_booking_path(@booking), alert: t(".slot_taken")
      end
    rescue ArgumentError, NoMethodError
      redirect_to admin_booking_path(@booking), alert: t("admin.bookings.not_allowed")
    end

    # The venue could not provide the court: cancelled, and a paid booking is owed back in full.
    def cancel_venue_fault
      @booking.cancel_for_venue_fault!(by: current_user)
      notify_cancelled
      redirect_back_or_to admin_booking_path(@booking), notice: t(".success")
    rescue ArgumentError
      redirect_back_or_to admin_booking_path(@booking), alert: t("admin.bookings.not_allowed")
    end

    def mark_refunded
      @booking.mark_refunded!(by: current_user, cash: params[:via] == "cash")
      redirect_back_or_to admin_booking_path(@booking), notice: t(".success")
    rescue ArgumentError
      redirect_back_or_to admin_booking_path(@booking), alert: t("admin.bookings.not_allowed")
    end

    def mark_paid
      transition(:mark_paid!)
    end

    # Moving a booking or a block to another court, date or time. The online booking rules do not apply,
    # the opening hours do (for reservations); the price is recalculated.
    def edit_schedule
      @form = BookingForm.from_booking(@booking)
    end

    def reschedule
      previous = @booking.attributes.slice("court_id", "starts_at", "ends_at")
      @form = BookingForm.new(venue: venue, attributes: params.require(:booking).permit(:court_id, :date, :start_minute, :end_minute).to_h)

      if @booking.reschedule(court: venue.courts.find_by(id: @form.court_id), starts_at: @form.starts_at, ends_at: @form.ends_at, by: current_user)
        if @booking.user
          BookingMailer.with(booking: @booking, previous: previous).rescheduled.deliver_later
          Push.booking_rescheduled(@booking)
        end
        redirect_to admin_booking_path(@booking), notice: t(".success")
      else
        render :edit_schedule, status: :unprocessable_content
      end
    end

    def undo_payment
      transition(:undo_payment!)
    end

    def cancel
      @booking.cancel!(by: current_user)
      notify_cancelled
      redirect_back_or_to admin_booking_path(@booking), notice: t(".success.#{@booking.kind}")
    rescue ArgumentError
      redirect_back_or_to admin_booking_path(@booking), alert: t("admin.bookings.not_allowed")
    rescue ActiveRecord::StaleObjectError
      redirect_back_or_to admin_booking_path(@booking), alert: t("bookings.changed_meanwhile")
    end

    private

    # Cancelled by the venue: the customer (with an account) gets the email and a push notification.
    def notify_cancelled
      return unless @booking.user

      BookingMailer.with(booking: @booking).cancelled.deliver_later
      Push.booking_cancelled(@booking)
    end

    def reserve_for_payment(booking, now: Time.current)
      Booking.transaction do
        booking.assign_attributes(status: :pending, expires_at: now + Payment::WINDOW + Payment::GRACE)
        booking.validate # prices the booking
        raise ActiveRecord::Rollback if booking.errors.any?

        booking.payment = Payment.create!(purpose: :bookings, user: booking.user, created_by: current_user,
                                          amount_vnd: booking.total_amount_vnd, expires_at: now + Payment::WINDOW)
        booking.reserve || raise(ActiveRecord::Rollback)
      end.tap do |saved|
        HoldExpiryJob.set(wait_until: booking.expires_at + 1.second).perform_later([ booking.court_id ]) if saved
      end
    end

    def set_booking
      @booking = Booking.find_by!(code: params[:code])
    end

    def transition(action)
      @booking.public_send(action)
      redirect_back_or_to admin_booking_path(@booking), notice: t(".success")
    rescue ArgumentError, ActiveRecord::RecordInvalid
      redirect_back_or_to admin_booking_path(@booking), alert: t("admin.bookings.not_allowed")
    # The booking changed since it was loaded (lock_version), e.g. the customer cancelled meanwhile.
    rescue ActiveRecord::StaleObjectError
      redirect_back_or_to admin_booking_path(@booking), alert: t("bookings.changed_meanwhile")
    end
  end
end
