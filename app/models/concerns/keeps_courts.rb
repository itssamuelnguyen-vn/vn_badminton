# Events that keep some courts for a few hours of one day (PlaySession, Tournament): blocks on the board
# (bookings of kind "block" pointing at them), made all or nothing with the event. The form gives a date and
# start/end minutes; times must be on the 30-minute grid, in the future, on active courts.
module KeepsCourts
  extend ActiveSupport::Concern

  included do
    normalizes :title, :title_en, with: ->(title) { title.squish.presence }
    normalizes :description, with: ->(text) { text.strip.presence }

    validates :title, presence: true, length: { maximum: 100 }
    validates :title_en, length: { maximum: 100 }
    validates :description, length: { maximum: 1000 }
    validates :starts_at, :ends_at, :court_ids, presence: true
    validate :court_range_valid
  end

  def courts
    Court.where(id: court_ids).order(:position, :id)
  end

  # The form's fields (the admin controllers build starts_at/ends_at from them).
  def date = starts_at && starts_at.in_time_zone(venue.zone).to_date
  def start_minute = starts_at && minute_of_day(starts_at)
  def end_minute = ends_at && minute_of_day(ends_at)

  def display_title(locale = I18n.locale)
    (locale.to_s == "en" && title_en.presence) || title
  end

  # Saves the event and blocks its courts, all or nothing (a court already taken is an error on the event).
  def create_with_blocks(by:)
    transaction do
      self.created_by = by
      raise ActiveRecord::Rollback unless save

      courts.each do |court|
        block = blocks.build(court: court, kind: :block, starts_at: starts_at, ends_at: ends_at, created_by: by, note: block_note)
        next if block.reserve

        block.errors.full_messages.each { |message| errors.add(:base, "#{court.display_name}: #{message}") }
        raise ActiveRecord::Rollback
      end
    end
    errors.empty? && persisted?
  end

  private

  def minute_of_day(time)
    local = time.in_time_zone(venue.zone)
    minute = local.hour * 60 + local.min
    time > starts_at && minute.zero? ? 1440 : minute # ending at midnight
  end

  def court_range_valid
    return if starts_at.blank? || ends_at.blank?

    errors.add(:ends_at, :after_start) unless ends_at > starts_at
    errors.add(:base, :off_slot_grid) unless [ starts_at, ends_at ].all? { |time| (time.to_r % Booking::SLOT_SECONDS).zero? }
    errors.add(:starts_at, :not_in_future) if new_record? && starts_at <= Time.current
    errors.add(:court_ids, :invalid) if court_ids.present? && venue && venue.courts.active.where(id: court_ids).count != court_ids.uniq.size
  end
end
