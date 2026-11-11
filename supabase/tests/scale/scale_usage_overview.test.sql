-- usage_overview on 20 meters with quotas and counters (ADR 0675): one call reads
-- the tenant's plans and entitlements once and the window once per period. The
-- per-meter form (usage_status for each meter, what usage_overview did before
-- 0.58) prints beside it, and both return the same rows. SCALE_CALLS counts the
-- tenant_entitlements calls of each.
begin;
select plan(3);

set local track_functions = 'all';

insert into better_supabase.usage_quotas (plan, meter, "limit", period)
select '*', 'scale_meter_' || g, 1000, case when g % 3 = 0 then 'day' else 'month' end
from generate_series(1, 20) g;

insert into better_supabase.usage_counters (tenant_id, meter, day, value)
select '00000000-0000-4000-8000-000000000001', 'scale_meter_' || g, current_date, g
from generate_series(1, 20) g;

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}', true);
set local role authenticated;

create function pg_temp.entitlement_calls() returns bigint language sql as
$$ select coalesce(pg_stat_get_xact_function_calls('better_supabase.tenant_entitlements(uuid)'::regprocedure), 0) $$;

create temp table t0 as select clock_timestamp() as t, pg_temp.entitlement_calls() as calls;

select better_supabase.usage_overview('00000000-0000-4000-8000-000000000001') as overview \gset
select pg_temp.entitlement_calls() - (select calls from t0) as overview_calls \gset
select diag('SCALE_MS usage_overview=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000, 1) || ' SCALE_CALLS ' || :overview_calls);

update t0 set t = clock_timestamp(), calls = pg_temp.entitlement_calls();
select jsonb_agg(better_supabase.usage_status('00000000-0000-4000-8000-000000000001', m.meter) order by m.meter) as per_meter
from (select jsonb_array_elements(:'overview'::jsonb) ->> 'meter' as meter) m \gset
select diag('SCALE_MS usage_status_per_meter=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000, 1) || ' SCALE_CALLS ' || (pg_temp.entitlement_calls() - (select calls from t0)));

select cmp_ok(jsonb_array_length(:'overview'::jsonb), '>=', 20, 'usage_overview lists every meter with a quota');
select is(:'overview'::jsonb, :'per_meter'::jsonb, 'usage_overview matches usage_status per meter');
select cmp_ok(:overview_calls::bigint, '<=', 2::bigint, 'usage_overview reads the tenant''s entitlements once, not once per quota');

select * from finish();
rollback;
