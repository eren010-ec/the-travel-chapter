-- ============================================================================
-- Workstream Z (2026-10-06) — Lucky draw vouchers (earned by spending)
--
--   * lucky_draw_tickets: one row = one play of the 3x3 lucky-draw game (the
--     same game, prizes and odds as check-in Day 7).
--       source 'booking' -> issued automatically when a booking becomes
--                           confirmed/completed (one per booking, booking_ref
--                           unique); removed again if that booking is
--                           cancelled before the ticket is played.
--       source 'manual'  -> given by admin/staff from the admin panel.
--     Members can read their own tickets; only admins/staff write them.
--   * tc_draw_award(member, pick, source): the prize pick + award + reveal
--     board, factored out of claim_lucky_draw() so both entry points share it.
--     Not callable by clients.
--   * claim_lucky_draw(pick): unchanged behaviour (check-in Day 7).
--   * play_draw_ticket(ticket, pick): plays one unused ticket.
--
-- Existing bookings are NOT backfilled — tickets start from the next confirmation.
-- Safe to run more than once.
-- ============================================================================

-- ── 1. tickets ──────────────────────────────────────────────────────────────
create table if not exists public.lucky_draw_tickets (
  id          uuid primary key default gen_random_uuid(),
  member_id   uuid not null references public.profiles(id) on delete cascade,
  source      text not null check (source in ('booking','manual')),
  booking_ref text unique,           -- bookings.id as text (source = 'booking')
  note        text,
  created_by  uuid references public.profiles(id) on delete set null,
  created_at  timestamptz not null default now(),
  used_at     timestamptz,
  prize       jsonb
);
create index if not exists lucky_draw_tickets_member_idx on public.lucky_draw_tickets(member_id);

alter table public.lucky_draw_tickets enable row level security;
drop policy if exists "members: read own draw tickets" on public.lucky_draw_tickets;
drop policy if exists "admins: manage draw tickets"    on public.lucky_draw_tickets;
create policy "members: read own draw tickets" on public.lucky_draw_tickets
  for select to authenticated using (member_id = auth.uid() or public.is_admin_or_staff());
create policy "admins: manage draw tickets" on public.lucky_draw_tickets
  for all to authenticated using (public.is_admin_or_staff()) with check (public.is_admin_or_staff());
grant select, insert, update, delete on public.lucky_draw_tickets to authenticated;

-- ── 2. bookings -> tickets ──────────────────────────────────────────────────
create or replace function public.tc_booking_draw_ticket()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
BEGIN
  IF NEW.member_id IS NULL THEN RETURN NEW; END IF;
  IF NEW.status IN ('confirmed','completed') THEN
    INSERT INTO public.lucky_draw_tickets (member_id, source, booking_ref, note)
    VALUES (NEW.member_id, 'booking', NEW.id::text, 'Booking confirmed')
    ON CONFLICT (booking_ref) DO NOTHING;
  ELSIF NEW.status = 'cancelled' THEN
    DELETE FROM public.lucky_draw_tickets
     WHERE booking_ref = NEW.id::text AND used_at IS NULL;
  END IF;
  RETURN NEW;
END;
$function$;

drop trigger if exists bookings_draw_ticket on public.bookings;
create trigger bookings_draw_ticket
  after insert or update of status on public.bookings
  for each row execute function public.tc_booking_draw_ticket();

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
      INSERT INTO public.product_requests
        (member_id, member_name, member_email, product_id, product_name,
         method, points_cost_snapshot, quantity, status, note)
      VALUES
        (p_member,
         nullif(trim(coalesce(v_prof.first_name,'') || ' ' || coalesce(v_prof.last_name,'')), ''),
         coalesce(v_prof.email, (SELECT email FROM auth.users WHERE id = p_member)),
         v_win.product_id, v_pname,
         'points', 0, 1, 'approved', p_source || ' lucky draw prize');
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
    'product_name', v_pname
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

-- ── 4. claim_lucky_draw(pick): check-in Day 7, now via tc_draw_award ─────────
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
  v_balance integer;
  v_res     jsonb;
BEGIN
  IF v_member IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT * INTO v_row FROM public.check_ins
  WHERE member_id = v_member AND check_in_date = v_today AND reward_kind = 'luckydraw'
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'No lucky draw to claim today'; END IF;

  IF v_row.draw_prize IS NOT NULL THEN
    SELECT reward_points INTO v_balance FROM public.profiles WHERE id = v_member;
    RETURN jsonb_build_object('ok', true, 'already_claimed', true,
      'prize', v_row.draw_prize, 'reward_points', coalesce(v_balance,0));
  END IF;

  v_res := public.tc_draw_award(v_member, pick, 'Check-in');

  UPDATE public.check_ins
     SET draw_prize = v_res->'prize',
         points_awarded = coalesce((v_res->'prize'->>'points')::int, 0)
   WHERE id = v_row.id;

  RETURN v_res || jsonb_build_object('ok', true, 'already_claimed', false);
END;
$function$;

revoke all     on function public.claim_lucky_draw(integer) from public, anon;
grant  execute on function public.claim_lucky_draw(integer) to authenticated;

-- ── 5. play_draw_ticket(ticket, pick) ───────────────────────────────────────
create or replace function public.play_draw_ticket(p_ticket uuid, pick integer default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
DECLARE
  v_member  uuid := auth.uid();
  v_t       public.lucky_draw_tickets%ROWTYPE;
  v_balance integer;
  v_res     jsonb;
BEGIN
  IF v_member IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT * INTO v_t FROM public.lucky_draw_tickets
  WHERE id = p_ticket AND member_id = v_member
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Lucky draw voucher not found'; END IF;

  IF v_t.used_at IS NOT NULL THEN
    SELECT reward_points INTO v_balance FROM public.profiles WHERE id = v_member;
    RETURN jsonb_build_object('ok', true, 'already_claimed', true,
      'prize', v_t.prize, 'reward_points', coalesce(v_balance,0));
  END IF;

  v_res := public.tc_draw_award(v_member, pick, 'Voucher');

  UPDATE public.lucky_draw_tickets
     SET used_at = now(), prize = v_res->'prize'
   WHERE id = v_t.id;

  RETURN v_res || jsonb_build_object('ok', true, 'already_claimed', false);
END;
$function$;

revoke all     on function public.play_draw_ticket(uuid, integer) from public, anon;
grant  execute on function public.play_draw_ticket(uuid, integer) to authenticated;
