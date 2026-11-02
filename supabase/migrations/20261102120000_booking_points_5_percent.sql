-- ============================================================================
-- 2026-11-02 — Confirmed bookings earn 5% of the trip price in points
--
--   * Was 1 point per RM (FLOOR(total_usd)); now ROUND(total_usd * 0.05),
--     a whole number (e.g. RM 2,990 -> 150 pts, RM 1,250 -> 63 pts).
--   * Also awards when admin/staff INSERT a booking already confirmed
--     ("Add Booking" with status Confirmed) — the old trigger only fired on
--     UPDATE, so those bookings earned nothing.
--   * Moving confirmed -> completed does not award a second time.
--   * Existing bookings / balances are NOT recalculated.
-- ============================================================================

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
    UPDATE public.profiles
    SET reward_points = reward_points + NEW.points_earned
    WHERE id = NEW.member_id;
  END IF;
  RETURN NEW;
END;
$function$;

-- The original trigger was created in the dashboard (name unknown, UPDATE only).
-- Drop whatever trigger runs this function and re-attach it for INSERT too.
do $$
declare t record;
begin
  for t in
    select tg.tgname from pg_trigger tg
    join pg_proc p on p.oid = tg.tgfoid
    where tg.tgrelid = 'public.bookings'::regclass
      and p.proname = 'award_points_on_confirm' and not tg.tgisinternal
  loop
    execute format('drop trigger %I on public.bookings', t.tgname);
  end loop;
end $$;

create trigger award_points_on_confirm
  before insert or update of status on public.bookings
  for each row execute function public.award_points_on_confirm();
