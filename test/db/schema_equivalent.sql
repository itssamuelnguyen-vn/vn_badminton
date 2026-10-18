-- SQL equivalent to what the migrations generate on PostgreSQL.
-- Used to test the constraints without Rails: psql -f schema_equivalent.sql
CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TABLE users (
  id bigserial PRIMARY KEY,
  email citext NOT NULL,
  encrypted_password varchar NOT NULL DEFAULT '',
  reset_password_token varchar,
  reset_password_sent_at timestamptz,
  remember_created_at timestamptz,
  full_name varchar NOT NULL,
  phone varchar,
  role varchar NOT NULL DEFAULT 'customer',
  locale varchar NOT NULL DEFAULT 'vi',
  booking_locked_until timestamptz,
  privacy_accepted_at timestamptz,
  confirmation_token varchar,
  confirmed_at timestamptz,
  confirmation_sent_at timestamptz,
  unconfirmed_email varchar,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT users_role_valid CHECK (role IN ('customer', 'admin')),
  CONSTRAINT users_full_name_length CHECK (length(btrim(full_name)) BETWEEN 1 AND 100),
  CONSTRAINT users_email_format CHECK (email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),
  CONSTRAINT users_phone_format CHECK (phone ~ '^\+84[0-9]{9}$'),
  CONSTRAINT users_locale_valid CHECK (locale IN ('vi', 'en'))
);
CREATE UNIQUE INDEX index_users_on_email ON users (email);
CREATE UNIQUE INDEX index_users_on_phone ON users (phone) WHERE phone IS NOT NULL;
CREATE UNIQUE INDEX index_users_on_reset_password_token ON users (reset_password_token);
CREATE UNIQUE INDEX index_users_on_confirmation_token ON users (confirmation_token);

CREATE TABLE venues (
  id bigserial PRIMARY KEY,
  name varchar NOT NULL,
  slug varchar NOT NULL,
  address varchar NOT NULL,
  phone varchar,
  time_zone varchar NOT NULL DEFAULT 'Asia/Ho_Chi_Minh',
  min_booking_minutes integer NOT NULL DEFAULT 60,
  max_booking_minutes integer NOT NULL DEFAULT 240,
  cancellation_cutoff_hours integer NOT NULL DEFAULT 2,
  booking_horizon_days integer NOT NULL DEFAULT 14,
  max_upcoming_bookings integer NOT NULL DEFAULT 2,
  cancellation_lock_threshold integer NOT NULL DEFAULT 3,
  cancellation_lock_days integer NOT NULL DEFAULT 7,
  status varchar NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT venues_name_present CHECK (length(btrim(name)) > 0),
  CONSTRAINT venues_address_present CHECK (length(btrim(address)) > 0),
  CONSTRAINT venues_slug_format CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  CONSTRAINT venues_phone_format CHECK (phone ~ '^\+84[0-9]{9}$'),
  CONSTRAINT venues_status_valid CHECK (status IN ('active', 'inactive')),
  CONSTRAINT venues_min_booking_minutes_valid CHECK (min_booking_minutes >= 30 AND min_booking_minutes % 30 = 0),
  CONSTRAINT venues_max_booking_minutes_valid CHECK (max_booking_minutes >= min_booking_minutes AND max_booking_minutes <= 720 AND max_booking_minutes % 30 = 0),
  CONSTRAINT venues_cancellation_cutoff_valid CHECK (cancellation_cutoff_hours BETWEEN 0 AND 168),
  CONSTRAINT venues_booking_horizon_valid CHECK (booking_horizon_days BETWEEN 1 AND 365),
  CONSTRAINT venues_max_upcoming_bookings_valid CHECK (max_upcoming_bookings BETWEEN 1 AND 50),
  CONSTRAINT venues_cancellation_lock_threshold_valid CHECK (cancellation_lock_threshold BETWEEN 1 AND 20),
  CONSTRAINT venues_cancellation_lock_days_valid CHECK (cancellation_lock_days BETWEEN 1 AND 90)
);
CREATE UNIQUE INDEX index_venues_on_slug ON venues (slug);

CREATE TABLE opening_hours (
  id bigserial PRIMARY KEY,
  venue_id bigint NOT NULL REFERENCES venues(id) ON DELETE CASCADE,
  day_of_week smallint NOT NULL,
  opens_minute integer NOT NULL,
  closes_minute integer NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT opening_hours_day_valid CHECK (day_of_week BETWEEN 0 AND 6),
  CONSTRAINT opening_hours_range_valid CHECK (opens_minute >= 0 AND closes_minute <= 1440 AND closes_minute > opens_minute),
  CONSTRAINT opening_hours_aligned_to_slot CHECK (opens_minute % 30 = 0 AND closes_minute % 30 = 0)
);
CREATE UNIQUE INDEX index_opening_hours_on_venue_id_and_day_of_week ON opening_hours (venue_id, day_of_week);

CREATE TABLE courts (
  id bigserial PRIMARY KEY,
  venue_id bigint NOT NULL REFERENCES venues(id),
  name varchar NOT NULL,
  position integer NOT NULL DEFAULT 0,
  status varchar NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT courts_name_length CHECK (length(btrim(name)) BETWEEN 1 AND 50),
  CONSTRAINT courts_status_valid CHECK (status IN ('active', 'inactive'))
);
CREATE UNIQUE INDEX index_courts_on_venue_id_and_lower_name ON courts (venue_id, lower(name));
CREATE UNIQUE INDEX index_courts_on_id_and_venue_id ON courts (id, venue_id);

CREATE TABLE price_rules (
  id bigserial PRIMARY KEY,
  venue_id bigint NOT NULL REFERENCES venues(id),
  court_id bigint,
  name varchar NOT NULL,
  name_en varchar,
  days_of_week smallint[] NOT NULL,
  start_minute integer NOT NULL,
  end_minute integer NOT NULL,
  price_per_hour_vnd bigint NOT NULL,
  priority integer NOT NULL DEFAULT 0,
  valid_from date,
  valid_until date,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT fk_price_rules_court_venue FOREIGN KEY (court_id, venue_id) REFERENCES courts (id, venue_id),
  CONSTRAINT price_rules_name_present CHECK (length(btrim(name)) > 0),
  CONSTRAINT price_rules_name_en_present CHECK (name_en IS NULL OR length(btrim(name_en)) > 0),
  CONSTRAINT price_rules_days_valid CHECK (cardinality(days_of_week) BETWEEN 1 AND 7 AND days_of_week <@ ARRAY[0,1,2,3,4,5,6]::smallint[]),
  CONSTRAINT price_rules_time_range_valid CHECK (start_minute >= 0 AND end_minute <= 1440 AND end_minute > start_minute AND start_minute % 30 = 0 AND end_minute % 30 = 0),
  CONSTRAINT price_rules_price_valid CHECK (price_per_hour_vnd > 0 AND price_per_hour_vnd <= 100000000 AND price_per_hour_vnd % 1000 = 0),
  CONSTRAINT price_rules_validity_range CHECK (valid_from IS NULL OR valid_until IS NULL OR valid_until >= valid_from)
);
CREATE INDEX index_price_rules_on_venue_id ON price_rules (venue_id);
CREATE INDEX index_price_rules_on_court_id ON price_rules (court_id);

CREATE TABLE bookings (
  id bigserial PRIMARY KEY,
  court_id bigint NOT NULL REFERENCES courts(id),
  user_id bigint REFERENCES users(id),
  created_by_id bigint REFERENCES users(id),
  cancelled_by_id bigint REFERENCES users(id),
  code varchar NOT NULL,
  kind varchar NOT NULL DEFAULT 'reservation',
  starts_at timestamptz NOT NULL,
  ends_at timestamptz NOT NULL,
  status varchar NOT NULL DEFAULT 'confirmed',
  expires_at timestamptz,
  source varchar NOT NULL DEFAULT 'online',
  customer_name varchar,
  customer_phone varchar,
  total_amount_vnd bigint NOT NULL DEFAULT 0,
  price_breakdown jsonb NOT NULL DEFAULT '[]',
  payment_status varchar NOT NULL DEFAULT 'unpaid',
  paid_at timestamptz,
  checked_in_at timestamptz,
  cancelled_at timestamptz,
  reminder_sent_at timestamptz,
  cancellation_reason varchar,
  note text,
  lock_version integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT bookings_no_overlap EXCLUDE USING gist (court_id WITH =, tstzrange(starts_at, ends_at, '[)') WITH &&)
    WHERE (status IN ('pending', 'confirmed', 'checked_in', 'completed', 'no_show')),
  CONSTRAINT bookings_kind_valid CHECK (kind IN ('reservation', 'block')),
  CONSTRAINT bookings_status_valid CHECK (status IN ('pending', 'confirmed', 'checked_in', 'completed', 'cancelled', 'no_show')),
  CONSTRAINT bookings_source_valid CHECK (source IN ('online', 'phone', 'walk_in', 'staff')),
  CONSTRAINT bookings_payment_status_valid CHECK (payment_status IN ('unpaid', 'paid', 'refunded')),
  CONSTRAINT bookings_code_format CHECK (code ~ '^[A-Z0-9]{8}$'),
  CONSTRAINT bookings_ends_after_starts CHECK (ends_at > starts_at),
  CONSTRAINT bookings_max_duration CHECK (ends_at - starts_at <= interval '24 hours'),
  CONSTRAINT bookings_aligned_to_slot CHECK (mod(extract(epoch FROM starts_at), 1800) = 0 AND mod(extract(epoch FROM ends_at), 1800) = 0),
  CONSTRAINT bookings_kind_fields CHECK (
    (kind = 'reservation' AND customer_name IS NOT NULL AND length(btrim(customer_name)) > 0 AND customer_phone IS NOT NULL)
    OR (kind = 'block' AND user_id IS NULL AND customer_name IS NULL AND customer_phone IS NULL
        AND total_amount_vnd = 0 AND payment_status = 'unpaid' AND source = 'staff')),
  CONSTRAINT bookings_customer_phone_format CHECK (customer_phone ~ '^\+84[0-9]{9}$'),
  CONSTRAINT bookings_online_requires_user CHECK (source <> 'online' OR user_id IS NOT NULL),
  CONSTRAINT bookings_amount_non_negative CHECK (total_amount_vnd >= 0),
  CONSTRAINT bookings_price_breakdown_array CHECK (jsonb_typeof(price_breakdown) = 'array'),
  CONSTRAINT bookings_paid_at_consistent CHECK ((payment_status = 'unpaid') = (paid_at IS NULL)),
  CONSTRAINT bookings_cancelled_at_consistent CHECK ((status = 'cancelled') = (cancelled_at IS NOT NULL)),
  CONSTRAINT bookings_pending_requires_expiry CHECK (status <> 'pending' OR expires_at IS NOT NULL),
  CONSTRAINT bookings_checked_in_at_present CHECK (status NOT IN ('checked_in', 'completed') OR checked_in_at IS NOT NULL)
);
CREATE INDEX index_bookings_on_user_id ON bookings (user_id);
CREATE INDEX index_bookings_on_created_by_id ON bookings (created_by_id);
CREATE UNIQUE INDEX index_bookings_on_code ON bookings (code);
CREATE INDEX index_bookings_on_court_id_and_starts_at ON bookings (court_id, starts_at);
CREATE INDEX index_bookings_on_starts_at ON bookings (starts_at);
CREATE INDEX index_bookings_on_expires_at ON bookings (expires_at) WHERE status = 'pending';
