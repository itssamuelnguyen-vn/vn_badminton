require "test_helper"

class BrowserSupportTest < ActionDispatch::IntegrationTest
  IOS_16_SAFARI = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) " \
    "Version/16.7 Mobile/15E148 Safari/604.1".freeze
  IOS_16_MESSENGER = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) " \
    "Mobile/20H19 [FBAN/MessengerLiteForiOS;FBAV/530.0.0.30.106;FBSN/iOS;FBSV/16.7;FBLC/vi_VN]".freeze
  IOS_15_SAFARI = "Mozilla/5.0 (iPhone; CPU iPhone OS 15_8 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) " \
    "Version/15.6 Mobile/15E148 Safari/604.1".freeze

  test "iPhones on iOS 16, in Safari or in the Messenger in-app browser, can open the schedule" do
    [ IOS_16_SAFARI, IOS_16_MESSENGER ].each do |user_agent|
      get root_path, headers: { "User-Agent" => user_agent }

      assert_response :success, user_agent
    end
  end

  test "browsers too old for the site get the unsupported-browser page" do
    get root_path, headers: { "User-Agent" => IOS_15_SAFARI }

    assert_response :not_acceptable
    assert_includes response.body, "Trình duyệt chưa được hỗ trợ"
  end
end
