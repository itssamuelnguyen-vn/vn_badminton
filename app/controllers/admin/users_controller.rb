module Admin
  class UsersController < BaseController
    # Lets a customer who cancelled too often book online again before the lock ends.
    def unlock_booking
      User.find(params[:id]).unlock_booking
      redirect_back_or_to admin_root_path, notice: t(".success")
    end
  end
end
