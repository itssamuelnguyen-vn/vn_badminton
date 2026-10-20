module Users
  # Devise's sign-up and account settings, with a limit on new accounts per IP address.
  # Deleting the account goes through Accounts::Deletion (asked with the password, finished once nothing is pending).
  class RegistrationsController < Devise::RegistrationsController
    rate_limit to: 5, within: 1.hour, only: :create, store: RATE_LIMIT_STORE,
               with: -> { rate_limited(new_user_registration_path) }
    rate_limit to: 5, within: 1.hour, only: :destroy, store: RATE_LIMIT_STORE,
               with: -> { rate_limited(edit_user_registration_path) }

    def destroy
      deletion = Accounts::Deletion.new(resource)
      return redirect_to(edit_user_registration_path, alert: t(".not_allowed")) unless deletion.allowed?
      return redirect_to(edit_user_registration_path, alert: t(".wrong_password")) unless resource.valid_password?(params.dig(:user, :current_password).to_s)

      finishes_at = deletion.finishes_at
      deletion.request!(by: resource)
      sign_out(resource_name)
      redirect_to root_path, notice: finishes_at ? t(".scheduled", time: l(finishes_at, format: :slot)) : t(".deleted")
    end
  end
end
