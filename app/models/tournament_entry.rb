# A player (singles) or a pair (doubles) in a Tournament (GD-02..04), registered by a customer: for doubles with a
# partner's name and phone number, linked to the partner's account when that phone number has one. The fee is paid
# by transfer within Payment::WINDOW, the place held meanwhile; a free tournament confirms the entry at once.
# Nobody plays twice in a tournament (as registrant or partner). Gendered events check the players' genders: the
# registrant's from their profile, the partner's from their profile or as given.
class TournamentEntry < ApplicationRecord
  enum :status, { pending: "pending", confirmed: "confirmed", cancelled: "cancelled" }, default: :pending, validate: true

  belongs_to :tournament
  belongs_to :user
  belongs_to :partner, class_name: "User", optional: true
  belongs_to :payment, optional: true

  # Holding a place: confirmed, or waiting for a transfer still in time (Payment#open?).
  scope :holding, ->(now = Time.current) {
    left_joins(:payment).where(status: :confirmed)
                        .or(left_joins(:payment).where(status: :pending, payments: { status: :awaiting })
                                                 .where("payments.expires_at + make_interval(secs => ?) > ?", Payment::GRACE.to_i, now))
  }
  scope :active, -> { where.not(status: :cancelled) }

  normalizes :partner_name, with: ->(name) { name.squish.presence }
  normalizes :partner_phone, with: ->(phone) { PhoneNumber.normalize(phone) }
  normalizes :partner_gender, with: ->(gender) { gender.presence }

  validates :partner_name, length: { maximum: 100 }
  validates :partner_phone, format: { with: PhoneNumber::FORMAT }, allow_nil: true
  validates :partner_gender, inclusion: { in: Tournament::GENDERS }, allow_nil: true

  # Takes a place and, unless the tournament is free, the transfer to pay it; errors when it cannot be taken.
  # partner: { name:, phone:, gender: } for doubles.
  def self.register(tournament, user, partner: {}, now: Time.current)
    entry = new(tournament: tournament, user: user, partner_name: partner[:name], partner_phone: partner[:phone],
                partner_gender: partner[:gender])
    transaction do
      tournament.lock!
      entry.errors.add(:base, :not_open) unless tournament.registration_open?(now)
      entry.errors.add(:base, :blacklisted) if CustomerProfile.blocked?(user.phone)
      entry.check_players(now) if entry.errors.empty?
      entry.errors.add(:base, :full) if entry.errors.empty? && tournament.spots_left(now) < 1
      raise ActiveRecord::Rollback if entry.errors.any? || !entry.valid?

      entry.amount_vnd = tournament.fee_vnd
      entry.status = :confirmed if entry.amount_vnd.zero?
      entry.save!
      if entry.amount_vnd.positive?
        payment = Payment.create!(purpose: :tournament, tournament_entry: entry, user: user, created_by: user,
                                  amount_vnd: entry.amount_vnd, expires_at: now + Payment::WINDOW)
        entry.update!(payment: payment)
      end
    end
    entry
  end

  # The partner (doubles) and the rules on who can play: called by .register with the tournament locked.
  def check_players(now)
    if tournament.doubles?
      errors.add(:partner_name, :blank) if partner_name.blank?
      return errors.add(:partner_phone, :blank) if partner_phone.blank?
      return errors.add(:partner_phone, :yourself) if partner_phone == user.phone

      self.partner = User.find_by(phone: partner_phone)
      self.partner_name = partner.full_name if partner
    end
    taken = tournament.entries.holding(now).where(user_id: player_ids).or(tournament.entries.holding(now).where(partner_id: player_ids))
    taken = taken.or(tournament.entries.holding(now).where(partner_phone: partner_phone)) if partner_phone
    errors.add(:base, :already_entered) if taken.exists?
    check_genders if tournament.gender || tournament.mixed_doubles?
  end

  def player_ids = [ user_id, partner_id ].compact

  # Who to tell about the tournament (emails go to the registrant, pushes to both players with an account).
  def players = [ user, partner ].compact

  def display_name
    tournament.doubles? ? "#{user.full_name} / #{partner&.full_name || partner_name}" : user.full_name
  end

  # Called by Payments::Confirm. Late (the place was released), only while registration is open with a place left.
  def confirm!(now = Time.current)
    tournament.lock!
    return false if cancelled? && !tournament.open?
    return false unless payment&.open?(now) || (tournament.registration_open?(now) && tournament.spots_left(now) >= 1)

    update!(status: :confirmed, cancelled_at: nil)
  end

  def cancellable_by_customer?(now = Time.current)
    !cancelled? && tournament.registration_open?(now)
  end

  # The customer withdraws while registration is open: the place frees up; a paid fee is not refunded (HUY-01).
  def cancel_by_customer!(now: Time.current)
    raise ArgumentError, "Registration is closed" unless cancellable_by_customer?(now)

    transaction do
      update!(status: :cancelled, cancelled_at: now)
      payment.update!(status: :cancelled) if payment&.awaiting?
    end
  end

  # The venue cancels the tournament or removes the entry: a paid fee is owed back in full.
  def cancel_by_venue!(now: Time.current)
    paid = confirmed? && amount_vnd.positive?
    update!(status: :cancelled, cancelled_at: now, refund_vnd: (amount_vnd if paid))
    payment.update!(status: :cancelled) if payment&.awaiting?
  end

  def mark_refunded!(now: Time.current)
    raise ArgumentError, "Nothing to refund" if refund_vnd.nil? || refunded_at

    update!(refunded_at: now)
  end

  private

  def check_genders
    own = user.gender.presence_in(Tournament::GENDERS)
    return errors.add(:base, :gender_missing) unless own

    genders = [ own ]
    if tournament.doubles?
      other = partner&.gender.presence_in(Tournament::GENDERS) || partner_gender
      return errors.add(:partner_gender, :blank) unless other

      genders << other
    end
    if tournament.mixed_doubles?
      errors.add(:base, :mixed_genders) unless genders.sort == %w[female male]
    elsif genders.any? { |gender| gender != tournament.gender }
      errors.add(:base, :"only_#{tournament.gender}")
    end
  end
end
