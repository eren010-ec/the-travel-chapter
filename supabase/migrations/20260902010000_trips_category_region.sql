-- ============================================================================
-- Trips: optional Category + Region (destination) tags
--   Powers the filter bar on the public Trips page (trips.html) and the
--   admin Trips editor. Both nullable — existing rows stay valid.
--   Safe to run more than once.
-- ============================================================================

alter table public.trips
  add column if not exists category text
    check (category is null or char_length(category) <= 60),
  add column if not exists region text
    check (region is null or char_length(region) <= 80);

create index if not exists trips_category_idx on public.trips(category);
create index if not exists trips_region_idx   on public.trips(region);
