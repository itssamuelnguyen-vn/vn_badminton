class SchedulesController < ApplicationController
  def show
    @venue = Venue.main
    @date = selected_date
    @day = Schedule::Day.new(venue: @venue, date: @date, user: current_user)
    @calendar = Schedule::Calendar.new(venue: @venue, selected: @date)
  end

  private

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
