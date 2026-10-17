# Court Booking: schema and models (MVP)

Requirements: Rails 8.1 (7.1 at minimum) and PostgreSQL 13 or later.

## Setup

1. Create the app: `rails new court_booking -d postgresql`
2. Copy `db/migrate`, `app/models`, `app/services` and `config/initializers` into the project.
3. In `config/application.rb`:
   ```ruby
   config.time_zone = "Asia/Ho_Chi_Minh"
   ```
4. Run `bin/rails db:create db:migrate`.
5. Devise is installed and enabled in `app/models/user.rb`.
   Do not run Devise's migration generator; the users table already has the required columns.

## Testing

Model tests:

```bash
bin/rails test
```

DB constraint tests, against the schema the migrations actually produce (runs in a transaction that is rolled back):

```bash
bin/rails db:test:prepare
psql -v ON_ERROR_STOP=1 -d vn_badminton_test -f test/db/constraint_tests.sql
```

`test/db/schema_equivalent.sql` is a hand-written copy of the schema for running the same tests without Rails.
It must be kept in sync with the migrations by hand, so prefer the command above.

## Key conventions

| Convention | Reason |
|---|---|
| Fixed 30-minute slot grid; times stored as timestamptz (UTC) | The DB rejects off-grid times; no time zone drift |
| Opening hours and price windows stored as minutes since midnight (`330` = 05:30) | Avoids Rails `time` column pitfalls; can represent 24:00 |
| VND amounts stored as `bigint` | No floating-point rounding errors |
| Maintenance and holidays are bookings with `kind = 'block'` | They share the exclusion constraint, so nobody can book during maintenance |
| Bookings store a price snapshot (`total_amount_vnd`, `price_breakdown`) | Changing prices does not affect existing bookings |
| Simple authorization through `users.role` (`admin` is the venue owner) | Enough for a single venue; add `staff` when needed |
| Courts and venues are never deleted, only set to `inactive` | Keeps booking history intact |

## Creating a booking

```ruby
booking = court.bookings.new(user: current_user, starts_at:, ends_at:, source: :online)
if booking.reserve        # always use reserve, not save
  # success
else
  booking.errors.full_messages
end
```

`reserve` rescues `ActiveRecord::ExclusionViolation`. That error occurs when two people book at the same moment and both pass validation, so it must be turned into a friendly message.

## User-facing messages

The app supports Vietnamese (default) and English. Validation messages use i18n keys (`errors.add(:base, :slot_taken)`),
translated in `config/locales/vi.yml` and `config/locales/en.yml`; Devise messages are in `devise.vi.yml` / `devise.en.yml`.
Rails' built-in messages and date formats come from the `rails-i18n` gem.

When adding a key, add it to both files: `test/i18n/locale_files_test.rb` fails if the two files drift apart,
and missing translations raise in development and test.

## Current limitations

- Venues open past midnight (for example 05:00 to 02:00 the next day) are not supported.
- `pending` bookings (for online payments later) need a periodic job that cancels bookings past their `expires_at`.
