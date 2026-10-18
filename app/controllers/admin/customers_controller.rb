module Admin
  # Customers by phone number: search, booking history, a private note and the blacklist.
  class CustomersController < BaseController
    before_action :set_customer, only: %i[show update]

    def index
      @query = params[:q].to_s.strip
      @customers = Customers::Directory.new(query: @query).entries
    end

    def show
      @profile = @customer.profile || CustomerProfile.new(phone: @customer.phone)
      @bookings = Booking.kind_reservation.where(customer_phone: @customer.phone).where.not(status: :pending)
                         .includes(:court).order(starts_at: :desc).limit(100)
    end

    def update
      profile = CustomerProfile.find_or_initialize_by(phone: @customer.phone)
      attributes = params.require(:customer_profile).permit(:note, :blocked, :blocked_reason)
      profile.note = attributes[:note]
      attributes[:blocked] == "1" ? profile.block(by: current_user, reason: attributes[:blocked_reason]) : profile.unblock

      if profile.save
        redirect_to admin_customer_path(@customer), notice: t(".success")
      else
        redirect_to admin_customer_path(@customer), alert: profile.errors.full_messages.to_sentence
      end
    end

    private

    def set_customer
      @customer = Customers::Directory.new.find(params[:phone]) or raise ActiveRecord::RecordNotFound
    end
  end
end
