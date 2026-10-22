require "net/http"

module Push
  # Sends one notification to one phone with the Firebase Cloud Messaging HTTP v1 API, signed in with the
  # Firebase service account (an OAuth2 access token, renewed before it expires).
  #
  # The key is read from FIREBASE_SERVICE_ACCOUNT_JSON (the file's content) or FIREBASE_SERVICE_ACCOUNT_PATH (its
  # path); never from the repository. Without either, pushes are off (Disabled): nothing is sent, and it is
  # logged once. The tests replace Fcm.current with a fake.
  #
  #   Push::Fcm.current.deliver(token: "fcm-token", title: "...", body: "...", data: { path: "/bookings/K7Q2M9XA" })
  #   # => :sent, or :invalid_token (Firebase no longer knows the phone); raises TransientError to retry later
  class Fcm
    SCOPE = "https://www.googleapis.com/auth/firebase.messaging".freeze
    # The Android notification channel the app creates (its name is shown in the phone's settings).
    CHANNEL_ID = "updates".freeze
    # Answers meaning the token is no longer valid: the app was uninstalled, its data cleared, or the token
    # belongs to another Firebase project.
    INVALID_TOKEN = %w[UNREGISTERED INVALID_ARGUMENT SENDER_ID_MISMATCH NOT_FOUND].freeze

    # A failure that may pass: network, rate limit (429), Firebase unavailable (5xx), expired access token.
    class TransientError < StandardError; end

    class << self
      attr_writer :current

      def current
        @current ||= from_env || Disabled.new
      end

      def from_env
        json = ENV["FIREBASE_SERVICE_ACCOUNT_JSON"].presence
        path = ENV["FIREBASE_SERVICE_ACCOUNT_PATH"].presence
        json ||= File.read(path) if path
        new(json) if json
      rescue SystemCallError, JSON::ParserError, KeyError => error
        Rails.logger.error("[push] Firebase service account unusable (#{error.class}); push notifications are off")
        nil
      end
    end

    def initialize(json)
      key = JSON.parse(json)
      @project_id = ENV["FIREBASE_PROJECT_ID"].presence || key.fetch("project_id")
      @credentials = Google::Auth::ServiceAccountCredentials.make_creds(json_key_io: StringIO.new(json), scope: SCOPE)
      @lock = Mutex.new
    end

    def enabled? = true

    def deliver(token:, title:, body:, data: {})
      response = post(message(token, title, body, data))
      return :sent if response.is_a?(Net::HTTPSuccess)

      status = response.code.to_i
      error = error_code(response)
      return :invalid_token if status == 404 || INVALID_TOKEN.include?(error) || (status == 400 && error.nil?)

      @credentials.access_token = nil if status == 401
      raise TransientError, "FCM answered #{status} #{error}".strip if status == 401 || status == 429 || status >= 500

      Rails.logger.error("[push] FCM refused a message: #{status} #{error}")
      :failed
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError,
           Faraday::Error, Signet::AuthorizationError, Signet::RemoteServerError, Signet::UnexpectedStatusError => error
      raise TransientError, error.class.name
    end

    private

    # Android only: a notification shown by the system (also when the app is closed) in the app's channel, and the
    # page to open when it is tapped (data.path, read by the app like the links of the emails).
    def message(token, title, body, data)
      {
        message: {
          token: token,
          notification: { title: title, body: body },
          data: data.transform_values(&:to_s),
          android: { priority: "high", notification: { channel_id: CHANNEL_ID } }
        }
      }
    end

    def post(payload)
      uri = URI("https://fcm.googleapis.com/v1/projects/#{@project_id}/messages:send")
      request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json", "Authorization" => "Bearer #{access_token}")
      request.body = payload.to_json
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) { |http| http.request(request) }
    end

    # e.g. "UNREGISTERED", from { "error": { "details": [{ "errorCode": "UNREGISTERED" }] } }.
    def error_code(response)
      details = JSON.parse(response.body.to_s).dig("error", "details")
      details.filter_map { |detail| detail["errorCode"] }.first if details.is_a?(Array)
    rescue JSON::ParserError
      nil
    end

    def access_token
      @lock.synchronize do
        @credentials.fetch_access_token! if @credentials.access_token.nil? || @credentials.expires_within?(60)
        @credentials.access_token
      end
    end

    # Pushes are off (no service account): development, the tests, CI.
    class Disabled
      def enabled?
        unless @logged
          @logged = true
          Rails.logger.info("[push] Push notifications are off: FIREBASE_SERVICE_ACCOUNT_PATH or _JSON is not set")
        end
        false
      end

      def deliver(**) = :skipped
    end
  end
end
