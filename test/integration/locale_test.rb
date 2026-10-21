require "test_helper"

class LocaleTest < ActionDispatch::IntegrationTest
  test "Vietnamese is the default and has no URL prefix" do
    get root_path

    assert_equal "/", root_path
    assert_select "html[lang=vi]"
    assert_select "h1", "Chọn sân, chọn giờ, chuyển khoản là xong"
  end

  test "English pages live under /en and keep the prefix in links" do
    get "/en"

    assert_select "html[lang=en]"
    assert_select "h1", "Pick a court, pick a time, pay by transfer. Done."
    assert_select "header a[href='/en/users/sign_in']", "Sign in"
  end

  test "the switcher links to the same page in the other language" do
    get "/en/users/sign_in"

    assert_select "a[hreflang=vi][href='/users/sign_in']", "VI"
    assert_select "a[hreflang=en][aria-current=true]", "EN"
  end

  test "the switcher falls back to the home page after a failed form post" do
    post "/en/users/sign_in", params: { user: { login: "an@example.com", password: "wrong" } }

    assert_select "a[hreflang=vi][href='/']"
  end

  test "an unknown locale prefix is not routed" do
    get "/fr/users/sign_in"

    assert_response :not_found
  end

  test "redirects to the sign-in page in the current locale" do
    get "/en/users/edit"

    assert_redirected_to "/en/users/sign_in"
    follow_redirect!
    assert_select "[role=alert]", "You need to sign in or sign up before continuing."
  end
end
