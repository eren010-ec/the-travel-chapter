-- ============================================================================
-- Workstream U (2026-08-27) — Remove the membership-tier system
--
-- Decisions (from the user):
--   * Trips are no longer gated  -> trips.min_tier kept in the DB but UNUSED.
--   * Existing tier_points move 1:1 into reward_points, then tier_points is zeroed
--     (so re-running this migration adds 0 more — it is idempotent).
--   * Confirmed bookings keep auto-awarding points, now into reward_points.
--   * profiles.tier / profiles.tier_points / trips.min_tier COLUMNS ARE KEPT
--     (not dropped) so this is reversible and nothing that still reads them breaks.
--     They simply stop being written or shown by the app.
--
-- Requires the Workstream T migration (reward_points column) first; the guard
-- below re-adds it if missing so order does not actually matter.
-- ============================================================================

alter table public.profiles
  add column if not exists reward_points integer not null default 0;

-- ── 1. One-time 1:1 carry-over of earned points ────────────────────────────
-- Idempotent: after this runs, tier_points is 0, so running it again adds 0.
update public.profiles
set reward_points = reward_points + coalesce(tier_points, 0),
    tier_points   = 0
where coalesce(tier_points, 0) <> 0;

-- ── 2. Booking auto-award now credits reward_points ───────────────────────
create or replace function public.award_points_on_confirm()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
BEGIN
  IF NEW.status = 'confirmed' AND OLD.status <> 'confirmed' THEN
    -- 1 point per RM spent
    NEW.points_earned := FLOOR(NEW.total_usd)::INTEGER;
    UPDATE public.profiles
    SET reward_points = reward_points + NEW.points_earned
    WHERE id = NEW.member_id;
  END IF;
  RETURN NEW;
END;
$function$;

-- ── 3. Simplify the profiles guard trigger ───────────────────────────────
-- Was guarding tier / tier_points / reward_points against member self-edits.
-- tier / tier_points are dead now, so only reward_points (and the position
-- flags) still need protecting.
create or replace function public.protect_position_flags()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
BEGIN
  IF NOT public.is_admin() THEN
    IF NEW.is_admin IS DISTINCT FROM OLD.is_admin OR NEW.is_staff IS DISTINCT FROM OLD.is_staff THEN
      RAISE EXCEPTION 'Only admins can change admin/staff position';
    END IF;
  END IF;
  IF NOT public.is_admin_or_staff() THEN
    IF NEW.reward_points IS DISTINCT FROM OLD.reward_points THEN
      RAISE EXCEPTION 'Only admins/staff can change a member''s reward points';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

-- ── 4. New members no longer get a tier assigned ────────────────────────────
-- profiles.tier still has its 'explorer' column default, so the row stays valid;
-- we just stop threading a value through from signup metadata.
create or replace function public.handle_new_user()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
BEGIN
  INSERT INTO public.profiles (id, first_name, last_name, phone)
  VALUES (
    NEW.id,
    NEW.raw_user_meta_data->>'first_name',
    NEW.raw_user_meta_data->>'last_name',
    NEW.phone
  );
  RETURN NEW;
END;
$function$;

-- NOTE: admin_members view still exposes tier / tier_points columns. They are
-- left in place because CREATE OR REPLACE VIEW cannot drop columns and
-- get_admin_members() returns SETOF admin_members. The admin UI just ignores them.
