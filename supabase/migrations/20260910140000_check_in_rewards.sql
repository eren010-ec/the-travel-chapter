-- ============================================================================
-- Workstream Z (2026-09-10) — Admin-editable daily check-in rewards
--
--   * check_in_rewards : 7 fixed rows (day 1..7). Admins/staff set the points
--                        awarded for each day of the streak cycle and, optionally,
--                        an icon image (public URL in the shared `trip-images`
--                        bucket, folder `checkin/`). No image -> the dashboard
--                        keeps showing the default present-box emoji.
--   * daily_check_in() : now reads the award from check_in_rewards for the current
--                        cycle day (((streak-1) % 7) + 1), falling back to the
--                        original formula if a row is somehow missing.
--
-- Seed values match what daily_check_in() awarded before this table existed:
--   day 1=5, 2=7, 3=9, 4=11, 5=13, 6=15, 7=42  (7 = 17 + the old 25 weekly bonus)
--
-- Safe to run more than once.
-- ============================================================================

create table if not exists public.check_in_rewards (
  day        smallint primary key check (day between 1 and 7),
  points     integer not null default 0 check (points >= 0),
  image_url  text,
  updated_at timestamptz not null default now()
);

insert into public.check_in_rewards (day, points) values
  (1, 5), (2, 7), (3, 9), (4, 11), (5, 13), (6, 15), (7, 42)
on conflict (day) do nothing;

drop trigger if exists check_in_rewards_updated_at on public.check_in_rewards;
create trigger check_in_rewards_updated_at before update on public.check_in_rewards
  for each row execute function public.set_updated_at();

alter table public.check_in_rewards enable row level security;

drop policy if exists "anyone: read check-in rewards" on public.check_in_rewards;
drop policy if exists "admins: write check-in rewards" on public.check_in_rewards;

-- Members (and logged-out visitors) need to read points + icons to render the card.
create policy "anyone: read check-in rewards" on public.check_in_rewards
  for select to anon, authenticated using (true);
create policy "admins: write check-in rewards" on public.check_in_rewards
  for all to authenticated
  using (public.is_admin_or_staff()) with check (public.is_admin_or_staff());

grant select                 on public.check_in_rewards to anon, authenticated;
grant insert, update, delete on public.check_in_rewards to authenticated;

-- ── daily_check_in(): award the configured points for the cycle day ──────────
create or replace function public.daily_check_in()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
DECLARE
  v_member    uuid := auth.uid();
  v_today     date := (now() AT TIME ZONE 'Asia/Kuala_Lumpur')::date;
  v_last      public.check_ins%ROWTYPE;
  v_streak    integer;
  v_cycle_day integer;
  v_points    integer;
  v_weekly    boolean;
  v_balance   integer;
BEGIN
  IF v_member IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_last
  FROM public.check_ins
  WHERE member_id = v_member
  ORDER BY check_in_date DESC
  LIMIT 1;

  IF FOUND AND v_last.check_in_date = v_today THEN
    SELECT reward_points INTO v_balance FROM public.profiles WHERE id = v_member;
    RETURN jsonb_build_object(
      'ok', true, 'already_checked_in', true,
      'check_in_date', v_today, 'streak_day', v_last.streak_day,
      'points_awarded', v_last.points_awarded, 'weekly_bonus', false,
      'reward_points', coalesce(v_balance, 0)
    );
  END IF;

  IF FOUND AND v_last.check_in_date = v_today - 1 THEN
    v_streak := v_last.streak_day + 1;
  ELSE
    v_streak := 1;
  END IF;

  -- Award = configured points for this cycle day; fall back to the old formula.
  v_cycle_day := ((v_streak - 1) % 7) + 1;
  SELECT points INTO v_points FROM public.check_in_rewards WHERE day = v_cycle_day;
  IF v_points IS NULL THEN
    v_points := 5 + least(greatest(v_streak - 1, 0), 6) * 2
                + CASE WHEN v_cycle_day = 7 THEN 25 ELSE 0 END;
  END IF;
  v_weekly := (v_cycle_day = 7);

  BEGIN
    INSERT INTO public.check_ins (member_id, check_in_date, points_awarded, streak_day)
    VALUES (v_member, v_today, v_points, v_streak);
  EXCEPTION WHEN unique_violation THEN
    SELECT * INTO v_last FROM public.check_ins
    WHERE member_id = v_member AND check_in_date = v_today;
    SELECT reward_points INTO v_balance FROM public.profiles WHERE id = v_member;
    RETURN jsonb_build_object(
      'ok', true, 'already_checked_in', true,
      'check_in_date', v_today, 'streak_day', v_last.streak_day,
      'points_awarded', v_last.points_awarded, 'weekly_bonus', false,
      'reward_points', coalesce(v_balance, 0)
    );
  END;

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
    'ok', true, 'already_checked_in', false,
    'check_in_date', v_today, 'streak_day', v_streak,
    'points_awarded', v_points, 'weekly_bonus', v_weekly,
    'reward_points', v_balance
  );
END;
$function$;

revoke all     on function public.daily_check_in() from public, anon;
grant  execute on function public.daily_check_in() to authenticated;
