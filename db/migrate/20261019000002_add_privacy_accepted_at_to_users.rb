# When the customer agreed to the privacy policy at sign-up (kept as proof of consent).
class AddPrivacyAcceptedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :privacy_accepted_at, :datetime, precision: 0
  end
end
