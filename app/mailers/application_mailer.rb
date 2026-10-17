class ApplicationMailer < ActionMailer::Base
  default from: -> { Rails.application.credentials.mailer_sender || ENV.fetch("MAILER_SENDER", "VN Badminton <no-reply@example.com>") }
  layout "mailer"
end
