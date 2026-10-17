# Devise's failure app runs outside the controller's I18n.with_locale block, so its flash messages
# ("You need to sign in...") would always be in the default locale. Take the locale from the URL instead.
class LocalizedFailureApp < Devise::FailureApp
  def i18n_locale
    locale = params[:locale]
    I18n.available_locales.map(&:to_s).include?(locale) ? locale : I18n.default_locale
  end
end
