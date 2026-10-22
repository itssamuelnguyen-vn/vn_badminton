require "test_helper"

# Android App Links (AP-04): /.well-known/assetlinks.json names the app and its signing keys from ANDROID_CERT_SHA256.
class Api::AssetLinksTest < ActionDispatch::IntegrationTest
  teardown { ENV.delete("ANDROID_CERT_SHA256") }

  test "lists the app with every fingerprint of ANDROID_CERT_SHA256" do
    ENV["ANDROID_CERT_SHA256"] = "aa:bb:cc, DD:EE:FF ,"
    get "/.well-known/assetlinks.json"

    assert_response :success
    assert_equal "application/json", response.media_type
    assert_equal [ {
      "relation" => [ "delegate_permission/common.handle_all_urls" ],
      "target" => { "namespace" => "android_app", "package_name" => "com.vnbadminton.vn_badminton_mobile",
                    "sha256_cert_fingerprints" => [ "AA:BB:CC", "DD:EE:FF" ] }
    } ], response.parsed_body
  end

  test "trusts no app without fingerprints" do
    get "/.well-known/assetlinks.json"

    assert_response :success
    assert_equal [], response.parsed_body
  end
end
