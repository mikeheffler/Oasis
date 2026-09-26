-- Tests for supabase/migrations/*_phase2_schema.sql.
-- Run with `supabase test db`. Each block acts as one API role:
-- anon (no account), A and B (contributors), M (moderator).
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(39);

-- ---------------------------------------------------------------- setup (postgres)
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'a@example.com'),
  ('00000000-0000-0000-0000-00000000000b', 'b@example.com'),
  ('00000000-0000-0000-0000-00000000000c', 'm@example.com');
update public.profiles set role = 'moderator' where id = '00000000-0000-0000-0000-00000000000c';

insert into public.osm_points (osm_id, geom, kind, hidden_reason, tags, removed_at) values
  ('node/1', st_setsrid(st_makepoint(-105.00, 39.70), 4326), 'fountain', null, '{"name": "Park fountain"}', null),
  ('node/2', st_setsrid(st_makepoint(-105.01, 39.70), 4326), null, 'access=private', '{}', null),
  ('node/3', st_setsrid(st_makepoint(-105.02, 39.70), 4326), 'tap', null, '{}', now()),
  ('node/4', st_setsrid(st_makepoint(-105.03, 39.70), 4326), 'convenience', null, '{"name": "Corner Market"}', null),
  ('node/5', st_setsrid(st_makepoint(-104.00, 40.50), 4326), 'fountain', null, '{}', null);

select is((select count(*) from public.profiles), 3::bigint,
  'a profile is created for each new account');
select ok((select bool_and(relrowsecurity) from pg_class
           where oid in ('public.profiles'::regclass, 'public.osm_points'::regclass,
                         'public.community_spots'::regclass, 'public.spot_reports'::regclass)),
  'RLS is on for all four tables');

-- ---------------------------------------------------------------- data rules (postgres)
select throws_ok($$ insert into public.osm_points (osm_id, geom, kind) values
  ('node/9', st_setsrid(st_makepoint(0, 0), 4326), 'bogus') $$, '23514', null,
  'an unknown kind is rejected');
select throws_ok($$ insert into public.osm_points (osm_id, geom, kind, hidden_reason) values
  ('node/9', st_setsrid(st_makepoint(0, 0), 4326), 'tap', 'access=no') $$, '23514', null,
  'a point cannot have both a kind and a hide reason');
select throws_ok($$ insert into public.spot_reports (reporter, type) values
  ('00000000-0000-0000-0000-00000000000a', 'working') $$, '23514', null,
  'a report must name exactly one point');

-- ---------------------------------------------------------------- anon
set local role anon;
set local request.jwt.claims = '{"role": "anon"}';

select set_eq($$ select id from public.spots_in_bbox(-105.1, 39.6, -104.9, 39.8, array['freeWater']) $$,
  array['node/1'],
  'anon: free water in the box, without hidden, removed, or far points');
select set_eq($$ select id from public.spots_in_bbox(-105.1, 39.6, -104.9, 39.8) $$,
  array['node/1', 'node/4'],
  'anon: both layers by default');
select set_eq($$ select id from public.spots_in_bbox(-105.1, 39.6, -104.9, 39.8, array['buyWater']) $$,
  array['node/4'],
  'anon: buy water only');
select is((select name from public.spots_in_bbox(-105.1, 39.6, -104.9, 39.8) where id = 'node/1'),
  'Park fountain', 'anon: name comes from the OSM tags');
select throws_ok($$ select * from public.spots_in_bbox(-106, 39, -103, 40) $$, '22023', null,
  'anon: a box wider than 2 degrees is rejected');
select throws_ok($$ select * from public.spots_in_bbox(-105, 40, -106, 39) $$, '22023', null,
  'anon: an inverted box is rejected');
select is((select count(*) from public.osm_points), 5::bigint,
  'anon: can read osm_points directly');
select throws_ok($$ insert into public.osm_points (osm_id, geom, kind) values
  ('node/8', st_setsrid(st_makepoint(0, 0), 4326), 'tap') $$, '42501', null,
  'anon: cannot write osm_points');
select throws_ok($$ select * from public.spot_reports $$, '42501', null,
  'anon: cannot read reports');
select throws_ok($$ insert into public.spot_reports (osm_id, type) values ('node/1', 'working') $$,
  '42501', null, 'anon: cannot report');
select throws_ok($$ insert into public.community_spots (geom, kind) values
  (st_setsrid(st_makepoint(-105, 39.7), 4326), 'tap') $$, '42501', null,
  'anon: cannot submit a spot');

-- ---------------------------------------------------------------- A (contributor)
set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-00000000000a", "role": "authenticated"}';

select lives_ok($$ insert into public.community_spots (geom, kind, name) values
  (st_setsrid(st_makepoint(-105.00, 39.71), 4326), 'tap', 'Trailhead tap') $$,
  'A: can submit a spot');
select is((select status from public.community_spots where name = 'Trailhead tap'), 'pending',
  'A: the new spot is pending');
select throws_ok($$ insert into public.community_spots (geom, kind, status) values
  (st_setsrid(st_makepoint(-105, 39.7), 4326), 'tap', 'approved') $$, '42501', null,
  'A: cannot submit a spot as approved');
select throws_ok($$ select submitted_by from public.community_spots $$, '42501', null,
  'A: cannot read who submitted a spot');
update public.community_spots set status = 'approved' where name = 'Trailhead tap';
select is((select status from public.community_spots where name = 'Trailhead tap'), 'pending',
  'A: cannot approve a spot (the update changes no rows)');
select set_eq($$ select id from public.spots_in_bbox(-105.1, 39.6, -104.9, 39.8, array['freeWater']) $$,
  array['node/1'], 'A: a pending spot is not on the map');

select lives_ok($$ insert into public.spot_reports (osm_id, type) values ('node/1', 'working') $$,
  'A: can report a point');
select throws_ok($$ insert into public.spot_reports (osm_id, type) values ('node/1', 'not_working') $$,
  'P0001', null, 'A: cannot report the same point again within one hour');
select throws_ok($$ insert into public.spot_reports (osm_id, type, reporter) values
  ('node/4', 'working', '00000000-0000-0000-0000-00000000000b') $$, '42501', null,
  'A: cannot report as someone else');
select throws_ok($$ update public.profiles set role = 'admin'
  where id = '00000000-0000-0000-0000-00000000000a' $$, '42501', null,
  'A: cannot change a role');
select lives_ok($$ update public.profiles set display_name = 'Rider A'
  where id = '00000000-0000-0000-0000-00000000000a' $$,
  'A: can change the display name');
select throws_ok($$ insert into public.community_spots (geom, kind)
  select st_setsrid(st_makepoint(-105, 39.7), 4326), 'tap' from generate_series(1, 20) $$,
  'P0001', null, 'A: at most 20 new spots per day');

-- ---------------------------------------------------------------- B (contributor)
set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-00000000000b", "role": "authenticated"}';

select is((select count(*) from public.spot_reports), 0::bigint,
  'B: cannot see the reports of A');
select is((select count(*) from public.community_spots), 0::bigint,
  'B: cannot see the pending spot of A');
select is((select count(*) from public.profiles), 1::bigint,
  'B: can see only the own profile');

-- ---------------------------------------------------------------- M (moderator)
set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-00000000000c", "role": "authenticated"}';

select is((select count(*) from public.spot_reports), 1::bigint,
  'M: can see all reports');
select lives_ok($$ update public.community_spots set status = 'approved', review_note = 'Checked'
  where name = 'Trailhead tap' $$, 'M: can approve a spot');

-- ---------------------------------------------------------------- results (postgres)
reset role;

select is((select reviewed_by from public.community_spots where name = 'Trailhead tap'),
  '00000000-0000-0000-0000-00000000000c'::uuid, 'the reviewer is recorded');

set local role anon;
set local request.jwt.claims = '{"role": "anon"}';
select set_eq($$ select source from public.spots_in_bbox(-105.1, 39.6, -104.9, 39.8, array['freeWater']) $$,
  array['osm', 'community'], 'anon: an approved spot is on the map');
select is((select last_report_type from public.spots_in_bbox(-105.1, 39.6, -104.9, 39.8)
           where id = 'node/1'), 'working', 'anon: the map shows the latest report type');

reset role;
delete from auth.users where id = '00000000-0000-0000-0000-00000000000a';
select is((select count(*) from public.spot_reports), 0::bigint,
  'deleting an account deletes its reports');
select is((select count(*) from public.community_spots where status = 'approved'), 1::bigint,
  'deleting an account keeps its approved spots');
select is((select submitted_by from public.community_spots where name = 'Trailhead tap'), null::uuid,
  'the kept spot is no longer linked to the deleted account');

select * from finish();
rollback;
