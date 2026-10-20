-- ============================================================================
-- Trips: content for the redesigned trip detail page (trip.html)
--   gallery         jsonb  ["https://…/photo.jpg", ...]             extra photos
--   tags            jsonb  ["Best Seller", "Spring Season", ...]    hero badges
--   features        jsonb  ["flight","hotel","transport","guide","meals","insurance"]
--   highlights      jsonb  [{ "title": "Iconic Cherry Blossom Spots", "image": "…" }]
--   itinerary_days  jsonb  [{ "title": "Kuala Lumpur → Tokyo", "desc": "…" }]
--                          (empty = trip.html falls back to the plain itinerary text)
--   accommodations  jsonb  [{ "city": "Tokyo", "hotel": "Hotel Gracery Shinjuku", "stars": 4, "image": "…" }]
--   inclusions / exclusions  text, one item per line
--   route_image     text   map / route picture
--   All optional — every section on the page hides itself when empty.
--   Safe to run more than once.
-- ============================================================================

alter table public.trips
  add column if not exists gallery        jsonb not null default '[]'::jsonb,
  add column if not exists tags           jsonb not null default '[]'::jsonb,
  add column if not exists features       jsonb not null default '[]'::jsonb,
  add column if not exists highlights     jsonb not null default '[]'::jsonb,
  add column if not exists itinerary_days jsonb not null default '[]'::jsonb,
  add column if not exists accommodations jsonb not null default '[]'::jsonb,
  add column if not exists inclusions     text,
  add column if not exists exclusions     text,
  add column if not exists route_image    text;
