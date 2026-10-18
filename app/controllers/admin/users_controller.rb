module Admin
  class UsersController < BaseController
    before_action :require_owner, only: %i[destroy cancel_deletion]

    # Lets a customer who cancelled too often book online again before the lock ends.
    def unlock_booking
      User.find(params[:id]).unlock_booking
      redirect_back_or_to admin_root_path, notice: t(".success")
    end

    # The owner deletes a customer's or a staff member's account (Accounts::Deletion): locked at once,
    # removed once its bookings are played.
    def destroy
      deletion = Accounts::Deletion.new(User.find(params[:id]))
      return redirect_back_or_to(admin_root_path, alert: t("admin.bookings.not_allowed")) unless deletion.allowed? && deletion.user.deletion_requested_at.nil?

      finishes_at = deletion.finishes_at
      deletion.request!(by: current_user)
      redirect_back_or_to admin_root_path, notice: finishes_at ? t(".scheduled", time: l(finishes_at, format: :slot)) : t(".deleted")
    end

    def cancel_deletion
      Accounts::Deletion.new(User.find(params[:id])).cancel!
      redirect_back_or_to admin_root_path, notice: t(".success")
    rescue ArgumentError
      redirect_back_or_to admin_root_path, alert: t("admin.bookings.not_allowed")
    end
  end
end
