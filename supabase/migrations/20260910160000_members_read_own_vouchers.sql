-- ============================================================================
-- Workstream Z (2026-09-10) — Member "My Vouchers" page (dashboard.html)
--
-- Vouchers are still applied by staff at booking time (not self-redeemed). The
-- member portal only needs to LIST a member's own codes, so add a permissive
-- SELECT policy scoped to member_id = auth.uid(). Admin/staff access is
-- unchanged (they read via get_admin_vouchers()).
--
-- Additive and idempotent — RLS policies are OR'd, so this only ever grants the
-- member read access to rows that are already theirs.
-- ============================================================================

alter table public.vouchers enable row level security;

drop policy if exists "members: read own vouchers" on public.vouchers;
create policy "members: read own vouchers" on public.vouchers
  for select to authenticated
  using (member_id = auth.uid());

grant select on public.vouchers to authenticated;
