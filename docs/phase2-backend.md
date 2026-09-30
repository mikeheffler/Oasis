# Phase 2 — Backend, accounts, reports, moderation

Status: **draft for Mike's approval.** No backend code exists yet.
Date: 2026-09-26.

Mike's decisions that this document uses:
- Phase 2 comes before phase 3 (routes).
- Backend: Supabase.
- Distribution: Mike's own phone first. No Apple Developer Program yet.
- First sync region: the state of Colorado.
- Verification: two levels, verified and unverified. User reports are the main value of the app.

## 1. Goals

1. The app stops calling the public Overpass server. A scheduled job copies OSM water data to our database. The app reads only from our database. The Overpass usage policy requires this before other people use the app.
2. People can sign in.
3. Signed-in people can report "working" or "not working" (and other problems) for any point.
4. A recent "working" report makes a point **verified**.
5. Signed-in people can submit a new water point. A moderator approves or rejects it.

Not in phase 2: photos, OSM upload, GPX routes, offline route download. See section 12.

## 2. Architecture

```
            weekly GitHub Action                      iPhone app
   Overpass ───────────────► oasis-sync ─────►  Supabase  ◄──────── supabase-swift
   (OSM data)                (Swift, uses        Postgres + PostGIS   (reads points,
                              OasisCore rules)   Auth                  writes reports)
```

- **Supabase** gives us Postgres with PostGIS, sign-in (Auth), and an HTTP API (PostgREST) with row-level security (RLS).
- **oasis-sync** is a small Swift command-line tool in this repo. It uses `OasisCore` for the query and the tag rules. So the sync, the app, and the tests all use one copy of the rules. It runs in GitHub Actions on Linux, where `OasisCore` already builds.
- **The app** gets a new `SupabaseSource` that implements `WaterSpotSource`. The map, the tile cache, the clusters, and the filters do not change.
- **Database changes** are SQL migration files in `supabase/migrations/`. They are in git and are reviewed in PRs like code.

## 3. OSM sync (Colorado first)

**What:** all free-water and buy-water features in Colorado, with the same query as the app today (`OverpassQuery.query(in:layers:)`).

**How:**
- Split Colorado (36.95–41.05 N, 102.0–109.1 W, with a small margin) into 0.5° tiles on a fixed grid: 150 tiles, some of them thin edge strips (`SyncRegion.colorado`, `OSMSync.tileSize`). The first live run (2026-09-30) used 1° tiles, and busy Overpass servers answered 504 "too busy"; 0.5° tiles keep each query light.
- Query one tile at a time, with a pause between queries. Use `out center meta` so we also get the edit date and version.
- Run `OSMRules.evaluate` on each feature. Store the kind, or the reason that the app hides it.
- Upsert each feature into `osm_points` by its OSM id.
- A feature that was in a tile before, but is not in a complete new sync of that tile, gets `removed_at` (function `mark_removed_osm_points`, service role only). We do not delete it at once, because reports can point to it. A point that comes back gets `removed_at = null` again.
- If Overpass returns a timeout remark for a tile (`OverpassParseError.incomplete`), keep the old data for that tile and try it again next run.

**When:** weekly, plus a manual "run now" button (`workflow_dispatch`).

**Load on Overpass:** about 150 queries per week, 5 seconds apart, each asking for at most 120 s. At most 2 retries (30 s and 60 s later), each on the next server in `OVERPASS_URLS` (default: overpass-api.de, then overpass.kumi.systems). This is far below the public server limits. If we later add many states, we should switch to regional extract files from Geofabrik, which do not use Overpass at all.

**Secrets:** the sync writes with the Supabase **secret key** (old name: service role key). This key is stored only as a GitHub Actions secret. It is never in the app or in git.

## 4. Data model

OSM data and community data stay in separate tables (ODbL rule in CLAUDE.md).

```sql
-- Who can do what.
create table profiles (
  id           uuid primary key references auth.users on delete cascade,
  display_name text,
  role         text not null default 'contributor'
               check (role in ('contributor', 'moderator', 'admin')),
  created_at   timestamptz not null default now()
);

-- Copied from OSM by oasis-sync. Read-only for users.
create table osm_points (
  osm_id        text primary key,            -- 'node/123'
  geom          geometry(Point, 4326) not null,
  kind          text,                        -- SpotKind raw value; null when hidden
  hidden_reason text,                        -- e.g. 'access=private'
  tags          jsonb not null,
  survey_date   date,                        -- latest check_date / survey:date
  osm_version   int,
  osm_edited_at timestamptz,
  synced_at     timestamptz not null,
  removed_at    timestamptz                  -- gone from OSM
);
create index on osm_points using gist (geom);

-- Submitted by users. Separate from OSM data.
create table community_spots (
  id           uuid primary key default gen_random_uuid(),
  geom         geometry(Point, 4326) not null,
  kind         text not null,
  name         text,
  description  text,
  status       text not null default 'pending'
               check (status in ('pending', 'approved', 'rejected')),
  submitted_by uuid references profiles on delete set null,  -- approved spots stay after account deletion
  submitted_at timestamptz not null default now(),
  reviewed_by  uuid references profiles,
  reviewed_at  timestamptz,
  review_note  text
);
create index on community_spots using gist (geom);

-- "Working", "not working", and other reports, for either kind of point.
create table spot_reports (
  id                uuid primary key default gen_random_uuid(),
  osm_id            text references osm_points,
  community_spot_id uuid references community_spots on delete cascade,
  reporter          uuid not null references profiles on delete cascade,
  type              text not null check (type in
                    ('working', 'not_working', 'seasonal_off', 'refused', 'not_potable', 'other')),
  note              text check (char_length(note) <= 500),
  created_at        timestamptz not null default now(),
  check (num_nonnulls(osm_id, community_spot_id) = 1)
);
```

**Read API** (Postgres functions that the app calls through PostgREST):
- `spots_in_bbox(west, south, east, north, layers)` returns OSM points (not hidden, not removed) plus approved community spots, with the latest report type and date for each point.
- `spots_near_route(route, buffer_m)` — added in phase 3.

The SQL above is a summary. The source of truth is `supabase/migrations/`. Points use `geometry(Point, 4326)`: box queries on it are exact and use the GiST index. Distance queries in phase 3 can cast to `geography`.

## 5. Verification with reports

This extends `VerificationRules` in `OasisCore`, with tests. The server sends the facts, and `OasisCore` decides.

| Evidence | Result |
|---|---|
| Latest report is `working`, in the last 12 months | **Verified** |
| OSM survey date in the last 24 months, and no newer problem report | **Verified** |
| Latest report is a problem (`not_working`, `not_potable`, `refused`) | **Reported problem** — red warning in the detail sheet; the point stays on the map |
| Anything else | **Unverified** |

"Reported problem" is not a third verification level. It is a warning, and red is our color for problems. **Decision for Mike:** should a point with 2 or more recent problem reports, from different people, be hidden until a moderator checks it?

## 6. Access rules (row-level security)

- A helper function `is_moderator()` checks `profiles.role`. It is `security definer` with a fixed `search_path`.
- `osm_points`: everyone can read. Nobody can write through the API. Only the sync writes, with the secret key.
- `community_spots`: everyone can read approved spots. People can read their own pending spots. Signed-in people can insert a spot only as `pending` and only as themselves. Only moderators can change the status.
- `spot_reports`: signed-in people can insert a report only as themselves. People can read their own reports. Moderators can read all reports. The public map sees only the latest report type and date, through `spots_in_bbox`. It never sees who reported.
- `profiles`: people can read and change their own display name. Only an admin can change a role.
- Limits against spam, in a database trigger: at most 1 report per person per point per hour, and at most 20 submissions per person per day.
- **Tests:** CI starts a Postgres + PostGIS container, applies the migrations, and runs SQL tests for each rule. For example: "a contributor cannot approve a spot" and "a user cannot read another user's reports".

## 7. Sign-in

- **Phase 2 uses an email code.** Supabase sends a 6-digit code by email, and you type it into the app. It needs no password, no web link back to the app, and no Apple Developer Program.
- **Sign in with Apple** needs the Apple Developer Program. We add it when you join the program. The App Store requires Sign in with Apple only when an app offers other third-party sign-in (for example Google). An email code alone does not trigger that rule. Confirm the current App Store Review Guidelines before release.
- **Account deletion:** the App Store requires an in-app way to delete an account. We add a "Delete account" button in phase 2. It deletes the profile, the reports, and the pending submissions. It keeps approved spots, with no link to the person.
- Browsing the map does not need an account. Only reports and submissions need one.

## 8. App changes

- Step 2.3 reads the map with a plain `URLSession` call to `spots_in_bbox` (one request type, parsed in `OasisCore`). Add the `supabase-swift` package (the only third-party dependency allowed by CLAUDE.md) in step 2.5, for sign-in.
- `SupabaseSource: WaterSpotSource` calls `spots_in_bbox`. The tile cache and the 7-day disk cache stay. With our own backend, the 0.5° limit for buy water can grow.
- `OverpassClient` stays only for development, behind a debug setting. The app no longer calls Overpass by default.
- New screens:
  - Sign in (email code).
  - In the detail sheet: "Working" and "Not working" buttons, plus "Other problem…".
  - "Add a water point" (long-press on the map, then a short form).
  - Moderator screen, only for moderators: pending submissions and points with problem reports.
  - Settings: sign out and delete account.
- `WaterSpot.Source.community` already exists for community points.

## 9. Privacy

- We store an email address (for sign-in), a display name, reports, and submissions. We store no location history. The app sends the map area to the server, not the phone's location.
- Reports show no names to other users.
- The App Store privacy label and a short privacy policy are needed before TestFlight or App Store release, not for Mike's own phone.

## 10. Cost

- The Supabase free tier should be enough for Colorado and a few users. I have not confirmed the current free-tier limits (database size, and pausing of inactive projects). Check them on the Supabase pricing page when you create the project.
- GitHub Actions: the weekly sync runs on Linux and is short.

## 11. Build order (small PRs)

| Step | What | Test |
|---|---|---|
| 2.1 | `supabase/` migrations: tables, indexes, RLS, `spots_in_bbox` | SQL tests in CI on Postgres + PostGIS |
| 2.2 | `oasis-sync` tool + weekly workflow; first Colorado sync | Unit tests with fixtures; first run by hand |
| 2.3 | App: `SupabaseSource`; Overpass off by default | CI build; Mike checks on his phone |
| 2.4 | `VerificationRules` with reports | `OasisCore` tests |
| 2.5 | App: sign-in (email code), account deletion | CI build; Mike checks |
| 2.6 | App: reports in the detail sheet | CI build; SQL tests for limits |
| 2.7 | App: add a water point; moderator screen | CI build; SQL tests for RLS |

## 12. Later phases (not in phase 2)

- Phase 3: GPX import, distance to next water, offline download along a route, opening hours.
- Phase 4: photos (Supabase Storage), OSM upload with the user's own OSM account, branding.

## 13. What Mike must do

I cannot create accounts or see secrets. You must do these steps.

**Project (done 2026-09-26):**
- Project ID (ref): `scbkoxbdzaipkxwyvrql`
- API URL: `https://scbkoxbdzaipkxwyvrql.supabase.co` (checked: it answers)
- The API URL and the project ID are not secret.

**PostGIS: no action.** The first migration turns it on with `create extension if not exists postgis with schema extensions;`.

**Keys.** Supabase renamed its keys. The dashboard can change, so look for these names:

| Name now | Old name | Secret? | Where it goes |
|---|---|---|---|
| Publishable key (`sb_publishable_…`) | anon key | No. RLS protects the data. | Send it to Claude. It goes in the app. |
| Secret key (`sb_secret_…`) | service_role key | **Yes.** It skips all access rules. | Only a GitHub secret. Never in a chat or in git. |

To find them: open the project, then **Project Settings → API Keys**. The old keys are on a "Legacy API keys" tab. The **Connect** button at the top of the project page also shows the URL and the publishable key.

**GitHub secrets.** In GitHub → repo Settings → Secrets and variables → Actions → New repository secret, add:
1. `SUPABASE_URL` = `https://scbkoxbdzaipkxwyvrql.supabase.co`
2. `SUPABASE_SECRET_KEY` = the secret key.
3. `SUPABASE_DB_URL` = the database connection string, for migrations from CI. Get it from **Connect** → the **Session pooler** string (port 5432), and put your database password in it. Use the pooler string, not the "direct connection" string: the direct one can need IPv6, and GitHub runners do not have IPv6.

**Publishable key (received 2026-09-26, checked):** `sb_publishable_GIP_IsErO92gY3H5eCBBfg_OS-viury`. It is public by design. The app uses it in step 2.3.

**First sync run (after the three secrets exist):**
1. GitHub → Actions → **Backend** → **Run workflow**.
2. For a first test, set "Only the first N tiles" to `2`. Select **Run workflow**.
3. The "Apply database migrations" job creates the tables. The "Sync OSM points" job prints one line for each tile.
4. When the test run is green, run it again with the tile field empty, for all of Colorado. After that, it runs every Monday.

If `SUPABASE_DB_URL` fails: check that the password in it has no raw `@`, `:`, `/`, or `#`. These characters must be percent-encoded (for example `@` → `%40`), or you can reset the database password to letters and numbers only.

**Sign-in:** later, in step 2.5, I will tell you the exact Auth settings to change.

## 14. Open questions for Mike

1. Should a point with 2 or more recent problem reports be hidden until a moderator checks it? (Section 5.)
2. Is a report 12 months "fresh" enough for "verified"? (OSM survey dates use 24 months.)
3. Who are the first moderators? Only you?
4. Should browsing need an account? (Proposal: no.)
