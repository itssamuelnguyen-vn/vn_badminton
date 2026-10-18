module Users
  # Devise's sign-in, with limits against password guessing: per IP address, and per account
  # (an email or phone number tried from many addresses).
  class SessionsController < Devise::SessionsController
    rate_limit to: 10, within: 3.minutes, only: :create, store: RATE_LIMIT_STORE,
               with: -> { rate_limited(new_user_session_path) }
    rate_limit to: 5, within: 15.minutes, only: :create, store: RATE_LIMIT_STORE, name: "login",
               by: -> { params.dig(:user, :login).to_s.gsub(/[\s.-]/, "").downcase },
               with: -> { rate_limited(new_user_session_path) }
  end
end
