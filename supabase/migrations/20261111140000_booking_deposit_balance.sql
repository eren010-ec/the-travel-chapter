-- ============================================================================
-- 2026-11-11 — Booking payments: deposit first, balance 3 months before the trip
--
--   trips.deposit_per_pax      RM deposit per traveller (blank = 30% of total)
--   bookings.deposit_amount    deposit owed when the booking is made
--   bookings.balance_due_date  departure_date - 3 months
--   bookings.deposit_paid_at / balance_paid_at   set by admin/staff when received
--
--   Worked out by a trigger, so members can't change the amounts or mark
--   anything as paid. If a booking is made less than 3 months before
--   departure, the deposit is the full amount (pay in full now).
--   Existing bookings get a due date + deposit amount; nothing is marked paid.
--   Safe to run more than once.
-- ============================================================================

alter table public.trips
  add column if not exists deposit_per_pax numeric(10,2);

alter table public.bookings
  add column if not exists deposit_amount   numeric(10,2),
  add column if not exists balance_due_date date,
  add column if not exists deposit_paid_at  timestamptz,
  add column if not exists balance_paid_at  timestamptz;

-- Backfill existing bookings (before the trigger exists)
update public.bookings
set balance_due_date = (departure_date - interval '3 months')::date
where balance_due_date is null and departure_date is not null;

update public.bookings
set deposit_amount = round(coalesce(total_usd, 0) * 0.30)
where deposit_amount is null;

create or replace function public.booking_payment_plan()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
DECLARE
  staff   boolean := public.is_admin_or_staff();
  per_pax numeric;
  recalc  boolean;
BEGIN
  -- Only admin/staff set payment fields; everyone else gets them worked out / kept
  IF NOT staff THEN
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

  -- Deposit: worked out on insert, and again if travellers/total change before it's paid
  -- (unless admin typed a different amount in the same save)
  recalc := NEW.deposit_amount IS NULL
    OR (TG_OP = 'UPDATE' AND NEW.deposit_paid_at IS NULL
        AND NEW.deposit_amount IS NOT DISTINCT FROM OLD.deposit_amount
        AND (NEW.num_travellers IS DISTINCT FROM OLD.num_travellers
          OR NEW.total_usd IS DISTINCT FROM OLD.total_usd));
  IF recalc THEN
    SELECT deposit_per_pax INTO per_pax FROM public.trips WHERE id = NEW.trip_id;
    IF NEW.balance_due_date IS NOT NULL AND NEW.balance_due_date <= current_date THEN
      NEW.deposit_amount := COALESCE(NEW.total_usd, 0);   -- under 3 months away: pay in full
    ELSIF per_pax > 0 THEN
      NEW.deposit_amount := LEAST(COALESCE(NEW.total_usd, 0), per_pax * COALESCE(NEW.num_travellers, 1));
    ELSE
      NEW.deposit_amount := ROUND(COALESCE(NEW.total_usd, 0) * 0.30);
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

drop trigger if exists booking_payment_plan on public.bookings;
create trigger booking_payment_plan
  before insert or update on public.bookings
  for each row execute function public.booking_payment_plan();
