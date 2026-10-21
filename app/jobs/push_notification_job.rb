# Sends one push notification to one phone (Push, Push::Fcm). A token Firebase no longer knows is deleted;
# network errors, rate limits and Firebase outages are retried a few times, then given up (the email was sent anyway).
class PushNotificationJob < ApplicationJob
  queue_as :default

  retry_on Push::Fcm::TransientError, wait: :polynomially_longer, attempts: 4
  # The phone signed out meanwhile.
  discard_on ActiveJob::DeserializationError

  def perform(device_token, title:, body:, path: nil)
    result = Push::Fcm.current.deliver(token: device_token.token, title: title, body: body, data: { path: path }.compact)
    device_token.destroy! if result == :invalid_token
  end
end
