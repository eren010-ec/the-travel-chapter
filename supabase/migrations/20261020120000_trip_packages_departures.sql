-- ============================================================================
-- Trips: multiple duration/price options + departures with a time
--   trips.packages   jsonb  [{ "label": "3D2N", "days": 3, "price": 1200 }, ...]
--   trips.departures jsonb  [{ "date": "2026-10-15", "time": "08:00" }, ...]
--   The admin editor keeps the legacy columns in sync so existing listings and
--   filters keep working: price_usd / duration_days = cheapest option,
--   departure_dates = the unique departure dates.
--
--   bookings records which option + departure time the member picked.
--   Safe to run more than once.
-- ============================================================================

alter table public.trips
  add column if not exists packages   jsonb not null default '[]'::jsonb,
  add column if not exists departures jsonb not null default '[]'::jsonb;

alter table public.bookings
  add column if not exists package_label  text check (package_label is null or char_length(package_label) <= 80),
  add column if not exists package_days   integer,
  add column if not exists departure_time text check (departure_time is null or departure_time ~ '^\d{2}:\d{2}$');
