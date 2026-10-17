class SchedulesController < ApplicationController
  def show
    @venue = Venue.main
    @date = selected_date
    @day = Schedule::Day.new(venue: @venue, date: @date, user: current_user)
  end

  private

  # Falls back to the default date for a missing, malformed or out-of-range ?date=.
  def selected_date
    date = Date.iso8601(params[:date].to_s)
    @venue.bookable_dates.cover?(date) ? date : default_date
  rescue Date::Error
    default_date
  end

  # Today, or tomorrow once today's last slot has started (e.g. after closing time).
  def default_date
    today = @venue.today
    Schedule::Day.new(venue: @venue, date: today).bookable? ? today : today + 1
  end
end
