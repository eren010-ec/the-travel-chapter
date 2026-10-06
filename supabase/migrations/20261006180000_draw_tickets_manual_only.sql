-- ============================================================================
-- Workstream Z (2026-10-06) — Lucky draw vouchers: manual only
--
-- Removes the automatic one-voucher-per-confirmed-booking trigger added in
-- 20261006160000_lucky_draw_tickets.sql. Lucky draw vouchers are now issued
-- only by admin/staff from the admin Vouchers page (source = 'manual').
-- Any vouchers already issued from bookings are left as they are.
--
-- Safe to run more than once.
-- ============================================================================

drop trigger if exists bookings_draw_ticket on public.bookings;
drop function if exists public.tc_booking_draw_ticket();
