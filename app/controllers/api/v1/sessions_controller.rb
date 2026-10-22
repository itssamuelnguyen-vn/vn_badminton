module Api
  module V1
    # Signing in from the app: email or phone number and password -> a token (ApiToken), with the same
    # limits against password guessing as the web sign-in. Or with Google (#google).
    class SessionsController < BaseController
      skip_before_action :authenticate!, only: %i[create google]
      rate_limit to: 10, within: 3.minutes, only: %i[create google], store: RATE_LIMIT_STORE, with: -> { rate_limited }
      rate_limit to: 5, within: 15.minutes, only: :create, store: RATE_LIMIT_STORE, name: "login",
                 by: -> { params[:login].to_s.gsub(/[\s.-]/, "").downcase }, with: -> { rate_limited }

      def create
        user = User.find_for_database_authentication(login: params[:login])
        unless user&.valid_password?(params[:password].to_s)
          return render_error(:invalid_login, [ t("devise.failure.invalid") ], status: :unauthorized)
        end
        return render_error(:account_deleted, [ t("devise.failure.account_deleted") ], status: :forbidden) unless user.active_for_authentication?

        render_signed_in(user)
      end

      # "Sign in with Google": { id_token } (Accounts::GoogleIdentity). The account with this Google ID, else the one
      # with this email (Google verified it), which is then linked to it -> { token, user } as #create.
      # Nobody yet -> { needs_phone: true, signup_token, name, email }, to finish with RegistrationsController#google.
      def google
        identity = Accounts::GoogleIdentity.verify(params[:id_token])
        user = User.find_by(google_uid: identity.uid) || User.find_by(email: identity.email)
        unless user
          return render json: { needs_phone: true, signup_token: Accounts::GoogleIdentity.signup_token(identity),
                                name: identity.name, email: identity.email }
        end
        # The email's account is already linked to another Google account.
        return render_error(:invalid_google, [ t("api.google.invalid") ], status: :unauthorized) if user.google_uid && user.google_uid != identity.uid
        return render_error(:account_deleted, [ t("devise.failure.account_deleted") ], status: :forbidden) unless user.active_for_authentication?

        user.update_column(:google_uid, identity.uid) unless user.google_uid
        # Google checked that the address is theirs, as the verification link would have.
        user.confirm if user.email == identity.email && !user.confirmed?
        render_signed_in(user)
      rescue Accounts::GoogleIdentity::Invalid
        render_error :invalid_google, [ t("api.google.invalid") ], status: :unauthorized
      rescue Accounts::GoogleIdentity::Unavailable
        render_error :google_unavailable, [ t("api.google.unavailable") ], status: :service_unavailable
      end

      def destroy
        current_token.destroy!
        head :no_content
      end
    end
  end
end
