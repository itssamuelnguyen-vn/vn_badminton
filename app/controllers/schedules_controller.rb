class SchedulesController < ApplicationController
  def show
    @venue = Venue.main
    @date = selected_date
    @rescheduling = rescheduling
    @day = Schedule::Day.new(venue: @venue, date: @date, user: current_user, ignore: @rescheduling)
    @calendar = Schedule::Calendar.new(venue: @venue, selected: @date)
    @holds = holds if current_user&.manager?
  end

  private

  # The slots of the day held right now by customers who have not finished booking.
  def holds
    Booking.holding_slot.pending.kind_reservation.where(court: @venue.courts).on_local_date(@date, @venue.zone)
           .includes(:court).order(:starts_at, :court_id)
  end

  # ?reschedule=CODE: the customer is moving that booking (see BookingsController#review_reschedule).
  def rescheduling
    return if params[:reschedule].blank? || !user_signed_in?

    booking = current_user.bookings.find_by(code: params[:reschedule])
    booking if booking&.reschedulable_by_customer?
  end

  # Falls back to the default date for a missing, malformed or out-of-range ?date=.
  def selected_date
    date = Date.iso8601(params[:date].to_s)
    @venue.bookable_dates.cover?(date) ? date : default_date
  rescue Date::Error
    default_date
  end

  # The first day that can still be booked: today, or tomorrow once today's last slot has started.
  def default_date
    Schedule::Calendar.new(venue: @venue, selected: @venue.today).first_selectable || @venue.today
  end
end
