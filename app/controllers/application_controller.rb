class ApplicationController < ActionController::Base
  # Where rate_limit counts requests. Rails.cache is a null store in tests, so they get their own memory store.
  RATE_LIMIT_STORE = Rails.env.test? ? ActiveSupport::Cache::MemoryStore.new : Rails.cache

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  around_action :switch_locale
  before_action :configure_permitted_parameters, if: :devise_controller?

  # Keep the current locale in every generated URL (no prefix for the default locale).
  def default_url_options
    { locale: I18n.locale == I18n.default_locale ? nil : I18n.locale }
  end

  private

  # Answer to a request over a rate limit: back to the form with a message, instead of a bare 429.
  def rate_limited(path)
    redirect_to path, alert: t("rate_limited")
  end

  def switch_locale(&action)
    I18n.with_locale(params[:locale] || I18n.default_locale, &action)
  end

  # Devise only permits its authentication keys by default, which is :login here, so add :email explicitly.
  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: %i[email full_name phone locale])
    devise_parameter_sanitizer.permit(:account_update, keys: %i[email full_name phone])
  end
end
