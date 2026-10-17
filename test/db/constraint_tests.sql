-- DB constraint tests. Run against a database migrated by Rails (e.g. the test database):
--   bin/rails db:test:prepare
--   psql -v ON_ERROR_STOP=1 -d vn_badminton_test -f test/db/constraint_tests.sql
-- Everything runs inside one transaction that is rolled back at the end, so no data is left behind.
BEGIN;
SET LOCAL client_min_messages = notice;
SET LOCAL TIME ZONE 'Asia/Ho_Chi_Minh';

-- Rails sets timestamps in Ruby, so the columns have no DB default; add one for these raw INSERTs.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['users', 'venues', 'opening_hours', 'courts', 'price_rules', 'bookings'] LOOP
    EXECUTE format('ALTER TABLE %I ALTER COLUMN created_at SET DEFAULT now(), ALTER COLUMN updated_at SET DEFAULT now()', t);
  END LOOP;
END $$;

-- Start from empty tables (e.g. the test database may still hold Rails fixtures); undone by the ROLLBACK.
TRUNCATE users, venues, opening_hours, courts, price_rules, bookings CASCADE;

CREATE TEMP TABLE results (label text, ok boolean, detail text);

-- The statement must be REJECTED by the expected constraint.
CREATE FUNCTION pg_temp.expect_fail(label text, stmt text, expected text) RETURNS void AS $$
DECLARE c text; m text;
BEGIN
  BEGIN
    EXECUTE stmt;
    INSERT INTO results VALUES (label, false, 'not rejected');
  EXCEPTION WHEN others THEN
    GET STACKED DIAGNOSTICS c = CONSTRAINT_NAME, m = MESSAGE_TEXT;
    INSERT INTO results VALUES (label, coalesce(c, '') = expected OR m ILIKE '%' || expected || '%', coalesce(c, m));
  END;
END $$ LANGUAGE plpgsql;

-- The statement must SUCCEED.
CREATE FUNCTION pg_temp.expect_ok(label text, stmt text) RETURNS void AS $$
DECLARE m text;
BEGIN
  BEGIN
    EXECUTE stmt;
    INSERT INTO results VALUES (label, true, 'ok');
  EXCEPTION WHEN others THEN
    GET STACKED DIAGNOSTICS m = MESSAGE_TEXT;
    INSERT INTO results VALUES (label, false, m);
  END;
END $$ LANGUAGE plpgsql;

-- ---------- Fixtures ----------
INSERT INTO users (id, email, full_name, phone) VALUES
  (1, 'an@example.com', 'Nguyễn An', '+84901234567'),
  (2, 'binh@example.com', 'Trần Bình', NULL);
INSERT INTO venues (id, name, slug, address) VALUES
  (1, 'Sân Cầu Lông Phú Nhuận', 'phu-nhuan', '12 Phan Xích Long'),
  (2, 'Sân Thủ Đức', 'thu-duc', '1 Võ Văn Ngân');
INSERT INTO courts (id, venue_id, name) VALUES (1, 1, 'Sân 1'), (2, 1, 'Sân 2'), (3, 2, 'Sân A');
SELECT setval('users_id_seq', 100), setval('venues_id_seq', 100), setval('courts_id_seq', 100);

-- ---------- users ----------
SELECT pg_temp.expect_fail('Duplicate email (different case)', $q$INSERT INTO users (email, full_name) VALUES ('AN@Example.com', 'X')$q$, 'index_users_on_email');
SELECT pg_temp.expect_fail('Malformed email', $q$INSERT INTO users (email, full_name) VALUES ('khong-co-a-cong', 'X')$q$, 'users_email_format');
SELECT pg_temp.expect_fail('Phone not normalized', $q$INSERT INTO users (email, full_name, phone) VALUES ('c@example.com', 'X', '0901234567')$q$, 'users_phone_format');
SELECT pg_temp.expect_fail('Duplicate phone', $q$INSERT INTO users (email, full_name, phone) VALUES ('d@example.com', 'X', '+84901234567')$q$, 'index_users_on_phone');
SELECT pg_temp.expect_fail('Unknown role', $q$INSERT INTO users (email, full_name, role) VALUES ('e@example.com', 'X', 'superuser')$q$, 'users_role_valid');
SELECT pg_temp.expect_fail('Blank name', $q$INSERT INTO users (email, full_name) VALUES ('f@example.com', '   ')$q$, 'users_full_name_length');
SELECT pg_temp.expect_ok  ('Several users without phone', $q$INSERT INTO users (email, full_name) VALUES ('g@example.com', 'G')$q$);

-- ---------- venues ----------
SELECT pg_temp.expect_fail('Slug with space', $q$INSERT INTO venues (name, slug, address) VALUES ('X', 'phu nhuan', 'Y')$q$, 'venues_slug_format');
SELECT pg_temp.expect_fail('Minimum duration of 45 minutes', $q$INSERT INTO venues (name, slug, address, min_booking_minutes) VALUES ('X', 'x1', 'Y', 45)$q$, 'venues_min_booking_minutes_valid');
SELECT pg_temp.expect_fail('Maximum < minimum', $q$INSERT INTO venues (name, slug, address, min_booking_minutes, max_booking_minutes) VALUES ('X', 'x2', 'Y', 120, 60)$q$, 'venues_max_booking_minutes_valid');

-- ---------- opening_hours ----------
SELECT pg_temp.expect_ok  ('Open 05:00-24:00 (Sunday)', $q$INSERT INTO opening_hours (venue_id, day_of_week, opens_minute, closes_minute) VALUES (1, 0, 300, 1440)$q$);
SELECT pg_temp.expect_fail('Duplicate day of week', $q$INSERT INTO opening_hours (venue_id, day_of_week, opens_minute, closes_minute) VALUES (1, 0, 360, 1320)$q$, 'index_opening_hours_on_venue_id_and_day_of_week');
SELECT pg_temp.expect_fail('Closes before opening', $q$INSERT INTO opening_hours (venue_id, day_of_week, opens_minute, closes_minute) VALUES (1, 1, 1320, 360)$q$, 'opening_hours_range_valid');
SELECT pg_temp.expect_fail('Off-grid time 05:15', $q$INSERT INTO opening_hours (venue_id, day_of_week, opens_minute, closes_minute) VALUES (1, 2, 315, 1320)$q$, 'opening_hours_aligned_to_slot');
SELECT pg_temp.expect_fail('Day 7 (outside 0-6)', $q$INSERT INTO opening_hours (venue_id, day_of_week, opens_minute, closes_minute) VALUES (1, 7, 300, 1320)$q$, 'opening_hours_day_valid');

-- ---------- courts ----------
SELECT pg_temp.expect_fail('Duplicate court name (different case)', $q$INSERT INTO courts (venue_id, name) VALUES (1, 'SÂN 1')$q$, 'index_courts_on_venue_id_and_lower_name');
SELECT pg_temp.expect_ok  ('Same court name at another venue', $q$INSERT INTO courts (venue_id, name) VALUES (2, 'Sân 1')$q$);

-- ---------- price_rules ----------
SELECT pg_temp.expect_ok  ('Venue-wide price', $q$INSERT INTO price_rules (venue_id, name, days_of_week, start_minute, end_minute, price_per_hour_vnd) VALUES (1, 'Giờ thường', '{0,1,2,3,4,5,6}', 300, 1440, 80000)$q$);
SELECT pg_temp.expect_ok  ('Court-specific price for court 1 of venue 1', $q$INSERT INTO price_rules (venue_id, court_id, name, days_of_week, start_minute, end_minute, price_per_hour_vnd, priority) VALUES (1, 1, 'Cao điểm sân 1', '{1,2,3,4,5}', 1020, 1260, 120000, 10)$q$);
SELECT pg_temp.expect_fail('Price for a court of ANOTHER venue', $q$INSERT INTO price_rules (venue_id, court_id, name, days_of_week, start_minute, end_minute, price_per_hour_vnd) VALUES (1, 3, 'Sai', '{1}', 300, 600, 80000)$q$, 'fk_price_rules_court_venue');
SELECT pg_temp.expect_fail('Day 9 of week', $q$INSERT INTO price_rules (venue_id, name, days_of_week, start_minute, end_minute, price_per_hour_vnd) VALUES (1, 'X', '{1,9}', 300, 600, 80000)$q$, 'price_rules_days_valid');
SELECT pg_temp.expect_fail('Empty days array', $q$INSERT INTO price_rules (venue_id, name, days_of_week, start_minute, end_minute, price_per_hour_vnd) VALUES (1, 'X', '{}', 300, 600, 80000)$q$, 'price_rules_days_valid');
SELECT pg_temp.expect_fail('Uneven price 80,500 VND', $q$INSERT INTO price_rules (venue_id, name, days_of_week, start_minute, end_minute, price_per_hour_vnd) VALUES (1, 'X', '{1}', 300, 600, 80500)$q$, 'price_rules_price_valid');
SELECT pg_temp.expect_fail('Negative price', $q$INSERT INTO price_rules (venue_id, name, days_of_week, start_minute, end_minute, price_per_hour_vnd) VALUES (1, 'X', '{1}', 300, 600, -1000)$q$, 'price_rules_price_valid');
SELECT pg_temp.expect_fail('Valid until before valid from', $q$INSERT INTO price_rules (venue_id, name, days_of_week, start_minute, end_minute, price_per_hour_vnd, valid_from, valid_until) VALUES (1, 'X', '{1}', 300, 600, 80000, '2026-12-01', '2026-11-01')$q$, 'price_rules_validity_range');

-- ---------- bookings: no double booking ----------
-- Base booking: court 1, 18:00-19:30 on 2026-10-20 (Vietnam time)
SELECT pg_temp.expect_ok('Base booking 18:00-19:30',
  $q$INSERT INTO bookings (court_id, user_id, code, starts_at, ends_at, customer_name, customer_phone, total_amount_vnd)
     VALUES (1, 1, 'AAAAAAA1', '2026-10-20 18:00+07', '2026-10-20 19:30+07', 'Nguyễn An', '+84901234567', 180000)$q$);
SELECT pg_temp.expect_fail('Exact overlap',
  $q$INSERT INTO bookings (court_id, user_id, code, starts_at, ends_at, customer_name, customer_phone)
     VALUES (1, 1, 'AAAAAAA2', '2026-10-20 18:00+07', '2026-10-20 19:30+07', 'B', '+84901234568')$q$, 'bookings_no_overlap');
SELECT pg_temp.expect_fail('Partial overlap 19:00-20:00',
  $q$INSERT INTO bookings (court_id, user_id, code, starts_at, ends_at, customer_name, customer_phone)
     VALUES (1, 1, 'AAAAAAA3', '2026-10-20 19:00+07', '2026-10-20 20:00+07', 'B', '+84901234568')$q$, 'bookings_no_overlap');
SELECT pg_temp.expect_fail('Contained 18:30-19:00',
  $q$INSERT INTO bookings (court_id, user_id, code, starts_at, ends_at, customer_name, customer_phone)
     VALUES (1, 1, 'AAAAAAA4', '2026-10-20 18:30+07', '2026-10-20 19:00+07', 'B', '+84901234568')$q$, 'bookings_no_overlap');
SELECT pg_temp.expect_fail('Enclosing 17:00-21:00',
  $q$INSERT INTO bookings (court_id, user_id, code, starts_at, ends_at, customer_name, customer_phone)
     VALUES (1, 1, 'AAAAAAA5', '2026-10-20 17:00+07', '2026-10-20 21:00+07', 'B', '+84901234568')$q$, 'bookings_no_overlap');
SELECT pg_temp.expect_fail('Overlap given in UTC (11:00Z = 18:00 Vietnam)',
  $q$INSERT INTO bookings (court_id, user_id, code, starts_at, ends_at, customer_name, customer_phone)
     VALUES (1, 1, 'AAAAAAA6', '2026-10-20 11:00Z', '2026-10-20 12:00Z', 'B', '+84901234568')$q$, 'bookings_no_overlap');
SELECT pg_temp.expect_ok('Back-to-back after 19:30-20:30',
  $q$INSERT INTO bookings (court_id, user_id, code, starts_at, ends_at, customer_name, customer_phone)
     VALUES (1, 1, 'BBBBBBB1', '2026-10-20 19:30+07', '2026-10-20 20:30+07', 'B', '+84901234568')$q$);
SELECT pg_temp.expect_ok('Back-to-back before 17:00-18:00',
  $q$INSERT INTO bookings (court_id, user_id, code, starts_at, ends_at, customer_name, customer_phone)
     VALUES (1, 1, 'BBBBBBB2', '2026-10-20 17:00+07', '2026-10-20 18:00+07', 'B', '+84901234568')$q$);
SELECT pg_temp.expect_ok('Same time, different court',
  $q$INSERT INTO bookings (court_id, user_id, code, starts_at, ends_at, customer_name, customer_phone)
     VALUES (2, 1, 'BBBBBBB3', '2026-10-20 18:00+07', '2026-10-20 19:30+07', 'B', '+84901234568')$q$);

-- Cancel the base booking -> the slot can be booked again
SELECT pg_temp.expect_fail('Cancel without cancelled_at',
  $q$UPDATE bookings SET status = 'cancelled' WHERE code = 'AAAAAAA1'$q$, 'bookings_cancelled_at_consistent');
SELECT pg_temp.expect_ok('Cancel base booking properly',
  $q$UPDATE bookings SET status = 'cancelled', cancelled_at = now(), cancelled_by_id = 1 WHERE code = 'AAAAAAA1'$q$);
SELECT pg_temp.expect_ok('Rebook the cancelled slot',
  $q$INSERT INTO bookings (court_id, user_id, code, starts_at, ends_at, customer_name, customer_phone)
     VALUES (1, 1, 'CCCCCCC1', '2026-10-20 18:00+07', '2026-10-20 19:30+07', 'C', '+84901234569')$q$);
SELECT pg_temp.expect_fail('Restore a cancelled booking whose slot was taken',
  $q$UPDATE bookings SET status = 'confirmed', cancelled_at = NULL WHERE code = 'AAAAAAA1'$q$, 'bookings_no_overlap');

-- ---------- bookings: maintenance blocks share the constraint ----------
SELECT pg_temp.expect_ok('Maintenance block on court 2, morning of 2026-10-21',
  $q$INSERT INTO bookings (court_id, kind, source, created_by_id, code, starts_at, ends_at)
     VALUES (2, 'block', 'staff', 2, 'MMMMMMM1', '2026-10-21 06:00+07', '2026-10-21 12:00+07')$q$);
SELECT pg_temp.expect_fail('Customer books during maintenance',
  $q$INSERT INTO bookings (court_id, user_id, code, starts_at, ends_at, customer_name, customer_phone)
     VALUES (2, 1, 'CCCCCCC2', '2026-10-21 08:00+07', '2026-10-21 09:00+07', 'C', '+84901234569')$q$, 'bookings_no_overlap');
SELECT pg_temp.expect_fail('Block with an amount',
  $q$INSERT INTO bookings (court_id, kind, source, code, starts_at, ends_at, total_amount_vnd)
     VALUES (1, 'block', 'staff', 'MMMMMMM2', '2026-10-22 06:00+07', '2026-10-22 07:00+07', 50000)$q$, 'bookings_kind_fields');

-- ---------- bookings: invalid data ----------
SELECT pg_temp.expect_fail('Off-grid time 18:15',
  $q$INSERT INTO bookings (court_id, user_id, code, starts_at, ends_at, customer_name, customer_phone)
     VALUES (1, 1, 'DDDDDDD1', '2026-10-23 18:15+07', '2026-10-23 19:15+07', 'D', '+84901234569')$q$, 'bookings_aligned_to_slot');
SELECT pg_temp.expect_fail('Off by seconds 18:00:05',
  $q$INSERT INTO bookings (court_id, user_id, code, starts_at, ends_at, customer_name, customer_phone)
     VALUES (1, 1, 'DDDDDDD2', '2026-10-23 18:00:05+07', '2026-10-23 19:00+07', 'D', '+84901234569')$q$, 'bookings_aligned_to_slot');
SELECT pg_temp.expect_fail('Ends before it starts',
  $q$INSERT INTO bookings (court_id, user_id, code, starts_at, ends_at, customer_name, customer_phone)
     VALUES (1, 1, 'DDDDDDD3', '2026-10-23 19:00+07', '2026-10-23 18:00+07', 'D', '+84901234569')$q$, 'bookings_ends_after_starts');
SELECT pg_temp.expect_fail('Two-day booking',
  $q$INSERT INTO bookings (court_id, user_id, code, starts_at, ends_at, customer_name, customer_phone)
     VALUES (1, 1, 'DDDDDDD4', '2026-10-23 06:00+07', '2026-10-25 06:00+07', 'D', '+84901234569')$q$, 'bookings_max_duration');
SELECT pg_temp.expect_fail('Reservation without customer name',
  $q$INSERT INTO bookings (court_id, source, code, starts_at, ends_at, customer_phone)
     VALUES (1, 'walk_in', 'DDDDDDD5', '2026-10-23 06:00+07', '2026-10-23 07:00+07', '+84901234569')$q$, 'bookings_kind_fields');
SELECT pg_temp.expect_fail('Online booking without an account',
  $q$INSERT INTO bookings (court_id, code, starts_at, ends_at, customer_name, customer_phone)
     VALUES (1, 'DDDDDDD6', '2026-10-23 06:00+07', '2026-10-23 07:00+07', 'D', '+84901234569')$q$, 'bookings_online_requires_user');
SELECT pg_temp.expect_ok('Phone booking by a walk-in customer (no account needed)',
  $q$INSERT INTO bookings (court_id, source, created_by_id, code, starts_at, ends_at, customer_name, customer_phone)
     VALUES (1, 'phone', 2, 'DDDDDDD7', '2026-10-23 06:00+07', '2026-10-23 07:00+07', 'Khách lẻ', '+84912345678')$q$);
SELECT pg_temp.expect_fail('Lowercase booking code',
  $q$INSERT INTO bookings (court_id, user_id, code, starts_at, ends_at, customer_name, customer_phone)
     VALUES (1, 1, 'abcdefgh', '2026-10-24 06:00+07', '2026-10-24 07:00+07', 'D', '+84901234569')$q$, 'bookings_code_format');
SELECT pg_temp.expect_fail('Duplicate booking code',
  $q$INSERT INTO bookings (court_id, user_id, code, starts_at, ends_at, customer_name, customer_phone)
     VALUES (1, 1, 'DDDDDDD7', '2026-10-24 06:00+07', '2026-10-24 07:00+07', 'D', '+84901234569')$q$, 'index_bookings_on_code');
SELECT pg_temp.expect_fail('Pending without expiry',
  $q$INSERT INTO bookings (court_id, user_id, code, status, starts_at, ends_at, customer_name, customer_phone)
     VALUES (1, 1, 'DDDDDDD8', 'pending', '2026-10-24 06:00+07', '2026-10-24 07:00+07', 'D', '+84901234569')$q$, 'bookings_pending_requires_expiry');
SELECT pg_temp.expect_fail('Mark paid without paid_at',
  $q$UPDATE bookings SET payment_status = 'paid' WHERE code = 'DDDDDDD7'$q$, 'bookings_paid_at_consistent');
SELECT pg_temp.expect_fail('Check-in without checked_in_at',
  $q$UPDATE bookings SET status = 'checked_in' WHERE code = 'DDDDDDD7'$q$, 'bookings_checked_in_at_present');
SELECT pg_temp.expect_ok('Check in and pay properly',
  $q$UPDATE bookings SET status = 'checked_in', checked_in_at = now(), payment_status = 'paid', paid_at = now() WHERE code = 'DDDDDDD7'$q$);
-- Rails names this foreign key fk_rails_<hash>, so match the table named in the error message.
SELECT pg_temp.expect_fail('Delete a court that has bookings',
  $q$DELETE FROM courts WHERE id = 2$q$, 'on table "bookings"');
-- Court 3 has no bookings, so only the price rule can block the delete.
SELECT pg_temp.expect_ok  ('Court-specific price for court 3 of venue 2', $q$INSERT INTO price_rules (venue_id, court_id, name, days_of_week, start_minute, end_minute, price_per_hour_vnd) VALUES (2, 3, 'Sân A', '{1}', 300, 600, 80000)$q$);
SELECT pg_temp.expect_fail('Delete a court that has its own price rules',
  $q$DELETE FROM courts WHERE id = 3$q$, 'fk_price_rules_court_venue');

-- ---------- Results ----------
SELECT CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS result, label, detail FROM results;
SELECT count(*) FILTER (WHERE ok) AS passed, count(*) FILTER (WHERE NOT ok) AS failed FROM results;

ROLLBACK;
