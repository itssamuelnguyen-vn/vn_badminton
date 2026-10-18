# Emails about deleting an account (Accounts::Deletion). They get the address and name as values, not the
# user: by the time the job sends them, the account may already be anonymized.
#   AccountMailer.with(email:, name:, locale:).deleted.deliver_later
class AccountMailer < ApplicationMailer
  helper :bookings

  # bookings: [{ code:, court:, starts_at:, ends_at: }] still to be played; finishes_at: when the account goes.
  def deletion_requested
    @bookings = params[:bookings]
    @finishes_at = params[:finishes_at]
    @by_owner = params[:by_owner]
    deliver(:deletion_requested)
  end

  def deleted
    deliver(:deleted)
  end

  def deletion_cancelled
    deliver(:deletion_cancelled)
  end

  private

  def deliver(action)
    @name = params[:name]
    I18n.with_locale(params[:locale]) { mail to: params[:email], subject: t("account_mailer.#{action}.subject") }
  end
end
