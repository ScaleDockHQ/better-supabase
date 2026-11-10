-- SLA clock reads on the scale fixture (ADR 0617): 60,000 customers with
-- 12,000 clocks on them, read as a
-- signed-in member. The read policies inline the subject check. The same
-- counts with can_subject added per row (the function the policies called
-- before the change) print beside them. Set bsb.scale_rows to resize.
begin;
select plan(2);

select set_config('bsb.n', coalesce(nullif(current_setting('bsb.scale_rows', true), ''), '60000'), true);

insert into public.customers (organization_id, name)
select '00000000-0000-4000-8000-000000000001', 'Family ' || g
from generate_series(1, current_setting('bsb.n')::int) g;

create temp table picked as
select id from public.customers where name like 'Family %' limit current_setting('bsb.n')::int / 5;

insert into better_supabase.sla_clocks (tenant_id, subject_type, subject_id, metric, started_at, due_at)
select '00000000-0000-4000-8000-000000000001', 'customer', id::text, 'first_response', now(), now() + interval '1 day' from picked;

analyze public.customers;
analyze better_supabase.sla_clocks;

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}', true);
set local role authenticated;

create temp table t0 as select clock_timestamp() as t;
grant all on t0 to public;

select count(*)::bigint as clocks_inlined from better_supabase.sla_clocks where metric = 'first_response' \gset
select diag('SCALE_MS sla_clocks_policy_inlined=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));

update t0 set t = clock_timestamp();
select count(*)::bigint as clocks_perrow from better_supabase.sla_clocks
where metric = 'first_response' and better_supabase.can_subject(subject_type, subject_id, 'read') \gset
select diag('SCALE_MS sla_clocks_can_subject_per_row=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));

select is(:clocks_inlined::bigint, (current_setting('bsb.n')::bigint / 5), 'the member reads every clock on a customer they can read');
select is(:clocks_perrow::bigint, :clocks_inlined::bigint, 'can_subject sees the same clocks');

select * from finish();
rollback;

select pg_stat_statements_reset() is not null as reset \gset
