class BookingsController < ApplicationController
  # Held slots (pending) are not bookings yet, so they are not listed.
  UPCOMING_STATUSES = %w[confirmed checked_in].freeze

  before_action :authenticate_user!
  # Each opening of the confirmation page can hold slots; keep that from being used to block the schedule.
  rate_limit to: 30, within: 10.minutes, only: :new, by: -> { current_user.id }, store: RATE_LIMIT_STORE,
             with: -> { rate_limited(root_path) }
  before_action :require_verified_email, only: %i[new create]
  before_action :set_booking, only: %i[show cancel review_reschedule reschedule]
  before_action :require_reschedulable, only: %i[review_reschedule reschedule]

  def index
    bookings = current_user.bookings.kind_reservation.where.not(status: :pending).includes(:court)
    @upcoming = bookings.where(status: UPCOMING_STATUSES).where(ends_at: Time.current..).order(:starts_at)
    @awaiting_payments = Payment.awaiting.where(user: current_user).where("expires_at > ?", Time.current).order(:expires_at)
    @past = bookings.where.not(id: @upcoming).order(starts_at: :desc).limit(50)
  end

  def show
  end

  # Confirmation page for the slots picked on the schedule (one range per court, possibly several courts):
  #   /bookings/new?slots[0][court_id]=1&slots[0][starts_at]=...&slots[0][ends_at]=...
  # Opening it holds the slots for Booking::HOLD_DURATION, so other customers see them as taken while this
  # one confirms; problems (slot just taken, too short, ...) are shown instead when they cannot be held.
  def new
    slots = slots_from(params)
    return redirect_to(root_path, alert: t(".no_selection")) if slots.empty?

    @batch = BookingBatch.new(user: current_user, slots: slots)
    @batch.hold
  end

  # Online bookings are paid in full by bank transfer: the bookings are held for Payment::WINDOW and confirmed
  # when the transfer arrives (Payments::Webhook), which also sends the confirmation email.
  def create
    booking_params = params.require(:booking)
    @batch = BookingBatch.new(user: current_user, slots: slots_from(booking_params), note: booking_params[:note],
                              voucher_code: booking_params[:voucher_code])
    return redirect_to(root_path, alert: t(".payments_unavailable")) unless @batch.venue.payments_enabled?

    if (payment = @batch.reserve_for_payment)
      current_user.remember_locale(I18n.locale)
      redirect_to payment_path(payment)
    else
      render :new, status: :unprocessable_content
    end
  end

  # Confirmation page for moving a booking to the slot picked on the schedule (reschedule mode):
  #   /bookings/K7Q2M9XA/reschedule?slots[0][court_id]=..&slots[0][starts_at]=..&slots[0][ends_at]=..
  # Shows the old and new times and the new price; checks the new slot without saving.
  def review_reschedule
    @original = @booking.dup
    slot = slots_from(params).first or return redirect_to(booking_path(@booking), alert: t("bookings.new.no_selection"))
    @booking.price_cap_vnd = @booking.total_amount_vnd if @booking.payment_paid? # same rule as Booking#reschedule
    @booking.assign_attributes(court: rescheduled_court(slot), starts_at: slot[:starts_at], ends_at: slot[:ends_at])
    @booking.validate
  end

  def reschedule
    @original = @booking.dup
    slot = params.require(:reschedule).permit(:court_id, :starts_at, :ends_at)

    if @booking.reschedule(court: rescheduled_court(slot), starts_at: slot[:starts_at], ends_at: slot[:ends_at], by: current_user)
      BookingMailer.with(booking: @booking, previous: @original.attributes.slice("court_id", "starts_at", "ends_at")).rescheduled.deliver_later
      redirect_to booking_path(@booking), notice: t(".success")
    else
      render :review_reschedule, status: :unprocessable_content
    end
  end

  # "Pick another time" on the confirmation page: frees the held slots right away instead of after the timeout.
  def release_hold
    Booking.delete_holds!(current_user.bookings)
    redirect_to root_path(date: params[:date].presence)
  end

  def cancel
    @booking.cancel!(by: current_user)
    current_user.remember_locale(I18n.locale)
    BookingMailer.with(booking: @booking).cancelled.deliver_later
    redirect_to bookings_path, notice: t(".success")
  rescue ArgumentError
    redirect_to booking_path(@booking), alert: t(".not_allowed")
  # The venue changed the booking at the same moment (lock_version), e.g. checked it in.
  rescue ActiveRecord::StaleObjectError
    redirect_to booking_path(@booking), alert: t("bookings.changed_meanwhile")
  end

  private

  def require_reschedulable
    redirect_to booking_path(@booking), alert: t("bookings.reschedule.not_allowed") unless @booking.reschedulable_by_customer?
  end

  def rescheduled_court(slot)
    Venue.main.courts.active.find(slot[:court_id])
  end

  def set_booking
    @booking = current_user.bookings.find_by!(code: params[:code])
  end

  # slots[0][court_id]=...&slots[1][court_id]=... -> [{ court_id:, starts_at:, ends_at: }, ...]
  def slots_from(scope)
    slots = scope.permit(slots: %i[court_id starts_at ends_at]).to_h.fetch(:slots, {})
    (slots.is_a?(Hash) ? slots.values : slots).map(&:symbolize_keys)
  end
end
