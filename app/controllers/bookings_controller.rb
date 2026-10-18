class BookingsController < ApplicationController
  UPCOMING_STATUSES = %w[pending confirmed checked_in].freeze

  before_action :authenticate_user!
  before_action :set_booking, only: %i[show cancel]

  def index
    bookings = current_user.bookings.kind_reservation.includes(:court)
    @upcoming = bookings.where(status: UPCOMING_STATUSES).where(ends_at: Time.current..).order(:starts_at)
    @past = bookings.where.not(id: @upcoming).order(starts_at: :desc).limit(50)
  end

  def show
  end

  # Confirmation page for the slots picked on the schedule (one range per court, possibly several courts):
  #   /bookings/new?slots[0][court_id]=1&slots[0][starts_at]=...&slots[0][ends_at]=...
  # Validating here shows problems (slot just taken, too short, ...) before the customer confirms.
  def new
    slots = slots_from(params)
    return redirect_to(root_path, alert: t(".no_selection")) if slots.empty?

    @batch = BookingBatch.new(user: current_user, slots: slots)
    @batch.valid?
  end

  def create
    booking_params = params.require(:booking)
    @batch = BookingBatch.new(user: current_user, slots: slots_from(booking_params), note: booking_params[:note])

    if @batch.reserve
      current_user.remember_locale(I18n.locale)
      BookingMailer.with(bookings: @batch.bookings, locale: I18n.locale).confirmed.deliver_later
      bookings = @batch.bookings
      redirect_to (bookings.one? ? booking_path(bookings.first) : bookings_path), notice: t(".success", count: bookings.size)
    else
      render :new, status: :unprocessable_content
    end
  end

  def cancel
    @booking.cancel!(by: current_user)
    current_user.remember_locale(I18n.locale)
    BookingMailer.with(booking: @booking).cancelled.deliver_later
    redirect_to bookings_path, notice: t(".success")
  rescue ArgumentError
    redirect_to booking_path(@booking), alert: t(".not_allowed")
  end

  private

  def set_booking
    @booking = current_user.bookings.find_by!(code: params[:code])
  end

  # slots[0][court_id]=...&slots[1][court_id]=... -> [{ court_id:, starts_at:, ends_at: }, ...]
  def slots_from(scope)
    slots = scope.permit(slots: %i[court_id starts_at ends_at]).to_h.fetch(:slots, {})
    (slots.is_a?(Hash) ? slots.values : slots).map(&:symbolize_keys)
  end
end
