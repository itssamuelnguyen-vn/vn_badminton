module Users
  # Devise's sign-up and account settings, with a limit on new accounts per IP address.
  class RegistrationsController < Devise::RegistrationsController
    rate_limit to: 5, within: 1.hour, only: :create, store: RATE_LIMIT_STORE,
               with: -> { rate_limited(new_user_registration_path) }
  end
end
