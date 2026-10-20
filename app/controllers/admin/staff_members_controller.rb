module Admin
  # The owner gives staff access to accounts that already exist: staff sign up like customers first,
  # so the owner never handles their passwords.
  class StaffMembersController < BaseController
    before_action :require_owner

    def index
      @members = User.where(role: %w[admin staff], deleted_at: nil).order(:role, :full_name)
    end

    # login: the email or phone number of the account.
    def create
      user = User.find_for_database_authentication(login: params[:login])

      if user.nil?
        redirect_to admin_staff_members_path, alert: t(".not_found")
      elsif !user.customer?
        redirect_to admin_staff_members_path, alert: t(".already_staff", name: user.full_name)
      else
        user.update!(role: :staff)
        redirect_to admin_staff_members_path, notice: t(".success", name: user.full_name)
      end
    end

    # Back to a customer account. The owner cannot remove themselves.
    def destroy
      user = User.staff.find(params[:id])
      if user.update(role: :customer)
        redirect_to admin_staff_members_path, notice: t(".success", name: user.full_name)
      else
        redirect_to admin_staff_members_path, alert: user.errors.full_messages.to_sentence
      end
    end
  end
end
