module Api
  module V1
    # Signing up from the app, with the same fields, consent and limit as the web sign-up. Devise emails the
    # verification link; booking waits for it, as on the web.
    class RegistrationsController < BaseController
      skip_before_action :authenticate!
      rate_limit to: 5, within: 1.hour, store: RATE_LIMIT_STORE, with: -> { rate_limited }

      def create
        attributes = params.permit(:full_name, :phone, :email, :password, :locale)
        user = User.new(attributes.merge(privacy_consent: ActiveModel::Type::Boolean.new.cast(params[:privacy_consent]) ? "1" : "0"))
        user.locale = I18n.locale.to_s unless I18n.available_locales.map(&:to_s).include?(user.locale)

        if user.save
          _token, secret = ApiToken.issue(user, device_name: params[:device_name])
          render json: { token: secret, user: ApiJson.user(user) }, status: :created
        else
          render_error :invalid, user.errors.full_messages, status: :unprocessable_content
        end
      end
    end
  end
end
