module Api
  module V1
    # The booking grid of one day (Schedule::Day), as on the web's booking page:
    #   GET /api/v1/schedule?date=2026-10-20
    # Slots already started today are left out. A slot's state: available, booked, held, mine, blocked, unavailable.
    # Public; signed in, the customer's own bookings show as "mine". ?reschedule=CODE: see #rescheduling.
    class SchedulesController < BaseController
      skip_before_action :authenticate!
      before_action { @current_token = ApiToken.authenticate(request.authorization.to_s[/\ABearer (.+)\z/, 1]) }

      def show
        venue = Venue.main
        calendar = Schedule::Calendar.new(venue: venue, selected: venue.today)
        dates = venue.bookable_dates.select { |date| calendar.selectable?(date) }
        date = requested_date
        date = dates.first unless dates.include?(date)
        day = Schedule::Day.new(venue: venue, date: date, user: current_user, ignore: rescheduling) if date

        render json: {
          date: date&.iso8601, dates: dates.map(&:iso8601),
          courts: day ? day.courts.map { |court| { id: court.id, name: court.display_name } } : [],
          times: day ? day.upcoming_times.map(&:iso8601) : [],
          slots: day ? day.courts.to_h { |court| [ court.id, day.upcoming_times.map { |time| slot(day.slot(court, time)) } ] } : {}
        }
      end

      private

      # ?reschedule=CODE: the customer is moving that booking, whose own slots show as available.
      def rescheduling
        return if params[:reschedule].blank? || !current_user

        booking = current_user.bookings.find_by(code: params[:reschedule])
        booking if booking&.reschedulable_by_customer?
      end

      def requested_date
        Date.iso8601(params[:date].to_s)
      rescue Date::Error
        nil
      end

      def slot(slot)
        { starts_at: slot.starts_at.iso8601, state: slot.state, price_vnd: slot.price_vnd }
      end
    end
  end
end
