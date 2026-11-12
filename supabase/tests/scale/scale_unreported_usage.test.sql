-- unreported_usage on 1,000 unreported counters of 20 tenants: the plans and
-- entitlements are read once per tenant, the quota once per tenant and meter,
-- and the window start once per tenant, period and day. SCALE_CALLS counts the
-- tenant_entitlements and usage_window_start calls.
begin;
select plan(3);

set local track_functions = 'all';

insert into better_supabase.usage_quotas (plan, meter, "limit", period)
select 'scale_plan', 'scale_meter_' || g, 1000, case when g % 2 = 0 then 'day' else 'month' end
from generate_series(1, 10) g;

insert into better_supabase.usage_counters (tenant_id, meter, day, value, reported_value)
select ('00000000-0000-4000-8000-' || lpad(t::text, 12, '0'))::uuid, 'scale_meter_' || m, current_date - d, 10 + d, 0
from generate_series(1, 20) t, generate_series(1, 10) m, generate_series(0, 4) d;

create function pg_temp.calls(fn text) returns bigint language sql as
$$ select coalesce(pg_stat_get_xact_function_calls(fn::regprocedure), 0) $$;

create temp table t0 as select clock_timestamp() as t,
  pg_temp.calls('better_supabase.tenant_entitlements(uuid)') as entitlements,
  pg_temp.calls('better_supabase.usage_window_start(uuid, text, date)') as windows;

select better_supabase.unreported_usage(1000) as rows \gset
select pg_temp.calls('better_supabase.tenant_entitlements(uuid)') - (select entitlements from t0) as entitlement_calls \gset
select pg_temp.calls('better_supabase.usage_window_start(uuid, text, date)') - (select windows from t0) as window_calls \gset
select diag('SCALE_MS unreported_usage=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000, 1)
  || ' SCALE_CALLS entitlements ' || :entitlement_calls || ' windows ' || :window_calls);

select is(jsonb_array_length(:'rows'::jsonb), 1000, 'every unreported counter is listed');
select cmp_ok(:entitlement_calls::bigint, '<=', 20::bigint, 'the entitlements are read once per tenant, not once per counter');
select cmp_ok(:window_calls::bigint, '<=', 200::bigint, 'the window start is computed once per tenant, period and day');

select * from finish();
rollback;
