module Api
  module V1
    # The phone's Firebase Cloud Messaging token (DeviceToken), sent after signing in and whenever Firebase renews it:
    # { token, platform: "android", app_version }. Removed when the customer turns notifications off in the app
    # ({ token }); signing out removes it with the sign-in.
    class DeviceTokensController < BaseController
      def create
        DeviceToken.register!(current_token, token: params.require(:token), platform: params[:platform], app_version: params[:app_version])
        head :no_content
      rescue ActiveRecord::RecordInvalid => error
        render_error :invalid, error.record.errors.full_messages, status: :unprocessable_content
      end

      def destroy
        current_user.device_tokens.where(token: params.require(:token).to_s.strip).delete_all
        head :no_content
      end
    end
  end
end
