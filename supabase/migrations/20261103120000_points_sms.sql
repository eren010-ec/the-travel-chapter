-- ============================================================================
-- 2026-11-03 — SMS the member when points are topped up
--
-- Which credits send an SMS (user's choice):
--   * 'booking' — a confirmed booking's 5% award (award_points_on_confirm)
--   * 'admin'   — admin/staff raising reward_points by hand (member modal)
-- Daily check-in / lucky-draw credits run with app.tc_points_ctx = 'checkin'
-- and never send. Deductions never send.
--
-- Message (English, one SMS segment), e.g.:
--   RM 0.00 The Travel Chapter: 150 points have been added to your account
--   for your confirmed booking. New balance: 1234 points.
--
-- Flow: profiles AFTER UPDATE trigger -> row in sms_outbox -> pg_net POST to
-- the `points-sms` edge function (after commit) -> Twilio Messaging API ->
-- row marked sent/failed. The outbox doubles as the send log.
--
-- The edge function proves the call came from here with a random secret kept
-- in Vault (created below); it checks it via points_sms_secret_ok(), which only
-- service_role can execute — so no secret needs copying by hand.
-- ============================================================================

create extension if not exists pg_net;

-- ── 1. Outbox / send log ────────────────────────────────────────────────────
create table if not exists public.sms_outbox (
  id          bigint generated always as identity primary key,
  member_id   uuid references public.profiles(id) on delete cascade,
  phone       text not null,
  body        text not null,
  source      text not null check (source in ('booking', 'admin')),
  points      integer not null,
  status      text not null default 'queued' check (status in ('queued', 'sent', 'failed')),
  error       text,
  twilio_sid  text,
  created_at  timestamptz not null default now(),
  sent_at     timestamptz
);

alter table public.sms_outbox enable row level security;

drop policy if exists "staff read sms outbox" on public.sms_outbox;
create policy "staff read sms outbox" on public.sms_outbox
  for select using (public.is_admin_or_staff());

-- ── 2. Shared secret for the edge function call ────────────────────────────
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'points_sms_secret') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(24), 'hex'), 'points_sms_secret');
  end if;
end $$;

create or replace function public.points_sms_secret_ok(p_secret text)
 returns boolean
 language sql
 security definer
 set search_path to 'public'
as $function$
  select exists (
    select 1 from vault.decrypted_secrets
    where name = 'points_sms_secret' and decrypted_secret = p_secret
  );
$function$;

revoke all on function public.points_sms_secret_ok(text) from public, anon, authenticated;
grant execute on function public.points_sms_secret_ok(text) to service_role;

-- ── 3. Tag booking awards so the profiles trigger knows the source ────────
-- Same body as 20261102140000, plus app.tc_points_ctx = 'booking' around the credit.
create or replace function public.award_points_on_confirm()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
BEGIN
  -- Inserts only award when admin/staff add the booking — members always book
  -- as 'pending', and must not be able to self-insert a confirmed booking for points.
  IF NEW.status IN ('confirmed', 'completed')
     AND ((TG_OP = 'INSERT' AND public.is_admin_or_staff())
          OR (TG_OP = 'UPDATE' AND COALESCE(OLD.status, '') NOT IN ('confirmed', 'completed'))) THEN
    -- 5% of the booking total, rounded to a whole number of points
    NEW.points_earned := ROUND(COALESCE(NEW.total_usd, 0) * 0.05)::INTEGER;
    PERFORM set_config('app.tc_points_ctx', 'booking', true);
    UPDATE public.profiles
    SET reward_points = reward_points + NEW.points_earned
    WHERE id = NEW.member_id;
    PERFORM set_config('app.tc_points_ctx', '', true);
  ELSIF TG_OP = 'UPDATE'
     AND OLD.status IN ('confirmed', 'completed')
     AND NEW.status NOT IN ('confirmed', 'completed') THEN
    -- Cancelled (or moved back to pending): take back what this booking earned
    UPDATE public.profiles
    SET reward_points = reward_points - COALESCE(OLD.points_earned, 0)
    WHERE id = OLD.member_id;
    NEW.points_earned := 0;
  END IF;
  RETURN NEW;
END;
$function$;

-- ── 4. Queue an SMS when points go up from a booking or an admin ──────────
create or replace function public.queue_points_sms()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
DECLARE
  v_ctx    text := COALESCE(current_setting('app.tc_points_ctx', true), '');
  v_added  integer := NEW.reward_points - OLD.reward_points;
  v_source text;
BEGIN
  IF v_added <= 0 OR COALESCE(NEW.phone, '') = '' THEN RETURN NEW; END IF;
  IF v_ctx = 'booking' THEN
    v_source := 'booking';
  ELSIF v_ctx = '' AND public.is_admin_or_staff() THEN
    v_source := 'admin';
  ELSE
    RETURN NEW;  -- check-in / lucky draw, or anything else
  END IF;

  INSERT INTO public.sms_outbox (member_id, phone, body, source, points)
  VALUES (
    NEW.id, NEW.phone,
    -- Malaysian operators require the "RM 0.00" header and the brand name;
    -- no links or phone numbers (blocked since 2024-09).
    'RM 0.00 The Travel Chapter: ' || v_added || ' points have been added to your account'
      || CASE WHEN v_source = 'booking' THEN ' for your confirmed booking' ELSE '' END
      || '. New balance: ' || NEW.reward_points || ' points.',
    v_source, v_added
  );
  RETURN NEW;
END;
$function$;

drop trigger if exists queue_points_sms on public.profiles;
create trigger queue_points_sms
  after update of reward_points on public.profiles
  for each row execute function public.queue_points_sms();

-- ── 5. Hand each queued row to the edge function ─────────────────────────
-- pg_net sends after the transaction commits, so a rolled-back credit never texts.
create or replace function public.dispatch_points_sms()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
DECLARE
  v_secret text;
BEGIN
  SELECT decrypted_secret INTO v_secret FROM vault.decrypted_secrets WHERE name = 'points_sms_secret';
  IF v_secret IS NULL THEN RETURN NEW; END IF;  -- row stays 'queued'
  PERFORM net.http_post(
    url     := 'https://nkrpkfqibsudqsonljve.supabase.co/functions/v1/points-sms',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-points-sms-secret', v_secret),
    body    := jsonb_build_object('id', NEW.id)
  );
  RETURN NEW;
END;
$function$;

drop trigger if exists dispatch_points_sms on public.sms_outbox;
create trigger dispatch_points_sms
  after insert on public.sms_outbox
  for each row execute function public.dispatch_points_sms();
