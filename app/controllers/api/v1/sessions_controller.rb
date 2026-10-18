module Api
  module V1
    # Signing in from the app: email or phone number and password -> a token (ApiToken), with the same
    # limits against password guessing as the web sign-in.
    class SessionsController < BaseController
      skip_before_action :authenticate!, only: :create
      rate_limit to: 10, within: 3.minutes, only: :create, store: RATE_LIMIT_STORE, with: -> { rate_limited }
      rate_limit to: 5, within: 15.minutes, only: :create, store: RATE_LIMIT_STORE, name: "login",
                 by: -> { params[:login].to_s.gsub(/[\s.-]/, "").downcase }, with: -> { rate_limited }

      def create
        user = User.find_for_database_authentication(login: params[:login])
        unless user&.valid_password?(params[:password].to_s)
          return render_error(:invalid_login, [ t("devise.failure.invalid") ], status: :unauthorized)
        end
        return render_error(:account_deleted, [ t("devise.failure.account_deleted") ], status: :forbidden) unless user.active_for_authentication?

        _token, secret = ApiToken.issue(user, device_name: params[:device_name])
        render json: { token: secret, user: ApiJson.user(user) }, status: :created
      end

      def destroy
        current_token.destroy!
        head :no_content
      end
    end
  end
end
