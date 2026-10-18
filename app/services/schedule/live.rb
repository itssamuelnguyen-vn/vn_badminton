module Schedule
  # Live updates of the schedule: the customer schedule and the owner's day board of a date subscribe to
  # its stream, and any change to a booking on that date asks every open page to refresh (Turbo morph,
  # which keeps the scroll position and what the customer is picking).
  #
  #   = turbo_stream_from Schedule::Live.stream(venue, date)   # in the view
  #   Schedule::Live.refresh([[court_id, starts_at, ends_at], ...])  # after bookings change
  module Live
    def self.stream(venue, date)
      "schedule:#{venue.id}:#{date.iso8601}"
    end

    # ranges: [court_id, starts_at, ends_at] of the bookings that changed. Sent once the outermost transaction
    # commits, so the refreshed pages see the change (and nothing is sent when it rolls back).
    def self.refresh(ranges)
      ranges = ranges.reject { |_, from, to| from.nil? || to.nil? }
      return if ranges.empty?

      venue_ids = Court.where(id: ranges.map(&:first)).pluck(:id, :venue_id).to_h
      venues = Venue.where(id: venue_ids.values.uniq).index_by(&:id)
      streams = ranges.flat_map do |court_id, from, to|
        venue = venues[venue_ids[court_id]] or next []
        dates(from, to, venue.zone).map { |date| stream(venue, date) }
      end.uniq

      ActiveRecord.after_all_transactions_commit do
        streams.each { |name| Turbo::StreamsChannel.broadcast_refresh_later_to(name) }
      end
    end

    # Local dates a booking touches (a booking can run past midnight).
    def self.dates(from, to, zone)
      (from.in_time_zone(zone).to_date..(to - 1).in_time_zone(zone).to_date).to_a
    end
  end
end
