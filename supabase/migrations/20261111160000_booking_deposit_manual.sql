-- ============================================================================
-- 2026-11-11 — Deposit is entered by admin per booking (no automatic amount)
--
--   Replaces the automatic deposit (trip deposit_per_pax / 30%) from
--   20261111140000. Now:
--     * bookings.deposit_amount = the deposit actually received, typed by
--       admin/staff on the booking; blank = not paid yet
--     * deposit_paid_at is stamped when an amount is entered
--     * balance_due_date is still worked out as departure - 3 months
--     * members still can't change any payment field
--   Clears the auto-calculated 30% amounts on bookings not marked paid.
--   trips.deposit_per_pax is no longer used (left in place, harmless).
--   Safe to run more than once.
-- ============================================================================

create or replace function public.booking_payment_plan()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
BEGIN
  -- Only admin/staff set payment fields; everyone else gets them worked out / kept
  IF NOT public.is_admin_or_staff() THEN
    IF TG_OP = 'INSERT' THEN
      NEW.deposit_amount := NULL; NEW.balance_due_date := NULL;
      NEW.deposit_paid_at := NULL; NEW.balance_paid_at := NULL;
    ELSE
      NEW.deposit_amount := OLD.deposit_amount; NEW.balance_due_date := OLD.balance_due_date;
      NEW.deposit_paid_at := OLD.deposit_paid_at; NEW.balance_paid_at := OLD.balance_paid_at;
    END IF;
  END IF;

  -- Balance is due 3 months before departure (follows departure date changes)
  IF NEW.departure_date IS NOT NULL AND (
       (TG_OP = 'INSERT' AND NEW.balance_due_date IS NULL)
    OR (TG_OP = 'UPDATE' AND NEW.departure_date IS DISTINCT FROM OLD.departure_date
        AND NEW.balance_due_date IS NOT DISTINCT FROM OLD.balance_due_date)) THEN
    NEW.balance_due_date := (NEW.departure_date - interval '3 months')::date;
  END IF;

  -- Deposit received = an amount entered; stamp when it was first entered
  IF COALESCE(NEW.deposit_amount, 0) > 0 THEN
    NEW.deposit_paid_at := COALESCE(NEW.deposit_paid_at, now());
  ELSE
    NEW.deposit_amount := NULL;
    NEW.deposit_paid_at := NULL;
  END IF;

  RETURN NEW;
END;
$function$;

-- Drop the auto-calculated amounts that were never marked as received.
-- (The trigger would keep old values for a non-admin SQL Editor session, so pause it.)
alter table public.bookings disable trigger booking_payment_plan;
update public.bookings
set deposit_amount = null
where deposit_paid_at is null and deposit_amount is not null;
alter table public.bookings enable trigger booking_payment_plan;
