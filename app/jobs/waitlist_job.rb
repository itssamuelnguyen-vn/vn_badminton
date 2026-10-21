# Tells the customers waiting for a time range (WaitlistEntry) that a court is free for all of it again.
# Enqueued when a booking or hold stops taking its slot (Booking: cancelled or moved away; Booking.delete_holds!)
# with the [court_id, starts_at, ends_at] ranges that freed up. Everyone waiting is told; the first to book gets it.
class WaitlistJob < ApplicationJob
  queue_as :default

  # Enqueues only when someone waits for a time overlapping the freed ranges (nearly never), so callers need not check.
  def self.enqueue_for(ranges, now: Time.current)
    ranges = ranges.reject { |_court_id, _starts_at, ends_at| ends_at.nil? || ends_at <= now }
    return if ranges.empty?
    return unless ranges.any? { |_court_id, starts_at, ends_at| WaitlistEntry.waiting(now).overlapping(starts_at, ends_at).exists? }

    perform_later(ranges.map { |court_id, starts_at, ends_at| [ court_id, starts_at.iso8601, ends_at.iso8601 ] })
  end

  def perform(ranges, now: Time.current)
    venue = Venue.main
    ranges.each do |_court_id, starts_at, ends_at|
      WaitlistEntry.waiting(now).overlapping(Time.zone.parse(starts_at.to_s), Time.zone.parse(ends_at.to_s)).includes(:user).find_each do |entry|
        next if entry.free_courts(venue, now).empty?
        # Claimed first, so two runs never tell the same customer twice.
        next unless WaitlistEntry.where(id: entry.id, notified_at: nil).update_all(notified_at: now) == 1

        next if entry.user.deleted_at

        NoticeMailer.with(entry: entry).slot_freed.deliver_later
        Push.slot_freed(entry)
      end
    end
  end
end
