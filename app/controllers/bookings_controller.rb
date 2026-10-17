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

  # Confirmation page for the slot picked on the schedule. Validating here shows problems
  # (slot just taken, too short, ...) before the customer presses "confirm".
  def new
    @booking = build_booking(params.permit(:court_id, :starts_at, :ends_at))
    @booking.validate
  end

  def create
    @booking = build_booking(params.expect(booking: %i[court_id starts_at ends_at note]))

    if @booking.reserve
      BookingMailer.with(booking: @booking, locale: I18n.locale).confirmed.deliver_later
      redirect_to booking_path(@booking), notice: t(".success")
    else
      render :new, status: :unprocessable_content
    end
  end

  def cancel
    @booking.cancel!(by: current_user)
    redirect_to bookings_path, notice: t(".success")
  rescue ArgumentError
    redirect_to booking_path(@booking), alert: t(".not_allowed")
  end

  private

  def set_booking
    @booking = current_user.bookings.find_by!(code: params[:code])
  end

  def build_booking(attrs)
    court = Venue.main.courts.active.find(attrs[:court_id])
    court.bookings.new(user: current_user, source: :online, **attrs.slice(:starts_at, :ends_at, :note))
  end
end
