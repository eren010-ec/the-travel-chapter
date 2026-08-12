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

**Follow-up (same day):** the member dashboard's original "Refer & Earn" page combined both features into one page (referral code + my referrals in one card, lucky draw wins in another card side by side). User asked for them to be two fully separate sections in both panels, matching how the admin panel already had them as separate nav tabs. Split `dashboard.html`'s single `page-referrals` into two: `page-referrals` (nav label "Referrals" — code + active-promo banner + my referrals list) and a new `page-luckydraw` (nav label "Lucky Draw" — my wins list only). Element IDs (`ref-code`, `referral-promo-banner`, `ref-list`, `ref-wins`) were kept as-is since `renderReferralsPage()` just fills them in regardless of which `<div class="page">` they live under — no JS logic changes needed, only the HTML structure/nav moved. Committed as `6f83535`, pushed, auto-deployed and re-verified live on the member site within ~10s.

---

## Workstream G — Reverted homepage hero/destinations back to pre-journal, kept i18n (added 2026-08-06)

User asked to revert `index.html`'s hero + destinations back to "the first version" — i.e. undo Workstream E's pinned book-chapter scroll journey (and its companion Manifesto section), restoring the plain hero section + destinations grid that existed before commit `3f49478`. Confirmed with the user up front exactly which version ("pre-journal", not the very first upload) and how to handle the conflict with the EN/ZH/MS language support added afterward (Workstream, commit `8a8142d`) — user chose to **keep i18n working on the restored sections**, not do a byte-for-byte revert.

**What changed:** `index.html`'s `<section class="journal" id="journal">` (pinned scroll: intro → 5 chapter stops → outro/epilogue) and the standalone `<section class="manifesto">` were both deleted and replaced with the original `<section class="hero" id="hero">` (card-stack visual, stats bar, single primary CTA) + `<section id="destinations">` (3-col grid, wide cards for 1st/5th item). All of the associated CSS (`.journal-*`, `.chapter-*`, `.manifesto-*`) was removed and the old `.hero-*`/`.dest-*` rules restored; the scroll-linked JS (`initJournal()`, journal tab click-to-jump, manifesto word-lighting, crossfade opacity math) was deleted down to just the navbar-shadow-on-scroll handler. `applyHero()` and `applyDestinations()` (the CMS-apply functions) were restored to their pre-journal bodies — notably `applyHero()` once again populates the hero card stack's `featured_card` (emoji/title/subtitle/price/image) and floating badge, which the journal-era `applyHero()` had silently dropped even though `admin-cms.html`'s hero form still has (and always had) fields for these. Nav and footer "Destinations" links point back to `#destinations` instead of `#journal`.

**i18n handling:** `hero.eyebrow` / `hero.heading` / `hero.subtext` / `hero.cta_primary` translation keys already existed (used by the journal intro) and needed no changes — same element IDs, so they just work. New keys `destinations.eyebrow` / `destinations.heading` / `destinations.subtext` (EN/ZH/MS) were added to `i18n.js` for the destinations section chrome, which had no equivalent in the journal version (destinations copy was folded into the journal's table-of-contents). Destination *card* content (names/regions) is still CMS-authored and intentionally not translated, matching the pre-existing documented limitation for all CMS content site-wide.

**Verified:** local `python -m http.server`, live against production Supabase (same publishable key baked into `index.html` for all environments). Hero and destinations render pixel-for-pixel like the pre-journal design; CMS content (real destination photos) loads correctly into the restored grid; language switcher correctly re-translates the restored hero/destinations chrome to Chinese (spot-checked, didn't re-check Malay). No console errors.

**Committed and pushed:** `c2b3d0d` on `main` (`index.html` + `i18n.js` only — `supabase/.temp/` stayed untracked). This is the customer-facing site (`thetravelchapter`, git-linked), so the push triggers Netlify's auto-deploy within ~30s — not separately re-verified live on Netlify this session, only locally.

**Note for anyone touching this later:** the journal/manifesto code is gone from `index.html`, not just hidden — if the book-chapter narrative is wanted back, it needs to be re-built from scratch or cherry-picked from commit `3f49478`/`064d2a5`, not un-commented. The `journal.*` and `manifesto.text` translation keys were deliberately left in `i18n.js` (harmless dead weight, low risk to remove blindly) rather than pruned.

---

## Workstream H — Install banner removed, Destinations+Trips merged, hero cards sync from live trips (added 2026-08-06, same day as Workstream G)

Three further changes to the restored (Workstream G) homepage layout, all in `index.html`. Committed and pushed to `main` as `98bfb90` — customer site (`thetravelchapter`, git-linked), auto-deploys within ~30s of push.

**1. PWA install banner removed entirely.** The `beforeinstallprompt`-driven "Install The Travel Chapter" banner described in Workstream C (`#install-banner` HTML, `.install-banner*`/`.btn-install*` CSS, and the IIFE handling `beforeinstallprompt`/iOS fallback/14-day dismiss) was deleted outright — not hidden, not commented out. Service worker registration (`sw-customer.js`) was left untouched, so the site is still installable via the browser's native/address-bar install affordance; only the custom in-page prompt UI is gone. If a custom install prompt is wanted again, it needs to be rebuilt from Workstream C's description or cherry-picked from history — nothing was left in place to un-comment.

**2. `#destinations` and `#trips` (Featured Trips) merged into a single `<section>`.** Per explicit user choice ("merge into one section," not just remove the visual gap), the "Our Journeys"/"Featured Trips" eyebrow+heading+subtext block was dropped entirely — there's now only one header at the top of the merged section (destinations' own "Where We Go" / "Handpicked Destinations" copy), followed by the destinations grid, then the trips grid directly underneath (added `margin-top:56px` on `.trips-grid` to keep visual separation without a header). **`#trips` is no longer a `<section>` id — it's now the `id` on the trips-grid `<div>` itself** (`<div class="trips-grid" id="trips">`), kept solely so existing `href="#trips"` nav links and the hero's "Explore Trips" CTA still scroll to the right spot. The old `#trips { background:var(--cream) }` CSS rule was removed (would otherwise paint a cream box behind just the trip cards, since that id no longer wraps a full section). JS was updated from `document.getElementById('trips-grid')` to `document.getElementById('trips')` in `renderDbTrips()`. **Gotcha for later:** don't assume `#trips` is a section boundary if touching this area again — check the current DOM structure first.

**3. Hero visual cards now sync live from the `trips` table instead of the CMS "Featured Card" fields.** The hero's card-stack visual (main card + a secondary card that was previously fully hardcoded — "Amalfi by Yacht," no CMS binding at all) now populates from the first two active trips (`sb.from('trips').select('*').eq('is_active', true).order('created_at')`, same query `loadTrips()` already used for the Featured Trips grid). New function `syncHeroCardsToTrips(data)`, called at the end of `renderDbTrips()`: sets `hero-card-main`'s title/duration/price/cover_image from `data[0]`, and the now-id'd secondary card (`hero-card-secondary`, `hero-card2-emoji/title/sub`) from `data[1]` — auto-hides (`display:none`) if there's only one active trip. Also re-runs on language switch (already inside the `TC_I18N.onChange` → `renderDbTrips` path). Added a `trips.from` i18n key (EN "From" / ZH "起价" / MS "Dari") for the "From RM …" price label, since the old CMS field was freeform English text with no translation.

**User explicitly chose "pull first 2 trips automatically" over keeping the CMS fields as an empty-state fallback.** Practical consequence: `admin-cms.html`'s Hero Banner form still has, and still saves, the "Featured Card" fields (emoji/title/subtitle/price/image) to `cms_content.hero.featured_card` — **but they're now dead on the live site**, silently overwritten by `syncHeroCardsToTrips()` a moment after `applyHero()` runs on every page load. Nobody removed the admin form fields; if that's confusing to whoever edits CMS content, either hide/relabel those fields in `admin-cms.html` or reintroduce a fallback (only used when the trips table has zero active rows) — neither was done this session, only asked-and-declined for the fallback option specifically.

---

## Workstream I — Phone-first customer registration (WhatsApp OTP), Twilio setup blocked (added 2026-08-08)

User asked to make customer registration on `login.html` "use phone number first." Clarified with the user this meant an actual flow change (not just field reordering): collect + verify the phone number via WhatsApp OTP **before** asking for name/password, not the old order (fill in everything, submit, verify after).

### Code changes — DONE, NOT YET COMMITTED

`login.html` register flow is now 3 steps instead of 1:
1. **`form-register`** (reused id, contents replaced) — phone number only, button now calls `handleRegisterPhone()`, which calls `sb.auth.signInWithOtp({ phone, options: { shouldCreateUser: true, channel: 'whatsapp' } })`. This creates an unconfirmed, passwordless auth user (if new) and sends the WhatsApp OTP immediately.
2. **`form-verify`** (existing form, now only reachable from step 1) — same 6-digit code UI as before, but `handleVerify()` now runs *before* any password/name exists. It sets `suppressAutoRedirect = true` first (same pattern as the existing forgot-password flow), calls `verifyOtp()`, then checks `profiles.first_name` for the now-authenticated user: if already set (this phone belongs to a pre-existing, fully set-up account — e.g. someone hit "Join Us" with an existing member's number), it signs them straight in via `routeSession()` instead of re-registering them; otherwise shows step 3.
3. **`form-register-finish`** (new) — First Name, Last Name, Password. Submits via `sb.auth.updateUser({ password, data: { first_name, last_name, tier: 'explorer' } })`, **then also directly `UPDATE`s the `profiles` row** with first_name/last_name (`sb.from('profiles').update(...).eq('id', session.user.id)`) — necessary because the `handle_new_user` trigger only populates `profiles` on the initial `auth.users` INSERT (which now happens back in step 1, before any name is known), so the trigger alone would leave `profiles.first_name` null forever without this extra write. RLS already permits a user to update their own `profiles` row (same pattern `dashboard.html`'s `saveProfile()` already uses), so no new policy was needed.

`resendCode()` was changed from `sb.auth.resend({type:'sms', channel:'whatsapp'})` to calling `signInWithOtp()` again — required because the OTP is now issued via `signInWithOtp` (sign-in-style OTP), not `signUp` (the old flow), and `auth.resend` is for resending signup/change confirmations, not sign-in OTPs.

New i18n keys added (EN/ZH/MS) in `i18n.js`: `login.send_code_button`, `login.finish_profile_label`.

**Verified locally** (local `python -m http.server`, real browser via Claude-in-Chrome): step 1→3 UI renders and transitions correctly, client-side validation fires without hitting the network. Did **not** verify an actual end-to-end OTP send/receive — see below, this is now blocked on Twilio being wired up. While testing, found and cleared a leftover service worker from an earlier local-testing session that was silently serving a stale cached `i18n.js` on `localhost` — not a code bug, just a stale local browser cache artifact, noted in case it trips up testing again (symptom: translated text renders as the literal uppercased dotted key, e.g. "LOGIN.SEND_CODE_BUTTON").

**Not committed/pushed.** `git status` shows `i18n.js` and `login.html` modified, nothing staged. Per [[feedback_netlify_deploy_gate]], don't push without asking first anyway — but also don't commit-and-sit-on-it without flagging: this code is **not functionally testable end-to-end yet** because WhatsApp OTP delivery itself isn't wired up (see below), so hold off presenting this as "done."

### Twilio setup — BLOCKED, not resolved this session

The WhatsApp OTP delivery needs Twilio configured as Supabase's Phone auth provider (`channel: 'whatsapp'` only works with Twilio/Twilio Verify — confirmed via Supabase's own docs). User signed up for a Twilio **trial** account ("My First Twilio Account", Account SID redacted here (GitHub's secret scanner flags Twilio Account SIDs regardless of Twilio's own stance that they're non-secret identifiers — see Twilio console for the actual value if needed; Auth Token was never shared with or entered by Claude, per the credential-handling boundary). Attempted to verify the user's own Malaysian mobile number as a "Verified Caller ID" (a trial-account prerequisite — trial accounts can only call/text numbers you've manually verified) and hit a chain of blockers:

1. **SMS verification method: hard-blocked for Malaysia.** Twilio's own error: "The verification has been blocked as this is a restricted country for verifying a caller ID by SMS." Confirmed via Twilio's help center — Malaysia doesn't allow the legacy Caller-ID-verification-by-SMS method at all; **Call is the only allowed method for MY.**
2. **Call verification: failed repeatedly** with a generic "We were unable to place the call. Please try again." Investigated Twilio's Voice → Settings → Geo Permissions page (`console.twilio.com` → Voice → Settings → Geo permissions) to rule out a geographic block: **Malaysia is already enabled under Low-Risk by default** (only two narrow high-risk sub-ranges — "Special Services Number Ranges" and "High-Risk for Toll Fraud" — are gated behind an account upgrade, and a normal mobile number shouldn't fall in either). So geo-permissions were **not** the actual cause of the Call failures — root cause of that specific error was never conclusively identified (possibly number-format entry issue — e.g. leaving the leading `0` in front of the local number instead of dropping it, since `+60` is already supplied by the country dropdown).
3. **After repeated attempts, the Verified Caller IDs page itself started hard-redirecting** to Twilio's "Upgrade your account" paywall (`1console.twilio.com/.../upgrade/v2`) instead of loading at all — strongly suggests the trial hit some usage/attempt-based gate that now requires adding a payment method before the account can continue verifying caller IDs (or possibly placing any more voice calls). Not confirmed whether this is a hard wall or a temporary throttle — wasn't retried after waiting.

**Decision:** user chose to stop here and pick this back up later rather than add a payment method mid-session. **Nothing was entered into Supabase's Auth → Phone provider settings** — Twilio is not yet wired up on the Supabase side at all, so the WhatsApp OTP flow (both the new code above, and technically the *old* pre-existing WhatsApp OTP flow this replaced) will not actually deliver messages if tested right now.

### To resume this later

1. Decide how to get past the Twilio trial wall: add a payment method (doesn't necessarily mean getting charged — trial credit is normally used first), or try the **WhatsApp Sandbox** join flow instead (Console → Messaging → Try it out → Send a WhatsApp message) — this is a separate Twilio feature from Caller ID verification and may not be gated the same way; wasn't tried this session before stopping.
2. Once you have a working Twilio Account SID + Auth Token + a WhatsApp-capable Messaging Service SID (see prior chat turn for the detailed Twilio-side walkthrough — create a Messaging Service, attach the WhatsApp sender/sandbox to it), enter them into **Supabase Dashboard → project `nkrpkfqibsudqsonljve` → Authentication → Sign In / Providers → Phone → SMS Provider: Twilio**.
3. Test the new 3-step register flow on `login.html` end-to-end with a real phone number.
4. Only then commit + ask before pushing (per [[feedback_netlify_deploy_gate]]) — `login.html`/`i18n.js` changes are sitting uncommitted locally right now.

### Update (2026-08-11) — switched from WhatsApp to plain SMS, still blocked

User upgraded and topped up the Twilio account (no longer trial), which lifts the Caller-ID-verification wall above — but rather than continue fighting Malaysia's WhatsApp-sender/Meta-approval path, decided to switch the whole OTP flow from WhatsApp to **plain SMS**, which needs no Meta approval or WhatsApp Sender at all, just an SMS-capable Twilio number attached to a Messaging Service.

**Code changed (uncommitted, same as the rest of this workstream):** all four `signInWithOtp(...)` calls in `login.html` (`handleRegisterPhone`, `resendCode`, `handleForgotSend`, `resendForgotCode` — i.e. both the new register flow *and* the pre-existing forgot-password flow, which also used to be WhatsApp) now pass `channel: 'sms'` instead of `'whatsapp'`. All user-facing copy mentioning "WhatsApp" in `login.html` and in all three `i18n.js` languages (EN/ZH/MS) was reworded to say SMS/text message instead — confirmed no `whatsapp` string remains in either file (case-insensitive grep).

**Also fixed while auditing:** `login.html`'s hero "Explore Destinations" / "Our Story" buttons were hardcoded to `https://elaborate-clafoutis-52f5fa.netlify.app/#destinations` / `#about` — an entirely unrelated Netlify site, not this project's. No idea how that got in there; not something introduced this session, just found and fixed to relative links (`index.html#destinations` / `index.html#about`) while going through every hardcoded URL in the repo for the domain change below.

**Still blocked, now on a different step:** waiting on Twilio phone number verification (buying/verifying an SMS-capable number in the Twilio console) before a Messaging Service can be created and the SID entered into Supabase. **User explicitly asked to leave this for later** — do not chase it further unprompted next session, wait to be asked.

### Update (2026-08-12) — RESOLVED: switched to Twilio Verify, working end-to-end

User asked to resume the Twilio SMS work. Picking up from "have a number, no Messaging Service yet" turned up a real blocker: **Malaysia local numbers on Twilio don't support SMS via self-serve purchase at all** — the number search (Phone Numbers → Buy a number, MY, Local, SMS capability checked) only ever returned Voice-capable results, no SMS option, no capability filter to change that. This is a Twilio/Malaysia regulatory limitation on self-serve local numbers, not a UI issue — confirmed by trying multiple searches with no SMS results ever appearing.

**Fix: switched to Twilio Verify instead of raw Twilio SMS.** Twilio Verify is a separate dedicated OTP product with its own shared/managed sender pool — it doesn't require buying a dedicated number at all, which sidesteps the Malaysia local-number limitation entirely. Supabase has native first-class support for this as a distinct SMS provider option (`Twilio Verify`, separate from plain `Twilio`) in Auth → Providers → Phone, so **no code changes were needed in `login.html`** — the client-side `signInWithOtp`/`verifyOtp` calls work identically regardless of which Twilio product is behind them; Supabase abstracts the difference server-side.

**What was set up:**
1. Twilio Console → Verify → Services → created a new Verify Service, friendly name "The Travel Chapter", SMS channel enabled (WhatsApp/Email/Voice left off), friendly-name-in-template authorized, Fraud Guard enabled (recommended default). Service SID: `VA3900663f226d4222a63a59731f82985c`.
2. Supabase Dashboard → project `nkrpkfqibsudqsonljve` → Authentication → Sign In / Providers → Phone: **Enable Phone provider** turned on, **SMS provider** switched from `Twilio` to `Twilio Verify`, `Twilio Account SID` and `Twilio Verify Service SID` filled in by Claude; **Twilio Auth Token** entered directly by the user (never seen by Claude, per the credential-handling boundary established earlier in this workstream). Saved and confirmed persisted (values were still there on reopening the panel).
3. **Verified end-to-end with a real Malaysian number** (user's own phone, entered and read back the OTP themselves — Claude drove the browser but cannot receive SMS) — register flow (phone → SMS OTP → verify → name/password) completed successfully against production Supabase + live Twilio Verify.

**Gotcha hit while setting up the Verify Service (Twilio console UI, not a code issue):** the "Create new" Verify Service modal in Twilio's console (both the `console.twilio.com` iframe version and the `1console.twilio.com` native version) would not reliably submit via browser automation — the Continue button click appeared to register but the dialog just closed without creating anything, twice in a row, and screenshots weren't reliably reflecting true modal scroll state. Root cause never fully diagnosed (suspected iframe/rendering quirk specific to that console's modal, possibly the "Enable Fraud Guard" Yes/No radio needing an explicit selection before the form would validate). Resolved by having the user complete just that one step manually in their own browser session instead of continuing to fight the automation.

**Also changed this session (`login.html`, `i18n.js`):** the three phone-number inputs (`login-phone`, `reg-phone`, `forgot-phone`) previously showed placeholder text `+65 9123 4567` (wrong country — Singapore, not Malaysia — never noticed/fixed in earlier workstreams) and started empty. Per user request after the successful live test, changed to **pre-fill the actual field value with `+60 ` on load** (not just an example in the placeholder) so users don't have to type the country code themselves; placeholder text changed to `12 345 6789` (a bare local-number example, since `+60` is now already in the value) across the HTML and all three `i18n.js` locales (EN/ZH/MS, same string). `startForgotPassword()`'s fallback (previously resetting `forgot-phone` to `''` when the login field wasn't already a valid phone) now falls back to `'+60 '` instead, so the prefill survives navigating into the forgot-password form. Verified visually in-browser (hard-reload needed — a stale service-worker/cache from earlier local testing was still serving the old placeholder text, same class of issue noted earlier in this workstream).

**Still uncommitted at time of writing** — `login.html`, `i18n.js` (this workstream's SMS-channel switch plus today's Verify-compatible flow and `+60` prefill) and this handoff doc update. Per [[feedback_netlify_deploy_gate]], will ask before pushing once committed.

---

## Workstream J — Custom domain `thetravelchapter.com.my` linked (added 2026-08-11)

User linked the customer-facing Netlify site (`thetravelchapter`, siteId `56615704-86bc-4072-9a46-a1733c80eb8e`) to the real custom domain **`thetravelchapter.com.my`** (domain/DNS setup done on Netlify's side, outside Claude Code). The admin site (`quietmeridian-4471`) is **not** affected — it's staying on its Netlify subdomain, consistent with Workstream D's goal of keeping the admin panel on an unguessable, unrelated URL.

**Audited every hardcoded absolute URL in the repo** (`grep -rn "netlify.app"`) and updated the ones pointing at the customer site's old Netlify subdomain to the new domain — **code changes only, none of this is deployed yet**:
- `supabase/functions/admin-users/index.ts` — `ALLOWED_ORIGINS` now includes `https://thetravelchapter.com.my` and `https://www.thetravelchapter.com.my` (added, didn't remove the old `thetravelchapter.netlify.app` / `quietmeridian-4471.netlify.app` entries — harmless to keep both during the transition, and the admin site's own origin still needs to stay listed regardless). **www vs. apex wasn't confirmed with the user — both were added defensively; if only one is actually live, the unused one is harmless dead weight, not a bug.**
- `admin/admin-login.html` ("Go to Member Portal"), `admin/admin-cms.html` (both "Preview Page" links), `admin/admin.html` ("← Back to Dashboard") — all four absolute cross-domain links updated from `https://thetravelchapter.netlify.app/...` to `https://thetravelchapter.com.my/...`.

**Edge function redeployed — DONE (2026-08-12).** `supabase functions deploy admin-users` ran successfully; `ALLOWED_ORIGINS` on the live function now includes `thetravelchapter.com.my` / `www.thetravelchapter.com.my` alongside the old `thetravelchapter.netlify.app` / `quietmeridian-4471.netlify.app` entries. **Note on CLI auth on this machine (macOS, different from the Windows machine referenced elsewhere in this doc):** the interactive `supabase login` browser flow doesn't work from inside a sandboxed Claude Code shell — it fails even when the user runs it themselves via the `! <command>` passthrough, since that still executes in the same non-TTY environment (`LegacyLoginMissingTokenError: Cannot use automatic login flow inside non-TTY environments`). Resolved via `supabase login --token <personal-access-token>`, using a token generated at https://supabase.com/dashboard/account/tokens. CLI is now logged in on this machine for future sessions (persists locally, same as the Netlify CLI login note below) — if a future deploy fails with `LegacyPlatformAuthRequiredError` again, generate a fresh token rather than trying the interactive flow.

**Practical consequence until that deploy happens:** admin-panel privileged actions (create/delete/update user) will get **CORS-blocked** for anyone visiting the admin panel from a session that itself originated from `thetravelchapter.com.my` context — actually, to be precise, the edge function only cares about the *admin site's* origin (`quietmeridian-4471.netlify.app`, unchanged), so admin actions themselves aren't broken by this — but nothing tests `thetravelchapter.com.my` as a calling origin until the redeploy ships, so don't assume the new domain is fully wired end-to-end yet.

**Also found and fixed while auditing (unrelated pre-existing bug, not caused by the domain change):** `login.html`'s hero "Explore Destinations" / "Our Story" buttons were hardcoded to `https://elaborate-clafoutis-52f5fa.netlify.app` — a stray, unrelated Netlify site. Fixed to relative anchors. See the Workstream I update above for detail.

**Committed locally (2026-08-11):**
1. `08628a7` — WhatsApp → SMS switch, fixed stray wrong-domain hero links (`login.html`, `i18n.js`)
2. `27c8268` — Admin cross-links + edge function CORS → `thetravelchapter.com.my` (`admin/admin-login.html`, `admin/admin-cms.html`, `admin/admin.html`, `supabase/functions/admin-users/index.ts`)
3. `5c39727` — This handoff doc update

**Push-protection block on the Twilio SID — RESOLVED (2026-08-12):** `git push origin main` was originally rejected by GitHub push protection, which flagged the raw Twilio Account SID written in the Twilio-setup section above (as a "Twilio Account String Identifier" secret) inside the commit documenting it. Twilio's own docs treat the Account SID as a public, non-secret identifier (the Auth Token is the real secret and was never entered anywhere) — this was very likely a false positive, but GitHub blocked it regardless. Resolved by amending that commit (and this one, which also quoted it) to redact the SID from both places in this doc, since these commits hadn't been pushed yet so rewriting them was safe. **Commit hashes above are the post-redaction versions** — the original hashes (`c90a495`, `60d64c8`) referenced in earlier session notes no longer exist on `main`.

**Still pending, independent of the (now-resolved) push block:**
- ~~`supabase login` then `supabase functions deploy admin-users`~~ — **DONE 2026-08-12**, see above.
- `netlify deploy --prod --dir=admin --site c5f73ef7-2043-4f04-8611-702f5a4e773b` — needed before the admin site's updated cross-links (also from `27c8268`) go live; git push doesn't touch this separately-deployed site. **Blocked 2026-08-12: Netlify build/deploy credit on the account has run out this billing cycle.** Deferred until credit renews — don't retry unprompted, wait for the user to say it's ready.
- Confirm whether `www.thetravelchapter.com.my` is actually a live/used variant or apex-only — `ALLOWED_ORIGINS` defensively includes both; trim once confirmed.

Per [[feedback_netlify_deploy_gate]]: don't push, don't run the edge-function deploy, and don't run the Netlify admin deploy without asking first, even though the commits themselves are done.

---

## Task checklist

- [x] Open all 6 pages in a real browser, confirm logo renders correctly (sizing/placement) — done 2026-07-26 at desktop size.
- [x] `git init` + first commit — done 2026-07-26.
- [x] Create GitHub repo, push — done, `eren010-ec/the-travel-chapter`.
- [x] Confirm the customer site (repo root) is connected to Netlify and auto-deploying from `main` — confirmed 2026-08-04, site `thetravelchapter`, auto-deploys within ~30s of push.
- [x] Second Netlify site for `admin/` — exists (`quietmeridian-4471`, confirmed 2026-08-04) but **is not git-linked**; it's a manual-CLI-deploy-only site. See Workstream F for the exact `netlify deploy` command needed after every admin-file change.
- [x] Redeploy the `admin-users` edge function (`supabase functions deploy admin-users`) — done 2026-08-12, `ALLOWED_ORIGINS` now includes `thetravelchapter.com.my`/`www` on the live function. See Workstream J for the CLI-login-via-token workaround used.
- [ ] Do a real install test on an Android phone (Chrome install prompt) and an iPhone ("Add to Home Screen") against both deployed HTTPS URLs — confirm the customer app and the admin app install as distinct home-screen apps with correct icons/names, and that offline app-shell loading works.
- [ ] Update any bookmarks/docs that pointed at the old `admin.html` / `admin-login.html` / `admin-cms.html` root-level URLs — the only working admin URL going forward is the new separate site.
- [ ] (Optional) `SET search_path = public` on the 3 flagged functions.
- [ ] (Optional) Enable leaked-password protection in Supabase Auth dashboard settings.
- [ ] (Optional, future) If a real native Android `.apk` is wanted later: wrap with Capacitor — requires installing Java JDK + Android SDK command-line tools on a build machine first.
- [ ] (Optional, future) If a real iOS app is wanted later: needs a Mac with Xcode (and an Apple Developer account to install on a physical device or ship to the App Store) — cannot be done from this Windows machine.
- [x] ~~Update `admin-cms.html`'s Destinations tab form to include `chapter_title` / `dateline` / `story` fields~~ — moot, Workstream G (2026-08-06) reverted the destinations grid back to plain `name`/`region`/`image`/`emoji`/`gradient` fields, which the CMS form already supports.
- [ ] Referral checkout flow is still manual/admin-recorded — there's no customer-facing "enter a referral code at booking" field (matches the existing vouchers pattern, which also has no checkout-time redemption UI). If that's wanted, it needs a new field in `dashboard.html`'s booking modal plus admin-side matching logic.
- [ ] Netlify CLI is now logged in on this machine (state persists in `%APPDATA%\netlify`) — future sessions may not need `netlify login` again, but if `netlify status` shows logged out, re-run it (retry once if the first attempt times out waiting for browser approval).
- [ ] If admin.html/admin-cms.html/admin-login.html change again, remember the deploy command is `netlify deploy --prod --dir=admin --site c5f73ef7-2043-4f04-8611-702f5a4e773b` — a plain `git push` will not update the live admin site (see Workstream F).
- [ ] (Optional) `admin-cms.html`'s Hero "Featured Card" fields are now dead on the live site (Workstream H, 2026-08-06) — either hide/relabel them so editors aren't confused, or add back a fallback path for when the trips table has zero active rows.
- [x] **Twilio SMS OTP — DONE and verified live (2026-08-12).** Switched to Twilio Verify (Malaysia local numbers don't support SMS via self-serve — see Workstream I's 2026-08-12 update), Verify Service created, Supabase Phone provider configured, phone-first register flow tested end-to-end with a real Malaysian number. `login.html`/`i18n.js` also updated so phone fields pre-fill `+60`. Not yet committed/pushed.
- [ ] **`git push origin main`** — the GitHub push-protection block is resolved (Twilio SID redacted from the two commits that quoted it, see Workstream J), but the push itself hasn't been done yet. Per [[feedback_netlify_deploy_gate]], ask before pushing. 5 commits are queued (`6d77c8d`, `08628a7`, `27c8268`, `5c39727`, plus this doc-consolidation commit).
- [ ] After `thetravelchapter.com.my` is confirmed fully live, redeploy `admin/` to the admin Netlify site too (`netlify deploy --prod --dir=admin --site c5f73ef7-2043-4f04-8611-702f5a4e773b`) so its cross-links point at the new domain — the admin HTML changes only take effect there once that manual deploy runs, same as any other admin-file change (see Workstream F).
- [ ] Confirm with the user whether `www.thetravelchapter.com.my` is actually a live/used variant or apex-only — `ALLOWED_ORIGINS` defensively includes both, worth trimming to just what's real once confirmed.
