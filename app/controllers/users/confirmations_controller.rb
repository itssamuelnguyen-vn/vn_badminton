module Users
  # Devise's email verification, with limits on resending the verification email.
  class ConfirmationsController < Devise::ConfirmationsController
    rate_limit to: 5, within: 1.hour, only: :create, store: RATE_LIMIT_STORE,
               with: -> { rate_limited(new_user_confirmation_path) }
    rate_limit to: 3, within: 1.hour, only: :create, store: RATE_LIMIT_STORE, name: "email",
               by: -> { params.dig(:user, :email).to_s.strip.downcase },
               with: -> { rate_limited(new_user_confirmation_path) }

    private

    # After clicking the link: signed-in customers go straight to the schedule to book.
    def after_confirmation_path_for(resource_name, resource)
      signed_in?(resource_name) ? root_path : new_session_path(resource_name)
    end
  end
end
