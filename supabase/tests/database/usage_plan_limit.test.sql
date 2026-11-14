-- The check a manifest `limits` entry makes (`canConsume`) reads usage_remaining:
-- a plan quota with its counter at the limit leaves nothing, and a tenant
-- quota overrides the plan's.
begin;
select plan(3);

insert into better_supabase.usage_quotas (tenant_id, meter, "limit", period)
values ('00000000-0000-4000-8000-000000000001', 'seats', 3, 'month');

insert into better_supabase.usage_counters (tenant_id, meter, day, value)
values ('00000000-0000-4000-8000-000000000001', 'seats', (now() at time zone 'utc')::date, 3);

select set_config('request.jwt.claims', '{"role":"service_role"}', true);

select is(
  (better_supabase.usage_remaining('00000000-0000-4000-8000-000000000001', 'seats') ->> 'remaining')::numeric,
  0::numeric,
  'a quota used up leaves nothing, so the limit refuses the call'
);

update better_supabase.usage_quotas set "limit" = 5
where tenant_id = '00000000-0000-4000-8000-000000000001' and meter = 'seats';

select is(
  (better_supabase.usage_remaining('00000000-0000-4000-8000-000000000001', 'seats') ->> 'remaining')::numeric,
  2::numeric,
  'a raised quota leaves room again'
);

select is(
  better_supabase.within_quota('00000000-0000-4000-8000-000000000001', 'seats', 2),
  true,
  'a quantity that fits is within the quota'
);

select * from finish();
rollback;
