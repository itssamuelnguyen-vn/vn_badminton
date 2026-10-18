module Accounts
  # "Tải dữ liệu của tôi" on the account page: everything kept about the account, as a JSON file
  # (Accounts::DataExport). Asked with the password, a few times an hour at most.
  class DataExportsController < ApplicationController
    before_action :authenticate_user!
    rate_limit to: 5, within: 1.hour, store: RATE_LIMIT_STORE, with: -> { rate_limited(edit_user_registration_path) }

    def create
      unless current_user.valid_password?(params[:current_password].to_s)
        return redirect_to(edit_user_registration_path, alert: t("users.registrations.destroy.wrong_password"))
      end

      export = DataExport.new(current_user)
      send_data export.to_json, type: :json, filename: export.filename
    end
  end
end
