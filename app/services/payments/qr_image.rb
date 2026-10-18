require "net/http"

module Payments
  # Downloads a payment's VietQR image, so the page can offer it as a file to save: bank apps scan QR codes
  # from the photo library, and VietQR's server does not let the page download the image itself (no CORS).
  module QrImage
    Error = Class.new(StandardError)

    def self.fetch(url)
      uri = URI(url)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 10) do |http|
        http.get(uri.request_uri)
      end
      raise Error, "VietQR answered #{response.code}" unless response.is_a?(Net::HTTPSuccess) && response.content_type == "image/png"

      response.body
    rescue SystemCallError, IOError, Timeout::Error, OpenSSL::SSL::SSLError => e
      raise Error, e.message
    end
  end
end
