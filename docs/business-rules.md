# Quy tắc nghiệp vụ – VN Badminton

Tài liệu này ghi lại **mọi quy tắc nghiệp vụ** của web đặt sân, tổng hợp từ code (không phải từ trí nhớ).
Mỗi quy tắc có **mã số** để tham chiếu và **nguồn**: file code thực thi nó và file test kiểm tra nó.
Test là bản mô tả chính xác nhất: nếu tài liệu và test khác nhau, **test đúng** và tài liệu cần sửa.

**Cách giữ tài liệu luôn đúng:** PR nào thay đổi một quy tắc thì sửa luôn mục tương ứng ở đây trong cùng PR
(xem `CLAUDE.md`). Các con số có thể chỉnh trong **Quản lý → Cài đặt** được đánh dấu ⚙️ và ghi giá trị mặc định.

> Cập nhật: 18/10/2026, theo `main` sau PR #13. Mục đánh dấu ⏳ (PR #14, PR #15, nhánh `deploy-config`) là quy tắc
> chưa có trên `main`; khi merge, bỏ dấu ⏳.

---

## 1. Cơ sở, sân, giờ mở cửa

| Mã | Quy tắc | Nguồn |
|---|---|---|
| CS-01 | Web phục vụ **một cơ sở** (`Venue.main`); múi giờ `Asia/Ho_Chi_Minh`. | `app/models/venue.rb` |
| CS-02 | **10 sân**, lưu tên là số (`1`…`10`), hiển thị "Sân N" / "Court N" theo ngôn ngữ; sân đặt tên khác (vd "VIP") hiển thị nguyên tên. Sân `inactive` không đặt được. | `app/models/court.rb`, `test/models/court_test.rb` |
| CS-03 | **Giờ mở cửa theo từng ngày trong tuần** (mặc định 05:00–22:00 mọi ngày); ngày không có giờ mở cửa = ngày nghỉ. Đổi giờ mở cửa **không ảnh hưởng** lượt đã đặt. ⚙️ | `app/models/admin/venue_settings.rb`, `test/integration/admin_test.rb` |
| CS-04 | Thời gian chia theo **khung 30 phút**; mọi giờ bắt đầu/kết thúc phải tròn :00 hoặc :30 (kiểm tra cả ở database). | `app/models/booking.rb` (`time_range_on_slot_grid`), ràng buộc `bookings_aligned_to_slot` |

## 2. Giá

| Mã | Quy tắc | Nguồn |
|---|---|---|
| GIA-01 | Giá tính **từng khung 30 phút** = giá/giờ của khung giá phù hợp ÷ 2; tổng lượt đặt = cộng các khung. Giá/giờ là bội số 1.000đ. | `app/services/pricing/quote.rb`, `test/services/pricing/quote_test.rb` |
| GIA-02 | Nhiều khung giá cùng khớp: **khung giá riêng của sân** thắng khung giá chung → **độ ưu tiên cao hơn** → **khung tạo sau**. | `app/services/pricing/rule_set.rb` |
| GIA-03 | Khung giá có thể giới hạn **ngày trong tuần**, **khoảng ngày** (từ/đến) và **tạm ngừng**. Khung nào không có giá thì **không đặt được**. | `app/models/price_rule.rb` |
| GIA-04 | Mỗi lượt đặt **giữ nguyên giá lúc đặt** (lưu `total_amount_vnd` và chi tiết từng đoạn); đổi bảng giá không đổi giá lượt cũ. Giá chỉ tính lại khi **đổi giờ/sân** (DOI-04). | `app/models/booking.rb` (`apply_price`) |
| GIA-05 | Khung giá có **tên tiếng Anh** tuỳ chọn, hiện trên trang tiếng Anh. Bảng giá công khai chỉ hiện các khung giá chung, đang áp dụng. | `app/models/price_rule.rb` (`display_name`) |
| GIA-06 | Thanh toán **tại sân** (chưa có thanh toán online). | — |

## 3. Tài khoản

| Mã | Quy tắc | Nguồn |
|---|---|---|
| TK-01 | Đăng ký: họ tên, **số điện thoại** (bắt buộc với khách, chuẩn hoá về `+84xxxxxxxxx`, không trùng), email, mật khẩu ≥ 8 ký tự, **tick đồng ý chính sách bảo mật** (lưu thời điểm đồng ý). | `app/models/user.rb`, `test/integration/authentication_test.rb` |
| TK-02 | Đăng nhập bằng **email hoặc số điện thoại** (mọi cách viết số: `0901 234 567`, `84901…`, `+84901…`). Báo lỗi chung, không lộ tài khoản có tồn tại hay không. | `app/models/user.rb` (`find_for_database_authentication`) |
| TK-03 | **Xác minh email**: chưa xác minh vẫn đăng nhập và xem lịch được, nhưng **không đặt sân được**; có thanh nhắc + nút gửi lại. Link có hạn **3 ngày**. Đổi email phải xác minh địa chỉ mới (email cũ dùng tới lúc đó). | `config/initializers/devise.rb`, `test/integration/email_verification_test.rb` |
| TK-04 | **Ngôn ngữ email** theo ngôn ngữ khách dùng lúc đăng ký, cập nhật mỗi lần khách tự đặt/huỷ. | `app/models/user.rb` (`remember_locale`) |
| TK-05 | **Vai trò**: `customer` (khách), `staff` (nhân viên), `admin` (chủ sân). Xem mục 9. | `app/models/user.rb` |
| TK-06 | ⏳ PR #14 – **Tự đăng xuất sau 30 phút không thao tác**, áp dụng cho mọi vai trò; **không còn "Ghi nhớ đăng nhập"**. Lịch tự cập nhật không tính là thao tác; trang tự chuyển về đăng nhập khi hết phiên. | `config/initializers/devise.rb` (`timeout_in`), `test/integration/session_timeout_test.rb` |

## 4. Đặt sân online (khách)

| Mã | Quy tắc | Nguồn |
|---|---|---|
| DAT-01 | Xem lịch **không cần đăng nhập**; đặt sân cần đăng nhập + email đã xác minh. | `app/controllers/bookings_controller.rb` |
| DAT-02 | Chỉ đặt được **từ hôm nay đến 14 ngày tới** ⚙️, ngày sân mở cửa. Lịch hôm nay **ẩn các khung đã bắt đầu**; hết giờ hôm nay thì mặc định mở ngày mai. | `app/services/schedule/calendar.rb`, `app/services/schedule/day.rb`, `test/integration/booking_flow_test.rb` |
| DAT-03 | Mỗi lượt **60–240 phút** ⚙️ (tối thiểu/tối đa), liên tục trên **một sân**; đặt **nhiều sân cùng lúc** được (mỗi sân một khoảng giờ riêng), tạo **tất cả hoặc không** sân nào. | `app/models/booking.rb` (`within_customer_policy`), `app/models/booking_batch.rb` |
| DAT-04 | Mỗi tài khoản giữ **tối đa 2 lượt sắp tới** ⚙️ (chưa chơi xong, chưa huỷ). Buổi của lịch cố định không tính (⏳ PR #15). | `app/models/booking_batch.rb`, `test/integration/booking_limits_test.rb` |
| DAT-05 | **Giữ chỗ 3 phút**: mở trang xác nhận là giữ các khung đã chọn; người khác thấy "Đang giữ" và không chọn được. Tải lại trang **không gia hạn**. Chọn giờ khác / bấm "Chọn giờ khác" là nhả ngay. Quá 3 phút vẫn xác nhận được **nếu chưa ai lấy**. Mỗi khách giữ một lựa chọn tại một thời điểm. | `app/models/booking_batch.rb` (`hold`), `test/integration/booking_hold_test.rb` |
| DAT-06 | Mở trang xác nhận tối đa **30 lần / 10 phút** mỗi tài khoản (chống giữ chỗ hàng loạt). | `app/controllers/bookings_controller.rb` |
| DAT-07 | Lượt đặt online: trạng thái **Đã xác nhận**, **Chưa thanh toán**; gửi **email xác nhận** (một email cho nhiều sân). Mã đặt sân 8 ký tự, bỏ các ký tự dễ nhầm (O/0, I/1). | `app/controllers/bookings_controller.rb`, `app/mailers/booking_mailer.rb` |
| DAT-08 | **Khách trong danh sách đen** hoặc **đang bị khoá** (HUY-03) không đặt online được. | `app/models/booking_batch.rb` |
| DAT-09 | **Hai người đặt cùng khung cùng lúc**: chỉ một người được; người kia thấy "Khung giờ này đã có người đặt". Đảm bảo bởi khoá theo sân + ràng buộc chống trùng trong database (không bao giờ có hai lượt chồng giờ trên một sân, kể cả giữ chỗ). | `Booking.lock_courts!`, ràng buộc `bookings_no_overlap`, `test/models/booking_concurrency_test.rb` |

## 5. Huỷ

| Mã | Quy tắc | Nguồn |
|---|---|---|
| HUY-01 | Khách tự huỷ online tới **2 giờ trước giờ chơi** ⚙️; sau đó phải gọi sân. Chủ sân/nhân viên huỷ được **bất cứ lúc nào**. | `app/models/booking.rb` (`cancellable_by_customer?`, `cancel!`) |
| HUY-02 | Huỷ → giờ đó trống lại ngay; khách có tài khoản nhận **email huỷ** (khách tự huỷ: xác nhận; sân huỷ: xin lỗi + số điện thoại sân). Khoá sân thì không gửi email. | `app/mailers/booking_mailer.rb`, `test/mailers/booking_mailer_test.rb` |
| HUY-03 | Khách **tự huỷ lần thứ 3 trong cùng một ngày** ⚙️ → **khoá đặt online 7 ngày** ⚙️. Có cảnh báo trước lần huỷ đó; chủ sân huỷ không tính; chủ sân/nhân viên **mở khoá sớm** được. Buổi lịch cố định không tính (⏳ PR #15). | `app/models/user.rb` (`lock_booking_if_cancelling_too_often`), `test/integration/booking_limits_test.rb` |

## 6. Đổi giờ

| Mã | Quy tắc | Nguồn |
|---|---|---|
| DOI-01 | **Khách** đổi giờ/sân lượt của mình nếu: còn trước hạn huỷ, **chưa thanh toán**, không trong danh sách đen; khung mới theo quy định online (DAT-02/03). Không áp dụng cho buổi lịch cố định (⏳ PR #15). | `app/models/booking.rb` (`reschedulable_by_customer?`), `test/integration/reschedule_test.rb` |
| DOI-02 | Khách đổi trên lịch ở **chế độ đổi giờ** (giờ cũ chọn lại được, một sân), xem **giờ cũ / giờ mới / giá mới** rồi xác nhận. | `app/controllers/schedules_controller.rb`, `app/views/bookings/review_reschedule.html.slim` |
| DOI-03 | **Chủ sân/nhân viên** đổi mọi lượt đặt hoặc khoá sân, **không** theo quy định online nhưng **vẫn** theo giờ mở cửa (với lượt đặt). | `app/controllers/admin/bookings_controller.rb` (`reschedule`) |
| DOI-04 | Đổi giờ: **tính lại giá**, **gửi lại nhắc lịch** theo giờ mới, gửi **email đổi giờ** (giờ cũ → giờ mới) cho khách có tài khoản. | `app/models/booking.rb` (`reschedule`) |

## 7. Email tự động

| Mã | Email | Khi nào | Người nhận |
|---|---|---|---|
| EM-01 | Xác minh email | Đăng ký / đổi email | Chủ tài khoản |
| EM-02 | Xác nhận đặt sân | Khách đặt online; chủ sân đặt hộ cho số điện thoại có tài khoản | Khách có tài khoản |
| EM-03 | Huỷ | Khách tự huỷ hoặc sân huỷ (HUY-02) | Khách có tài khoản |
| EM-04 | **Nhắc lịch** | **3 giờ trước giờ chơi**, mỗi lượt một lần; bỏ qua lượt đặt sát giờ (< 3 giờ trước) | Khách có tài khoản, lượt đã xác nhận |
| EM-05 | Đổi giờ | DOI-04 | Khách có tài khoản |
| EM-06 | Đặt lại mật khẩu | Khách yêu cầu | Chủ tài khoản |

Chủ sân **không** nhận email (xem trên Lịch trong ngày). Nguồn: `app/mailers/`, `app/jobs/booking_reminder_job.rb`, `test/jobs/booking_reminder_job_test.rb`.

## 8. Vận hành của chủ sân / nhân viên

| Mã | Quy tắc | Nguồn |
|---|---|---|
| VH-01 | **Lịch trong ngày**: mọi sân, mọi ngày (kể cả đã qua), thẻ theo trạng thái; bấm ô trống để đặt hộ. | `app/services/schedule/board.rb` |
| VH-02 | **Đặt hộ** (qua điện thoại / khách đến trực tiếp): không theo quy định online, vẫn theo giờ mở cửa; số điện thoại trùng tài khoản → lượt đặt gắn vào tài khoản đó. | `app/models/admin/booking_form.rb` |
| VH-03 | **Khoá sân** (bảo trì, sự kiện): bất kỳ giờ nào, không giá, không khách; gỡ khoá bất cứ lúc nào. | `app/models/admin/booking_form.rb` |
| VH-04 | Thao tác: **Nhận sân**, **Không đến**, **Đã thu tiền**, **Huỷ**; và **hoàn tác** từng thao tác (Huỷ nhận sân / Huỷ "không đến" / Huỷ "đã thu"). | `app/controllers/admin/bookings_controller.rb`, `test/integration/admin_test.rb` |
| VH-05 | Hai người cùng thao tác một lượt đặt (vd nhận sân lúc khách huỷ): người sau thấy "Lượt đặt vừa được cập nhật ở nơi khác", không lỗi. | `lock_version`, `test/integration/admin_test.rb` |
| VH-06 | **Khách hàng**: định danh theo **số điện thoại** (có hoặc không tài khoản); lịch sử, thống kê, **ghi chú riêng**, **danh sách đen** (chặn đặt online; vẫn đặt hộ được, kèm cảnh báo). | `app/services/customers/directory.rb`, `test/integration/customers_test.rb` |
| VH-07 | **Báo cáo tháng** (chỉ chủ sân): doanh thu dự kiến (lượt không huỷ), đã thu (đã thanh toán), số lượt, **tỷ lệ lấp đầy** = giờ sân đã đặt / giờ sân mở cửa, theo ngày và theo khung giờ; **xuất CSV**. | `app/services/reports/month.rb`, `test/integration/reports_test.rb` |
| VH-08 | **Lịch tự cập nhật** (trang Đặt sân và Lịch trong ngày) khi có giữ chỗ/đặt/huỷ/đổi; giữ nguyên ô khách đang chọn. | `app/services/schedule/live.rb`, `test/integration/live_schedule_test.rb` |

## 9. Phân quyền

| Việc | Khách | Nhân viên | Chủ sân |
|---|---|---|---|
| Đặt/huỷ/đổi lượt của mình online | ✓ | ✓ | ✓ |
| Lịch trong ngày, đặt hộ, khoá sân, nhận sân, thu tiền, huỷ, hoàn tác, đổi giờ | | ✓ | ✓ |
| Khách hàng (ghi chú, danh sách đen, mở khoá) | | ✓ (không thấy doanh thu) | ✓ |
| Lịch cố định (⏳ PR #15) | | ✓ | ✓ |
| Báo cáo, bảng giá, cài đặt, quản lý nhân viên | | | ✓ |

Cấp quyền nhân viên: nhân viên **tự đăng ký** tài khoản, chủ sân nhập email/số điện thoại của họ ở trang Nhân viên. Nguồn: `app/models/user.rb` (`manager?`, `owner?`), `test/integration/staff_test.rb`.

## 10. Lịch cố định hằng tuần (⏳ PR #15)

| Mã | Quy tắc | Nguồn |
|---|---|---|
| CD-01 | **Chỉ chủ sân/nhân viên** tạo: khách, một hoặc nhiều sân, các ngày trong tuần, khung giờ, từ ngày–đến ngày (tối đa 1 năm), **giá riêng mỗi giờ** tuỳ chọn (trống = bảng giá). | `app/models/booking_series.rb` |
| CD-02 | **Xem trước từng buổi**; buổi trùng người khác / ngày nghỉ / ngoài giờ mở cửa **bị bỏ qua**, chỉ tạo buổi hợp lệ. Mỗi buổi là một lượt đặt bình thường. | `app/services/series/planner.rb` |
| CD-03 | **Đóng tiền đầu tháng dương lịch**: cần thu = tiền các buổi trong tháng − tiền hoàn của các tháng trước. Bấm "Đã thu" → các buổi trong tháng thành "Đã thanh toán". Buổi bị huỷ **trước** khi đóng tiền thì không tính vào hoá đơn. | `app/services/series/billing.rb` |
| CD-04 | **Báo nghỉ một buổi** (khách trên web trước hạn huỷ, hoặc nhân viên): giờ đó mở cho người khác; không tính vào HUY-03 và DAT-04. | `app/models/booking.rb` (`cancel!`) |
| CD-05 | **Hoàn tiền buổi báo nghỉ**, xét **sau khi giờ chơi kết thúc**: hoàn **theo tỷ lệ phần giờ có người khác đặt và đã chơi** (không huỷ, không "không đến"); không ai đặt → sân giữ tiền; tháng chưa đóng tiền → không hoàn (vì không tính). | `app/services/series/refunds.rb` |
| CD-06 | **Sân nghỉ** (lễ, sửa chữa): huỷ các buổi trong khoảng ngày, **hoàn đủ** (với tháng đã đóng). **Kết thúc lịch** từ một ngày: huỷ các buổi còn lại, **không hoàn**. | `app/controllers/admin/series_controller.rb` |
| CD-07 | Tiền hoàn **trừ vào tháng kế tiếp chưa đóng**, cũ trước, **mỗi khoản một lần**. | `app/services/series/billing.rb` |
| CD-08 | **Gia hạn** tới ngày mới (kiểm tra như CD-02). **Đổi giá riêng**: chỉ tính lại các buổi **chưa chơi thuộc tháng chưa đóng**. Đổi giờ cả lịch = kết thúc lịch cũ + tạo lịch mới. Khách không tự đổi giờ buổi cố định (nhân viên đổi hộ). | `test/integration/booking_series_test.rb` |

## 11. Bảo mật, quyền riêng tư, chống lạm dụng

| Mã | Quy tắc | Nguồn |
|---|---|---|
| BM-01 | Giới hạn: đăng nhập **10 lần/3 phút** mỗi IP và **5 lần/15 phút** mỗi email/số điện thoại; đăng ký **5/giờ** mỗi IP; quên mật khẩu và gửi lại email xác minh **5/giờ** mỗi IP và **3/giờ** mỗi email. Vượt giới hạn: quay lại form kèm thông báo. | `app/controllers/users/`, `test/integration/rate_limit_test.rb` |
| BM-02 | **Chính sách bảo mật** (bản nháp, cần chủ sân/luật sư duyệt) tại `/privacy`; đồng ý bắt buộc khi đăng ký. | `app/views/pages/privacy.*.html.slim` |
| BM-03 | Log **ẩn** mật khẩu, email, token. ⏳ nhánh `deploy-config`: ẩn thêm **số điện thoại** và ô đăng nhập. | `config/initializers/filter_parameter_logging.rb` |
| BM-04 | Bí mật **không bao giờ** nằm trong repo (repo công khai): `.kamal/secrets` chỉ đọc từ file/biến (có test kiểm tra); GitHub secret scanning + push protection bật. | `test/security/deploy_secrets_test.rb` (nhánh `deploy-config`) |
| BM-05 | Trang lỗi 400/404/422/500 theo giao diện web, **tiếng Việt**, tiếng Anh khi đường dẫn bắt đầu bằng `/en`. | `public/*.html` |

## 12. Việc định kỳ (job nền)

| Job | Lịch | Việc |
|---|---|---|
| `BookingReminderJob` | 10 phút/lần | Gửi nhắc lịch (EM-04) |
| `HoldExpiryJob` | đúng lúc giữ chỗ hết hạn | Nhả chỗ giữ, cập nhật lịch đang mở |
| `Booking.release_expired_holds!` | 15 phút/lần | Dọn giữ chỗ hết hạn còn sót |
| `SeriesRefundJob` (⏳ PR #15) | 15 phút/lần | Xét hoàn tiền buổi lịch cố định (CD-05) |
| Dọn job đã xong | mỗi giờ (production) | Solid Queue |

Nguồn: `config/recurring.yml`.

---

## Chưa làm / đã hoãn

- **OTP điện thoại**: hoãn tới khi mở cho khách thật (dự kiến Firebase – 10 SMS/ngày miễn phí, sau đó Zalo ZNS).
- **Thanh toán online** (VietQR…), **thông báo qua Zalo**.
- **Đổi giờ cả lịch cố định** trong một thao tác.
- Chủ sân **không nhận email** thông báo (quyết định của chủ sân).
