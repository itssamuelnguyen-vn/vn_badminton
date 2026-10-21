module WellKnown
  # Digital Asset Links for the Android app (AP-04): lets Android open the links of the emails (/payments/<token>,
  # /bookings/<code>) straight in the app. The SHA-256 fingerprints of the app's signing keys come from
  # ANDROID_CERT_SHA256 (comma-separated, e.g. the debug key and the release key); without it, no app is trusted.
  class AssetLinksController < ActionController::API
    PACKAGE = "com.vnbadminton.vn_badminton_mobile".freeze

    def show
      fingerprints = ENV["ANDROID_CERT_SHA256"].to_s.split(",").map { |value| value.strip.upcase }.compact_blank
      statements = fingerprints.empty? ? [] : [ {
        relation: [ "delegate_permission/common.handle_all_urls" ],
        target: { namespace: "android_app", package_name: PACKAGE, sha256_cert_fingerprints: fingerprints }
      } ]
      expires_in 1.hour, public: true
      render json: statements
    end
  end
end
