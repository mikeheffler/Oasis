-- Tests for supabase/migrations/*_osm_sync.sql.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(9);

-- Three points in the tile 39..40 N, 105..104 W, and one outside it.
insert into public.osm_points (osm_id, geom, kind, synced_at) values
  ('node/1', st_setsrid(st_makepoint(-104.9, 39.7), 4326), 'fountain', '2026-01-01T00:00:00Z'),
  ('node/2', st_setsrid(st_makepoint(-104.8, 39.7), 4326), 'tap',      '2026-09-27T10:00:00Z'),
  ('node/3', st_setsrid(st_makepoint(-104.7, 39.7), 4326), 'tap',      '2026-01-01T00:00:00Z'),
  ('node/4', st_setsrid(st_makepoint(-103.5, 39.7), 4326), 'tap',      '2026-01-01T00:00:00Z');
update public.osm_points set removed_at = '2026-05-01T00:00:00Z' where osm_id = 'node/3';

-- ---------------------------------------------------------------- who can call it
set local role anon;
select throws_ok($$ select public.mark_removed_osm_points(-105, 39, -104, 40, now()) $$, '42501', null,
  'anon cannot mark points removed');
set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-00000000000a", "role": "authenticated"}';
select throws_ok($$ select public.mark_removed_osm_points(-105, 39, -104, 40, now()) $$, '42501', null,
  'a signed-in user cannot mark points removed');
set local role authenticated;
select throws_ok($$ update public.osm_points set removed_at = now() $$, '42501', null,
  'a signed-in user cannot change osm_points');

-- ---------------------------------------------------------------- the sync (service role)
set local role service_role;
select throws_ok($$ select public.mark_removed_osm_points(-104, 39, -105, 40, now()) $$, '22023', null,
  'an inverted tile is rejected');
select is(public.mark_removed_osm_points(-105, 39, -104, 40, '2026-09-27T09:00:00Z'), 1,
  'only the old, present point in the tile is marked removed');
reset role;
select ok((select removed_at is not null from public.osm_points where osm_id = 'node/1'),
  'the point that the run did not see is now removed');
select ok((select removed_at is null from public.osm_points where osm_id = 'node/2'),
  'the point that the run saw stays');
select ok((select removed_at = '2026-05-01T00:00:00Z' from public.osm_points where osm_id = 'node/3'),
  'an already removed point keeps its first removal time');
select ok((select removed_at is null from public.osm_points where osm_id = 'node/4'),
  'a point outside the tile is not touched');

select * from finish();
rollback;
