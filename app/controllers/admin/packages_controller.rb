module Admin
  # Prepaid hours on sale (Package) and who bought them. Owner only. A package already sold is turned off, not deleted.
  class PackagesController < BaseController
    before_action :require_owner
    before_action :set_package, only: %i[edit update]

    def index
      @packages = venue.packages.order(active: :desc, price_vnd: :asc)
      @purchases = PackagePurchase.where.not(status: :awaiting).includes(:user).order(paid_at: :desc).limit(50)
    end

    def new
      @package = venue.packages.new(minutes: 600, valid_days: 60)
    end

    def create
      @package = venue.packages.new(package_params)
      if @package.save
        redirect_to admin_packages_path, notice: t(".success")
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit
    end

    def update
      if @package.update(package_params)
        redirect_to admin_packages_path, notice: t(".success")
      else
        render :edit, status: :unprocessable_content
      end
    end

    private

    def set_package
      @package = venue.packages.find(params[:id])
    end

    def package_params
      permitted = params.require(:package).permit(:name, :name_en, :hours, :price_vnd, :valid_days, :start_minute, :end_minute, :active)
      permitted[:minutes] = (permitted.delete(:hours).to_f * 60).round if permitted.key?(:hours)
      %i[start_minute end_minute].each { |key| permitted[key] = permitted[key].presence if permitted.key?(key) }
      permitted
    end
  end
end
