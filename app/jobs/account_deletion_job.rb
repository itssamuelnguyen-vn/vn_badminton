# Finishes the account deletions asked earlier, once their bookings are played and transfers settled
# (see Accounts::Deletion).
class AccountDeletionJob < ApplicationJob
  queue_as :default

  def perform(now: Time.current)
    User.where.not(deletion_requested_at: nil).where(deleted_at: nil).find_each do |user|
      deletion = Accounts::Deletion.new(user)
      deletion.finish!(now: now) if deletion.due?(now)
    end
  end
end
