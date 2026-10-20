class ApplicationController < ActionController::Base
  # Where rate_limit counts requests. Rails.cache is a null store in tests, so they get their own memory store.
  RATE_LIMIT_STORE = Rails.env.test? ? ActiveSupport::Cache::MemoryStore.new : Rails.cache

  # Block only browsers too old for Tailwind 4 and import maps. Rails' :modern set (Safari 17.2) turned away iPhones
  # still on iOS 16, including the in-app browsers of Messenger and Zalo, which use the system Safari.
  MINIMUM_BROWSER_VERSIONS = { safari: 16.4, chrome: 111, firefox: 128, opera: 97, ie: false }.freeze
  allow_browser versions: MINIMUM_BROWSER_VERSIONS, block: :reject_unsupported_browser

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  prepend_before_action :ignore_background_refresh
  around_action :switch_locale
  before_action :configure_permitted_parameters, if: :devise_controller?
  # Not in Devise's controllers: there current_user would sign in from the form before the sign-in rate limit runs.
  before_action(unless: :devise_controller?) { Current.user = current_user }

  # Keep the current locale in every generated URL (no prefix for the default locale).
  def default_url_options
    { locale: I18n.locale == I18n.default_locale ? nil : I18n.locale }
  end

  private
  def reject_unsupported_browser
    logger.info "Unsupported browser: #{request.user_agent}"
    render file: Rails.root.join("public/406-unsupported-browser.html"), layout: false, status: :not_acceptable
  end

  # Live schedule refreshes (Turbo stream "refresh", marked by app/javascript/application.js) happen without
  # the user doing anything, so they must not keep the session alive: the timeout is still checked, but the
  # last activity time is left as it was.
  def ignore_background_refresh
    request.env["devise.skip_trackable"] = true if request.headers["X-Background-Refresh"] == "1"
  end

  # Answer to a request over a rate limit: back to the form with a message, instead of a bare 429.
  def rate_limited(path)
    redirect_to path, alert: t("rate_limited")
  end

  def switch_locale(&action)
    I18n.with_locale(params[:locale] || I18n.default_locale, &action)
  end

  # Devise only permits its authentication keys by default, which is :login here, so add :email explicitly.
  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: %i[email full_name phone locale privacy_consent])
    devise_parameter_sanitizer.permit(:account_update, keys: %i[email full_name phone birth_year gender skill_level avatar])
  end
end
