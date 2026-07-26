# The Travel Chapter — Progress Handoff

**For continuing in Claude Code on another machine.** This replaces the earlier draft version of this file — that draft described a *plan*; this describes what's actually built and verified live against the Supabase project as of 2026-07-21. Read this whole file before trusting old notes elsewhere (chat history, other machines' Claude memory, etc.) — none of that carries over to a new machine, this file is the only thing that does.

---

## Project snapshot

- **App:** The Travel Chapter — boutique travel agency web app, Malaysian market (currency MYR).
- **Frontend:** plain multi-page HTML/CSS/JS, no build step, no framework, no bundler. As of 2026-07-26, customer pages are at repo root and admin pages live under `admin/` (see PWA workstream below for why).
  - `index.html` — public landing page (reads CMS content live)
  - `login.html` — member login
  - `dashboard.html` — member dashboard
  - `admin/admin-login.html` — admin login
  - `admin/admin.html` — admin panel (members, bookings, users)
  - `admin/admin-cms.html` — admin CMS content editor
  - `the-travel-chapter-logo.jpg` — original full brand lockup (kept for reference, no longer directly linked from any page)
  - `the-travel-chapter-icon.png` — cropped, transparent-background icon graphic (favicon + navbar/sidebar icon on every page)
  - `icons/` — generated square PWA icons (customer = cream bg, admin = navy bg; standard + maskable + apple-touch variants)
  - `manifest-customer.json` / `sw-customer.js` (root) and `admin/manifest-admin.json` / `admin/sw-admin.js` — PWA installability layer, see below
  - `supabase/functions/admin-users/index.ts` — the one server-side piece (Deno edge function)
- **Backend:** Supabase project ref `nkrpkfqibsudqsonljve`, URL `https://nkrpkfqibsudqsonljve.supabase.co`. Free tier.
- **Hosting target:** Netlify, static site, publish directory = repo root, no build command. Edge function `ALLOWED_ORIGINS` in `admin-users/index.ts` is currently hardcoded to `https://thetravelchapter.netlify.app` — **update that array if the real Netlify site gets a different subdomain or a custom domain**, or admin-panel calls will get CORS-blocked in production.
- **Git/GitHub:** set up 2026-07-26. Git for Windows installed via winget (wasn't present before, and still isn't on PATH in fresh shells — invoke via full path `C:\Program Files\Git\bin\git.exe` until confirmed otherwise). Repo pushed to `https://github.com/eren010-ec/the-travel-chapter`, branch `main`. Note: this project lives on a network share (`Z:\...`), which needed a `git config --global --add safe.directory` exception (already applied). Interactive GitHub login (for push auth) doesn't work from inside a sandboxed Claude Code shell — do that once from a terminal opened outside Claude Code, then credentials are cached for subsequent pushes.

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

## Logo (updated 2026-07-26 — superseded the 2026-07-21 version below)

The logo and wordmark are now separate, everywhere:
- `the-travel-chapter-icon.png` — just the icon graphic (plane/globe/ship/mountains/train/book), cropped out of the original `the-travel-chapter-logo.jpg` lockup and made transparent-background. Used as favicon + navbar/sidebar icon image on all 6 pages.
- The "The Travel Chapter" / "TC Admin" text next to it is now real, separate DOM text (uppercase/bold/letter-spaced, gold), not baked into the image and not the old serif/italic "The *Travel* Chapter" styling.
- `icons/` holds further square, solid-background variants generated from `the-travel-chapter-icon.png` specifically for PWA app icons (see below) — cream background for the customer app, navy background for the admin app, so the two are visually distinct on a home screen.

Visually verified across index/login/admin-login at desktop size 2026-07-26; mobile breakpoints were checked by computing element widths against real phone sizes (320–400px) rather than live rendering, since the browser automation extension was not connected this session. Worth a live phone/narrow-browser check if anything looks off.

---

## Git / GitHub / Netlify — DONE (as of 2026-07-26)

Repo: `https://github.com/eren010-ec/the-travel-chapter`, branch `main`. Git for Windows installed via winget on this machine. See the Git/GitHub bullet in the project snapshot above for the path/auth quirks discovered while setting this up.

Netlify connection status: **not confirmed in this session** — if the site isn't already connected, use **Add new site → Import from Git**, pick the repo, leave build command blank, publish directory = `.` (repo root). If it *is* already connected and auto-deploying from `main`, note that the admin pages moved from repo root to `admin/` on 2026-07-26 (see PWA workstream) — any hardcoded links to `thetravelchapter.netlify.app/admin.html` etc. elsewhere (bookmarks, docs, the edge function's `ALLOWED_ORIGINS` check is origin-only so unaffected) need updating to `.../admin/admin-login.html`.

**What to include:** everything except `.claude/`. The Supabase key in the HTML is a publishable key (meant to be public) and the edge function has no hardcoded secrets — both are safe to commit. `supabase/` folder is optional to include (doesn't affect Netlify either way; the edge function deploys separately via `supabase functions deploy admin-users`, not through Netlify/GitHub at all).

**Remember to update `ALLOWED_ORIGINS`** in `supabase/functions/admin-users/index.ts` once you know the real Netlify URL, then redeploy the function.

---

## Workstream C — PWA / installable mobile apps (added 2026-07-26)

User asked to turn the site into installable Android + iOS apps, with separate customer and admin versions, as a downloadable package. Real constraint surfaced and agreed with the user up front: a genuine native `.ipa` can only be built and signed on macOS with Xcode — not possible from this Windows machine. User chose **PWA (Progressive Web App)** for both platforms instead: installable via the browser's "Add to Home Screen" / install prompt, no app store, no native build tooling required, works today.

What exists now:
- **Two separate installable identities** from the same codebase/origin: "The Travel Chapter" (customer: index/login/dashboard) and "TC Admin" (admin: admin/admin-login/admin-cms). Distinguished via each PWA manifest's `id` field, distinct `start_url`, distinct icons (cream vs navy bg), distinct names.
- Admin pages were **physically moved into an `admin/` subfolder** specifically so the admin service worker's scope (`/admin/`) is cleanly separated from the customer service worker's scope (`/`) — two service workers can't both cleanly own an overlapping scope if they're just sitting in the same flat directory. All relative links between the two apps were fixed accordingly (`../` prefixes for cross-links, root icon file, etc.).
- `manifest-customer.json` (root) / `admin/manifest-admin.json`, `sw-customer.js` (root) / `admin/sw-admin.js` — the service workers are deliberately simple: network-first with cache fallback for same-origin app-shell requests only, and they explicitly ignore any cross-origin request (`if (url.origin !== self.location.origin) return;`) so they never intercept or cache Supabase API calls, the Supabase CDN script, or Google Fonts.
- Every page registers its app's service worker on load.
- `index.html` and `admin/admin-login.html` each show a small dismissible "Install" banner: real `beforeinstallprompt`-driven Install button on Android/Chrome/Edge; falls back to "Tap Share → Add to Home Screen" instructions on iOS Safari (which has no programmatic install API); hides itself if already running standalone; dismissal is remembered in `localStorage` for 14 days.

**Testing note:** service workers require a secure context — `file://` will NOT let these register. Test via `npx serve` (or any `http://localhost` server) or the real HTTPS Netlify deployment. This session smoke-tested via a local server that every page/manifest/service-worker/icon URL resolves with a 200 and correct content-type, but did **not** verify the actual browser install prompt/flow live (no connected browser tooling this session) — worth doing a real install on an Android phone and an iPhone before calling this fully done.

**Not done / explicitly out of scope this pass:** a real native Android `.apk` via Capacitor (user chose PWA for both platforms instead — see chat for the tradeoffs discussed), and anything iOS-native (impossible without a Mac + Xcode).

---

## Workstream D — Admin on a separate domain (added 2026-07-26, same day)

User wants the admin panel unreachable/unguessable from the public customer site — not a replacement for real auth (Supabase `is_admin` checks are still the actual security boundary), but stops casual snooping/scanning of the main site's paths. Site is on the free `*.netlify.app` tier (no custom domain), so the plan is: **deploy `admin/` as its own separate Netlify site** (different repo-linked deployment, publish directory = `admin`), giving it a genuinely different, unlinked domain — not `/admin/` under the same site.

To make that possible, `admin/` was made **fully self-contained** (no more reaching outside its own folder):
- `the-travel-chapter-icon.png` and the admin-flavored PWA icons (`icon-admin-*.png`, `apple-touch-icon-admin.png`) were copied into `admin/` and `admin/icons/` respectively (small duplication of static images, intentional — the root copies are still used by the customer site).
- `admin/manifest-admin.json` and `admin/sw-admin.js` now reference those local copies (no `../`).
- Links from admin pages back to the customer site (`admin.html`'s unauthenticated redirect, "Back to Dashboard", `admin-login.html`'s "Go to Member Portal", `admin-cms.html`'s "Preview Landing Page" / "Preview Page") are now **absolute URLs** to `https://thetravelchapter.netlify.app/...` instead of `../...`, since relative paths can't cross a domain boundary.
- `supabase/functions/admin-users/index.ts`'s `ALLOWED_ORIGINS` now also includes `https://quietmeridian-4471.netlify.app` — the suggested name for the new admin-only Netlify site (user hadn't created it yet as of this write-up; **if the actual site ends up with a different name, update this array and redeploy the function**, or admin create/delete/update-user actions will get CORS-blocked).

**Manual steps still needed (none of this can be done from Claude Code without dashboard access):**
1. In Netlify: **Add new site → Import from Git** → same repo (`eren010-ec/the-travel-chapter`) → set **Publish directory** to `admin` (no build command) → deploy. Name the site `quietmeridian-4471` (or whatever was actually chosen — keep `ALLOWED_ORIGINS` above in sync).
2. Redeploy the `admin-users` edge function so the updated `ALLOWED_ORIGINS` takes effect: `supabase functions deploy admin-users` (Supabase CLI wasn't installed on this machine as of 2026-07-26).
3. Since the two apps are now on fully separate domains, the admin PWA's install banner / manifest / service worker only need to work standalone at that new domain — no further code change needed once deployed, but worth a real install test there too (see Workstream C testing note).
4. Old bookmarks/links to `thetravelchapter.netlify.app/admin-login.html` (pre-move) or `.../admin/admin-login.html` (the intermediate same-site-subfolder state, if that was ever deployed) will 404 — the only working admin URL going forward is the new separate site.

---

## Task checklist

- [x] Open all 6 pages in a real browser, confirm logo renders correctly (sizing/placement) — done 2026-07-26 at desktop size.
- [x] `git init` + first commit — done 2026-07-26.
- [x] Create GitHub repo, push — done, `eren010-ec/the-travel-chapter`.
- [ ] Confirm the customer site (repo root) is connected to Netlify and auto-deploying from `main` (not verified this session).
- [ ] Create the **second** Netlify site for `admin/` (Import from Git → same repo → publish directory `admin`) — see Workstream D. This is what actually makes the admin panel live; it is not served by the customer site at all anymore.
- [ ] Redeploy the `admin-users` edge function (`supabase functions deploy admin-users`) so the updated `ALLOWED_ORIGINS` (now includes the new admin site's origin) takes effect — needed before admin user-management actions will work on the new domain.
- [ ] Do a real install test on an Android phone (Chrome install prompt) and an iPhone ("Add to Home Screen") against both deployed HTTPS URLs — confirm the customer app and the admin app install as distinct home-screen apps with correct icons/names, and that offline app-shell loading works.
- [ ] Update any bookmarks/docs that pointed at the old `admin.html` / `admin-login.html` / `admin-cms.html` root-level URLs — the only working admin URL going forward is the new separate site.
- [ ] (Optional) `SET search_path = public` on the 3 flagged functions.
- [ ] (Optional) Enable leaked-password protection in Supabase Auth dashboard settings.
- [ ] (Optional, future) If a real native Android `.apk` is wanted later: wrap with Capacitor — requires installing Java JDK + Android SDK command-line tools on a build machine first.
- [ ] (Optional, future) If a real iOS app is wanted later: needs a Mac with Xcode (and an Apple Developer account to install on a physical device or ship to the App Store) — cannot be done from this Windows machine.
