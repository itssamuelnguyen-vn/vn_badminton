# The owner's booking form: a court, a local date and a time range picked as minutes since
# midnight, either for a customer (phone call, walk-in) or as a block (maintenance, private event).
#
#   form = Admin::BookingForm.new(venue: Venue.main, attributes: { kind: "block", court_id: 3, date: "2026-10-20",
#                                                                  start_minute: 300, end_minute: 540, note: "Sơn sân" })
#   form.build(created_by: owner).reserve
module Admin
  class BookingForm
    include ActiveModel::Model
    include ActiveModel::Attributes

    FIELDS = %i[kind court_id date start_minute end_minute customer_name customer_phone source note].freeze
    SOURCES = %w[phone walk_in].freeze

    attribute :kind, :string, default: "reservation"
    attribute :court_id, :integer
    attribute :date, :date
    attribute :start_minute, :integer
    attribute :end_minute, :integer
    attribute :customer_name, :string
    attribute :customer_phone, :string
    attribute :source, :string, default: "phone"
    attribute :note, :string

    attr_reader :venue

    def initialize(venue:, attributes: {})
      @venue = venue
      super(attributes.to_h.symbolize_keys.slice(*FIELDS))
      self.kind = "reservation" unless Booking.kinds.key?(kind)
      self.source = "phone" unless SOURCES.include?(source)
      self.date ||= venue.today
    end

    # The form filled in from an existing booking (for moving it).
    def self.from_booking(booking)
      venue = booking.court.venue
      local = booking.starts_at.in_time_zone(venue.zone)
      day_start = local.beginning_of_day
      new(venue: venue, attributes: { kind: booking.kind, court_id: booking.court_id, date: local.to_date,
                                      start_minute: ((booking.starts_at - day_start) / 60).to_i,
                                      end_minute: ((booking.ends_at - day_start) / 60).to_i })
    end

    def starts_at = time_at(start_minute)
    def ends_at = time_at(end_minute)

    def block?
      kind == "block"
    end

    # The booking to save. Blocks carry no customer; a reservation is linked to the customer's
    # account when one has the same phone number, so it also shows in their bookings.
    def build(created_by:)
      court = venue.courts.find_by(id: court_id)
      booking = Booking.new(court: court, kind: kind, starts_at: time_at(start_minute), ends_at: time_at(end_minute),
                            note: note.presence, created_by: created_by)
      return booking if block?

      booking.assign_attributes(source: source, customer_name: customer_name, customer_phone: customer_phone)
      booking.user = User.find_by(phone: booking.customer_phone) if booking.customer_phone.present?
      booking
    end

    private

    def time_at(minute)
      return if date.nil? || minute.nil?

      venue.zone.local(date.year, date.month, date.day) + minute.minutes
    end
  end
end
