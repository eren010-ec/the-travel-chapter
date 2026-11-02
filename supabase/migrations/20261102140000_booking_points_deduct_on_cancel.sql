-- ============================================================================
-- 2026-11-02 — Take booking points back when a confirmed booking is cancelled
--
--   * Leaving confirmed/completed (-> cancelled, or back to pending) deducts
--     exactly the points that booking awarded (points_earned), then zeroes it.
--     So re-confirming later awards once again — never twice.
--   * Older bookings awarded at 1 pt/RM get those same points deducted.
--   * The balance may go negative if the member already spent the points;
--     the product-request points check then blocks redemptions until it
--     recovers. (profiles has no reward_points >= 0 constraint.)
--   * Trigger attachment is unchanged (BEFORE INSERT OR UPDATE OF status).
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
