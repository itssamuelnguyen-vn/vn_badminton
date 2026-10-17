# SMTP server for real email delivery, read from credentials so the provider can change
# (Gmail now, Brevo or similar later) without touching code:
#
#   smtp:
#     address: smtp.gmail.com
#     port: 587
#     user_name: vnbadminton.app@gmail.com
#     password: <app password>
#   mailer_sender: "VN Badminton <vnbadminton.app@gmail.com>"
#
# Production always uses SMTP; development only when started with SMTP=1 (letter_opener otherwise).
ActiveSupport.on_load(:action_mailer) do
  smtp = Rails.application.credentials.smtp || {}

  self.smtp_settings = {
    address: smtp[:address],
    port: smtp.fetch(:port, 587),
    user_name: smtp[:user_name],
    password: smtp[:password],
    authentication: :plain,
    enable_starttls: true
  }
end
