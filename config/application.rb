require_relative "boot"

require "rails/all"
require_relative "../lib/log_formatter"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module VnBadminton
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks log_formatter.rb])

    # Format log lines as "[LEVEL] [time] [request_id] message".
    config.log_formatter = LogFormatter.new
    config.log_tags = [ :request_id ]
    # No ANSI color codes, so log files stay readable in editors and log viewers.
    config.colorize_logging = false

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.eager_load_paths << Rails.root.join("extras")

    config.time_zone = "Asia/Ho_Chi_Minh"

    # Vietnamese by default, English as the second language.
    config.i18n.available_locales = [ :vi, :en ]
    config.i18n.default_locale = :vi
  end
end
