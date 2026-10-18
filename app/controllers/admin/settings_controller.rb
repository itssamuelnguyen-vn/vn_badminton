module Admin
  # The venue's details, online booking policy and weekly opening hours.
  class SettingsController < BaseController
    before_action :require_owner

    def edit
      @settings = VenueSettings.new(venue)
    end

    def update
      @settings = VenueSettings.new(venue)

      if @settings.update(params.require(:settings).permit(*VenueSettings.permitted_params))
        redirect_to edit_admin_settings_path, notice: t(".success")
      else
        render :edit, status: :unprocessable_content
      end
    end
  end
end
