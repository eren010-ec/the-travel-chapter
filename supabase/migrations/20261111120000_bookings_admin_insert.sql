-- ============================================================================
-- 2026-11-11 — Let admin/staff insert bookings for any member
--
--   Admin "Add Booking" inserts rows with member_id = the picked member, not
--   the admin's own id, so the members' own insert policy (member_id =
--   auth.uid()) rejects it: "new row violates row-level security policy for
--   table bookings". This adds a separate INSERT policy for admin/staff.
--   Policies are OR'ed, so members' own booking rules are unchanged.
--   Safe to run more than once.
-- ============================================================================

drop policy if exists "admin staff insert bookings" on public.bookings;

create policy "admin staff insert bookings"
  on public.bookings
  for insert
  to authenticated
  with check (public.is_admin_or_staff());
