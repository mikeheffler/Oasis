-- Phase 2 schema (docs/phase2-backend.md, sections 4-6).
-- OSM data and community data stay in separate tables (ODbL).
-- Kind values are the raw values of OasisCore SpotKind. Keep them in sync.

create extension if not exists postgis with schema extensions;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  display_name text check (char_length(display_name) between 1 and 40),
  role         text not null default 'contributor'
               check (role in ('contributor', 'moderator', 'admin')),
  created_at   timestamptz not null default now()
);

-- Copied from OSM by oasis-sync (service role). Read-only for users.
create table public.osm_points (
  osm_id        text primary key check (osm_id ~ '^(node|way|relation)/[0-9]+$'),
  geom          extensions.geometry(Point, 4326) not null,
  kind          text check (kind in ('fountain', 'tap', 'business', 'convenience',
                                     'grocery', 'restaurant', 'other')),
  hidden_reason text,
  tags          jsonb not null default '{}'::jsonb,
  survey_date   date,
  osm_version   integer,
  osm_edited_at timestamptz,
  synced_at     timestamptz not null default now(),
  removed_at    timestamptz,
  -- Exactly one of: a kind (shown) or a reason (hidden by OSMRules).
  check ((kind is null) <> (hidden_reason is null))
);
create index osm_points_geom_idx on public.osm_points using gist (geom);

create table public.community_spots (
  id           uuid primary key default gen_random_uuid(),
  geom         extensions.geometry(Point, 4326) not null,
  kind         text not null check (kind in ('fountain', 'tap', 'business', 'convenience',
                                               'grocery', 'restaurant', 'other')),
  name         text check (char_length(name) between 1 and 120),
  description  text check (char_length(description) <= 1000),
  status       text not null default 'pending'
               check (status in ('pending', 'approved', 'rejected')),
  -- Null after the submitter deletes the account: approved spots stay, unlinked.
  submitted_by uuid default auth.uid() references public.profiles (id) on delete set null,
  submitted_at timestamptz not null default now(),
  reviewed_by  uuid references public.profiles (id) on delete set null,
  reviewed_at  timestamptz,
  review_note  text check (char_length(review_note) <= 500)
);
create index community_spots_geom_idx on public.community_spots using gist (geom);
create index community_spots_submitter_idx on public.community_spots (submitted_by, submitted_at desc);

create table public.spot_reports (
  id                uuid primary key default gen_random_uuid(),
  osm_id            text references public.osm_points (osm_id) on delete cascade,
  community_spot_id uuid references public.community_spots (id) on delete cascade,
  reporter          uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  type              text not null check (type in ('working', 'not_working', 'seasonal_off',
                                                   'refused', 'not_potable', 'other')),
  note              text check (char_length(note) <= 500),
  created_at        timestamptz not null default now(),
  check (num_nonnulls(osm_id, community_spot_id) = 1)
);
create index spot_reports_osm_idx on public.spot_reports (osm_id, created_at desc);
create index spot_reports_community_idx on public.spot_reports (community_spot_id, created_at desc);
create index spot_reports_reporter_idx on public.spot_reports (reporter, created_at desc);

-- ---------------------------------------------------------------------------
-- Functions and triggers
-- ---------------------------------------------------------------------------

-- A profile for every new account.
create function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id) values (new.id);
  return new;
end;
$$;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create function public.is_moderator()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role in ('moderator', 'admin')
  );
$$;

-- At most 1 report per person per point per hour.
create function public.limit_report_rate()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if exists (
    select 1 from public.spot_reports r
    where r.reporter = new.reporter
      and r.osm_id is not distinct from new.osm_id
      and r.community_spot_id is not distinct from new.community_spot_id
      and r.created_at > now() - interval '1 hour'
  ) then
    raise exception 'You already reported this point in the last hour.' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
create trigger spot_reports_rate_limit
  before insert on public.spot_reports
  for each row execute function public.limit_report_rate();

-- At most 20 submissions per person per day.
create function public.limit_submission_rate()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if (
    select count(*) from public.community_spots s
    where s.submitted_by = new.submitted_by
      and s.submitted_at > now() - interval '1 day'
  ) >= 20 then
    raise exception 'Too many new points today. Try again tomorrow.' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
create trigger community_spots_rate_limit
  before insert on public.community_spots
  for each row execute function public.limit_submission_rate();

-- Record who reviewed a spot and when.
create function public.stamp_review()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.status is distinct from old.status then
    new.reviewed_by := auth.uid();
    new.reviewed_at := now();
  end if;
  return new;
end;
$$;
create trigger community_spots_stamp_review
  before update on public.community_spots
  for each row execute function public.stamp_review();

-- Map read API: OSM points (not hidden, not removed) plus approved community spots,
-- each with its latest report. Never returns who reported or who submitted.
create function public.spots_in_bbox(
  west double precision,
  south double precision,
  east double precision,
  north double precision,
  layers text[] default array['freeWater', 'buyWater']
)
returns table (
  source           text,
  id               text,
  lat              double precision,
  lon              double precision,
  kind             text,
  name             text,
  tags             jsonb,
  survey_date      date,
  osm_edited_at    timestamptz,
  last_report_type text,
  last_report_at   timestamptz
)
language plpgsql stable security definer set search_path = '' as $$
declare
  kinds text[] := '{}';
  box   extensions.geometry;
begin
  if west is null or south is null or east is null or north is null
     or west >= east or south >= north then
    raise exception 'Invalid box.' using errcode = '22023';
  end if;
  if east - west > 2 or north - south > 2 then
    raise exception 'Box too large: at most 2 degrees on each side.' using errcode = '22023';
  end if;
  -- Same split as OasisCore SpotKind.layer.
  if 'freeWater' = any (layers) then
    kinds := kinds || array['fountain', 'tap', 'business', 'other'];
  end if;
  if 'buyWater' = any (layers) then
    kinds := kinds || array['convenience', 'grocery', 'restaurant'];
  end if;
  box := extensions.st_makeenvelope(west, south, east, north, 4326);

  return query
  select 'osm'::text, p.osm_id,
         extensions.st_y(p.geom), extensions.st_x(p.geom),
         p.kind, p.tags ->> 'name', p.tags, p.survey_date, p.osm_edited_at,
         lr.type, lr.created_at
  from public.osm_points p
  left join lateral (
    select r.type, r.created_at from public.spot_reports r
    where r.osm_id = p.osm_id
    order by r.created_at desc limit 1
  ) lr on true
  where p.geom operator(extensions.&&) box
    and p.kind = any (kinds)
    and p.removed_at is null
  union all
  select 'community'::text, c.id::text,
         extensions.st_y(c.geom), extensions.st_x(c.geom),
         c.kind, c.name,
         jsonb_strip_nulls(jsonb_build_object('name', c.name, 'description', c.description)),
         null::date, null::timestamptz,
         lr.type, lr.created_at
  from public.community_spots c
  left join lateral (
    select r.type, r.created_at from public.spot_reports r
    where r.community_spot_id = c.id
    order by r.created_at desc limit 1
  ) lr on true
  where c.geom operator(extensions.&&) box
    and c.kind = any (kinds)
    and c.status = 'approved'
  limit 5000;
end;
$$;

-- ---------------------------------------------------------------------------
-- Privileges. Start from nothing, then grant only what the API needs.
-- The service role (oasis-sync, dashboard) keeps full access and skips RLS.
-- ---------------------------------------------------------------------------

revoke all on public.profiles, public.osm_points, public.community_spots, public.spot_reports
  from anon, authenticated;

grant select on public.osm_points to anon, authenticated;

-- submitted_by and reviewed_by are not readable through the API.
grant select (id, geom, kind, name, description, status, submitted_at, reviewed_at, review_note)
  on public.community_spots to anon, authenticated;
grant insert (geom, kind, name, description) on public.community_spots to authenticated;
grant update (status, review_note) on public.community_spots to authenticated;

grant select on public.spot_reports to authenticated;
grant insert (osm_id, community_spot_id, type, note) on public.spot_reports to authenticated;

grant select on public.profiles to authenticated;
grant update (display_name) on public.profiles to authenticated;

revoke execute on function public.handle_new_user(), public.limit_report_rate(),
  public.limit_submission_rate(), public.stamp_review()
  from public, anon, authenticated;
revoke execute on function public.is_moderator(), public.spots_in_bbox(double precision,
  double precision, double precision, double precision, text[]) from public;
grant execute on function public.is_moderator() to anon, authenticated;
grant execute on function public.spots_in_bbox(double precision, double precision,
  double precision, double precision, text[]) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.osm_points enable row level security;
alter table public.community_spots enable row level security;
alter table public.spot_reports enable row level security;

create policy "profiles: read own, moderators read all"
  on public.profiles for select to authenticated
  using (id = (select auth.uid()) or (select public.is_moderator()));
create policy "profiles: update own"
  on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

create policy "osm_points: everyone reads"
  on public.osm_points for select to anon, authenticated
  using (true);

create policy "community_spots: approved, own, or moderator"
  on public.community_spots for select to anon, authenticated
  using (status = 'approved'
         or submitted_by = (select auth.uid())
         or (select public.is_moderator()));
create policy "community_spots: insert own, pending only"
  on public.community_spots for insert to authenticated
  with check (submitted_by = (select auth.uid()) and status = 'pending');
create policy "community_spots: moderators review"
  on public.community_spots for update to authenticated
  using ((select public.is_moderator()))
  with check ((select public.is_moderator()));

create policy "spot_reports: own, or moderator"
  on public.spot_reports for select to authenticated
  using (reporter = (select auth.uid()) or (select public.is_moderator()));
create policy "spot_reports: insert own"
  on public.spot_reports for insert to authenticated
  with check (reporter = (select auth.uid()));
