-- Support for oasis-sync (docs/phase2-backend.md, section 3).
-- The sync upserts every point it sees with synced_at = the run start time.
-- Afterwards, points in the tile that the run did not see are marked removed.
-- Only the service role (the secret key) can call this.

create function public.mark_removed_osm_points(
  west double precision,
  south double precision,
  east double precision,
  north double precision,
  run_started timestamptz
)
returns integer
language plpgsql security definer set search_path = '' as $$
declare
  n integer;
begin
  if west is null or south is null or east is null or north is null or run_started is null
     or west >= east or south >= north then
    raise exception 'Invalid arguments.' using errcode = '22023';
  end if;
  update public.osm_points
     set removed_at = now()
   where removed_at is null
     and synced_at < run_started
     and geom operator(extensions.&&) extensions.st_makeenvelope(west, south, east, north, 4326);
  get diagnostics n = row_count;
  return n;
end;
$$;

revoke execute on function public.mark_removed_osm_points(double precision, double precision,
  double precision, double precision, timestamptz) from public, anon, authenticated;
grant execute on function public.mark_removed_osm_points(double precision, double precision,
  double precision, double precision, timestamptz) to service_role;
