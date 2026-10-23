module Accounts
  # "Sign in with Google" in the app (Api::V1) and on the web (Users::GoogleController): the app, or Google's button
  # on the sign-in page, gets an ID token from Google for the web OAuth client and sends it; it is checked here
  # (Google's signature, audience = the web client ID, issuer, expiry) and must carry a verified email.
  #
  # A new person also needs a phone number (customers must have one), so the identity goes back as a signup token,
  # signed and valid SIGNUP_TTL, and comes back with the phone (Api::V1::RegistrationsController#google,
  # Users::GoogleController#register). Nothing is stored until then.
  module GoogleIdentity
    # Public (it is in the app too); GOOGLE_WEB_CLIENT_ID overrides it, several IDs separated by commas.
    DEFAULT_CLIENT_ID = "644407501095-l2oe4an1g7j2ont7spmevspm1l0ea8f0.apps.googleusercontent.com".freeze
    SIGNUP_TTL = 15.minutes

    Identity = Data.define(:uid, :email, :name)

    # The ID token is not valid (forged, expired, for another app, email not verified).
    class Invalid < StandardError; end
    # Google's keys could not be fetched: try again later.
    class Unavailable < StandardError; end

    # Replaced by a fake in the tests: (id_token, client_ids) -> the token's claims.
    mattr_accessor :verifier, default: ->(id_token, client_ids) { Google::Auth::IDTokens.verify_oidc(id_token, aud: client_ids) }

    module_function

    def client_ids
      ENV.fetch("GOOGLE_WEB_CLIENT_ID", DEFAULT_CLIENT_ID).split(",").map(&:strip).compact_blank
    end

    def verify(id_token)
      raise Invalid if id_token.blank?

      claims = verifier.call(id_token.to_s, client_ids)
      raise Invalid unless claims["sub"].present? && claims["email"].present? && [ true, "true" ].include?(claims["email_verified"])

      Identity.new(uid: claims["sub"].to_s, email: claims["email"].to_s.strip.downcase, name: claims["name"].to_s.squish.first(100))
    rescue Google::Auth::IDTokens::KeySourceError
      raise Unavailable
    rescue Google::Auth::IDTokens::VerificationError
      raise Invalid
    end

    # The account of this identity: with its Google ID, else with its email (Google verified it). nil for someone
    # new; Invalid when the email's account is already linked to another Google account.
    def account_for(identity)
      user = User.find_by(google_uid: identity.uid) || User.find_by(email: identity.email)
      raise Invalid if user&.google_uid && user.google_uid != identity.uid

      user
    end

    # Signing in links the account to the Google account, and confirms the email: Google checked that the address
    # is theirs, as the verification link would have.
    def link(user, identity)
      user.update_column(:google_uid, identity.uid) unless user.google_uid
      user.confirm if user.email == identity.email && !user.confirmed?
    end

    # Someone new, with the name, phone and consent they gave. The email is Google's, already verified (no
    # verification email); the password is random: "Forgot password" sets one, Google is enough to sign in.
    def build_user(identity, full_name:, phone:, locale:, privacy_consent:)
      User.new(full_name: full_name.presence || identity.name, phone: phone, email: identity.email, google_uid: identity.uid,
               password: SecureRandom.base58(32), locale: locale, privacy_consent: privacy_consent).tap(&:skip_confirmation!)
    end

    def signup_token(identity)
      signup_verifier.generate(identity.to_h, expires_in: SIGNUP_TTL)
    end

    # The identity of a signup token, or nil when it was tampered with or expired.
    def from_signup_token(token)
      data = signup_verifier.verified(token.to_s)
      Identity.new(**data.symbolize_keys.slice(:uid, :email, :name)) if data.is_a?(Hash)
    rescue ArgumentError
      nil
    end

    def signup_verifier
      Rails.application.message_verifier("google_signup")
    end
  end
end
