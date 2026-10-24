# Open play ("giao lưu", "vãng lai"): the venue keeps some courts for a few hours (blocks on the board) and sells
# places per player (PlaySessionTicket), paid by transfer. Created by the owner or staff (Admin::PlaySessionsController).
# Cancelling it frees the courts and owes the paid places back in full.
class PlaySession < ApplicationRecord
  LEVELS = %w[beginner intermediate advanced expert].freeze

  enum :status, { open: "open", cancelled: "cancelled" }, default: :open, validate: true

  belongs_to :venue
  belongs_to :created_by, class_name: "User"
  has_many :tickets, class_name: "PlaySessionTicket", dependent: :restrict_with_error
  # The courts kept for it.
  has_many :blocks, class_name: "Booking", dependent: :restrict_with_error

  scope :upcoming, ->(now = Time.current) { open.where("ends_at > ?", now).order(:starts_at) }
  # What customers see (web and app): the coming ones not started yet.
  scope :listed, ->(now = Time.current) { upcoming(now).where("starts_at > ?", now).limit(30) }

  # Loads the places taken of many sessions with one query, for the lists.
  def self.preload_seats_taken(sessions, now = Time.current)
    taken = PlaySessionTicket.holding(now).where(play_session_id: sessions.map(&:id)).group(:play_session_id).sum(:quantity)
    sessions.each { |session| session.preloaded_seats_taken = taken.fetch(session.id, 0) }
  end

  attr_writer :preloaded_seats_taken

  normalizes :title, :title_en, with: ->(title) { title.squish.presence }
  normalizes :description, with: ->(text) { text.strip.presence }
  normalizes :level, with: ->(level) { level.presence }

  validates :title, presence: true, length: { maximum: 100 }
  validates :title_en, length: { maximum: 100 }
  validates :description, length: { maximum: 1000 }
  validates :starts_at, :ends_at, :court_ids, presence: true
  validates :capacity, numericality: { only_integer: true, in: 1..200 }
  validates :price_vnd, numericality: { only_integer: true, greater_than: 0 }
  validates :level, inclusion: { in: LEVELS }, allow_nil: true
  validate :ranges_valid

  def courts
    Court.where(id: court_ids).order(:position, :id)
  end

  # The form's fields (Admin::PlaySessionsController builds starts_at/ends_at from them).
  def date = starts_at && starts_at.in_time_zone(venue.zone).to_date
  def start_minute = starts_at && minute_of_day(starts_at)
  def end_minute = ends_at && minute_of_day(ends_at)

  def display_title(locale = I18n.locale)
    (locale.to_s == "en" && title_en.presence) || title
  end

  # Saves the session and blocks its courts, all or nothing (a court already taken is an error on the session).
  def create_with_blocks(by:)
    transaction do
      self.created_by = by
      raise ActiveRecord::Rollback unless save

      courts.each do |court|
        block = blocks.build(court: court, kind: :block, starts_at: starts_at, ends_at: ends_at, created_by: by,
                             note: I18n.t("play_sessions.block_note", title: title, locale: :vi))
        next if block.reserve

        block.errors.full_messages.each { |message| errors.add(:base, "#{court.display_name}: #{message}") }
        raise ActiveRecord::Rollback
      end
    end
    errors.empty? && persisted?
  end

  # Places held now: confirmed tickets and those waiting for a transfer still in time.
  def seats_taken(now = Time.current)
    @preloaded_seats_taken || tickets.holding(now).sum(:quantity)
  end

  def seats_left(now = Time.current)
    [ capacity - seats_taken(now), 0 ].max
  end

  def bookable?(now = Time.current)
    open? && starts_at > now
  end

  # The venue cancels: the courts are freed, paid places are owed back in full (the owner transfers and marks
  # them refunded), unpaid ones are dropped. Each customer gets an email and a push notification (Push).
  def cancel!(by:, now: Time.current)
    raise ArgumentError, "Already cancelled" if cancelled?

    affected = []
    transaction do
      update!(status: :cancelled, cancelled_at: now)
      blocks.where.not(status: :cancelled).find_each { |block| block.cancel!(by: by, now: now) }
      tickets.where.not(status: :cancelled).includes(:payment).find_each do |ticket|
        affected << ticket
        ticket.cancel_by_venue!(now: now)
      end
    end
    affected.each do |ticket|
      NoticeMailer.with(ticket: ticket).play_session_cancelled.deliver_later
      Push.play_session_cancelled(ticket)
    end
  end

  private

  def minute_of_day(time)
    local = time.in_time_zone(venue.zone)
    minute = local.hour * 60 + local.min
    time > starts_at && minute.zero? ? 1440 : minute # ending at midnight
  end

  def ranges_valid
    return if starts_at.blank? || ends_at.blank?

    errors.add(:ends_at, :after_start) unless ends_at > starts_at
    errors.add(:base, :off_slot_grid) unless [ starts_at, ends_at ].all? { |time| (time.to_r % Booking::SLOT_SECONDS).zero? }
    errors.add(:starts_at, :not_in_future) if new_record? && starts_at <= Time.current
    errors.add(:court_ids, :invalid) if court_ids.present? && venue && venue.courts.active.where(id: court_ids).count != court_ids.uniq.size
  end
end
