-- ============================================================================
-- Workstream Z (2026-09-10) — Day-7 lucky draw: more prize types
--
-- check_in_draw_prizes.reward_type widens from ('points','voucher') to:
--   'points'        -> credits profiles.reward_points
--   'cash'          -> a fixed-RM public.vouchers row, note "Cash reward"
--   'trip_voucher'  -> a public.vouchers row (fixed or percent), note "Trip voucher"
--   'hotel_voucher' -> a public.vouchers row (fixed or percent), note "Hotel voucher"
--   'product'       -> an APPROVED public.product_requests row for the chosen
--                      product (0-cost), which staff then fulfil from the
--                      existing Redemption Requests queue.
--
-- The cash / trip / hotel prizes reuse the existing voucher_discount_type /
-- voucher_discount_value / voucher_valid_days columns. 'product' adds product_id.
--
-- Safe to run more than once.
-- ============================================================================

alter table public.check_in_draw_prizes drop constraint if exists check_in_draw_prizes_reward_type_check;
-- any pre-existing 'voucher' rows become 'cash' (same fixed-RM behaviour)
update public.check_in_draw_prizes set reward_type = 'cash' where reward_type = 'voucher';
alter table public.check_in_draw_prizes
  add constraint check_in_draw_prizes_reward_type_check
  check (reward_type in ('points','cash','trip_voucher','hotel_voucher','product'));

alter table public.check_in_draw_prizes
  add column if not exists product_id uuid references public.products(id) on delete set null;

-- ── claim_lucky_draw(pick): award any of the 5 prize types ──────────────────
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

  SELECT * INTO v_win FROM public.check_in_draw_prizes ORDER BY random() LIMIT 1;
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
