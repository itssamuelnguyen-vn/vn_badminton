# Store every datetime with whole seconds (timestamptz(0)) instead of Rails' default microseconds.
# Existing values are rounded to the nearest second by PostgreSQL.
# New datetime columns must also use precision: 0 (enforced by test/models/schema_conventions_test.rb).
class RemoveFractionalSecondsFromDatetimes < ActiveRecord::Migration[8.1]
  TABLES = %i[users venues opening_hours courts price_rules bookings].freeze

  def up
    change_datetime_precision(0)
  end

  def down
    change_datetime_precision(6)
  end

  private

  def change_datetime_precision(precision)
    TABLES.each do |table|
      columns(table).select { |column| column.type == :datetime }.each do |column|
        change_column table, column.name, :datetime, precision: precision, null: column.null
      end
    end
  end
end
