module Accounts
  # Deleting an account, asked by its customer or staff member, or by the owner. In two steps:
  #
  # 1. Requested (#request!): the account is locked at once, so Devise signs it out everywhere
  #    (User#active_for_authentication?), and open pages reload to the sign-in page (the user's "account"
  #    stream, see the layout). The confirmation-page holds are released. Bookings still to be played and
  #    transfers still awaited stay as they are: a transfer arriving meanwhile still confirms its booking, and
  #    the venue can still reach the customer.
  # 2. Finished (#finish!, by AccountDeletionJob) once nothing is pending: the personal data is removed and the
  #    records are kept (bookings, payments and transfers are business and accounting records).
  #    Customers become ANONYMOUS_NAME; staff keep their name, so the booking history still says who did what.
  #    The private note on the customer is removed, unless they are blacklisted (kept, so that deleting the
  #    account cannot be used to get round the blacklist).
  #
  #   deletion = Accounts::Deletion.new(user)
  #   deletion.pending_bookings  # bookings to be played before the account can go
  #   deletion.request!(by: current_user)
  class Deletion
    ANONYMOUS_NAME = "Khách đã xoá tài khoản"

    attr_reader :user

    def initialize(user)
      @user = user
    end

    # The owner's account cannot be deleted (the venue would lose its only owner).
    def allowed?
      !user.admin? && user.deleted_at.nil?
    end

    # Still to be played: confirmed or checked in, or held while their transfer is awaited.
    def pending_bookings(now = Time.current)
      scope = user.bookings.kind_reservation.where("ends_at > ?", now)
      scope.where(status: %w[confirmed checked_in]).or(scope.pending.where.not(payment_id: nil)).includes(:court).order(:starts_at)
    end

    def awaiting_payments(now = Time.current)
      Payment.awaiting.where(user: user).select { |payment| payment.open?(now) }
    end

    def due?(now = Time.current)
      pending_bookings(now).none? && awaiting_payments(now).none?
    end

    # When the account will go, as far as known now: the end of the last booking, or of the last awaited transfer.
    def finishes_at(now = Time.current)
      [ pending_bookings(now).maximum(:ends_at), *awaiting_payments(now).map { |payment| payment.expires_at + Payment::GRACE } ].compact.max
    end

    def request!(by:, now: Time.current)
      raise ArgumentError, "This account cannot be deleted" unless allowed? && user.deletion_requested_at.nil?

      User.transaction do
        user.update_columns(deletion_requested_at: now, deletion_requested_by_id: by.id, updated_at: now)
        user.api_tokens.delete_all # the mobile app is signed out too
        Booking.delete_holds!(user.bookings)
      end
      Turbo::StreamsChannel.broadcast_refresh_to(user, :account)
      return finish!(now: now) if due?(now)

      AccountMailer.with(**recipient, by_owner: by != user, finishes_at: finishes_at(now),
                                      bookings: pending_bookings(now).map { |booking| booking_summary(booking) }).deletion_requested.deliver_later
      self
    end

    # The owner changed their mind for the customer (e.g. they called): the account works again.
    def cancel!(now: Time.current)
      raise ArgumentError, "No deletion to cancel" if user.deletion_requested_at.nil? || user.deleted_at

      user.update_columns(deletion_requested_at: nil, deletion_requested_by_id: nil, updated_at: now)
      AccountMailer.with(**recipient).deletion_cancelled.deliver_later
      self
    end

    def finish!(now: Time.current)
      return self if user.deleted_at

      mail = AccountMailer.with(**recipient)
      User.transaction do
        user.bookings.update_all(customer_name: ANONYMOUS_NAME, customer_phone: nil, updated_at: now)
        BookingSeries.where(user: user).update_all(user_id: nil, updated_at: now)
        if user.phone && (profile = CustomerProfile.find_by(phone: user.phone)) && !profile.blocked?
          profile.destroy!
        end
        user.update_columns(
          full_name: user.manager? ? user.full_name : ANONYMOUS_NAME, email: "deleted-#{user.id}@deleted.invalid", phone: nil,
          encrypted_password: "", unconfirmed_email: nil, confirmation_token: nil, reset_password_token: nil,
          booking_locked_until: nil, deleted_at: now, updated_at: now
        )
      end
      mail.deleted.deliver_later
      self
    end

    private

    # The email is read now: by the time the job sends it, the account may already be anonymized.
    def recipient
      { email: user.email, name: user.full_name, locale: user.locale }
    end

    def booking_summary(booking)
      { code: booking.code, court: booking.court.display_name, starts_at: booking.starts_at, ends_at: booking.ends_at }
    end
  end
end
