# API của app khách (`/api/v1`)

Dành cho app Flutter (Android). **Chỉ chức năng của khách**: mọi thao tác quản lý ở trên web (AP-01).
Quy tắc nghiệp vụ: `docs/business-rules.md`. Test: `test/integration/api/v1_test.rb`.

## Chung

- JSON vào/ra. Thời gian ISO 8601 có múi giờ của sân (`2026-10-20T18:00:00+07:00`), tiền là số nguyên VND.
- Đăng nhập: header `Authorization: Bearer <token>`. Ngôn ngữ thông báo: `Accept-Language: vi` (mặc định) hoặc `en`.
- Lỗi: mã HTTP + `{ "error": "<mã>", "messages": ["câu cho người dùng", ...] }`.
  Mã: `unauthorized` (401, đăng nhập lại), `invalid_login`, `account_deleted`, `wrong_password`, `email_unverified` (403),
  `not_bookable`, `invalid`, `payments_unavailable`, `not_allowed` (422), `changed_meanwhile` (409), `not_found` (404),
  `rate_limited` (429).

## Tài khoản

| Gọi | Vào | Ra |
|---|---|---|
| `POST /api/v1/session` | `login` (email hoặc SĐT), `password`, `device_name` | 201 `{ token, user }` |
| `DELETE /api/v1/session` | | 204 |
| `POST /api/v1/registration` | `full_name`, `phone`, `email`, `password`, `privacy_consent: true`, `locale`, `device_name` | 201 `{ token, user }` (email xác minh được gửi) |
| `GET /api/v1/account` | | `{ user, can_delete, loyalty, bookings_to_play: [booking], deleted_after }` |
| `PATCH /api/v1/account` | `full_name`, `phone`, `locale`, `birth_year`, `gender` (`male`/`female`/`other`), `skill_level` (`beginner`/`intermediate`/`advanced`/`expert`) | `{ user }` |
| `POST /api/v1/account/resend_verification` | | 204 |
| `PUT /api/v1/account/avatar` | `avatar` (multipart; JPG/PNG/WebP ≤ 2 MB) | `{ user }` |
| `DELETE /api/v1/account/avatar` | | `{ user }` |
| `POST /api/v1/account/export` | `password` | dữ liệu cá nhân (như file JSON trên web) |
| `DELETE /api/v1/account` | `password` | `{ deleted_after }` (null: đã xoá ngay); token bị huỷ |

`loyalty` (UD-01): `{ tier (bronze/silver/gold/diamond), name, percent, hours, enabled, next: { tier, name, hours } | null, tiers: [{ tier, name, hours, percent }] }`.

`user`: `{ id, full_name, email, phone, locale, email_verified, booking_locked_until, birth_year, gender, skill_level, avatar_path }`.
`avatar_path` là đường dẫn trên máy chủ (ghép với địa chỉ máy chủ), `null` khi chưa có ảnh. Hồ sơ không bắt buộc (TK-10).

## Sân và lịch (không cần đăng nhập)

- `GET /api/v1/venue`: `{ name, address, phone, contact_links: { zalo, messenger, phone }, payments_enabled, courts: [{ id, name }], products: [{ id, name, price_vnd }], policy: { min_booking_minutes, max_booking_minutes, booking_horizon_days, cancellation_cutoff_hours, max_upcoming_bookings, slot_minutes }, prices: [{ name, days_of_week, start_minute, end_minute, price_per_hour_vnd }] }`
- `GET /api/v1/schedule?date=YYYY-MM-DD`: `{ date, dates: [ngày chọn được], courts, times: [giờ bắt đầu các ô], slots: { "<court_id>": [{ starts_at, state, price_vnd }] } }`.
  `state`: `available`, `booked`, `held`, `mine` (khi đã đăng nhập), `blocked`, `unavailable`. Ô 30 phút; ngày không hợp lệ → ngày đầu tiên chọn được.
  `&reschedule=<code>`: chế độ đổi giờ, các ô của lượt đó hiện `available` (DOI-05).
- `GET /api/v1/announcements`: `{ announcements: [{ id, title, body, tone (info/offer/warning), starts_on, ends_on }] }` đang hiện hôm nay (TI-02).

## Đặt sân

`slots`: `[{ court_id, starts_at, ends_at }]`, mỗi sân một khoảng giờ liền.

| Gọi | Vào | Ra |
|---|---|---|
| `POST /api/v1/hold` | `slots` | 201 `{ held_until, amount_vnd, bookings: [booking] }`: giữ chỗ 3 phút (bước xác nhận) |
| `DELETE /api/v1/hold` | | 204 (chọn giờ khác) |
| `POST /api/v1/quote` | `slots`, `items`, `voucher_code`, `package_purchase_id` | `{ court_vnd, items_vnd, discount_vnd, total_vnd, offer: { kind (tier/voucher/package), label } \| null, messages }`, không lưu (UD-03) |
| `POST /api/v1/bookings` | `slots`, `note`, `items: [{ product_id, quantity }]` (tuỳ chọn, TI-01), `voucher_code` (UD-02) | 201 `payment`: giữ 15 phút chờ chuyển khoản |
| `POST /api/v1/bookings` | `slots`, `note`, `package_purchase_id` (UD-05) | 201 `{ bookings: [booking] }`: đã xác nhận và trả bằng gói |
| `GET /api/v1/payments/:token` | | `payment` (app hỏi lại vài giây một lần khi đang ở màn chuyển khoản) |
| `GET /api/v1/bookings` | | `{ upcoming: [booking], past: [booking], awaiting_payments: [payment] }` |
| `GET /api/v1/bookings/:code` | | `booking` |
| `PATCH /api/v1/bookings/:code/cancel` | | `booking` |
| `GET /api/v1/bookings/:code/reschedule` | `court_id`, `starts_at`, `ends_at` | `{ booking (giờ và giá mới), valid, messages }`, không lưu |
| `PATCH /api/v1/bookings/:code/reschedule` | `court_id`, `starts_at`, `ends_at` | `booking` (DOI-05) |
| `POST /api/v1/bookings/:code/review` | `rating` (1–5), `comment` | 201 `booking` (TI-03) |

`booking`: `{ code, court: { id, name }, starts_at, ends_at, status, payment_status, discount_vnd, paid_with_package, amount_vnd (tiền sân), items_amount_vnd, total_vnd (sân + đồ), items: [{ name, quantity, unit_price_vnd }], note, held_until, cancellation_reason, refund_vnd, series, can_cancel, can_reschedule, cancel_without_refund, payment_token, can_review, review: { rating, comment, created_at } }`.

`payment`: `{ token, code, purpose (bookings/series_period/package/tickets), status (awaiting/paid/expired/cancelled), open, amount_vnd, discount_vnd, offer (tier/voucher), received_vnd, remaining_vnd, expires_at, paid_at, bank: { code, account_number, account_name }, qr_image_url, bookings: [booking] }`.
Nội dung chuyển khoản phải là `code`; số tiền là `remaining_vnd` (chuyển thiếu thì chuyển thêm cùng nội dung).

## Báo khi có sân trống (TI-04)

| Gọi | Vào | Ra |
|---|---|---|
| `GET /api/v1/waitlist` | | `{ entries: [{ id, starts_at, ends_at, notified_at }] }` (đang chờ) |
| `POST /api/v1/waitlist` | `starts_at`, `ends_at` | 201 entry |
| `DELETE /api/v1/waitlist/:id` | | 204 |

## Lịch cố định (CD-09, CD-10)

| Gọi | Vào | Ra |
|---|---|---|
| `GET /api/v1/series_requests` | | `{ requests: [request] }` |
| `POST /api/v1/series_requests` | `court_ids: []`, `days_of_week: []` (0 = CN), `start_minute`, `end_minute`, `starts_on`, `ends_on`, `note` | 201 request |
| `DELETE /api/v1/series_requests/:id` | | request (`cancelled`), chỉ khi còn `pending` |
| `GET /api/v1/series` | | `{ series: [{ id, courts, days_of_week, start_minute, end_minute, starts_on, ends_on, price_per_hour_vnd, months: [{ month (YYYY-MM), sessions, amount_vnd, credit_vnd, due_vnd, paid, payment_token }] }] }` |
| `POST /api/v1/series/:id/pay` | `month` (YYYY-MM) | `payment` cho số cần đóng |

`request`: `{ id, court_ids, courts, days_of_week, start_minute, end_minute, starts_on, ends_on, note, status (pending/approved/declined/cancelled), decline_reason, series_id, created_at }`.

## Gói giờ (UD-04, UD-05)

| Gọi | Vào | Ra |
|---|---|---|
| `GET /api/v1/packages` | | `{ packages: [{ id, name, minutes, price_vnd, valid_days, start_minute, end_minute }], purchases: [{ id, name, status (awaiting/active), minutes_total, minutes_left, expires_at, start_minute, end_minute, payment_token }] }` |
| `POST /api/v1/packages/:id/buy` | | 201 `payment` (purpose `package`) |

