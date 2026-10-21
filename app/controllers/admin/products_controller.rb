module Admin
  # What customers can add to a booking in the app (racket rental, shuttlecocks, drinks). Owner only.
  # A product already picked is turned off rather than deleted (the bookings keep its name and price).
  class ProductsController < BaseController
    before_action :require_owner
    before_action :set_product, only: %i[edit update]

    def index
      @products = venue.products.ordered
    end

    def new
      @product = venue.products.new(position: venue.products.maximum(:position).to_i + 1)
    end

    def create
      @product = venue.products.new(product_params)
      if @product.save
        redirect_to admin_products_path, notice: t(".success")
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit
    end

    def update
      if @product.update(product_params)
        redirect_to admin_products_path, notice: t(".success")
      else
        render :edit, status: :unprocessable_content
      end
    end

    private

    def set_product
      @product = venue.products.find(params[:id])
    end

    def product_params
      params.require(:product).permit(:name, :name_en, :price_vnd, :position, :active)
    end
  end
end
