-- ============================================================================
-- Workstream Z (2026-09-10) — Member "Daily Check-In"
--
--   * check_ins            : one row per member per calendar day (day boundary
--                            is Asia/Kuala_Lumpur, matching the MYR / +60 audience).
--   * daily_check_in()      : the ONLY way a check-in row is written. Computes the
--                            consecutive-day streak, awards reward_points, and
--                            returns the result as jsonb for the dashboard.
--
-- Points schedule (kept in sync with checkinPoints() in dashboard.html):
--     base            = 5
--     + 2 per consecutive day, growth capped at day 7
--     + 25 bonus on every 7th consecutive day
--   => day 1 = 5, day 2 = 7, ... day 7 = 17 (+25 = 42), day 8+ = 17
-- Missing a day resets the streak to 1.
--
-- reward_points is otherwise locked against member self-edits by the
-- protect_position_flags() trigger (see Workstream T / U). Rather than widen
-- that trigger, daily_check_in() flips a transaction-local GUC
-- (app.tc_points_ctx = 'checkin') that the trigger treats as an allowed context.
-- Members cannot set that GUC themselves — PostgREST only lets them call the
-- RPCs we expose, and this one only ever credits the one legit daily award.
--
-- Safe to run more than once (guards on every object).
-- ============================================================================

-- ── 1. Check-in log ────────────────────────────────────────────────────────
create table if not exists public.check_ins (
  id             uuid primary key default gen_random_uuid(),
  member_id      uuid not null references public.profiles(id) on delete cascade,
  check_in_date  date    not null,
  points_awarded integer not null default 0 check (points_awarded >= 0),
  streak_day     integer not null default 1 check (streak_day >= 1),
  created_at     timestamptz not null default now(),
  unique (member_id, check_in_date)
);

create index if not exists check_ins_member_date_idx
  on public.check_ins (member_id, check_in_date desc);

alter table public.check_ins enable row level security;

drop policy if exists "members: read own check-ins"  on public.check_ins;
drop policy if exists "admins: read all check-ins"   on public.check_ins;

-- Reads only. Every write goes through daily_check_in() (SECURITY DEFINER),
-- so members get no insert/update/delete policy at all — they cannot forge a
-- row with an arbitrary points_awarded / streak_day.
create policy "members: read own check-ins" on public.check_ins
  for select using (member_id = auth.uid() or public.is_admin_or_staff());

grant select on public.check_ins to authenticated;

-- ── 2. Let the trusted RPC credit reward_points past the self-edit guard ────
-- Unchanged from Workstream U except for the `current_setting(...)` carve-out.
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
  IF NOT public.is_admin_or_staff()
     AND current_setting('app.tc_points_ctx', true) IS DISTINCT FROM 'checkin' THEN
    IF NEW.reward_points IS DISTINCT FROM OLD.reward_points THEN
      RAISE EXCEPTION 'Only admins/staff can change a member''s reward points';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

-- ── 3. The check-in RPC ────────────────────────────────────────────────────
create or replace function public.daily_check_in()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
DECLARE
  v_member   uuid := auth.uid();
  v_today    date := (now() AT TIME ZONE 'Asia/Kuala_Lumpur')::date;
  v_last     public.check_ins%ROWTYPE;
  v_streak   integer;
  v_points   integer;
  v_weekly   boolean;
  v_balance  integer;
BEGIN
  IF v_member IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_last
  FROM public.check_ins
  WHERE member_id = v_member
  ORDER BY check_in_date DESC
  LIMIT 1;

  -- Already checked in today — return current state, award nothing.
  IF FOUND AND v_last.check_in_date = v_today THEN
    SELECT reward_points INTO v_balance FROM public.profiles WHERE id = v_member;
    RETURN jsonb_build_object(
      'ok', true,
      'already_checked_in', true,
      'check_in_date', v_today,
      'streak_day', v_last.streak_day,
      'points_awarded', v_last.points_awarded,
      'weekly_bonus', false,
      'reward_points', coalesce(v_balance, 0)
    );
  END IF;

  -- Continue the streak only if the last check-in was exactly yesterday.
  IF FOUND AND v_last.check_in_date = v_today - 1 THEN
    v_streak := v_last.streak_day + 1;
  ELSE
    v_streak := 1;
  END IF;

  -- Points schedule — keep in sync with checkinPoints() in dashboard.html.
  v_points := 5 + least(greatest(v_streak - 1, 0), 6) * 2;
  v_weekly := (v_streak % 7 = 0);
  IF v_weekly THEN
    v_points := v_points + 25;
  END IF;

  BEGIN
    INSERT INTO public.check_ins (member_id, check_in_date, points_awarded, streak_day)
    VALUES (v_member, v_today, v_points, v_streak);
  EXCEPTION WHEN unique_violation THEN
    -- Raced with another tab/request that checked in first this second.
    SELECT * INTO v_last FROM public.check_ins
    WHERE member_id = v_member AND check_in_date = v_today;
    SELECT reward_points INTO v_balance FROM public.profiles WHERE id = v_member;
    RETURN jsonb_build_object(
      'ok', true,
      'already_checked_in', true,
      'check_in_date', v_today,
      'streak_day', v_last.streak_day,
      'points_awarded', v_last.points_awarded,
      'weekly_bonus', false,
      'reward_points', coalesce(v_balance, 0)
    );
  END;

  -- Credit the points. The GUC tells protect_position_flags() this is allowed;
  -- it is transaction-local (set_config(..., true)) so it cannot leak.
  PERFORM set_config('app.tc_points_ctx', 'checkin', true);
  UPDATE public.profiles
     SET reward_points = reward_points + v_points
   WHERE id = v_member
  RETURNING reward_points INTO v_balance;
  PERFORM set_config('app.tc_points_ctx', '', true);

  IF v_balance IS NULL THEN
    RAISE EXCEPTION 'No profile row for %', v_member;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'already_checked_in', false,
    'check_in_date', v_today,
    'streak_day', v_streak,
    'points_awarded', v_points,
    'weekly_bonus', v_weekly,
    'reward_points', v_balance
  );
END;
$function$;

revoke all     on function public.daily_check_in() from public, anon;
grant  execute on function public.daily_check_in() to authenticated;
