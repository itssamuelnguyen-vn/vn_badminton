# Bookings a customer makes together, one per court (each court can have its own time range).
# They are created all-or-nothing: if one court cannot be booked, none is.
#
#   batch = BookingBatch.new(user: current_user, slots: [{ court_id: 1, starts_at: "...", ends_at: "..." }], note: "...")
#   batch.reserve  # => true when every booking was saved
class BookingBatch
  attr_reader :bookings

  def initialize(user:, slots:, note: nil, venue: Venue.main)
    courts = venue.courts.active.where(id: slots.map { |slot| slot[:court_id] }).index_by(&:id)

    @bookings = slots.map do |slot|
      court = courts.fetch(slot[:court_id].to_i) { raise ActiveRecord::RecordNotFound, "Court #{slot[:court_id]} not found" }
      court.bookings.new(user: user, source: :online, starts_at: slot[:starts_at], ends_at: slot[:ends_at], note: note.presence)
    end.sort_by { |booking| [ booking.court.position, booking.court.id, booking.starts_at.to_i ] }
  end

  # Validates every booking (not just up to the first failure) so all problems can be shown.
  def valid?
    bookings.map(&:validate).all?
  end

  def reserve
    return false if bookings.empty?

    Booking.transaction do
      results = bookings.map(&:reserve)
      raise ActiveRecord::Rollback unless results.all?
    end
    bookings.all?(&:persisted?)
  end

  def errors?
    bookings.any? { |booking| booking.errors.any? }
  end

  def total_amount_vnd
    bookings.sum(&:total_amount_vnd)
  end
end
