# How the mobile app signs in (Api::V1): a random token sent as "Authorization: Bearer <token>".
# Only its SHA-256 digest is stored. It lapses after IDLE_LIMIT without use, and is deleted on sign-out,
# on a password change, and when the account's deletion is asked (the user is then inactive anyway).
#
#   token, secret = ApiToken.issue(user, device_name: "Pixel 8")
#   ApiToken.authenticate(secret)  # => the token, or nil
class ApiToken < ApplicationRecord
  IDLE_LIMIT = 90.days
  # last_used_at is written at most this often, not on every request.
  TOUCH_EVERY = 1.hour

  belongs_to :user

  def self.issue(user, device_name: nil, now: Time.current)
    secret = SecureRandom.base58(40)
    token = create!(user: user, token_digest: digest(secret), device_name: device_name.to_s.strip.first(100).presence, last_used_at: now)
    [ token, secret ]
  end

  def self.authenticate(secret, now: Time.current)
    return if secret.blank?

    token = includes(:user).find_by(token_digest: digest(secret))
    return unless token && token.last_used_at > now - IDLE_LIMIT && token.user.active_for_authentication?

    token.update_column(:last_used_at, now) if token.last_used_at < now - TOUCH_EVERY
    token
  end

  def self.digest(secret)
    OpenSSL::Digest::SHA256.hexdigest(secret)
  end
end
