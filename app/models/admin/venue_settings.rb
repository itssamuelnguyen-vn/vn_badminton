# The settings page: the venue's details and booking policy, and its opening hours for each day of
# the week. A day without opening hours is a closed day. Everything is saved together or not at all.
#
#   settings = Admin::VenueSettings.new(venue)
#   settings.update(name: "...", opening_hours: { "1" => { open: "1", opens_minute: "300", closes_minute: "1320" }, "0" => { open: "0" } })
module Admin
  class VenueSettings
    VENUE_FIELDS = %i[name address phone zalo_phone facebook_page min_booking_minutes max_booking_minutes cancellation_cutoff_hours booking_horizon_days
                      max_upcoming_bookings cancellation_lock_threshold cancellation_lock_days
                      bank_code bank_account_number bank_account_name].freeze
    # Monday first, as on Vietnamese calendars.
    WEEK = [ 1, 2, 3, 4, 5, 6, 0 ].freeze
    DEFAULT_HOURS = { opens_minute: 300, closes_minute: 1320 }.freeze

    attr_reader :venue

    def initialize(venue)
      @venue = venue
      existing = venue.opening_hours.index_by(&:day_of_week)
      # venue_id rather than venue: with has_many inversing, venue.save! would also save the closed days.
      @opening_hours = WEEK.to_h { |day| [ day, existing[day] || OpeningHour.new(venue_id: venue.id, day_of_week: day, **DEFAULT_HOURS) ] }
      @open = WEEK.to_h { |day| [ day, existing.key?(day) ] }
    end

    # For the controller: { settings: { name:, ..., opening_hours: { "1" => { open:, opens_minute:, closes_minute: } } } }
    def self.permitted_params
      [ *VENUE_FIELDS, opening_hours: WEEK.to_h { |day| [ day.to_s, %i[open opens_minute closes_minute] ] } ]
    end

    def opening_hours
      @opening_hours.values
    end

    def open?(day)
      @open.fetch(day)
    end

    def update(params)
      params = params.to_h.with_indifferent_access
      venue.assign_attributes(params.slice(*VENUE_FIELDS))
      assign_opening_hours(params.fetch(:opening_hours, {}))
      return false unless valid?

      Venue.transaction do
        venue.save!
        @opening_hours.each do |day, opening_hour|
          open?(day) ? opening_hour.save! : (opening_hour.destroy! if opening_hour.persisted?)
        end
      end
      true
    end

    def errors?
      venue.errors.any? || opening_hours.any? { |opening_hour| opening_hour.errors.any? }
    end

    private

    def assign_opening_hours(days)
      @opening_hours.each do |day, opening_hour|
        attributes = days.fetch(day.to_s, {})
        @open[day] = attributes[:open] == "1"
        opening_hour.assign_attributes(attributes.slice(:opens_minute, :closes_minute)) if open?(day)
      end
    end

    # Validates everything (not just up to the first failure) so all problems can be shown.
    def valid?
      checks = [ venue.validate ] + @opening_hours.map { |day, opening_hour| open?(day) ? opening_hour.validate : true }
      checks.all?
    end
  end
end
