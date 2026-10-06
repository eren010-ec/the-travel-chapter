-- ============================================================================
-- Workstream Z (2026-10-06) — Day-7 lucky draw: optional per-prize odds
--
-- check_in_draw_prizes.odds (nullable, 0–100) is the chance, in percent, that
-- a box's prize is the one won. It is optional:
--   * blank on every box      -> each box has an even 1-in-9 chance (as before)
--   * set on some boxes       -> those get exactly their %, and the blank boxes
--                                split whatever is left of 100% evenly
--   * set on every box        -> used as relative weights (scaled to 100%)
--   * 0                       -> the prize shows on the board but is never won
-- The admin UI keeps the set odds at or under 100% in total.
--
-- Safe to run more than once.
-- ============================================================================

alter table public.check_in_draw_prizes
  add column if not exists odds numeric(5,2);
alter table public.check_in_draw_prizes drop constraint if exists check_in_draw_prizes_odds_check;
alter table public.check_in_draw_prizes
  add constraint check_in_draw_prizes_odds_check check (odds is null or (odds >= 0 and odds <= 100));

-- ── draw_prize_chances(): effective % chance per box ────────────────────────
-- Single source of truth for the rule above; claim_lucky_draw() picks with it.
-- The admin page mirrors it in drawChances() — keep the two in sync.
create or replace function public.draw_prize_chances()
 returns table(slot integer, chance numeric)
 language sql
 stable
 security definer
 set search_path to 'public'
as $function$
  WITH p AS (
    SELECT d.slot, d.odds,
           coalesce(sum(d.odds) OVER (), 0)                   AS set_total,
           count(*) FILTER (WHERE d.odds IS NULL) OVER ()      AS blanks
    FROM public.check_in_draw_prizes d
  ), w AS (
    SELECT p.slot,
           CASE WHEN p.odds IS NOT NULL THEN p.odds
                ELSE greatest(100 - p.set_total, 0) / p.blanks END AS weight
    FROM p
  )
  SELECT w.slot,
         CASE WHEN sum(w.weight) OVER () > 0
              THEN round(w.weight * 100 / sum(w.weight) OVER (), 4)
              ELSE 0 END
  FROM w ORDER BY w.slot;
$function$;

revoke all on function public.draw_prize_chances() from public, anon, authenticated;

-- ── claim_lucky_draw(pick): weighted winner pick ─────────────────────────────
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
  v_pname   text;
  v_pts     integer := 0;
  v_prize   jsonb;
  v_board   jsonb := '[]'::jsonb;
  v_note    text;
  r         record;
  v_pos     integer;
  v_prof    public.profiles%ROWTYPE;
  v_r       numeric;
  v_slot    integer;
BEGIN
  IF v_member IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF v_pick < 1 OR v_pick > 9 THEN v_pick := 1 + floor(random()*9)::int; END IF;

  SELECT * INTO v_row FROM public.check_ins
  WHERE member_id = v_member AND check_in_date = v_today AND reward_kind = 'luckydraw';
  IF NOT FOUND THEN RAISE EXCEPTION 'No lucky draw to claim today'; END IF;

  IF v_row.draw_prize IS NOT NULL THEN
    SELECT reward_points INTO v_balance FROM public.profiles WHERE id = v_member;
    RETURN jsonb_build_object('ok', true, 'already_claimed', true,
      'prize', v_row.draw_prize, 'reward_points', coalesce(v_balance,0));
  END IF;

  -- Weighted pick (see public.draw_prize_chances). Falls back to an even 1-in-N
  -- if every prize works out to 0%.
  v_r := random();
  SELECT slot INTO v_slot FROM (
    SELECT slot, sum(chance) OVER (ORDER BY slot) AS cum, sum(chance) OVER () AS total
    FROM public.draw_prize_chances() WHERE chance > 0
  ) c WHERE c.cum > v_r * c.total ORDER BY c.cum LIMIT 1;
  IF v_slot IS NULL THEN
    SELECT slot INTO v_slot FROM public.check_in_draw_prizes ORDER BY random() LIMIT 1;
  END IF;
  SELECT * INTO v_win FROM public.check_in_draw_prizes WHERE slot = v_slot;
  IF NOT FOUND THEN RAISE EXCEPTION 'No draw prizes configured'; END IF;
  SELECT * INTO v_prof FROM public.profiles WHERE id = v_member;

  IF v_win.reward_type = 'product' AND v_win.product_id IS NOT NULL THEN
    SELECT name INTO v_pname FROM public.products WHERE id = v_win.product_id;
    IF v_pname IS NOT NULL THEN
      INSERT INTO public.product_requests
        (member_id, member_name, member_email, product_id, product_name,
         method, points_cost_snapshot, quantity, status, note)
      VALUES
        (v_member,
         nullif(trim(coalesce(v_prof.first_name,'') || ' ' || coalesce(v_prof.last_name,'')), ''),
         coalesce(v_prof.email, (SELECT email FROM auth.users WHERE id = v_member)),
         v_win.product_id, v_pname,
         'points', 0, 1, 'approved', 'Check-in lucky draw prize');
    END IF;

  ELSIF v_win.reward_type IN ('cash','trip_voucher','hotel_voucher')
        AND v_win.voucher_discount_value IS NOT NULL THEN
    v_note := CASE v_win.reward_type
                WHEN 'cash' THEN 'Cash reward'
                WHEN 'trip_voucher' THEN 'Trip voucher'
                ELSE 'Hotel voucher' END || ' — check-in lucky draw';
    v_expires := v_today + coalesce(v_win.voucher_valid_days, 30);
    LOOP
      v_try := v_try + 1; v_code := public.tc_random_code('DRAW');
      BEGIN
        INSERT INTO public.vouchers (code, discount_type, discount_value, member_id, expires_at, note, created_by)
        VALUES (v_code,
                coalesce(nullif(v_win.voucher_discount_type,''), 'fixed'),
                v_win.voucher_discount_value, v_member, v_expires, v_note, v_member);
        EXIT;
      EXCEPTION WHEN unique_violation THEN
        IF v_try >= 6 THEN RAISE EXCEPTION 'Could not allocate a voucher code'; END IF;
      END;
    END LOOP;

  ELSIF v_win.reward_type = 'points' AND coalesce(v_win.points,0) > 0 THEN
    v_pts := v_win.points;
    PERFORM set_config('app.tc_points_ctx', 'checkin', true);
    UPDATE public.profiles SET reward_points = reward_points + v_pts
     WHERE id = v_member RETURNING reward_points INTO v_balance;
    PERFORM set_config('app.tc_points_ctx', '', true);
  END IF;

  IF v_balance IS NULL THEN SELECT reward_points INTO v_balance FROM public.profiles WHERE id = v_member; END IF;

  v_prize := jsonb_build_object(
    'slot', v_win.slot, 'reward_type', v_win.reward_type, 'label', v_win.label,
    'points', CASE WHEN v_win.reward_type = 'points' THEN coalesce(v_win.points,0) END,
    'voucher_discount_type',  CASE WHEN v_win.reward_type IN ('cash','trip_voucher','hotel_voucher')
                                   THEN coalesce(nullif(v_win.voucher_discount_type,''),'fixed') END,
    'voucher_discount_value', CASE WHEN v_win.reward_type IN ('cash','trip_voucher','hotel_voucher')
                                   THEN v_win.voucher_discount_value END,
    'voucher_code', v_code, 'voucher_expires_at', v_expires,
    'product_id', CASE WHEN v_win.reward_type = 'product' THEN v_win.product_id END,
    'product_name', v_pname
  );

  UPDATE public.check_ins
     SET draw_prize = v_prize,
         points_awarded = CASE WHEN v_win.reward_type = 'points' THEN coalesce(v_win.points,0) ELSE 0 END
   WHERE id = v_row.id;

  -- Board for the reveal: winner at the picked cell, the other 8 elsewhere.
  v_pos := 0;
  FOR r IN SELECT * FROM public.check_in_draw_prizes WHERE slot <> v_win.slot ORDER BY random() LOOP
    v_pos := v_pos + 1;
    IF v_pos = v_pick THEN v_pos := v_pos + 1; END IF;
    v_board := v_board || jsonb_build_object(
      'cell', v_pos, 'reward_type', r.reward_type, 'label', r.label,
      'points', CASE WHEN r.reward_type = 'points' THEN coalesce(r.points,0) END,
      'voucher_discount_type',  CASE WHEN r.reward_type IN ('cash','trip_voucher','hotel_voucher')
                                     THEN coalesce(nullif(r.voucher_discount_type,''),'fixed') END,
      'voucher_discount_value', CASE WHEN r.reward_type IN ('cash','trip_voucher','hotel_voucher')
                                     THEN r.voucher_discount_value END,
      'product_name', CASE WHEN r.reward_type = 'product'
                           THEN (SELECT name FROM public.products WHERE id = r.product_id) END
    );
  END LOOP;
  v_board := v_board || jsonb_build_object(
    'cell', v_pick, 'reward_type', v_win.reward_type, 'label', v_win.label,
    'points', CASE WHEN v_win.reward_type = 'points' THEN coalesce(v_win.points,0) END,
    'voucher_discount_type',  CASE WHEN v_win.reward_type IN ('cash','trip_voucher','hotel_voucher')
                                   THEN coalesce(nullif(v_win.voucher_discount_type,''),'fixed') END,
    'voucher_discount_value', CASE WHEN v_win.reward_type IN ('cash','trip_voucher','hotel_voucher')
                                   THEN v_win.voucher_discount_value END,
    'product_name', v_pname
  );

  RETURN jsonb_build_object('ok', true, 'already_claimed', false,
    'picked', v_pick, 'prize', v_prize, 'board', v_board,
    'reward_points', coalesce(v_balance,0));
END;
$function$;

revoke all     on function public.claim_lucky_draw(integer) from public, anon;
grant  execute on function public.claim_lucky_draw(integer) to authenticated;
