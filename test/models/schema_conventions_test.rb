require "test_helper"

class SchemaConventionsTest < ActiveSupport::TestCase
  # Datetimes are stored with whole seconds; Rails defaults new columns to precision 6,
  # so every migration has to pass precision: 0 explicitly (t.timestamps precision: 0).
  test "every datetime column stores whole seconds" do
    connection = ActiveRecord::Base.connection
    # Rails' own bookkeeping tables are created by Rails and keep its defaults.
    app_tables = connection.tables - [ ActiveRecord::Base.internal_metadata_table_name, ActiveRecord::Base.schema_migrations_table_name ]
    offenders = app_tables.flat_map do |table|
      connection.columns(table)
        .select { |column| column.type == :datetime && column.precision != 0 }
        .map { |column| "#{table}.#{column.name} (precision #{column.precision.inspect})" }
    end

    assert_empty offenders, "Use precision: 0 for these datetime columns"
  end
end
