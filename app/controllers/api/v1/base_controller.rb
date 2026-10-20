module Api
  module V1
    # The JSON API of the customer mobile app (Flutter, Android). Customers only: everything the owner and
    # staff do stays on the web, so no management action is ever exposed here.
    #
    # Signed in with "Authorization: Bearer <token>" (ApiToken). The language of the messages follows
    # "Accept-Language" (vi by default, en). Errors: { "error": "<code>", "messages": [...] } with an HTTP status.
    class BaseController < ActionController::API
      include AbstractController::Translation

      RATE_LIMIT_STORE = ApplicationController::RATE_LIMIT_STORE

      around_action :switch_locale
      before_action :authenticate!

      rescue_from ActiveRecord::RecordNotFound do
        render_error :not_found, status: :not_found
      end
      rescue_from ActionController::ParameterMissing do |error|
        render_error :invalid, [ error.message ], status: :unprocessable_content
      end

      private

      attr_reader :current_token

      def current_user = current_token&.user

      def authenticate!
        @current_token = ApiToken.authenticate(request.authorization.to_s[/\ABearer (.+)\z/, 1])
        return render_error(:unauthorized, [ t("api.unauthorized") ], status: :unauthorized) unless current_user

        Current.user = current_user
      end

      def render_error(code, messages = [], status:)
        render json: { error: code, messages: messages }, status: status
      end

      def rate_limited
        render_error :rate_limited, [ t("rate_limited") ], status: :too_many_requests
      end

      def switch_locale(&action)
        locale = request.headers["Accept-Language"].to_s[/\A\s*(vi|en)/, 1] || I18n.default_locale
        I18n.with_locale(locale, &action)
      end
    end
  end
end
