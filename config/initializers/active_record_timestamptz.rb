# Make every t.datetime column "timestamp with time zone" instead of "timestamp without time zone".
# Add this file BEFORE running the first migration.
ActiveSupport.on_load(:active_record_postgresqladapter) do
  self.datetime_type = :timestamptz
end
