-- ============================================================================
-- Workstream Z (2026-09-10) — Day-7 check-in Lucky Draw minigame
--
--   * check_in_rewards.reward_type gains 'luckydraw' (meaningful on day 7).
--   * check_in_draw_prizes : 9 fixed rows (slot 1..9) — the prizes shown in the
--                            member's 3x3 present-box minigame. Each is points OR
--                            a voucher, same shape as a day reward, plus a label.
--   * daily_check_in(): on a day-7 'luckydraw' claim it records the check-in with
--     reward_kind='luckydraw' and draw_prize=null, awards nothing yet, and tells
--     the client to open the minigame.
--   * claim_lucky_draw(pick int): called when the member picks a box. Picks a
--     random winning prize, awards it (points -> reward_points, voucher -> a real
--     vouchers row, code DRAW-XXXXXX), records it on the check_ins row, and
--     returns the winning prize + a 9-cell board for the reveal. Re-calling after
--     it's been played just returns the stored prize.
--
-- Safe to run more than once.
-- ============================================================================

-- ── 1. widen the enums / add the column ────────────────────────────────────
alter table public.check_in_rewards drop constraint if exists check_in_rewards_reward_type_check;
alter table public.check_in_rewards
  add constraint check_in_rewards_reward_type_check
  check (reward_type in ('points','voucher','luckydraw'));

alter table public.check_ins drop constraint if exists check_ins_reward_kind_check;
alter table public.check_ins
  add constraint check_ins_reward_kind_check
  check (reward_kind in ('points','voucher','luckydraw'));

alter table public.check_ins add column if not exists draw_prize jsonb;

-- ── 2. the 9 minigame prizes ──────────────────────────────────────────────
create table if not exists public.check_in_draw_prizes (
  slot        smallint primary key check (slot between 1 and 9),
  reward_type text not null default 'points' check (reward_type in ('points','voucher')),
  points      integer check (points is null or points >= 0),
  voucher_discount_type  text    check (voucher_discount_type is null or voucher_discount_type in ('fixed','percent')),
  voucher_discount_value numeric(10,2) check (voucher_discount_value is null or voucher_discount_value >= 0),
  voucher_valid_days     integer check (voucher_valid_days is null or voucher_valid_days > 0),
  label       text,
  updated_at  timestamptz not null default now()
);

insert into public.check_in_draw_prizes (slot, reward_type, points, label) values
  (1,'points',10,'10 points'), (2,'points',20,'20 points'), (3,'points',30,'30 points'),
  (4,'points',50,'50 points'), (5,'points',5,'5 points'),   (6,'points',15,'15 points'),
  (7,'points',25,'25 points'), (8,'points',40,'40 points'), (9,'points',100,'Jackpot!')
on conflict (slot) do nothing;

drop trigger if exists check_in_draw_prizes_updated_at on public.check_in_draw_prizes;
create trigger check_in_draw_prizes_updated_at before update on public.check_in_draw_prizes
  for each row execute function public.set_updated_at();

alter table public.check_in_draw_prizes enable row level security;
drop policy if exists "anyone: read draw prizes"  on public.check_in_draw_prizes;
drop policy if exists "admins: write draw prizes"  on public.check_in_draw_prizes;
create policy "anyone: read draw prizes" on public.check_in_draw_prizes
  for select to anon, authenticated using (true);
create policy "admins: write draw prizes" on public.check_in_draw_prizes
  for all to authenticated using (public.is_admin_or_staff()) with check (public.is_admin_or_staff());
grant select                 on public.check_in_draw_prizes to anon, authenticated;
grant insert, update, delete on public.check_in_draw_prizes to authenticated;

-- ── 3. shared helper: random unambiguous code ─────────────────────────────
create or replace function public.tc_random_code(prefix text)
 returns text language plpgsql volatile set search_path to 'public'
as $function$
DECLARE a text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; c text := prefix || '-'; i int;
BEGIN
  FOR i IN 1..6 LOOP c := c || substr(a, 1 + floor(random()*length(a))::int, 1); END LOOP;
  RETURN c;
END;
$function$;

-- ── 4. daily_check_in(): + luckydraw branch ──────────────────────────────
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

  IF v_cycle_day = 7 AND v_cfg.reward_type = 'luckydraw' THEN
    v_kind := 'luckydraw';
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
    'voucher_expires_at', v_expires
  );
END;
$function$;

-- ── 5. claim_lucky_draw(pick) ────────────────────────────────────────────
create or replace function public.claim_lucky_draw(pick integer default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
DECLARE
  v_member  uuid := auth.uid();
  v_today   date := (now() AT TIME ZONE 'Asia/Kuala_Lumpur')::date;
  v_row     public.check_ins%ROWTYPE;
  v_win     public.check_in_draw_prizes%ROWTYPE;
  v_pick    integer := coalesce(pick, 1 + floor(random()*9)::int);
  v_balance integer;
  v_code    text;
  v_expires date;
  v_try     integer := 0;
  v_prize   jsonb;
  v_board   jsonb := '[]'::jsonb;
  r         record;
  v_pos     integer;
BEGIN
  IF v_member IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF v_pick < 1 OR v_pick > 9 THEN v_pick := 1 + floor(random()*9)::int; END IF;

  SELECT * INTO v_row FROM public.check_ins
  WHERE member_id = v_member AND check_in_date = v_today AND reward_kind = 'luckydraw';
  IF NOT FOUND THEN RAISE EXCEPTION 'No lucky draw to claim today'; END IF;

  -- Already played — hand back the stored result.
  IF v_row.draw_prize IS NOT NULL THEN
    SELECT reward_points INTO v_balance FROM public.profiles WHERE id = v_member;
    RETURN jsonb_build_object('ok', true, 'already_claimed', true,
      'prize', v_row.draw_prize, 'reward_points', coalesce(v_balance,0));
  END IF;

  -- Pick the winner uniformly from the 9 configured prizes.
  SELECT * INTO v_win FROM public.check_in_draw_prizes ORDER BY random() LIMIT 1;
  IF NOT FOUND THEN RAISE EXCEPTION 'No draw prizes configured'; END IF;

  -- Award it.
  IF v_win.reward_type = 'voucher'
     AND v_win.voucher_discount_type IS NOT NULL AND v_win.voucher_discount_value IS NOT NULL THEN
    v_expires := v_today + coalesce(v_win.voucher_valid_days, 30);
    LOOP
      v_try := v_try + 1; v_code := public.tc_random_code('DRAW');
      BEGIN
        INSERT INTO public.vouchers (code, discount_type, discount_value, member_id, expires_at, note, created_by)
        VALUES (v_code, v_win.voucher_discount_type, v_win.voucher_discount_value, v_member,
                v_expires, 'Check-in lucky draw', v_member);
        EXIT;
      EXCEPTION WHEN unique_violation THEN
        IF v_try >= 6 THEN RAISE EXCEPTION 'Could not allocate a voucher code'; END IF;
      END;
    END LOOP;
  ELSIF coalesce(v_win.points,0) > 0 THEN
    PERFORM set_config('app.tc_points_ctx', 'checkin', true);
    UPDATE public.profiles SET reward_points = reward_points + v_win.points
     WHERE id = v_member RETURNING reward_points INTO v_balance;
    PERFORM set_config('app.tc_points_ctx', '', true);
  END IF;
  IF v_balance IS NULL THEN SELECT reward_points INTO v_balance FROM public.profiles WHERE id = v_member; END IF;

  v_prize := jsonb_build_object(
    'slot', v_win.slot, 'reward_type', v_win.reward_type, 'label', v_win.label,
    'points', CASE WHEN v_win.reward_type = 'points' THEN coalesce(v_win.points,0) END,
    'voucher_discount_type',  CASE WHEN v_win.reward_type = 'voucher' THEN v_win.voucher_discount_type END,
    'voucher_discount_value', CASE WHEN v_win.reward_type = 'voucher' THEN v_win.voucher_discount_value END,
    'voucher_code', v_code, 'voucher_expires_at', v_expires
  );

  UPDATE public.check_ins
     SET draw_prize = v_prize,
         points_awarded = CASE WHEN v_win.reward_type = 'points' THEN coalesce(v_win.points,0) ELSE 0 END
   WHERE id = v_row.id;

  -- Board for the reveal: winner at the picked cell, the other 8 prizes elsewhere (random order).
  v_pos := 0;
  FOR r IN
    SELECT * FROM public.check_in_draw_prizes WHERE slot <> v_win.slot ORDER BY random()
  LOOP
    v_pos := v_pos + 1;
    IF v_pos = v_pick THEN v_pos := v_pos + 1; END IF;  -- skip the picked cell
    v_board := v_board || jsonb_build_object(
      'cell', v_pos, 'reward_type', r.reward_type, 'label', r.label,
      'points', CASE WHEN r.reward_type = 'points' THEN coalesce(r.points,0) END,
      'voucher_discount_type',  CASE WHEN r.reward_type = 'voucher' THEN r.voucher_discount_type END,
      'voucher_discount_value', CASE WHEN r.reward_type = 'voucher' THEN r.voucher_discount_value END
    );
  END LOOP;
  v_board := v_board || jsonb_build_object(
    'cell', v_pick, 'reward_type', v_win.reward_type, 'label', v_win.label,
    'points', CASE WHEN v_win.reward_type = 'points' THEN coalesce(v_win.points,0) END,
    'voucher_discount_type',  CASE WHEN v_win.reward_type = 'voucher' THEN v_win.voucher_discount_type END,
    'voucher_discount_value', CASE WHEN v_win.reward_type = 'voucher' THEN v_win.voucher_discount_value END
  );

  RETURN jsonb_build_object('ok', true, 'already_claimed', false,
    'picked', v_pick, 'prize', v_prize, 'board', v_board,
    'reward_points', coalesce(v_balance,0));
END;
$function$;

revoke all     on function public.daily_check_in()            from public, anon;
revoke all     on function public.claim_lucky_draw(integer)   from public, anon;
grant  execute on function public.daily_check_in()            to authenticated;
grant  execute on function public.claim_lucky_draw(integer)   to authenticated;
