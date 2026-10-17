require "application_system_test_case"

class DatePickerTest < ApplicationSystemTestCase
  setup { travel_to Time.zone.parse("2026-10-20 10:00") } # horizon: 20/10 - 03/11

  test "picks a day from the month calendar" do
    visit root_path

    assert_no_selector "[role=dialog]"
    click_on "Thứ ba, 20/10/2026"
    within("[role=dialog]") do
      assert_text "Tháng 10, 2026"
      assert_selector "span[aria-disabled=true]", text: "19"
      click_on "23"
    end

    assert_selector "button[aria-haspopup=dialog]", text: "Thứ sáu, 23/10/2026"
    assert_no_selector "[role=dialog]"
  end

  test "switches to the next month and closes on Escape or an outside click" do
    visit root_path
    click_on "Thứ ba, 20/10/2026"

    click_on "Tháng sau"
    within("[role=dialog]") do
      assert_text "Tháng 11, 2026"
      assert_selector "a", text: "3"
      assert_selector "span[aria-disabled=true]", text: "4"
    end

    send_keys :escape
    assert_no_selector "[role=dialog]"

    click_on "Thứ ba, 20/10/2026"
    find("h1").click
    assert_no_selector "[role=dialog]"
  end

  test "the arrows move one day" do
    visit root_path

    click_on "Ngày sau"
    assert_selector "button[aria-haspopup=dialog]", text: "Thứ tư, 21/10/2026"
    click_on "Ngày trước"
    assert_selector "button[aria-haspopup=dialog]", text: "Thứ ba, 20/10/2026"
  end
end
