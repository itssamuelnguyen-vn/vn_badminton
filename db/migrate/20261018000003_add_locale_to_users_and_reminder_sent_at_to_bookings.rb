# Emails sent outside of a request (reminders, cancellations by the owner) use the customer's language,
# and each booking is reminded at most once.
class AddLocaleToUsersAndReminderSentAtToBookings < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :locale, :string, null: false, default: "vi"
    add_check_constraint :users, "locale IN ('vi', 'en')", name: "users_locale_valid"

    add_column :bookings, :reminder_sent_at, :datetime, precision: 0
  end
end
