-- ============================================================================
-- Workstream T (2026-08-27) — Member "Rewards Store"
--   * profiles.reward_points  : a spendable points balance, separate from
--                               tier_points (spending it must NOT affect tier standing)
--   * products                : admin/staff-managed catalogue (points cost and/or MYR price)
--   * product_requests        : member redemption / purchase requests, fulfilled MANUALLY
--                               by staff (no automatic points deduction)
--
-- Safe to run more than once (guards on every object).
-- Images reuse the existing public `trip-images` bucket, folder `products/`
-- (same pattern as trip covers and the Free Gifts page).
-- ============================================================================

-- ── 1. Separate redeemable-points balance ───────────────────────────────────
alter table public.profiles
  add column if not exists reward_points integer not null default 0;

-- Guard reward_points the same way tier / tier_points are already guarded:
-- members may PATCH their own profiles row (policy "update own profile" has no
-- WITH CHECK), so a trigger is the thing that actually stops them editing it.
create or replace function public.protect_position_flags()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
BEGIN
  IF NOT public.is_admin() THEN
    IF NEW.is_admin IS DISTINCT FROM OLD.is_admin OR NEW.is_staff IS DISTINCT FROM OLD.is_staff THEN
      RAISE EXCEPTION 'Only admins can change admin/staff position';
    END IF;
  END IF;
  IF NOT public.is_admin_or_staff() THEN
    IF NEW.tier IS DISTINCT FROM OLD.tier
       OR NEW.tier_points IS DISTINCT FROM OLD.tier_points
       OR NEW.reward_points IS DISTINCT FROM OLD.reward_points THEN
      RAISE EXCEPTION 'Only admins/staff can change membership tier or points';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

-- ── 2. Products catalogue ──────────────────────────────────────────────────
create table if not exists public.products (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  description  text,
  image_url    text,
  points_cost  integer       check (points_cost is null or points_cost >= 0),
  price_myr    numeric(10,2) check (price_myr  is null or price_myr  >= 0),
  is_active    boolean not null default true,
  sort_order   integer not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

drop trigger if exists products_updated_at on public.products;
create trigger products_updated_at before update on public.products
  for each row execute function public.set_updated_at();

alter table public.products enable row level security;

drop policy if exists "public: read active products"  on public.products;
drop policy if exists "admins: insert products"        on public.products;
drop policy if exists "admins: update products"        on public.products;
drop policy if exists "admins: delete products"        on public.products;

create policy "public: read active products" on public.products
  for select using (is_active = true or public.is_admin_or_staff());
create policy "admins: insert products" on public.products
  for insert with check (public.is_admin_or_staff());
create policy "admins: update products" on public.products
  for update using (public.is_admin_or_staff()) with check (public.is_admin_or_staff());
create policy "admins: delete products" on public.products
  for delete using (public.is_admin_or_staff());

-- ── 3. Member redemption / purchase requests ──────────────────────────────
-- Fulfilment is entirely manual: staff read the queue, hand over the item, and
-- (if paid in points) adjust the member's reward_points from the member modal.
-- member_name / member_email / product_name are stored as snapshots so the
-- admin queue needs no joins and the record survives a product being deleted.
create table if not exists public.product_requests (
  id                   uuid primary key default gen_random_uuid(),
  member_id            uuid not null references public.profiles(id) on delete cascade,
  member_name          text,
  member_email         text,
  product_id           uuid references public.products(id) on delete set null,
  product_name         text not null,
  method               text not null check (method in ('points','cash')),
  points_cost_snapshot integer,
  price_snapshot       numeric(10,2),
  quantity             integer not null default 1 check (quantity between 1 and 99),
  note                 text,
  status               text not null default 'pending'
                       check (status in ('pending','approved','fulfilled','rejected','cancelled')),
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  handled_by           uuid references public.profiles(id),
  handled_at           timestamptz
);

create index if not exists product_requests_member_idx on public.product_requests(member_id);
create index if not exists product_requests_status_idx on public.product_requests(status);

drop trigger if exists product_requests_updated_at on public.product_requests;
create trigger product_requests_updated_at before update on public.product_requests
  for each row execute function public.set_updated_at();

alter table public.product_requests enable row level security;

drop policy if exists "members: read own product requests"   on public.product_requests;
drop policy if exists "members: create own product requests" on public.product_requests;
drop policy if exists "members: cancel own product requests" on public.product_requests;
drop policy if exists "admins: manage product requests"      on public.product_requests;

create policy "members: read own product requests" on public.product_requests
  for select using (member_id = auth.uid() or public.is_admin_or_staff());
create policy "members: create own product requests" on public.product_requests
  for insert with check (member_id = auth.uid() and status = 'pending');
-- lets a member cancel (or leave pending) their own row; they cannot self-approve/fulfil
create policy "members: cancel own product requests" on public.product_requests
  for update using (member_id = auth.uid())
  with check (member_id = auth.uid() and status in ('pending','cancelled'));
create policy "admins: manage product requests" on public.product_requests
  for all using (public.is_admin_or_staff()) with check (public.is_admin_or_staff());

-- ── 4. Surface reward_points to the admin panel ──────────────────────────────
-- admin_members is consumed by get_admin_members() (SETOF admin_members,
-- `select *`); appending a column flows through automatically. CREATE OR REPLACE
-- keeps the existing REVOKE grants from lock_down_admin_views.
create or replace view public.admin_members as
 SELECT p.id,
    p.first_name,
    p.last_name,
    p.tier,
    p.tier_points,
    p.is_admin,
    p.joined_at,
    u.email,
    count(b.id) AS total_bookings,
    COALESCE(sum(b.total_usd), 0::numeric) AS total_spent,
    p.is_staff,
    p.phone,
    p.date_of_birth,
    p.nationality,
    p.passport_no,
    p.email AS contact_email,
    p.reward_points
   FROM profiles p
     JOIN auth.users u ON u.id = p.id
     LEFT JOIN bookings b ON b.member_id = p.id
  GROUP BY p.id, p.first_name, p.last_name, p.tier, p.tier_points, p.is_admin,
           p.joined_at, u.email, p.is_staff, p.phone, p.date_of_birth,
           p.nationality, p.passport_no, p.email, p.reward_points;
