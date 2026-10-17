class SchedulesController < ApplicationController
  def show
    @venue = Venue.main
    @date = selected_date
    @day = Schedule::Day.new(venue: @venue, date: @date, user: current_user)
  end

  private

  # Falls back to today for a missing, malformed or out-of-range ?date=.
  def selected_date
    date = Date.iso8601(params[:date].to_s)
    @venue.bookable_dates.cover?(date) ? date : @venue.today
  rescue Date::Error
    @venue.today
  end
end
