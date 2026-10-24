# A customer's own tournament ("giải đấu nội bộ", GD-01..): a tool for a group of players, run entirely by them.
# They book and pay their courts as usual; the venue plays no part in the tournament itself.
#
# setup: the creator types the players' names (TournamentEntry), sets seeds, may link their bookings.
# in_progress: the draw is made (Tournaments::Draw): the creator and the organizers enter the results.
# finished: the last match is played.
#
# Formats: knockout (a bracket, byes for the top seeds), groups_knockout (round robin groups of group_size, the
# best advance_per_group of each go on to a knockout bracket) and round_robin (everyone meets everyone).
#
# Not listed anywhere: anyone with the share link sees it (/t/<share_token>). The organizer link
# (/t/<share_token>/organize/<organizer_token>) lets a signed-in customer enter results too.
class Tournament < ApplicationRecord
  FORMATS = %w[knockout groups_knockout round_robin].freeze
  DISCIPLINES = %w[singles doubles mixed_doubles].freeze
  MAX_ENTRIES = 64
  # Everyone meets everyone: n × (n − 1) / 2 matches, so a round robin stays small.
  ROUND_ROBIN_MAX = 10
  # Tournaments not finished yet that one customer can have.
  MAX_OPEN_PER_USER = 10
  MAX_ORGANIZERS = 10

  enum :play_format, FORMATS.index_by(&:itself), validate: true
  enum :discipline, DISCIPLINES.index_by(&:itself), validate: true
  enum :status, { setup: "setup", in_progress: "in_progress", finished: "finished" }, default: :setup, validate: true

  belongs_to :created_by, class_name: "User"
  # The matches go first: they point to the entries.
  has_many :matches, class_name: "TournamentMatch", dependent: :delete_all
  has_many :entries, -> { order(:id) }, class_name: "TournamentEntry", inverse_of: :tournament, dependent: :delete_all
  has_many :organizers, class_name: "TournamentOrganizer", dependent: :delete_all
  has_many :organizer_users, through: :organizers, source: :user
  # Where it is played (optional): the organizers' own bookings.
  has_many :bookings, dependent: :nullify

  # The ones a customer created or helps organize, the newest first.
  scope :managed_by, ->(user) {
    where(created_by: user).or(where(id: TournamentOrganizer.where(user: user).select(:tournament_id))).order(created_at: :desc)
  }

  normalizes :title, with: ->(title) { title.squish.presence }
  normalizes :description, with: ->(text) { text.strip.presence }

  validates :title, presence: true, length: { maximum: 100 }
  validates :description, length: { maximum: 2000 }
  validates :group_size, numericality: { only_integer: true, in: 3..6 }, if: :groups_knockout?
  validates :advance_per_group, numericality: { only_integer: true, in: 1..2 }, if: :groups_knockout?
  validate :entries_fit_format, on: :update, if: :setup?
  validate :not_too_many, on: :create

  before_validation :assign_tokens, on: :create

  def self.find_shared(token)
    find_by!(share_token: token.to_s)
  end

  def to_param = share_token

  def doubles? = !singles?

  # The creator does everything; organizers enter results and call matches.
  def creator?(user) = user.present? && created_by_id == user.id
  def organizer?(user) = creator?(user) || (user.present? && organizers.exists?(user_id: user.id))

  # Joining with the organizer link (a customer who is already one, or the creator, is left as is).
  def add_organizer(user, token)
    return false unless ActiveSupport::SecurityUtils.secure_compare(organizer_token, token.to_s)
    return true if organizer?(user)

    errors.add(:base, :too_many_organizers, count: MAX_ORGANIZERS) if organizers.count >= MAX_ORGANIZERS
    errors.empty? && organizers.create!(user: user)
  end

  # A new organizer link: the old one stops working (people who already joined stay).
  def reset_organizer_token!
    update!(organizer_token: self.class.new_token)
  end

  # Entries can change, and the draw be made or undone, only until a match is played (byes aside).
  def entries_editable? = setup?
  def redrawable? = in_progress? && matches.where("walkover OR scores <> '[]'::jsonb").none?

  # Back to setup: the matches go, seeds and names stay.
  def undo_draw!
    raise ArgumentError, "A match was played" unless redrawable?

    transaction do
      matches.delete_all
      entries.update_all(group_number: nil, updated_at: Time.current)
      update!(status: :setup, drawn_at: nil)
    end
  end

  # The day it is played: the earliest linked booking's, else the day the creator gave.
  def play_date(zone = Venue.main.zone)
    first = bookings.reject { |booking| booking.cancelled? }.min_by(&:starts_at)
    first ? first.starts_at.in_time_zone(zone).to_date : played_on
  end

  # Courts of the linked bookings still on, to call matches to.
  def courts
    Court.where(id: bookings.where.not(status: :cancelled).select(:court_id)).order(:position)
  end

  # Bookings an organizer can link: their own, still to be played or played today, not linked to another one.
  def linkable_bookings(user, now = Time.current)
    user.bookings.kind_reservation.where(status: %w[confirmed checked_in completed], tournament_id: [ nil, id ])
        .where(ends_at: (now - 1.day)..).includes(:court).order(:starts_at)
  end

  # "Đôi nam nữ", "Đơn", "Đôi"...
  def event_name
    I18n.t("tournaments.events.#{discipline}")
  end

  # The champion once finished: the final's winner, or the top of the round robin.
  def champion
    return unless finished?

    round_robin? ? Tournaments::Standings.new(self).groups.values.first&.first&.entry : matches.knockout.order(:round).last&.winner
  end

  def self.new_token = SecureRandom.alphanumeric(16)

  private

  def assign_tokens
    self.share_token ||= self.class.new_token
    self.organizer_token ||= self.class.new_token
  end

  def not_too_many
    return unless created_by

    open = Tournament.where(created_by: created_by).where.not(status: :finished).count
    errors.add(:base, :too_many, count: MAX_OPEN_PER_USER) if open >= MAX_OPEN_PER_USER
  end

  # Switching to a round robin with too many entries already typed.
  def entries_fit_format
    errors.add(:play_format, :too_many_for_round_robin, count: ROUND_ROBIN_MAX) if round_robin? && entries.size > ROUND_ROBIN_MAX
  end
end
