# Optional English name of a price rule, shown on English pages (PriceRule#display_name).
class AddNameEnToPriceRules < ActiveRecord::Migration[8.1]
  SEEDED_NAMES = { "Giờ thường" => "Standard", "Cuối tuần" => "Weekend", "Cao điểm ngày thường" => "Weekday peak" }.freeze

  def up
    add_column :price_rules, :name_en, :string
    add_check_constraint :price_rules, "name_en IS NULL OR length(btrim(name_en)) > 0", name: "price_rules_name_en_present"

    SEEDED_NAMES.each do |vi, en|
      execute sanitize_sql([ "UPDATE price_rules SET name_en = ? WHERE name = ?", en, vi ])
    end
  end

  def down
    remove_check_constraint :price_rules, name: "price_rules_name_en_present"
    remove_column :price_rules, :name_en
  end

  private

  def sanitize_sql(args)
    ActiveRecord::Base.sanitize_sql_array(args)
  end
end
