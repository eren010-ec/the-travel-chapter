-- ============================================================================
-- Contact form submissions (public "Contact" page — contact.html)
--
--   * Anyone (anon) may submit a message.
--   * Only admins / staff may read the queue and mark rows handled.
--   * No email side-effect — staff work the queue in the admin panel.
--
-- Mirrors the RLS shape used by product_requests / products.
-- Safe to run more than once (guards on every object).
-- ============================================================================

create table if not exists public.contact_messages (
  id         uuid primary key default gen_random_uuid(),
  name       text not null   check (char_length(name)    between 1 and 200),
  email      text not null   check (char_length(email)   between 3 and 320),
  phone      text            check (phone is null or char_length(phone) <= 40),
  interest   text            check (interest is null or char_length(interest) <= 200),
  message    text not null   check (char_length(message) between 1 and 5000),
  status     text not null   default 'new'
                             check (status in ('new','read','handled','archived')),
  created_at timestamptz not null default now(),
  handled_by uuid references public.profiles(id),
  handled_at timestamptz
);

-- Added after first cut of this table — no-op if the column is already there.
alter table public.contact_messages
  add column if not exists interest text
  check (interest is null or char_length(interest) <= 200);

create index if not exists contact_messages_status_idx  on public.contact_messages(status);
create index if not exists contact_messages_created_idx on public.contact_messages(created_at desc);

alter table public.contact_messages enable row level security;

drop policy if exists "anyone: submit a contact message" on public.contact_messages;
drop policy if exists "admins: read contact messages"     on public.contact_messages;
drop policy if exists "admins: update contact messages"   on public.contact_messages;
drop policy if exists "admins: delete contact messages"   on public.contact_messages;

-- Public submit. status defaults to 'new' and handled_* default null; anon has no
-- SELECT/UPDATE/DELETE, so an open WITH CHECK is safe and avoids surprises when a
-- client asks for the inserted row back (RETURNING is checked against SELECT).
create policy "anyone: submit a contact message" on public.contact_messages
  for insert to anon, authenticated
  with check (true);

create policy "admins: read contact messages" on public.contact_messages
  for select using (public.is_admin_or_staff());

create policy "admins: update contact messages" on public.contact_messages
  for update using (public.is_admin_or_staff()) with check (public.is_admin_or_staff());

create policy "admins: delete contact messages" on public.contact_messages
  for delete using (public.is_admin());

grant insert on public.contact_messages to anon, authenticated;
grant select, update, delete on public.contact_messages to authenticated;
