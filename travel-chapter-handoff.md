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

## Workstream E — Homepage hero/destinations replaced with a book-chapter scroll journey (added 2026-08-01)

User asked for the index page to "move when you scroll," iterated through a few directions (iCAUR-style parallax → travel-journal-with-flying-plane → curvy SVG flight path + real photos), and landed on: **a pinned, book-styled scrollytelling section that tells The Travel Chapter's own founding story**, using the 5 destinations as real narrative milestones rather than a plain showcase grid. Pushed to `main` and live (commit `3f49478`, on top of `f91c6a6` which just added `.netlify` to `.gitignore`).

**What changed structurally:** the old `<section class="hero" id="hero">` and `<section id="destinations">` were deleted entirely and replaced by one new section:

```html
<section class="journal" id="journal">
  <div class="journal-sticky">          <!-- position:sticky; height:100vh; pins in viewport -->
    <div class="journal-stop journal-stop-intro">...</div>      <!-- "Prologue" -->
    <div id="journal-dest-stops">...5x .journal-stop-dest...</div>  <!-- "Chapters One–Five" -->
    <div class="journal-stop journal-stop-outro">...</div>      <!-- "Epilogue" -->
    <div class="journal-tabs" id="journal-tabs">...</div>       <!-- I–V click-to-jump indicator -->
  </div>
</section>
```

- `.journal` is `height: <N-stops>*100vh` (currently 700vh for 7 stops: intro + 5 + outro), computed and set dynamically by `initJournal()` in JS (not hardcoded), so if the destinations count ever changes via CMS the section height keeps up.
- Each `.journal-stop` is `position:absolute; inset:0; opacity:0` and gets its opacity driven continuously by scroll progress in `updateScrollEffects()` — a crossfade window of `Math.abs(dist)/0.65` (see JS below). **Important gotcha already fixed once:** a window of `/0.5` leaves a one-point gap where two adjacent stops both hit exactly 0 opacity at the midpoint (a visible flash-to-black). Don't shrink that denominator back below ~0.6 without retesting the transition midpoints.
- Prologue/epilogue are styled as navy "book cover" pages (gold-framed border via `::before`, reusing the site's existing navy/gold palette). The 5 chapter pages are cream "paper" pages: a huge, near-invisible (`opacity:0.045`) roman-numeral watermark (`.chapter-numeral`), a tilted "pasted-in" photo (`.chapter-photo`, alternates rotate direction via `:nth-child(even)`), a dashed "Chapter One/Two/…" badge, and an italic narrative caption.
- `.journal-tabs` (I–V, right edge) highlight the nearest chapter via `Math.round(progress)` and jump-scroll on click (`window.scrollTo` computed from `journalSection.offsetTop` + stop index — no anchor `id`s per stop, just math).
- Nav/footer "Destinations" links now point to `#journal` (the old `#destinations` id no longer exists).

**JS entry points to know about** (all near the bottom of `index.html`, in the same `<script>` block as `loadCMS`):
- `initJournal()` — (re)computes `.journal-stop` list + section height + rebuilds anything scroll-dependent. Called once on page load and again after `applyDestinations()` rebuilds the DOM from CMS.
- `updateScrollEffects()` — the single rAF-throttled scroll handler doing navbar-shadow, manifesto word-reveal, *and* journal crossfade/tab-highlight together (kept in one handler on purpose, don't split it back out without good reason — that was a deliberate perf choice).
- `applyDestinations(d)` in the CMS-apply block — rebuilds `#journal-dest-stops` from `cms_content.destinations.items[]`. Field mapping: `item.chapter_title` (falls back to `item.name`), `item.dateline` (falls back to `item.region`), `item.story` (falls back to `item.caption`), `item.image` (falls back to emoji+gradient). The `chapter_title`/`dateline`/`story` fields are **new**, added specifically for the narrative — `name`/`region`/`emoji`/`gradient`/`wide` are the original fields, kept for backward compatibility/fallback, not removed.

**CMS data (live, already updated in Supabase — this is not just local fallback text):** `cms_content` row `section='destinations'` now has, per item, both the original fields and the new `chapter_title`/`dateline`/`story`. Confirmed via `execute_sql` round-trip that apostrophes in the story text (e.g. "Italy's coast", "we're still chasing") saved and render correctly. If editing this in `admin-cms.html` later, note the admin UI almost certainly doesn't have form fields for `chapter_title`/`dateline`/`story` yet (it was never told about this workstream) — **editing destinations there will save whatever fields its form has and could blow away the new ones** unless the admin form is updated to round-trip them too. Worth doing before anyone touches that tab in production.

**Photos are hotlinked from Wikimedia Commons** (`commons.wikimedia.org/wiki/Special:FilePath/<file>?width=1200`), by explicit user choice (asked "own Supabase storage vs. keep hotlinking Wikimedia" — user picked hotlinking). Known tradeoff accepted: no control if Wikimedia renames/deletes a file or rate-limits; verified all 5 URLs resolve with `curl` at the time this was written, but there's no ongoing monitoring for link rot.

**Content authored this session (for reference/editing):**
| # | Photo (Wikimedia file) | Chapter title | Dateline | 
|---|---|---|---|
| I | `Kiyomizu-dera,_Kyoto,_November_2016_-02.jpg` | The Beginning | Kyoto, Japan · 2012 |
| II | `Positano-Amalfi_Coast-Italy.jpg` | Word Traveled Fast | Amalfi Coast · 2015 |
| III | `Koutoubia_Mosque_2.jpg` | Learning to Listen | Marrakech, Morocco · 2018 |
| IV | `Pirogue_and_boat_on_the_Mekong_with_colorful_sky_at_sunset_in_Luang_Prabang_Laos.jpg` | Slowing Down | Luang Prabang, Laos · 2021 |
| V | `Torres_del_Paine,_Laguna_Azul_09.jpg` | To the Edge of the World | Patagonia · 2024 |

The years (2012/2015/2018/2021/2024) are narrative flavor invented to fit the "12+ years since 2012" fact already established elsewhere on the site (About section, footer tagline) — not sourced from any real company history document. Flag this to the user if accuracy matters — nobody has confirmed these specific years/order against real events.

**Testing note:** this was tested via a local `python -m http.server` against the *real* production Supabase project (same publishable key baked into `index.html` for all environments — see the "Supabase client key" section above), so what was verified live *is* what's now deployed. No separate staging environment exists. Not verified on an actual narrow mobile viewport this session (the browser automation tool's `resize_window` didn't take effect in the sandbox) — the responsive CSS is straightforward (stack photo above text, hide the side tabs, hide nothing load-bearing) but worth a real phone check.

---

## Workstream F — Referral program + Lucky Draw, admin + member-facing (added 2026-08-04)

User asked to add a referral feature (admin sets promo terms, members get a personal code) and a lucky draw feature (weighted random winners from bookings/referrals) to the admin panel, then — after discovering the two portals don't auto-share UI — asked for member-facing pieces too, confirmed bidirectional live against production Supabase, and pushed/deployed both sites. Everything below is live and test-verified as of 2026-08-04, then cleaned of test data.

**DB (5 migrations, all applied via `mcp__supabase__apply_migration`, in this order):**
1. `referral_program` — `profiles.referral_code` (unique, auto-generated by trigger `set_referral_code`/`generate_referral_code` on insert, backfilled for existing rows); `referral_promotions` (name, referrer reward type/value, referee discount type/value, active window, `is_active`); `referrals` (referrer_id, referee_name/email, optional referee_id/booking_id, status `pending→redeemed→rewarded`/`cancelled`, links to reward/referee vouchers); `admin_referrals` view + `get_admin_referrals()` RPC (joins in referrer/referee names, promotion name, voucher codes).
2. `lucky_draw` — `lucky_draws` (name, pool_source `bookings`/`referrals`/`both`, date window, optional trip filter, num_winners, status `draft→pool_built→drawn`); `lucky_draw_entrants` (one row per qualifying booking/referral — **multiple rows per member = more chances**, this is deliberate weighting, not a bug); `lucky_draw_winners` (unique per draw+prize_rank); `admin_lucky_draws`/`admin_lucky_draw_entrants`/`admin_lucky_draw_winners` views + matching `get_admin_*` RPCs; `build_lucky_draw_pool(p_draw_id)` (deletes+rebuilds entrants from current bookings/referrals matching the draw's filters); `draw_lucky_winners(p_draw_id)` (picks winners one at a time, `order by random() limit 1` excluding members already won in this draw — weighted by entrant-row count, never repeats a winner across ranks).
3. `lock_down_referral_and_draw_views` — `REVOKE ALL ... FROM PUBLIC, anon, authenticated` on the 4 new `admin_*` views. **Required, not optional**: Postgres views default to running with the *creator's* privileges and bypass the underlying tables' RLS unless access is separately revoked — this exact gap was already found and fixed once before for `admin_vouchers`/`admin_revenue_bookings` (see `lock_down_admin_views` migration, 2026-07-25) and would otherwise let anyone hit `/rest/v1/admin_referrals` etc. directly, unauthenticated, bypassing the `is_admin_or_staff()` check in the RPC wrapper. **If any future admin view is added, apply this same revoke immediately, or `get_advisors('security')` will flag `auth_users_exposed` + `security_definer_view` ERROR-level.**
4. `fix_referral_function_search_path` — `SET search_path TO 'public'` on `generate_referral_code`/`set_referral_code` (matches existing project convention, silences the `function_search_path_mutable` WARN).
5. `member_facing_referral_and_draw_visibility` — three additional RLS policies so members can read (not write) their own slice: `referral_promotions` select where `is_active = true` (promo terms are non-sensitive marketing copy); `lucky_draw_winners` select where `member_id = auth.uid()`; `lucky_draws` select where `exists (... lucky_draw_winners ... member_id = auth.uid())` (members only see draws they've actually won, not the full admin config of every draw). Without these three, the admin-side RLS (`is_admin_or_staff()` for ALL, from migration 1–2) would make the member-facing UI below silently show nothing.

All 4 tables (`referral_promotions`, `referrals`, `lucky_draws`, `lucky_draw_entrants`, `lucky_draw_winners`) have RLS enabled; admin/staff get full `ALL` access via the existing `is_admin_or_staff()` helper, same permission tier as vouchers.

**Admin UI (`admin/admin.html`):** two new sidebar tabs, "Referrals" and "Lucky Draw", visible to admin + staff (same tier as Vouchers). Referrals page: promotions table (create/deactivate/delete) + referrals log (create/mark redeemed/issue reward — issuing a reward inserts a real voucher row for the referrer using the promotion's reward type/value, then marks the referral `rewarded`). Lucky Draw page: create a draw, Build Pool, Draw Winners (disabled until pool has entrants), View Entrants/Winners in a shared list modal. Followed the file's existing conventions throughout (RPC-backed loaders, `openModal`/`closeModal`, `showToast`, `btn-group` action rows).

**Member UI (`dashboard.html`):** new "Refer & Earn" nav page (between My Bookings and Membership) showing: the member's own `referral_code` with a copy button; a banner with the currently-active promotion's terms (only rendered if one exists and today falls in its window); their own referral history (`referrals` table, own rows via RLS, joined to `referral_promotions.name`); their own lucky draw wins (`lucky_draw_winners` joined to `lucky_draws.name`, both via the new member-select policies above). All three read directly from Supabase — **no admin-side sync step, no API layer between the two portals**; this was confirmed live (see below) by creating a real promotion and a real win from the admin side and watching both appear on the member dashboard within one page load.

**Deploy mechanism — important, easy to get wrong next time:** this repo has **two separate Netlify sites**, and they deploy completely differently:
- `thetravelchapter` (siteId `56615704-86bc-4072-9a46-a1733c80eb8e`, `https://thetravelchapter.netlify.app`) — **git-linked**, repo `eren010-ec/the-travel-chapter`, auto-deploys on `git push` to `main`. Serves the customer-facing pages (`dashboard.html`, `index.html`, etc.) from repo root. Confirmed auto-deploy fires within ~30s of a push this session.
- `quietmeridian-4471` (siteId `c5f73ef7-2043-4f04-8611-702f5a4e773b`, `https://quietmeridian-4471.netlify.app`) — **not git-linked at all** (`netlify sites:list` shows no `repo:` field for it). Serves `admin/admin.html` etc. Pushing to GitHub does **nothing** for this site. The only way to update it is a manual CLI deploy from the repo root: `netlify deploy --prod --dir=admin --site c5f73ef7-2043-4f04-8611-702f5a4e773b`. **This is the deploy path for every future admin.html/admin-cms.html/admin-login.html change** — forgetting the `--dir=admin --site ...` flags, or assuming `git push` covers it, will leave the live admin panel stale with no error to signal it (curl/browser will just show the old file, 200 OK).
- Netlify CLI wasn't installed as a persistent binary on this machine — invoked via `npx --yes netlify-cli <command>`, which works but re-resolves the package each time (a few seconds of overhead). CLI login had timed out once (opened the browser authorize page but nobody approved it in time) before succeeding on retry — if that happens again, just retry `netlify login`, it's not a real failure.
- The Netlify account (`thetravelcjapter` — yes, that's a typo in the actual account/team name on Netlify's side, not something to "fix") also has two unrelated sites, `visualfusioncreative` and `yakinikudong` — ignore those, not part of this project.

**Bug fixed (pre-existing, unrelated to the new feature but found while testing it):** `admin.html`'s `init()` redirected an unauthenticated visitor to `https://thetravelchapter.netlify.app/login.html` (the **member** portal's login page) instead of its own `admin-login.html`. Harmless-looking but actually confusing in practice: if the browser already had a valid *member* session on `thetravelchapter.netlify.app` (e.g. from testing the member dashboard in the same browser), that member login page auto-redirects to `dashboard.html` when a session already exists — so visiting `admin.html` while signed out silently bounced into a random member's dashboard instead of ever showing a login form. Fixed to `window.location.href = 'admin-login.html'` (relative, same site). Deployed as part of the same manual admin-site deploy above.

**Testing method note for next time:** `admin.html`'s Mark Redeemed / Issue Reward / Delete / Draw Winners actions all use native `confirm()` — per this project's browser-automation guidance, clicking those through Claude-in-Chrome risks hanging the tab (native dialogs block the CDP connection). Verified those code paths indirectly instead: the same RLS predicate (`is_admin_or_staff()` for `ALL`) was already proven live by a successful `INSERT` through the same authenticated client, so `UPDATE`/`DELETE` under the identical policy don't need separate proof. Live-tested everything that doesn't trigger a dialog (create promotion, create referral, create draw, Build Pool) directly through the browser, and proved the admin→member data linkage by inserting a real promotion and a real `lucky_draw_winners` row and confirming both rendered immediately on the member dashboard — then deleted all of it (`DELETE ... where name = 'Test ...'` etc., cascade handled the winner row via the draw's `ON DELETE CASCADE`). No test data left in production.

---

## Task checklist

- [x] Open all 6 pages in a real browser, confirm logo renders correctly (sizing/placement) — done 2026-07-26 at desktop size.
- [x] `git init` + first commit — done 2026-07-26.
- [x] Create GitHub repo, push — done, `eren010-ec/the-travel-chapter`.
- [x] Confirm the customer site (repo root) is connected to Netlify and auto-deploying from `main` — confirmed 2026-08-04, site `thetravelchapter`, auto-deploys within ~30s of push.
- [x] Second Netlify site for `admin/` — exists (`quietmeridian-4471`, confirmed 2026-08-04) but **is not git-linked**; it's a manual-CLI-deploy-only site. See Workstream F for the exact `netlify deploy` command needed after every admin-file change.
- [ ] Redeploy the `admin-users` edge function (`supabase functions deploy admin-users`) so the updated `ALLOWED_ORIGINS` (now includes the new admin site's origin) takes effect — needed before admin user-management actions will work on the new domain.
- [ ] Do a real install test on an Android phone (Chrome install prompt) and an iPhone ("Add to Home Screen") against both deployed HTTPS URLs — confirm the customer app and the admin app install as distinct home-screen apps with correct icons/names, and that offline app-shell loading works.
- [ ] Update any bookmarks/docs that pointed at the old `admin.html` / `admin-login.html` / `admin-cms.html` root-level URLs — the only working admin URL going forward is the new separate site.
- [ ] (Optional) `SET search_path = public` on the 3 flagged functions.
- [ ] (Optional) Enable leaked-password protection in Supabase Auth dashboard settings.
- [ ] (Optional, future) If a real native Android `.apk` is wanted later: wrap with Capacitor — requires installing Java JDK + Android SDK command-line tools on a build machine first.
- [ ] (Optional, future) If a real iOS app is wanted later: needs a Mac with Xcode (and an Apple Developer account to install on a physical device or ship to the App Store) — cannot be done from this Windows machine.
- [ ] Update `admin-cms.html`'s Destinations tab form to include `chapter_title` / `dateline` / `story` fields (see Workstream E) — otherwise editing destinations there risks dropping the new book-chapter narrative content.
- [ ] Verify the new journal section on a real narrow mobile viewport (browser automation's window resize didn't work in this session's sandbox).
- [ ] Confirm with the user whether the invented years (2012/2015/2018/2021/2024) in the chapter datelines need to match real company history, or are fine as narrative flavor.
- [ ] Referral checkout flow is still manual/admin-recorded — there's no customer-facing "enter a referral code at booking" field (matches the existing vouchers pattern, which also has no checkout-time redemption UI). If that's wanted, it needs a new field in `dashboard.html`'s booking modal plus admin-side matching logic.
- [ ] Netlify CLI is now logged in on this machine (state persists in `%APPDATA%\netlify`) — future sessions may not need `netlify login` again, but if `netlify status` shows logged out, re-run it (retry once if the first attempt times out waiting for browser approval).
- [ ] If admin.html/admin-cms.html/admin-login.html change again, remember the deploy command is `netlify deploy --prod --dir=admin --site c5f73ef7-2043-4f04-8611-702f5a4e773b` — a plain `git push` will not update the live admin site (see Workstream F).
