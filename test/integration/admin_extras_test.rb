require "test_helper"

# The owner's pages for the app's extras: products and announcements are the owner's, reviews also the staff's.
class AdminExtrasTest < ActionDispatch::IntegrationTest
  test "the owner adds, edits and turns off extras; staff cannot" do
    sign_in users(:owner)
    post admin_products_path, params: { product: { name: "Thuê vợt", name_en: "Racket rental", price_vnd: 30_000, position: 1, active: "1" } }
    assert_redirected_to admin_products_path
    product = Product.last

    post admin_products_path, params: { product: { name: "Nước", price_vnd: 12_500 } }
    assert_response :unprocessable_content

    patch admin_product_path(product), params: { product: { active: "0" } }
    assert_not product.reload.active
    get admin_products_path
    assert_select "p", text: /Thuê vợt/

    sign_in users(:staffer)
    get admin_products_path
    assert_redirected_to admin_root_path
    get admin_reviews_path
    assert_response :success
  end

  test "an announcement is edited and deleted" do
    sign_in users(:owner)
    announcement = venues(:phu_nhuan).announcements.create!(title: "Khuyến mãi", starts_on: Date.current, ends_on: Date.current + 3)
    patch admin_announcement_path(announcement), params: { announcement: { ends_on: Date.current - 1 } }
    assert_response :unprocessable_content
    patch admin_announcement_path(announcement), params: { announcement: { title: "Giảm 10% giờ trưa", tone: "offer" } }
    assert_equal [ "Giảm 10% giờ trưa", "offer" ], announcement.reload.values_at(:title, :tone)
    delete admin_announcement_path(announcement)
    assert_not Announcement.exists?(announcement.id)
  end
end
