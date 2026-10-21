# Places a customer bought in an open play session (themselves and up to 9 friends), paid by transfer within
# Payment::WINDOW; the places are held meanwhile. The customer cancels like a booking (until the venue's
# cancellation cutoff, a paid place is not refunded); the venue cancelling the session owes it back.
class PlaySessionTicket < ApplicationRecord
  MAX_QUANTITY = 10

  enum :status, { pending: "pending", confirmed: "confirmed", cancelled: "cancelled" }, default: :pending, validate: true

  belongs_to :play_session
  belongs_to :user
  belongs_to :payment, optional: true

  # Holding places: paid, or waiting for a transfer still in time (Payment#open?).
  scope :holding, ->(now = Time.current) {
    left_joins(:payment).where(status: :confirmed)
                        .or(left_joins(:payment).where(status: :pending, payments: { status: :awaiting })
                                                 .where("payments.expires_at + make_interval(secs => ?) > ?", Payment::GRACE.to_i, now))
  }

  scope :active, -> { where.not(status: :cancelled) }

  validates :quantity, numericality: { only_integer: true, in: 1..MAX_QUANTITY }

  # Takes the places and the transfer to pay them; nil with errors when they cannot be taken.
  def self.buy(session, user, quantity, now: Time.current)
    ticket = new(play_session: session, user: user, quantity: quantity.to_i)
    transaction do
      session.lock!
      ticket.errors.add(:base, :not_bookable) unless session.bookable?(now)
      ticket.errors.add(:base, :blacklisted) if CustomerProfile.blocked?(user.phone)
      ticket.errors.add(:base, :full, left: session.seats_left(now)) if ticket.errors.empty? && session.seats_left(now) < ticket.quantity
      raise ActiveRecord::Rollback if ticket.errors.any? || !ticket.valid?

      ticket.amount_vnd = session.price_vnd * ticket.quantity
      ticket.save!
      payment = Payment.create!(purpose: :tickets, play_session_ticket: ticket, user: user, created_by: user, amount_vnd: ticket.amount_vnd,
                                expires_at: now + Payment::WINDOW)
      ticket.update!(payment: payment)
    end
    ticket
  end

  # Called by Payments::Confirm. Late (the places were released), only while there are places left.
  def confirm!(now = Time.current)
    play_session.lock!
    return false if cancelled? && play_session.cancelled?
    return false unless payment&.open?(now) || play_session.seats_left(now) >= quantity

    update!(status: :confirmed, cancelled_at: nil)
  end

  def cancellable_by_customer?(now = Time.current)
    !cancelled? && play_session.open? && now <= play_session.starts_at - play_session.venue.cancellation_cutoff_hours.hours
  end

  # The customer cancels: the places free up; paid ones are not refunded (HUY-01).
  def cancel_by_customer!(now: Time.current)
    raise ArgumentError, "Cancellation cutoff has passed" unless cancellable_by_customer?(now)

    transaction do
      update!(status: :cancelled, cancelled_at: now)
      payment.update!(status: :cancelled) if payment&.awaiting?
    end
  end

  def cancel_by_venue!(now: Time.current)
    paid = confirmed?
    update!(status: :cancelled, cancelled_at: now, refund_vnd: (amount_vnd if paid))
    payment.update!(status: :cancelled) if payment&.awaiting?
  end

  def mark_refunded!(now: Time.current)
    raise ArgumentError, "Nothing to refund" if refund_vnd.nil? || refunded_at

    update!(refunded_at: now)
  end

  def checked_in?
    checked_in_at.present?
  end
end
