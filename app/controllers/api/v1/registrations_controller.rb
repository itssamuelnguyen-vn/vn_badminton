module Api
  module V1
    # Signing up from the app, with the same fields, consent and limit as the web sign-up. Devise emails the
    # verification link; booking waits for it, as on the web.
    class RegistrationsController < BaseController
      skip_before_action :authenticate!
      rate_limit to: 5, within: 1.hour, store: RATE_LIMIT_STORE, with: -> { rate_limited }

      def create
        attributes = params.permit(:full_name, :phone, :email, :password, :locale)
        user = User.new(attributes.merge(privacy_consent: privacy_consent))
        save_and_sign_in(user)
      end

      # The end of a Google sign-in for someone new (SessionsController#google): { signup_token, full_name, phone,
      # privacy_consent, locale } (Accounts::GoogleIdentity.build_user).
      def google
        identity = Accounts::GoogleIdentity.from_signup_token(params[:signup_token])
        return render_error(:signup_expired, [ t("api.google.signup_expired") ], status: :unprocessable_content) unless identity

        save_and_sign_in(Accounts::GoogleIdentity.build_user(identity, full_name: params[:full_name], phone: params[:phone],
                                                                       locale: params[:locale], privacy_consent: privacy_consent))
      rescue ActiveRecord::RecordNotUnique
        # The same Google account signed up at the same moment.
        render_error :invalid, [ t("api.google.already_registered") ], status: :unprocessable_content
      end

      private

      def privacy_consent
        ActiveModel::Type::Boolean.new.cast(params[:privacy_consent]) ? "1" : "0"
      end

      def save_and_sign_in(user)
        user.locale = I18n.locale.to_s unless I18n.available_locales.map(&:to_s).include?(user.locale)
        if user.save
          render_signed_in(user)
        else
          render_error :invalid, user.errors.full_messages, status: :unprocessable_content
        end
      end
    end
  end
end
