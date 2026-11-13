-- usage_quotas_for over 50 tenants and 10 meters: the plans and entitlements
-- are read once per distinct tenant, not once per tenant and meter, and every
-- pair gets the quota usage_quota returns for it. SCALE_CALLS counts the
-- tenant_entitlements calls.
begin;
select plan(3);

set local track_functions = 'all';

insert into better_supabase.usage_quotas (plan, meter, "limit", period)
select 'scale_plan', 'scale_quota_' || g, 1000, case when g % 2 = 0 then 'day' else 'month' end
from generate_series(1, 10) g;
insert into better_supabase.usage_quotas (plan, meter, "limit", period)
select '*', 'scale_quota_' || g, null, 'month'
from generate_series(1, 3) g;
insert into better_supabase.usage_quotas (tenant_id, meter, "limit", period)
select ('00000000-0000-4000-8000-' || lpad(t::text, 12, '0'))::uuid, 'scale_quota_4', 7, 'week'
from generate_series(1, 50, 5) t;

create temp table pairs as
select ('00000000-0000-4000-8000-' || lpad(t::text, 12, '0'))::uuid as tenant, 'scale_quota_' || m as meter
from generate_series(1, 50) t, generate_series(1, 10) m;

create function pg_temp.calls(fn text) returns bigint language sql as
$$ select coalesce(pg_stat_get_xact_function_calls(fn::regprocedure), 0) $$;

create temp table t0 as select clock_timestamp() as t,
  pg_temp.calls('better_supabase.tenant_entitlements(uuid)') as entitlements;

create temp table got as
select * from better_supabase.usage_quotas_for(
  (select array_agg(distinct tenant) from pairs),
  (select array_agg(distinct meter) from pairs)
);
select pg_temp.calls('better_supabase.tenant_entitlements(uuid)') - (select entitlements from t0) as entitlement_calls \gset
select diag('SCALE_MS usage_quotas_for=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000, 1)
  || ' SCALE_CALLS entitlements ' || :entitlement_calls);

select cmp_ok(:entitlement_calls::bigint, '<=', 50::bigint, 'the entitlements are read once per tenant, not once per pair');
select cmp_ok((select count(*)::int from got), '>=', 160, 'the tenant and every-plan quotas come back');
select set_eq(
  'select g.tenant, g.meter, g.quota_limit, g.period from got g',
  'select p.tenant, p.meter, q.quota_limit, q.period from pairs p cross join lateral better_supabase.usage_quota(p.tenant, p.meter) q',
  'each pair gets the quota usage_quota returns, and no other'
);

select * from finish();
rollback;
