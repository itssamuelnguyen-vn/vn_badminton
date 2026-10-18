module Admin
  class PriceRulesController < BaseController
    before_action :require_owner
    before_action :set_price_rule, only: %i[edit update destroy]

    def index
      # Same order as Pricing::RuleSet: court-specific rules first, then higher priority.
      @price_rules = venue.price_rules.includes(:court).sort_by { |r| [ r.active ? 0 : 1, r.court_id ? 0 : 1, -r.priority, r.start_minute ] }
    end

    def new
      @price_rule = venue.price_rules.new(days_of_week: (0..6).to_a, start_minute: venue.opening_hours.minimum(:opens_minute),
                                          end_minute: venue.opening_hours.maximum(:closes_minute))
    end

    def create
      @price_rule = venue.price_rules.new(price_rule_params)

      if @price_rule.save
        redirect_to admin_price_rules_path, notice: t(".success")
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit
    end

    def update
      if @price_rule.update(price_rule_params)
        redirect_to admin_price_rules_path, notice: t(".success")
      else
        render :edit, status: :unprocessable_content
      end
    end

    # Bookings keep their price (and a copy of the rule in price_breakdown), so a rule can be deleted safely.
    def destroy
      @price_rule.destroy!
      redirect_to admin_price_rules_path, notice: t(".success")
    end

    private

    def set_price_rule
      @price_rule = venue.price_rules.find(params[:id])
    end

    def price_rule_params
      permitted = params.require(:price_rule).permit(:name, :name_en, :court_id, :start_minute, :end_minute, :price_per_hour_vnd,
                                                     :priority, :valid_from, :valid_until, :active, days_of_week: [])
      # The check boxes send an empty value so that unticking every day still submits the field.
      permitted[:days_of_week] = permitted[:days_of_week].compact_blank if permitted.key?(:days_of_week)
      permitted
    end
  end
end
