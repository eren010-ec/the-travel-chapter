-- ============================================================================
-- 2026-11-03 — Remove the points-top-up SMS (20261103120000_points_sms)
--
-- User decided against it: Twilio can't send from a Malaysian number and an
-- overseas sender costs ~US$0.34 per SMS. SMS stays for login/reset codes
-- (Twilio Verify) only. The points-sms edge function was never deployed.
--
-- Kept: award_points_on_confirm() still sets app.tc_points_ctx = 'booking'
-- around its credit — harmless (protect_position_flags only reacts to
-- 'checkin') and ready if notifications come back.
-- ============================================================================

drop trigger if exists queue_points_sms on public.profiles;
drop function if exists public.queue_points_sms();

drop trigger if exists dispatch_points_sms on public.sms_outbox;
drop function if exists public.dispatch_points_sms();

drop table if exists public.sms_outbox;

drop function if exists public.points_sms_secret_ok(text);
delete from vault.secrets where name = 'points_sms_secret';

-- Installed only for this feature
drop extension if exists pg_net;
