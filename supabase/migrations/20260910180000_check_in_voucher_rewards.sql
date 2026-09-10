-- ============================================================================
-- Workstream Z (2026-09-10) — Check-in reward can be points OR a voucher
--
-- Each of the 7 check_in_rewards rows gains a reward_type:
--   * 'points'  (default, unchanged) — credits profiles.reward_points
--   * 'voucher'                       — daily_check_in() issues a real
--                                      public.vouchers row assigned to the
--                                      member, expiring voucher_valid_days
--                                      after the claim date. It shows up
--                                      immediately in the member's
--                                      "My Vouchers" page.
--
-- check_ins.reward_kind records which kind each claim gave, so the dashboard
-- can keep voucher claims out of the points activity feed.
--
-- Safe to run more than once.
-- ============================================================================

alter table public.check_in_rewards
  add column if not exists reward_type text not null default 'points'
    check (reward_type in ('points','voucher')),
  add column if not exists voucher_discount_type text
    check (voucher_discount_type is null or voucher_discount_type in ('fixed','percent')),
  add column if not exists voucher_discount_value numeric(10,2)
    check (voucher_discount_value is null or voucher_discount_value >= 0),
  add column if not exists voucher_valid_days integer
    check (voucher_valid_days is null or voucher_valid_days > 0);

alter table public.check_ins
  add column if not exists reward_kind text not null default 'points'
    check (reward_kind in ('points','voucher'));

-- ── daily_check_in(): points OR voucher per configured day ──────────────────
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
  v_cfg       public.check_in_rewards%ROWTYPE;
  v_streak    integer;
  v_cycle_day integer;
  v_points    integer := 0;
  v_weekly    boolean;
  v_balance   integer;
  v_kind      text := 'points';
  v_code      text;
  v_expires   date;
  v_try       integer := 0;
  v_alpha     text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  i           integer;
BEGIN
  IF v_member IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_last FROM public.check_ins
  WHERE member_id = v_member ORDER BY check_in_date DESC LIMIT 1;

  -- Already checked in today.
  IF FOUND AND v_last.check_in_date = v_today THEN
    SELECT reward_points INTO v_balance FROM public.profiles WHERE id = v_member;
    RETURN jsonb_build_object(
      'ok', true, 'already_checked_in', true,
      'check_in_date', v_today, 'streak_day', v_last.streak_day,
      'points_awarded', v_last.points_awarded, 'reward_kind', v_last.reward_kind,
      'weekly_bonus', false, 'reward_points', coalesce(v_balance, 0)
    );
  END IF;

  IF FOUND AND v_last.check_in_date = v_today - 1 THEN
    v_streak := v_last.streak_day + 1;
  ELSE
    v_streak := 1;
  END IF;

  v_cycle_day := ((v_streak - 1) % 7) + 1;
  v_weekly := (v_cycle_day = 7);
  SELECT * INTO v_cfg FROM public.check_in_rewards WHERE day = v_cycle_day;

  IF v_cfg.reward_type = 'voucher'
     AND v_cfg.voucher_discount_type IS NOT NULL
     AND v_cfg.voucher_discount_value IS NOT NULL THEN
    v_kind    := 'voucher';
    v_expires := v_today + coalesce(v_cfg.voucher_valid_days, 30);

    -- Unique code, a few retries against a collision.
    LOOP
      v_try := v_try + 1;
      v_code := 'DAILY-';
      FOR i IN 1..6 LOOP
        v_code := v_code || substr(v_alpha, 1 + floor(random() * length(v_alpha))::int, 1);
      END LOOP;
      BEGIN
        INSERT INTO public.vouchers (code, discount_type, discount_value, member_id,
                                     expires_at, note, created_by)
        VALUES (v_code, v_cfg.voucher_discount_type, v_cfg.voucher_discount_value, v_member,
                v_expires, 'Daily check-in reward — day ' || v_cycle_day, v_member);
        EXIT;
      EXCEPTION WHEN unique_violation THEN
        IF v_try >= 6 THEN RAISE EXCEPTION 'Could not allocate a voucher code'; END IF;
      END;
    END LOOP;
  ELSE
    -- Points path. Configured points, else the original formula.
    v_points := v_cfg.points;
    IF v_points IS NULL THEN
      v_points := 5 + least(greatest(v_streak - 1, 0), 6) * 2
                  + CASE WHEN v_cycle_day = 7 THEN 25 ELSE 0 END;
    END IF;
  END IF;

  BEGIN
    INSERT INTO public.check_ins (member_id, check_in_date, points_awarded, streak_day, reward_kind)
    VALUES (v_member, v_today, v_points, v_streak, v_kind);
  EXCEPTION WHEN unique_violation THEN
    SELECT * INTO v_last FROM public.check_ins
    WHERE member_id = v_member AND check_in_date = v_today;
    SELECT reward_points INTO v_balance FROM public.profiles WHERE id = v_member;
    RETURN jsonb_build_object(
      'ok', true, 'already_checked_in', true,
      'check_in_date', v_today, 'streak_day', v_last.streak_day,
      'points_awarded', v_last.points_awarded, 'reward_kind', v_last.reward_kind,
      'weekly_bonus', false, 'reward_points', coalesce(v_balance, 0)
    );
  END;

  IF v_kind = 'points' AND v_points > 0 THEN
    PERFORM set_config('app.tc_points_ctx', 'checkin', true);
    UPDATE public.profiles SET reward_points = reward_points + v_points
     WHERE id = v_member RETURNING reward_points INTO v_balance;
    PERFORM set_config('app.tc_points_ctx', '', true);
    IF v_balance IS NULL THEN RAISE EXCEPTION 'No profile row for %', v_member; END IF;
  ELSE
    SELECT reward_points INTO v_balance FROM public.profiles WHERE id = v_member;
  END IF;

  RETURN jsonb_build_object(
    'ok', true, 'already_checked_in', false,
    'check_in_date', v_today, 'streak_day', v_streak, 'weekly_bonus', v_weekly,
    'reward_kind', v_kind,
    'points_awarded', v_points,
    'reward_points', coalesce(v_balance, 0),
    'voucher_code', v_code,
    'voucher_discount_type', CASE WHEN v_kind = 'voucher' THEN v_cfg.voucher_discount_type END,
    'voucher_discount_value', CASE WHEN v_kind = 'voucher' THEN v_cfg.voucher_discount_value END,
    'voucher_expires_at', v_expires
  );
END;
$function$;

revoke all     on function public.daily_check_in() from public, anon;
grant  execute on function public.daily_check_in() to authenticated;
