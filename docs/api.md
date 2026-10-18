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
| `GET /api/v1/account` | | `{ user, can_delete, bookings_to_play: [booking], deleted_after }` |
| `PATCH /api/v1/account` | `full_name`, `phone`, `locale` | `{ user }` |
| `POST /api/v1/account/resend_verification` | | 204 |
| `POST /api/v1/account/export` | `password` | dữ liệu cá nhân (như file JSON trên web) |
| `DELETE /api/v1/account` | `password` | `{ deleted_after }` (null: đã xoá ngay); token bị huỷ |

`user`: `{ id, full_name, email, phone, locale, email_verified, booking_locked_until }`.

## Sân và lịch (không cần đăng nhập)

- `GET /api/v1/venue`: `{ name, address, phone, contact_links: { zalo, messenger, phone }, payments_enabled, courts: [{ id, name }], policy: { min_booking_minutes, max_booking_minutes, booking_horizon_days, cancellation_cutoff_hours, max_upcoming_bookings, slot_minutes }, prices: [{ name, days_of_week, start_minute, end_minute, price_per_hour_vnd }] }`
- `GET /api/v1/schedule?date=YYYY-MM-DD`: `{ date, dates: [ngày chọn được], courts, times: [giờ bắt đầu các ô], slots: { "<court_id>": [{ starts_at, state, price_vnd }] } }`.
  `state`: `available`, `booked`, `held`, `mine` (khi đã đăng nhập), `blocked`, `unavailable`. Ô 30 phút; ngày không hợp lệ → ngày đầu tiên chọn được.

## Đặt sân

`slots`: `[{ court_id, starts_at, ends_at }]`, mỗi sân một khoảng giờ liền.

| Gọi | Vào | Ra |
|---|---|---|
| `POST /api/v1/hold` | `slots` | 201 `{ held_until, amount_vnd, bookings: [booking] }`: giữ chỗ 3 phút (bước xác nhận) |
| `DELETE /api/v1/hold` | | 204 (chọn giờ khác) |
| `POST /api/v1/bookings` | `slots`, `note` | 201 `payment`: giữ 15 phút chờ chuyển khoản |
| `GET /api/v1/payments/:token` | | `payment` (app hỏi lại vài giây một lần khi đang ở màn chuyển khoản) |
| `GET /api/v1/bookings` | | `{ upcoming: [booking], past: [booking], awaiting_payments: [payment] }` |
| `GET /api/v1/bookings/:code` | | `booking` |
| `PATCH /api/v1/bookings/:code/cancel` | | `booking` |

`booking`: `{ code, court: { id, name }, starts_at, ends_at, status, payment_status, amount_vnd, note, held_until, cancellation_reason, refund_vnd, series, can_cancel, cancel_without_refund, payment_token }`.

`payment`: `{ token, code, status (awaiting/paid/expired/cancelled), open, amount_vnd, received_vnd, remaining_vnd, expires_at, paid_at, bank: { code, account_number, account_name }, qr_image_url, bookings: [booking] }`.
Nội dung chuyển khoản phải là `code`; số tiền là `remaining_vnd` (chuyển thiếu thì chuyển thêm cùng nội dung).
