-- ============================================================================
-- 2026-11-02 — Take booking points back when a confirmed booking is deleted
--
--   * Admin deleting a confirmed/completed booking deducts the points that
--     booking awarded (points_earned), same as cancelling it.
--   * Skipped when the delete is a cascade from deleting the whole member
--     (auth user -> profiles -> bookings). That runs through the admin-users
--     edge function with the service role, where protect_position_flags()
--     would reject the reward_points change and abort the member delete —
--     and the profile is being removed anyway.
--   * Balance may go negative, as with cancellations.
-- ============================================================================

create or replace function public.deduct_points_on_booking_delete()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
BEGIN
  -- pg_trigger_depth() > 1 means this delete came from an FK cascade
  IF pg_trigger_depth() = 1
     AND OLD.status IN ('confirmed', 'completed')
     AND COALESCE(OLD.points_earned, 0) <> 0 THEN
    UPDATE public.profiles
    SET reward_points = reward_points - OLD.points_earned
    WHERE id = OLD.member_id;
  END IF;
  RETURN OLD;
END;
$function$;

drop trigger if exists deduct_points_on_booking_delete on public.bookings;
create trigger deduct_points_on_booking_delete
  after delete on public.bookings
  for each row execute function public.deduct_points_on_booking_delete();
