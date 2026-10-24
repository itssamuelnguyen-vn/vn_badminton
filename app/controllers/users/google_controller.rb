module Users
  # "Sign in with Google" on the web, as in the app (AP-05, Accounts::GoogleIdentity): Google's button on the sign-in
  # and sign-up pages (google_sign_in Stimulus controller) posts the ID token to #create. A known account is signed
  # in and linked to the Google account; someone new gives a phone number and consent first (#new, #register).
  class GoogleController < ApplicationController
    rate_limit to: 10, within: 3.minutes, only: %i[create register], store: RATE_LIMIT_STORE,
               with: -> { rate_limited(new_user_session_path) }

    def create
      identity = Accounts::GoogleIdentity.verify(params[:credential])
      user = Accounts::GoogleIdentity.account_for(identity)
      unless user
        session[:google_signup] = Accounts::GoogleIdentity.signup_token(identity)
        return redirect_to new_google_sign_in_path
      end
      return redirect_to(new_user_session_path, alert: t("devise.failure.account_deleted")) unless user.active_for_authentication?

      Accounts::GoogleIdentity.link(user, identity)
      sign_in(:user, user)
      redirect_to after_sign_in_path_for(user)
    rescue Accounts::GoogleIdentity::Invalid
      redirect_to new_user_session_path, alert: t("api.google.invalid")
    rescue Accounts::GoogleIdentity::Unavailable
      redirect_to new_user_session_path, alert: t("api.google.unavailable")
    end

    def new
      @identity = signup_identity or return
      @user = User.new(full_name: @identity.name, email: @identity.email)
    end

    def register
      @identity = signup_identity or return
      attributes = params.require(:user).permit(:full_name, :phone, :privacy_consent)
      @user = Accounts::GoogleIdentity.build_user(@identity, **attributes.to_h.symbolize_keys, locale: I18n.locale.to_s)
      if @user.save
        session.delete(:google_signup)
        sign_in(:user, @user)
        redirect_to after_sign_in_path_for(@user), notice: t(".success")
      else
        render :new, status: :unprocessable_content
      end
    rescue ActiveRecord::RecordNotUnique
      # The same Google account signed up at the same moment.
      redirect_to new_user_session_path, alert: t("api.google.already_registered")
    end

    private

    # Who Google said they are, kept in the session for SIGNUP_TTL; sent back to sign in again once expired.
    def signup_identity
      identity = Accounts::GoogleIdentity.from_signup_token(session[:google_signup])
      redirect_to new_user_session_path, alert: t("api.google.signup_expired") unless identity
      identity
    end
  end
end
