# A phone that gets push notifications (Firebase Cloud Messaging): the app sends its FCM registration token after
# signing in (Api::V1::DeviceTokensController). It belongs to that sign-in (ApiToken): signing out, a new password
# or the account's deletion removes the sign-in and its device tokens with it (foreign key ON DELETE CASCADE).
# A token Firebase no longer knows is deleted when a push to it fails (PushNotificationJob).
class DeviceToken < ApplicationRecord
  PLATFORMS = %w[android].freeze

  belongs_to :user
  belongs_to :api_token

  # The phones still signed in: a sign-in unused for ApiToken::IDLE_LIMIT no longer works, so it gets nothing.
  scope :live, ->(now = Time.current) { joins(:api_token).where(api_tokens: { last_used_at: (now - ApiToken::IDLE_LIMIT).. }) }

  normalizes :token, with: ->(token) { token.strip }

  validates :token, presence: true, length: { maximum: 4096 }
  validates :platform, inclusion: { in: PLATFORMS }
  validates :app_version, length: { maximum: 30 }

  # The phone's token for this sign-in, taken over from another account or sign-in if the phone changed hands.
  def self.register!(api_token, token:, platform: nil, app_version: nil, now: Time.current)
    device = find_or_initialize_by(token: token.to_s.strip)
    device.update!(user: api_token.user, api_token: api_token, platform: platform.presence || "android",
                   app_version: app_version.to_s.strip.first(30).presence, last_seen_at: now)
    device
  rescue ActiveRecord::RecordNotUnique
    retry # registered at the same moment by another request: found this time
  end
end
