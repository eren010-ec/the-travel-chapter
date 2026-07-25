# The Travel Chapter — Progress Handoff

**For continuing in Claude Code on another machine.** This replaces the earlier draft version of this file — that draft described a *plan*; this describes what's actually built and verified live against the Supabase project as of 2026-07-21. Read this whole file before trusting old notes elsewhere (chat history, other machines' Claude memory, etc.) — none of that carries over to a new machine, this file is the only thing that does.

---

## Project snapshot

- **App:** The Travel Chapter — boutique travel agency web app, Malaysian market (currency MYR).
- **Frontend:** plain multi-page HTML/CSS/JS, no build step, no framework, no bundler. Files live at repo root.
  - `index.html` — public landing page (reads CMS content live)
  - `login.html` — member login
  - `dashboard.html` — member dashboard
  - `admin-login.html` — admin login
  - `admin.html` — admin panel (members, bookings, users)
  - `admin-cms.html` — admin CMS content editor
  - `the-travel-chapter-logo.jpg` — brand logo (favicon + navbar/sidebar icon on every page)
  - `supabase/functions/admin-users/index.ts` — the one server-side piece (Deno edge function)
- **Backend:** Supabase project ref `nkrpkfqibsudqsonljve`, URL `https://nkrpkfqibsudqsonljve.supabase.co`. Free tier.
- **Hosting target:** Netlify, static site, publish directory = repo root, no build command. Edge function `ALLOWED_ORIGINS` in `admin-users/index.ts` is currently hardcoded to `https://thetravelchapter.netlify.app` — **update that array if the real Netlify site gets a different subdomain or a custom domain**, or admin-panel calls will get CORS-blocked in production.
- **Git/GitHub:** not yet set up as of 2026-07-21 — this machine doesn't have git installed. A `.gitignore` exists (excludes `.claude/`). Next step on whichever machine has git: `git init`, `git add .`, `git commit`, create a GitHub repo, push, then connect that repo in Netlify.

---

## Workstream A — Live CMS: DONE

Real table is `public.cms_content` (`section` text unique, `content` jsonb, `updated_at`, `updated_by` uuid → `auth.users`). NOT a generic key/value table — each row is a whole section's data as JSON.

- `admin-cms.html` saves via `sb.from('cms_content').upsert({section, content, updated_at}, {onConflict:'section'})`.
- `index.html` loads via `sb.from('cms_content').select('*')` in `loadCMS()`, then applies per-section with dedicated functions: `applyHero`, `applyDestinations`, `applyMembership`, `applyAbout`, `applyTestimonials`, `applyCta`, `applyContact`, `applyFooter`, `applyNavbar`.
- Sections: `hero`, `destinations`, `featured_trips`, `membership`, `about`, `testimonials`, `cta_banner`, `contact`, `footer`, `navbar`.
- **Confirmed populated** (2026-07-21, live `SELECT`) — all 10 sections have real seeded copy, last edited 2026-06-06. Not placeholder/empty.
- RLS on `cms_content`: public `SELECT` (`true`), admin-only `ALL` (write) gated on `profiles.is_admin = true`.

Nothing left to do here unless new sections are needed.

---

## Workstream B — Supabase security: DONE, verified live

- Admin flag: `public.profiles.is_admin` (boolean, default false).
- `supabase/functions/admin-users/index.ts` handles create/delete/update user actions with the service_role key **read from env var at runtime** (`Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')`) — never hardcoded, never shipped to the browser. It verifies the caller's session + `profiles.is_admin` before acting. `admin.html` calls this function for privileged actions instead of embedding the service role key anywhere.
- RLS is enabled on all 5 public tables (`profiles`, `destinations`, `trips`, `bookings`, `cms_content`). An `is_admin()` SECURITY DEFINER SQL function (with `SET search_path TO 'public'`) backs most of the admin-only policies.
- The old "admin views return empty list when RLS tightens" problem is solved with **`get_admin_bookings()` / `get_admin_members()`** — SECURITY DEFINER Postgres functions that check `is_admin()` internally (raise an exception if not admin) and only then `select * from` the underlying view, bypassing RLS *after* the check passes. `admin.html` calls these via `sb.rpc('get_admin_bookings')` / `sb.rpc('get_admin_members')` — not the raw views directly.
- Supabase Advisor (security), as of 2026-07-21 — all WARN-level, none critical:
  - `function_search_path_mutable` on `award_points_on_confirm`, `handle_new_user`, `set_updated_at` — low real risk (both SECURITY DEFINER ones fully-qualify `public.profiles` in their bodies) but cheap to fix: add `SET search_path = public` to each. **Not yet done.**
  - Several "SECURITY DEFINER executable by anon/authenticated" flags on `is_admin`, `get_admin_bookings`, `get_admin_members`, `handle_new_user`, `award_points_on_confirm` — expected/benign, see above.
  - `auth_leaked_password_protection` disabled — real, easy fix, but only doable from the Supabase **dashboard** (Auth settings), not SQL. **Not yet done.**

### Optional remaining follow-ups (neither urgent)
- [ ] Add `SET search_path = public` to `award_points_on_confirm`, `handle_new_user`, `set_updated_at`.
- [ ] Enable leaked-password protection in Supabase Auth settings (dashboard only).

---

## Supabase client key (important — this bit already broke once)

All 6 HTML pages construct their own Supabase client independently (no shared config file) — each has its own `SUPABASE_URL` / `SUPABASE_ANON` consts near the top of a `<script>` block. As of 2026-07-21 they all use the **publishable key**:

```
sb_publishable_8mbRk904S5zktFv6UIlRUg_gp1PFAWm
```

The project's *legacy* JWT anon key was found disabled (`get_publishable_keys` showed `disabled: true`) and had to be swapped out everywhere. **If auth/data calls ever start failing across the whole site at once, check Supabase → Project Settings → API for a newer active key before assuming it's a code bug** — this project's keys get rotated/disabled from the dashboard without anyone updating the HTML to match. There's no single place to fix it — all 6 files need the same edit.

---

## Logo (added 2026-07-21)

`the-travel-chapter-logo.jpg` (a full square badge: plane/ship/train/book art + Chinese characters + "THE TRAVEL CHAPTER" + tagline, white background) is wired into all 6 pages:
- Browser-tab favicon on every page (`<link rel="icon" type="image/jpeg" href="the-travel-chapter-logo.jpg">`).
- `index.html` / `login.html`: small ~32-34px icon to the left of the "The Travel Chapter" text in the navbar (`.nav-logo-img` class).
- `admin-login.html`: replaces the gear-emoji brand badge (`.brand-icon`).
- `dashboard.html` / `admin.html` / `admin-cms.html`: icon added to the sidebar header (`.sidebar-brand` / `.sb-header`).

Not yet visually verified in a real browser — file:// screenshots were blocked by the browser automation tool's URL restrictions (a hardcoded tool limitation, not fixed by the OS-level "allow file URLs" extension permission). **Open `index.html` (and the other 5 pages) directly in a browser and eyeball the logo placement/sizing before considering this fully done.**

---

## Git / GitHub / Netlify — not started yet

This machine has no git installed (checked 2026-07-21 — not on PATH, not in common install locations). A `.gitignore` was created (excludes `.claude/` only). Steps once on a machine with git:

```
git init
git add .
git commit -m "Initial commit"
```
Create an empty GitHub repo (no README/gitignore from GitHub's side, to avoid conflicts), then:
```
git remote add origin https://github.com/<you>/<repo>.git
git branch -M main
git push -u origin main
```
In Netlify: **Add new site → Import from Git**, pick the repo, leave build command blank, publish directory = `.` (repo root).

**What to include:** everything except `.claude/`. The Supabase key in the HTML is a publishable key (meant to be public) and the edge function has no hardcoded secrets — both are safe to commit. `supabase/` folder is optional to include (doesn't affect Netlify either way; the edge function deploys separately via `supabase functions deploy admin-users`, not through Netlify/GitHub at all).

**Remember to update `ALLOWED_ORIGINS`** in `supabase/functions/admin-users/index.ts` once you know the real Netlify URL, then redeploy the function.

---

## Task checklist

- [ ] Open all 6 pages in a real browser, confirm logo renders correctly (sizing/placement).
- [ ] `git init` + first commit (needs a machine with git installed).
- [ ] Create GitHub repo, push.
- [ ] Connect repo to Netlify, deploy.
- [ ] Update `ALLOWED_ORIGINS` in `admin-users/index.ts` to match the real Netlify URL, redeploy the edge function via Supabase CLI/dashboard.
- [ ] (Optional) `SET search_path = public` on the 3 flagged functions.
- [ ] (Optional) Enable leaked-password protection in Supabase Auth dashboard settings.
