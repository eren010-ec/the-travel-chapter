-- ============================================================================
-- Trips: translated content (Chinese for now) for the customer site
--   i18n  jsonb  { "zh": { "title": "…", "summary": "…", "description": "…",
--                          "inclusions": "…", "exclusions": "…",
--                          "highlights": { "<English highlight title>": "…" },
--                          "packages": { "<option id>": { "label": "…",
--                                        "itinerary_days": [{ "title": "…", "desc": "…" }] } } } }
--   Read by TC_I18N.trip() in i18n.js; anything missing falls back to English.
--   Safe to run more than once.
-- ============================================================================

alter table public.trips
  add column if not exists i18n jsonb not null default '{}'::jsonb;
