-- Members log in on login.html with phone + password, which matches auth.users.phone.
-- Accounts created from the admin panel before 2026-11-17 only had the phone saved on
-- profiles.phone (auth.users got a placeholder @thetravelchapter.internal email), so they
-- could never log in. Copy the profile phone onto the auth user and mark it confirmed.
--
-- Same normalisation as admin-users/index.ts: digits only, local "0…" -> "60…",
-- "600…" -> "60…". Skips admin/staff accounts, invalid numbers, and any number already
-- used by another auth user. Passwords are untouched.

with candidates as (
  select u.id,
         regexp_replace(
           regexp_replace(regexp_replace(p.phone, '\D', '', 'g'), '^0', '60'),
           '^600', '60') as norm_phone
  from auth.users u
  join public.profiles p on p.id = u.id
  where (u.phone is null or u.phone = '')
    and coalesce(p.phone, '') <> ''
    and not coalesce(p.is_admin, false)
    and not coalesce(p.is_staff, false)
)
update auth.users u
set phone = c.norm_phone,
    phone_confirmed_at = coalesce(u.phone_confirmed_at, now()),
    updated_at = now()
from candidates c
where u.id = c.id
  and c.norm_phone ~ '^[1-9][0-9]{7,14}$'
  and not exists (select 1 from auth.users o where o.phone = c.norm_phone and o.id <> c.id)
returning u.id, u.email, u.phone, u.phone_confirmed_at;
