-- Count modes on the scale fixture (ADR 0425): the exact count scans every
-- visible row, the estimated count stops at the PostgREST threshold and asks
-- the planner above it. Set bsb.scale_rows to resize (default 1,000,000).
begin;
select plan(3);

select set_config('bsb.n', coalesce(nullif(current_setting('bsb.scale_rows', true), ''), '1000000'), true);

insert into public.customers (organization_id, name)
select '00000000-0000-4000-8000-000000000001', 'Count ' || g
from generate_series(1, current_setting('bsb.n')::int) g;
analyze public.customers;

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}', true);
set local role authenticated;

create temp table t0 as select clock_timestamp() as t;
grant all on t0 to public;

select count(*)::bigint as exact from public.customers where name like 'Count %' \gset
select diag('SCALE_MS count_exact=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));

update t0 set t = clock_timestamp();
select count(*)::bigint as capped from (select 1 from public.customers where name like 'Count %' limit 1001) c \gset
select diag('SCALE_MS count_capped_1001=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));

select is(:capped::int, 1001, 'the capped count stops one past the threshold');
select ok(:exact::bigint >= :capped::bigint, 'the exact count is at least the capped one');
select is(:exact::bigint, current_setting('bsb.n')::bigint, 'the exact count sees every row');

select * from finish();
rollback;
