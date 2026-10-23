# An in-house tournament ("giải đấu nội bộ", GD-01..): one event (singles, doubles or mixed doubles) on some courts
# for a few hours of one day (KeepsCourts), created by the owner or staff (Admin::TournamentsController).
#
# open: customers register (TournamentEntry) until registration_closes_at, paying the fee by transfer.
# in_progress: the draw is made (Tournaments::Draw): the matches exist, staff call them to a court and enter scores.
# finished: the last match is played. cancelled: the courts are freed and paid entries are owed back.
#
# Formats: knockout (a bracket, byes for the top seeds), groups_knockout (round robin groups of group_size, the
# best advance_per_group of each go on to a knockout bracket) and round_robin (everyone meets everyone).
class Tournament < ApplicationRecord
  include KeepsCourts

  FORMATS = %w[knockout groups_knockout round_robin].freeze
  DISCIPLINES = %w[singles doubles mixed_doubles].freeze
  GENDERS = %w[male female].freeze
  # Everyone meets everyone: n × (n − 1) / 2 matches, so a round robin stays small.
  ROUND_ROBIN_MAX = 10

  enum :play_format, FORMATS.index_by(&:itself), validate: true
  enum :discipline, DISCIPLINES.index_by(&:itself), validate: true
  enum :status, { open: "open", in_progress: "in_progress", finished: "finished", cancelled: "cancelled" }, default: :open, validate: true

  belongs_to :venue
  belongs_to :created_by, class_name: "User"
  has_many :entries, class_name: "TournamentEntry", dependent: :restrict_with_error
  has_many :matches, class_name: "TournamentMatch", dependent: :delete_all
  # The courts kept for it.
  has_many :blocks, class_name: "Booking", dependent: :restrict_with_error

  scope :upcoming, ->(now = Time.current) { where.not(status: :cancelled).where("ends_at > ?", now).order(:starts_at) }
  # What customers see (web and app): coming and running ones, then the ones of the last month.
  scope :listed, ->(now = Time.current) { where.not(status: :cancelled).where("ends_at > ?", now - 30.days).order(:starts_at).limit(30) }

  normalizes :level, :gender, with: ->(value) { value.presence }

  validates :level, inclusion: { in: PlaySession::LEVELS }, allow_nil: true
  validates :gender, inclusion: { in: GENDERS }, allow_nil: true
  validates :gender, absence: true, if: :mixed_doubles?
  validates :max_entries, numericality: { only_integer: true, in: 2..64 }
  validates :max_entries, numericality: { less_than_or_equal_to: ROUND_ROBIN_MAX }, if: :round_robin?
  validates :fee_vnd, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :group_size, numericality: { only_integer: true, in: 3..6 }, if: :groups_knockout?
  validates :advance_per_group, numericality: { only_integer: true, in: 1..2 }, if: :groups_knockout?
  validates :registration_closes_at, presence: true
  validate :fee_in_thousands, :registration_before_start

  def doubles? = !singles?

  # The form's fields for registration_closes_at (Admin::TournamentsController builds it from them).
  def registration_date = registration_closes_at && registration_closes_at.in_time_zone(venue.zone).to_date
  def registration_minute = registration_closes_at && registration_closes_at.in_time_zone(venue.zone).then { |time| time.hour * 60 + time.min }

  # Places held now: confirmed entries and those waiting for a transfer still in time.
  def entries_taken(now = Time.current)
    entries.holding(now).count
  end

  def spots_left(now = Time.current)
    [ max_entries - entries_taken(now), 0 ].max
  end

  def registration_open?(now = Time.current)
    open? && now < registration_closes_at
  end

  # "Đôi nam nữ", "Đơn nữ", "Đôi"...
  def event_name
    I18n.t("tournaments.events.#{discipline}#{"_#{gender}" if gender}")
  end

  # The champion once finished: the final's winner, or the top of the round robin.
  def champion
    return unless finished?

    round_robin? ? Tournaments::Standings.new(self).groups.values.first&.first&.entry : matches.knockout.order(:round).last&.winner
  end

  # The venue cancels: the courts are freed, paid entries are owed back in full (the owner transfers and marks
  # them refunded), unpaid ones are dropped. Each player gets an email and a push notification (Push).
  def cancel!(by:, now: Time.current)
    raise ArgumentError, "Already over" if cancelled? || finished?

    affected = []
    transaction do
      update!(status: :cancelled, cancelled_at: now)
      blocks.where.not(status: :cancelled).find_each { |block| block.cancel!(by: by, now: now) }
      entries.where.not(status: :cancelled).includes(:payment).find_each do |entry|
        affected << entry
        entry.cancel_by_venue!(now: now)
      end
    end
    affected.each do |entry|
      NoticeMailer.with(entry: entry).tournament_cancelled.deliver_later
      Push.tournament_cancelled(entry)
    end
  end

  private

  def block_note = I18n.t("tournaments.block_note", title: title, locale: :vi)

  def fee_in_thousands
    errors.add(:fee_vnd, :not_multiple_of_1000) if fee_vnd.to_i % 1000 != 0
  end

  def registration_before_start
    errors.add(:registration_closes_at, :after_tournament_start) if registration_closes_at && starts_at && registration_closes_at > starts_at
  end
end
