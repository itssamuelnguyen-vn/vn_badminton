class AddContactChannelsToVenues < ActiveRecord::Migration[8.1]
  def change
    add_column :venues, :zalo_phone, :string
    add_column :venues, :facebook_page, :string
  end
end
