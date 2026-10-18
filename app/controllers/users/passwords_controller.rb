module Users
  # Devise's password reset, with limits on reset emails per IP address and per email address.
  class PasswordsController < Devise::PasswordsController
    rate_limit to: 5, within: 1.hour, only: :create, store: RATE_LIMIT_STORE,
               with: -> { rate_limited(new_user_password_path) }
    rate_limit to: 3, within: 1.hour, only: :create, store: RATE_LIMIT_STORE, name: "email",
               by: -> { params.dig(:user, :email).to_s.strip.downcase },
               with: -> { rate_limited(new_user_password_path) }
  end
end
