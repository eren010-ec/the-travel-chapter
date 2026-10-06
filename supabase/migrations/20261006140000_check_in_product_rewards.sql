-- ============================================================================
-- Workstream Z (2026-10-06) — Check-in days can give a PRODUCT
--
--   * check_in_rewards.reward_type gains 'product', + product_id (FK products).
--   * check_ins.reward_kind gains 'product'.
--   * daily_check_in(): on a product day it records the check-in (0 points) and
--     creates an APPROVED, 0-cost public.product_requests row for that product,
--     note 'Daily check-in reward — day N'. Staff fulfil it from the existing
--     Redemption Requests queue; the member sees it under My Requests.
--     If the product was deleted, the day falls back to its points value.
--
-- Safe to run more than once.
-- ============================================================================

alter table public.check_in_rewards
  add column if not exists product_id uuid references public.products(id) on delete set null;

alter table public.check_in_rewards drop constraint if exists check_in_rewards_reward_type_check;
alter table public.check_in_rewards
  add constraint check_in_rewards_reward_type_check
  check (reward_type in ('points','voucher','luckydraw','product'));

alter table public.check_ins drop constraint if exists check_ins_reward_kind_check;
alter table public.check_ins
  add constraint check_ins_reward_kind_check
  check (reward_kind in ('points','voucher','luckydraw','product'));

-- ── daily_check_in(): + product branch ─────────────────────────────────────
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
  v_pname     text;
  v_prof      public.profiles%ROWTYPE;
BEGIN
  IF v_member IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT * INTO v_last FROM public.check_ins
  WHERE member_id = v_member ORDER BY check_in_date DESC LIMIT 1;

  IF FOUND AND v_last.check_in_date = v_today THEN
    SELECT reward_points INTO v_balance FROM public.profiles WHERE id = v_member;
    RETURN jsonb_build_object(
      'ok', true, 'already_checked_in', true,
      'check_in_date', v_today, 'streak_day', v_last.streak_day,
      'points_awarded', v_last.points_awarded, 'reward_kind', v_last.reward_kind,
      'draw_pending', (v_last.reward_kind = 'luckydraw' AND v_last.draw_prize IS NULL),
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

  IF v_cfg.reward_type = 'product' AND v_cfg.product_id IS NOT NULL THEN
    SELECT name INTO v_pname FROM public.products WHERE id = v_cfg.product_id;
  END IF;

  IF v_cycle_day = 7 AND v_cfg.reward_type = 'luckydraw' THEN
    v_kind := 'luckydraw';
  ELSIF v_pname IS NOT NULL THEN
    -- Product day: the request row is inserted after the check_ins row below,
    -- so a double-tap (unique_violation there) can't create two.
    v_kind := 'product';
  ELSIF v_cfg.reward_type = 'voucher'
        AND v_cfg.voucher_discount_type IS NOT NULL
        AND v_cfg.voucher_discount_value IS NOT NULL THEN
    v_kind := 'voucher';
    v_expires := v_today + coalesce(v_cfg.voucher_valid_days, 30);
    LOOP
      v_try := v_try + 1; v_code := public.tc_random_code('DAILY');
      BEGIN
        INSERT INTO public.vouchers (code, discount_type, discount_value, member_id, expires_at, note, created_by)
        VALUES (v_code, v_cfg.voucher_discount_type, v_cfg.voucher_discount_value, v_member,
                v_expires, 'Daily check-in reward — day ' || v_cycle_day, v_member);
        EXIT;
      EXCEPTION WHEN unique_violation THEN
        IF v_try >= 6 THEN RAISE EXCEPTION 'Could not allocate a voucher code'; END IF;
      END;
    END LOOP;
  ELSE
    v_points := v_cfg.points;
    IF v_points IS NULL THEN
      v_points := 5 + least(greatest(v_streak - 1, 0), 6) * 2 + CASE WHEN v_cycle_day = 7 THEN 25 ELSE 0 END;
    END IF;
  END IF;

  BEGIN
    INSERT INTO public.check_ins (member_id, check_in_date, points_awarded, streak_day, reward_kind)
    VALUES (v_member, v_today, v_points, v_streak, v_kind);
  EXCEPTION WHEN unique_violation THEN
    SELECT * INTO v_last FROM public.check_ins WHERE member_id = v_member AND check_in_date = v_today;
    SELECT reward_points INTO v_balance FROM public.profiles WHERE id = v_member;
    RETURN jsonb_build_object(
      'ok', true, 'already_checked_in', true,
      'check_in_date', v_today, 'streak_day', v_last.streak_day,
      'points_awarded', v_last.points_awarded, 'reward_kind', v_last.reward_kind,
      'draw_pending', (v_last.reward_kind = 'luckydraw' AND v_last.draw_prize IS NULL),
      'weekly_bonus', false, 'reward_points', coalesce(v_balance, 0)
    );
  END;

  IF v_kind = 'product' THEN
    SELECT * INTO v_prof FROM public.profiles WHERE id = v_member;
    INSERT INTO public.product_requests
      (member_id, member_name, member_email, product_id, product_name,
       method, points_cost_snapshot, quantity, status, note)
    VALUES
      (v_member,
       nullif(trim(coalesce(v_prof.first_name,'') || ' ' || coalesce(v_prof.last_name,'')), ''),
       coalesce(v_prof.email, (SELECT email FROM auth.users WHERE id = v_member)),
       v_cfg.product_id, v_pname,
       'points', 0, 1, 'approved', 'Daily check-in reward — day ' || v_cycle_day);
  END IF;

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
    'reward_kind', v_kind, 'points_awarded', v_points,
    'reward_points', coalesce(v_balance, 0),
    'draw_pending', (v_kind = 'luckydraw'),
    'voucher_code', v_code,
    'voucher_discount_type',  CASE WHEN v_kind = 'voucher' THEN v_cfg.voucher_discount_type END,
    'voucher_discount_value', CASE WHEN v_kind = 'voucher' THEN v_cfg.voucher_discount_value END,
    'voucher_expires_at', v_expires,
    'product_id',   CASE WHEN v_kind = 'product' THEN v_cfg.product_id END,
    'product_name', v_pname
  );
END;
$function$;

revoke all     on function public.daily_check_in() from public, anon;
grant  execute on function public.daily_check_in() to authenticated;
