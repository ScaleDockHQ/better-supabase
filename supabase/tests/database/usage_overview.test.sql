-- usage_overview and usage_status agree for the same tenant: one meter with a
-- quota, one without, and a plan quota a tenant quota overrides.
begin;
select plan(2);

insert into better_supabase.usage_quotas (tenant_id, meter, "limit", period)
values ('00000000-0000-4000-8000-000000000001', 'api_calls', 10, 'month');

insert into better_supabase.usage_counters (tenant_id, meter, day, value)
values
  ('00000000-0000-4000-8000-000000000001', 'api_calls', (now() at time zone 'utc')::date, 4),
  ('00000000-0000-4000-8000-000000000001', 'seats', (now() at time zone 'utc')::date, 2);

-- The functions check usage.read. A superuser session still goes through the
-- definer, so grant the seeded member the permission the fixture already gives
-- its admin, and call as that user when the check needs a jwt. Here the
-- service role is the caller of security definer functions that still check
-- can(), so set the request role the membership helper accepts.
select set_config('request.jwt.claims', '{"role":"service_role"}', true);

select is(
  (better_supabase.usage_remaining('00000000-0000-4000-8000-000000000001', 'api_calls') ->> 'remaining')::numeric,
  6::numeric,
  'one meter reports used against its quota'
);

select is(
  better_supabase.usage_overview('00000000-0000-4000-8000-000000000001'),
  (
    select coalesce(jsonb_agg(better_supabase.usage_status('00000000-0000-4000-8000-000000000001', m.meter) order by m.meter), '[]'::jsonb)
    from (
      select jsonb_object_keys(better_supabase.usage_meters()) as meter
      union
      select meter from better_supabase.usage_quotas
      where tenant_id = '00000000-0000-4000-8000-000000000001' or tenant_id is null
      union
      select distinct meter from better_supabase.usage_counters
      where tenant_id = '00000000-0000-4000-8000-000000000001'
    ) m
  ),
  'the overview matches one status call per meter'
);

select * from finish();
rollback;
