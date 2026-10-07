-- ============================================================================
-- Workstream Z (2026-10-07) — 3x3 lucky draw free gifts: validity period
--
--   * check_in_draw_prizes.voucher_valid_days is now also used by 'product'
--     boxes: NULL = the gift never expires, N = valid for N days from the win.
--   * product_requests.expires_at (date, nullable): last day staff will hand
--     the gift over (Asia/Kuala_Lumpur). Only set on lucky-draw gifts.
--     Members cannot change it (trigger below).
--   * tc_draw_award(): sets expires_at on the gift row and returns it as
--     prize.product_expires_at.
--
-- Safe to run more than once.
-- ============================================================================

alter table public.product_requests add column if not exists expires_at date;

create or replace function public.tc_product_request_guard_expiry()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
BEGIN
  IF NOT public.is_admin_or_staff() THEN
    NEW.expires_at := OLD.expires_at;
  END IF;
  RETURN NEW;
END;
$function$;

drop trigger if exists product_requests_guard_expiry on public.product_requests;
create trigger product_requests_guard_expiry
  before update on public.product_requests
  for each row execute function public.tc_product_request_guard_expiry();

-- ── 3. shared prize award ───────────────────────────────────────────────────
create or replace function public.tc_draw_award(p_member uuid, pick integer, p_source text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
DECLARE
  v_win     public.check_in_draw_prizes%ROWTYPE;
  v_pick    integer := coalesce(pick, 1 + floor(random()*9)::int);
  v_balance integer;
  v_code    text;
  v_expires date;
  v_today   date := (now() AT TIME ZONE 'Asia/Kuala_Lumpur')::date;
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
  v_gift_exp date;
BEGIN
  IF v_pick < 1 OR v_pick > 9 THEN v_pick := 1 + floor(random()*9)::int; END IF;

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
  SELECT * INTO v_prof FROM public.profiles WHERE id = p_member;

  IF v_win.reward_type = 'product' AND v_win.product_id IS NOT NULL THEN
    SELECT name INTO v_pname FROM public.products WHERE id = v_win.product_id;
    IF v_pname IS NOT NULL THEN
      IF v_win.voucher_valid_days IS NOT NULL THEN
        v_gift_exp := v_today + v_win.voucher_valid_days;
      END IF;
      INSERT INTO public.product_requests
        (member_id, member_name, member_email, product_id, product_name,
         method, points_cost_snapshot, quantity, status, note, expires_at)
      VALUES
        (p_member,
         nullif(trim(coalesce(v_prof.first_name,'') || ' ' || coalesce(v_prof.last_name,'')), ''),
         coalesce(v_prof.email, (SELECT email FROM auth.users WHERE id = p_member)),
         v_win.product_id, v_pname,
         'points', 0, 1, 'approved', p_source || ' lucky draw prize', v_gift_exp);
    END IF;

  ELSIF v_win.reward_type IN ('cash','trip_voucher','hotel_voucher')
        AND v_win.voucher_discount_value IS NOT NULL THEN
    v_note := CASE v_win.reward_type
                WHEN 'cash' THEN 'Cash reward'
                WHEN 'trip_voucher' THEN 'Trip voucher'
                ELSE 'Hotel voucher' END || ' — ' || lower(p_source) || ' lucky draw';
    v_expires := v_today + coalesce(v_win.voucher_valid_days, 30);
    LOOP
      v_try := v_try + 1; v_code := public.tc_random_code('DRAW');
      BEGIN
        INSERT INTO public.vouchers (code, discount_type, discount_value, member_id, expires_at, note, created_by)
        VALUES (v_code,
                coalesce(nullif(v_win.voucher_discount_type,''), 'fixed'),
                v_win.voucher_discount_value, p_member, v_expires, v_note, p_member);
        EXIT;
      EXCEPTION WHEN unique_violation THEN
        IF v_try >= 6 THEN RAISE EXCEPTION 'Could not allocate a voucher code'; END IF;
      END;
    END LOOP;

  ELSIF v_win.reward_type = 'points' AND coalesce(v_win.points,0) > 0 THEN
    v_pts := v_win.points;
    PERFORM set_config('app.tc_points_ctx', 'checkin', true);
    UPDATE public.profiles SET reward_points = reward_points + v_pts
     WHERE id = p_member RETURNING reward_points INTO v_balance;
    PERFORM set_config('app.tc_points_ctx', '', true);
  END IF;

  IF v_balance IS NULL THEN SELECT reward_points INTO v_balance FROM public.profiles WHERE id = p_member; END IF;

  v_prize := jsonb_build_object(
    'slot', v_win.slot, 'reward_type', v_win.reward_type, 'label', v_win.label,
    'points', CASE WHEN v_win.reward_type = 'points' THEN coalesce(v_win.points,0) END,
    'voucher_discount_type',  CASE WHEN v_win.reward_type IN ('cash','trip_voucher','hotel_voucher')
                                   THEN coalesce(nullif(v_win.voucher_discount_type,''),'fixed') END,
    'voucher_discount_value', CASE WHEN v_win.reward_type IN ('cash','trip_voucher','hotel_voucher')
                                   THEN v_win.voucher_discount_value END,
    'voucher_code', v_code, 'voucher_expires_at', v_expires,
    'product_id', CASE WHEN v_win.reward_type = 'product' THEN v_win.product_id END,
    'product_name', v_pname,
    'product_expires_at', v_gift_exp
  );


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


  RETURN jsonb_build_object('picked', v_pick, 'prize', v_prize, 'board', v_board,
    'reward_points', coalesce(v_balance,0));
END;
$function$;

revoke all on function public.tc_draw_award(uuid, integer, text) from public, anon, authenticated;

notify pgrst, 'reload schema';
