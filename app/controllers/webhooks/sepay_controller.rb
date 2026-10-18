module Webhooks
  # SePay calls this for every transfer on the venue's account (see Payments::Webhook).
  # Authenticated by the API key set in SePay ("Authorization: Apikey ..."): SEPAY_WEBHOOK_API_KEY when set
  # (tests, servers), otherwise credentials (sepay.webhook_api_key). SePay expects 200 with {"success": true}, and retries otherwise.
  class SepayController < ActionController::API
    # The fields of a SePay transfer notification.
    FIELDS = %w[id gateway transactionDate accountNumber subAccount code content transferType description
                transferAmount accumulated referenceCode].freeze

    before_action :authenticate

    def create
      Payments::Webhook.process(params.permit(*FIELDS).to_h)
      render json: { success: true }
    end

    private

    def authenticate
      key = ENV["SEPAY_WEBHOOK_API_KEY"].presence || Rails.application.credentials.dig(:sepay, :webhook_api_key).presence
      given = request.headers["Authorization"].to_s.delete_prefix("Apikey ").strip
      head :unauthorized unless key && ActiveSupport::SecurityUtils.secure_compare(given, key)
    end
  end
end
