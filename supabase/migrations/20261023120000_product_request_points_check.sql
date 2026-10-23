-- ============================================================================
-- 2026-10-23 — Members cannot request a points gift costing more than they have
--   available = profiles.reward_points − points held by their open
--   (pending / approved) points requests. Also re-checked when a member re-opens a
--   cancelled request. Staff/admin writes are exempt, and
--   0-cost rows (check-in / lucky-draw free gifts) always pass.
-- Safe to run more than once.
-- ============================================================================

create or replace function public.check_product_request_points()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
DECLARE
  cost      integer := coalesce(NEW.points_cost_snapshot, 0) * coalesce(NEW.quantity, 1);
  balance   integer;
  on_hold   integer;
BEGIN
  IF NEW.method <> 'points' OR cost <= 0 OR public.is_admin_or_staff()
     OR NEW.status NOT IN ('pending', 'approved') THEN
    RETURN NEW;
  END IF;
  -- An update that keeps an already-open request open was counted when it opened.
  IF TG_OP = 'UPDATE' AND OLD.status IN ('pending', 'approved') THEN
    RETURN NEW;
  END IF;

  -- Lock the member's profile row so two simultaneous requests can't both pass.
  SELECT reward_points INTO balance FROM public.profiles WHERE id = NEW.member_id FOR UPDATE;

  SELECT coalesce(sum(coalesce(points_cost_snapshot, 0) * quantity), 0) INTO on_hold
    FROM public.product_requests
   WHERE member_id = NEW.member_id
     AND method = 'points'
     AND status IN ('pending', 'approved')
     AND id <> NEW.id;

  IF cost > coalesce(balance, 0) - on_hold THEN
    RAISE EXCEPTION 'Not enough points: % available, % needed', greatest(coalesce(balance, 0) - on_hold, 0), cost;
  END IF;
  RETURN NEW;
END;
$function$;

drop trigger if exists product_requests_points_check on public.product_requests;
create trigger product_requests_points_check before insert or update on public.product_requests
  for each row execute function public.check_product_request_points();
