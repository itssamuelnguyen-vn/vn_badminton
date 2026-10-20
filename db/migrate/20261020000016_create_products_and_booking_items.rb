class CreateProductsAndBookingItems < ActiveRecord::Migration[8.1]
  def change
    # What customers can add to a booking (racket rental, shuttlecocks, drinks), set up by the owner.
    create_table :products do |t|
      t.references :venue, null: false, foreign_key: true
      t.string :name, null: false
      t.string :name_en
      t.bigint :price_vnd, null: false
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.timestamps precision: 0
    end
    add_check_constraint :products, "price_vnd > 0 AND price_vnd % 1000 = 0", name: "products_price_valid"

    # The products picked with a booking, priced when picked (a later price change does not touch them).
    # Paid with the booking's transfer; the staff hand them over at check-in.
    create_table :booking_items do |t|
      t.references :booking, null: false, foreign_key: { on_delete: :cascade }
      t.references :product, null: false, foreign_key: true
      t.string :name, null: false
      t.bigint :unit_price_vnd, null: false
      t.integer :quantity, null: false
      t.timestamps precision: 0
    end
    add_check_constraint :booking_items, "quantity BETWEEN 1 AND 20", name: "booking_items_quantity_valid"
    add_check_constraint :booking_items, "unit_price_vnd > 0", name: "booking_items_price_positive"
    add_index :booking_items, %i[booking_id product_id], unique: true

    # Court price plus the items: what the booking costs in all.
    add_column :bookings, :items_amount_vnd, :bigint, null: false, default: 0
    add_check_constraint :bookings, "items_amount_vnd >= 0", name: "bookings_items_amount_non_negative"
  end
end
