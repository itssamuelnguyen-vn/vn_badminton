module Admin
  # Pages of the owner's area. Only managers can open them.
  class BaseController < ApplicationController
    layout "admin"

    before_action :authenticate_user!
    before_action :require_manager

    private

    def require_manager
      redirect_to root_path, alert: t("admin.not_authorized") unless current_user.manager?
    end

    # For the owner-only pages: prices, settings, reports, staff.
    def require_owner
      redirect_to admin_root_path, alert: t("admin.owner_only") unless current_user.owner?
    end

    def venue
      @venue ||= Venue.main
    end
  end
end
