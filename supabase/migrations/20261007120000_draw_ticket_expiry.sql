-- ============================================================================
-- Workstream Z (2026-10-07) — Lucky draw vouchers: valid-until date
--
--   * lucky_draw_tickets.expires_at (date, nullable): last day the voucher can
--     be played (Asia/Kuala_Lumpur). NULL = no expiry (all existing vouchers).
--   * play_draw_ticket(ticket, pick): refuses an unused voucher past its date.
--
-- Safe to run more than once.
-- ============================================================================

alter table public.lucky_draw_tickets add column if not exists expires_at date;

create or replace function public.play_draw_ticket(p_ticket uuid, pick integer default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
DECLARE
  v_member  uuid := auth.uid();
  v_today   date := (now() AT TIME ZONE 'Asia/Kuala_Lumpur')::date;
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

  IF v_t.expires_at IS NOT NULL AND v_t.expires_at < v_today THEN
    RAISE EXCEPTION 'This Lucky Draw voucher has expired';
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
