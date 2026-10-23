require "test_helper"

# Online bookings are paid in full by bank transfer (VietQR), confirmed by SePay webhooks.
class PaymentsTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.parse("2026-10-19 10:00")
    @slots = { "0" => { court_id: courts(:court_one).id, starts_at: at("18:00").iso8601, ends_at: at("19:30").iso8601 } }
  end

  test "the customer pays on the payment page and the booking is confirmed when the transfer arrives" do
    sign_in users(:an)
    post bookings_path, params: { booking: { slots: @slots } }
    payment = Payment.last
    booking = Booking.last

    follow_redirect!
    assert_select "img[src*='vietqr.app'][src*='amount=180000'][src*='des=#{payment.code}']"
    assert_select "dd", text: payment.code
    assert_select "[role=timer][data-hold-countdown-seconds-value='900']"
    assert booking.pending?
    assert_equal payment, booking.payment

    get bookings_path
    assert_select "a[href='/payments/#{payment.token}']", text: /180.000đ/

    assert_enqueued_emails(1) { transfer }
    assert_response :success
    assert_equal({ "success" => true }, response.parsed_body)
    booking.reload
    assert booking.confirmed?
    assert booking.payment_paid?
    assert payment.reload.paid?
    assert BankTransaction.last.matched?

    get payment_path(payment)
    assert_select "h1", text: "Đã nhận được tiền"
  end

  test "the webhook needs the API key" do
    sign_in users(:an)
    post bookings_path, params: { booking: { slots: @slots } }
    payment = Payment.last

    post sepay_webhook_path, as: :json, params: { id: 1, content: payment.code, transferType: "in", transferAmount: payment.amount_vnd },
                             headers: { "Authorization" => "Apikey wrong" }
    assert_response :unauthorized
    assert payment.reload.awaiting?
    assert_empty BankTransaction.all
  end

  test "the QR image can be saved as a file while the payment is open" do
    sign_in users(:an)
    post bookings_path, params: { booking: { slots: @slots } }
    payment = Payment.last

    get payment_path(payment)
    assert_select "a[href='/payments/#{payment.token}/qr'][download='QR-#{payment.code}.png']", text: "Lưu ảnh mã QR"

    urls = with_qr_image { get qr_payment_path(payment) }
    assert_response :success
    assert_equal "image/png", response.media_type
    assert_equal "PNG", response.body
    assert_match(/attachment; filename="QR-#{payment.code}.png"/, response.headers["Content-Disposition"])
    assert_equal [ payment.qr_url(Venue.main) ], urls

    with_qr_image(error: true) { get qr_payment_path(payment) }
    assert_response :bad_gateway

    travel 18.minutes
    with_qr_image { get qr_payment_path(payment) }
    assert_response :not_found
  end

  test "a delivery sent twice is handled once" do
    sign_in users(:an)
    post bookings_path, params: { booking: { slots: @slots } }

    assert_enqueued_emails(1) { 2.times { transfer(id: 4242) } }
    assert_equal 1, BankTransaction.count
  end

  test "a transfer within the grace period still confirms; a later one takes the court back while it is free" do
    sign_in users(:an)
    post bookings_path, params: { booking: { slots: @slots } }
    on_time = Payment.last

    travel 16.minutes # deadline 15 min, grace 2 min
    transfer(on_time)
    assert Booking.last.confirmed?

    post bookings_path, params: { booking: { slots: { "0" => @slots["0"].merge(court_id: courts(:court_two).id) } } }
    late = Payment.last
    travel 18.minutes
    perform_enqueued_jobs(only: HoldExpiryJob)
    late_booking = late.bookings.sole
    assert late_booking.cancelled?
    assert_equal Booking::PAYMENT_EXPIRED, late_booking.cancellation_reason
    assert late.reload.expired?

    assert_enqueued_emails(1) { transfer(late) }
    assert BankTransaction.last.matched?
    assert late.reload.paid?
    late_booking.reload
    assert late_booking.confirmed?
    assert late_booking.payment_paid?
    assert_nil late_booking.cancellation_reason
  end

  test "a late transfer is left for a refund when the court was taken meanwhile" do
    sign_in users(:an)
    post bookings_path, params: { booking: { slots: @slots } }
    late = Payment.last
    travel 18.minutes # not released yet: the next booking of the court releases it

    sign_in users(:chi)
    post bookings_path, params: { booking: { slots: @slots } }
    assert_equal users(:chi), Booking.pending.sole.user

    transfer(late)
    assert_equal [ "needs_review", "late" ], BankTransaction.last.then { |t| [ t.status, t.review_reason ] }
    assert late.reload.expired?
    assert late.bookings.sole.cancelled?
  end

  test "a transfer short of the amount waits for the rest, with the same code" do
    sign_in users(:an)
    post bookings_path, params: { booking: { slots: @slots } }
    payment = Payment.last

    transfer(payment, amount: 100_000)
    assert_equal [ "needs_review", "underpaid" ], BankTransaction.last.then { |t| [ t.status, t.review_reason ] }
    assert Booking.last.pending?

    get payment_path(payment)
    assert_select "[role=status]", text: /Đã nhận 100.000đ, còn thiếu 80.000đ/
    assert_select "img[src*='amount=80000']"

    transfer(payment, amount: 80_000)
    assert Booking.last.confirmed?
    assert_equal %w[matched matched], payment.transfers.order(:id).pluck(:status)
  end

  test "a transfer above the amount confirms and leaves the excess to refund" do
    sign_in users(:an)
    post bookings_path, params: { booking: { slots: @slots } }
    payment = Payment.last

    transfer(payment, amount: 200_000)
    assert Booking.last.confirmed?
    assert_equal [ "needs_review", "overpaid" ], BankTransaction.last.then { |t| [ t.status, t.review_reason ] }

    sign_in users(:owner)
    get admin_bank_transactions_path
    assert_select "span", text: "Chuyển thừa"
    assert_select "p", text: /Cần hoàn phần thừa 20.000đ/
  end

  test "the owner assigns a transfer without a code to its booking" do
    sign_in users(:an)
    post bookings_path, params: { booking: { slots: @slots } }
    booking = Booking.last
    transfer(content: "chuyen tien san cau long")
    transaction = BankTransaction.last
    assert_equal "unknown_code", transaction.review_reason

    sign_in users(:owner)
    patch assign_admin_bank_transaction_path(transaction), params: { code: "NOPE1234" }
    assert_equal "Không tìm thấy mã NOPE1234.", flash[:alert]

    patch assign_admin_bank_transaction_path(transaction), params: { code: booking.code.downcase }
    assert_equal "Đã gán giao dịch và xác nhận đơn.", flash[:notice]
    assert transaction.reload.matched?
    assert booking.reload.confirmed?
  end

  test "unknown codes, payments made twice, cancelled payments and money going out are not confirmed" do
    sign_in users(:an)
    post bookings_path, params: { booking: { slots: @slots } }
    payment = Payment.last

    transfer(payment, content: "chuyen tien san cau long")
    assert_equal "unknown_code", BankTransaction.last.review_reason

    transfer(payment)
    transfer(payment)
    assert_equal "already_paid", BankTransaction.last.review_reason

    post bookings_path, params: { booking: { slots: { "0" => @slots["0"].merge(court_id: courts(:court_two).id) } } }
    replaced = Payment.last
    post bookings_path, params: { booking: { slots: { "0" => @slots["0"].merge(court_id: courts(:court_two).id) } } }
    transfer(replaced)
    assert_equal "cancelled", BankTransaction.last.review_reason

    post sepay_webhook_path, as: :json, headers: { "Authorization" => "Apikey #{ENV["SEPAY_WEBHOOK_API_KEY"]}" },
                             params: { id: 99, content: "rut tien", transferType: "out", transferAmount: 50_000 }
    assert BankTransaction.find_by(sepay_id: 99).ignored?
  end

  test "paying again for the same slots replaces the earlier try; giving up an unpaid booking does not count towards the lock" do
    sign_in users(:an)
    post bookings_path, params: { booking: { slots: @slots } }
    first = Payment.last
    post bookings_path, params: { booking: { slots: @slots } }
    second = Payment.last

    assert first.reload.cancelled?
    assert second.awaiting?
    assert_equal 1, Booking.pending.count

    3.times do |i|
      post bookings_path, params: { booking: { slots: { "0" => @slots["0"].merge(starts_at: at("0#{6 + i}:00").iso8601, ends_at: at("0#{7 + i}:00").iso8601) } } }
      patch cancel_booking_path(Booking.last)
    end
    assert_nil users(:an).reload.booking_locked_until
  end

  test "the customer gives up on the payment page: the court is free again at once, a transfer after that goes to review" do
    voucher = venues(:phu_nhuan).vouchers.create!(code: "HUY", kind: "amount", value: 10_000, valid_from: "2026-10-01", valid_until: "2026-10-31")
    sign_in users(:an)
    post bookings_path, params: { booking: { slots: @slots, voucher_code: "HUY" } }
    payment = Payment.last
    booking = Booking.last
    assert_equal 1, voucher.uses

    get payment_path(payment)
    assert_select "form[action='/payments/#{payment.token}/cancel'][data-turbo-confirm] button", text: "Huỷ đặt sân"

    # Only the customer who booked can cancel it.
    sign_in users(:chi)
    get payment_path(payment)
    assert_select "form[action='/payments/#{payment.token}/cancel']", count: 0
    patch cancel_payment_path(payment)
    assert_redirected_to payment_path(payment)
    assert payment.reload.awaiting?

    sign_in users(:an)
    patch cancel_payment_path(payment)
    assert_redirected_to root_path(date: "2026-10-19")
    assert payment.reload.cancelled?
    assert_equal [ "cancelled", Booking::PAYMENT_CANCELLED, nil ], booking.reload.values_at(:status, :cancellation_reason, :cancelled_by_id)
    assert_equal 0, voucher.uses, "the voucher use is given back"
    assert_nil users(:an).reload.booking_locked_until

    get payment_path(payment)
    assert_select "h1", text: "Đã huỷ"

    # The court can be booked again straight away.
    sign_in users(:chi)
    post bookings_path, params: { booking: { slots: @slots } }
    assert_redirected_to payment_path(Payment.last)

    transfer(payment)
    assert_equal "cancelled", BankTransaction.last.review_reason
  end

  test "a payment cannot be cancelled once money has arrived" do
    sign_in users(:an)
    post bookings_path, params: { booking: { slots: @slots } }
    payment = Payment.last
    transfer(payment, amount: 100_000)

    get payment_path(payment)
    assert_select "form[action='/payments/#{payment.token}/cancel']", count: 0
    patch cancel_payment_path(payment)
    assert_redirected_to payment_path(payment)
    assert_equal "Không thể huỷ đơn này nữa (đã nhận tiền, đã hết hạn hoặc đã huỷ).", flash[:alert]
    assert Booking.last.pending?
  end

  test "online booking is closed until the venue has a receiving account" do
    venues(:phu_nhuan).update!(bank_code: nil, bank_account_number: nil)
    sign_in users(:an)

    assert_no_difference("Booking.count") { post bookings_path, params: { booking: { slots: @slots } } }
    assert_redirected_to root_path
    assert_equal "Sân chưa bật thanh toán online. Vui lòng gọi cho sân để đặt.", flash[:alert]
  end

  test "walk-ins pay cash and are confirmed at once; staff can confirm a transfer by hand" do
    sign_in users(:staffer)
    post admin_bookings_path, params: { booking: { kind: "reservation", court_id: courts(:court_one).id, date: "2026-10-19", start_minute: 1080,
                                                   end_minute: 1140, source: "walk_in", customer_name: "Khách lẻ", customer_phone: "0912000111" } }
    walk_in = Booking.last
    assert walk_in.confirmed?
    assert_nil walk_in.payment

    post admin_bookings_path, params: { booking: { kind: "reservation", court_id: courts(:court_two).id, date: "2026-10-19", start_minute: 1080,
                                                   end_minute: 1140, source: "phone", customer_name: "Anh Bình", customer_phone: "0912000222" } }
    phone = Booking.last
    assert phone.pending?
    patch confirm_payment_admin_booking_path(phone)
    assert phone.reload.confirmed?
    assert phone.payment_paid?
  end

  test "a customer cancelling a paid booking is warned there is no refund; the venue's fault is refunded" do
    sign_in users(:an)
    post bookings_path, params: { booking: { slots: @slots } }
    transfer
    booking = Booking.last

    get booking_path(booking)
    assert_select "form[data-turbo-confirm*='KHÔNG được hoàn tiền']"

    sign_in users(:staffer)
    patch cancel_venue_fault_admin_booking_path(booking)
    booking.reload
    assert booking.cancelled?
    assert_equal [ Booking::VENUE_FAULT, 180_000 ], [ booking.cancellation_reason, booking.refund_vnd ]

    sign_in users(:owner)
    get admin_bank_transactions_path
    assert_select "a[href='/admin/bookings/#{booking.code}']", text: /180.000đ · Nguyễn An/
    patch mark_refunded_admin_booking_path(booking)
    assert booking.reload.payment_refunded?
    assert booking.refunded_at
  end

  test "the owner reviews transfers that need a decision; staff cannot see them" do
    sign_in users(:an)
    post bookings_path, params: { booking: { slots: @slots } }
    transfer(amount: 100_000)
    transaction = BankTransaction.last

    sign_in users(:staffer)
    get admin_bank_transactions_path
    assert_redirected_to admin_root_path

    sign_in users(:owner)
    get admin_bank_transactions_path
    assert_select "span", text: "Chuyển thiếu"
    patch admin_bank_transaction_path(transaction), params: { resolution_note: "Đã hoàn 100.000đ cho khách" }
    assert transaction.reload.resolved?
    assert_equal users(:owner), transaction.resolved_by
  end

  test "a regular customer pays the month by transfer" do
    sign_in users(:owner)
    post admin_series_index_path, params: { booking_series: { customer_name: "Nguyễn An", customer_phone: "0901 234 567",
                                                              court_ids: [ courts(:court_one).id ], days_of_week: [ "2" ], start_minute: 1080,
                                                              end_minute: 1200, starts_on: "2026-10-20", ends_on: "2026-10-27" } }
    series = BookingSeries.last
    post request_payment_admin_series_path(series, month: "2026-10-01")
    payment = series.payments.awaiting.sole
    assert_equal 480_000, payment.amount_vnd

    transfer(payment)
    assert series.billing(Date.new(2026, 10, 1)).paid?
    assert series.bookings.all?(&:payment_paid?)
  end

  private

  # Stands in for VietQR's server; returns the URLs asked for.
  def with_qr_image(error: false)
    urls = []
    original = Payments::QrImage.method(:fetch)
    Payments::QrImage.define_singleton_method(:fetch) do |url|
      urls << url
      error ? raise(Payments::QrImage::Error, "down") : "PNG"
    end
    yield
    urls
  ensure
    Payments::QrImage.define_singleton_method(:fetch, original)
  end

  def at(time) = Time.zone.parse("2026-10-19 #{time}").then { |t| t < Time.current ? t + 1.day : t }
end
