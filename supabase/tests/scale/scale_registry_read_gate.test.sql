-- The registry read gate (ADR 1232) on the care, funding and deadlines tables. Planning
-- a read used to expand a 55-branch CASE in each of two policies, so a signed-in
-- read of one table touched thousands of catalog pages before it ran. The plan
-- of each table now stays small, and the rows still match the per-row
-- can_subject answer. Set bsb.scale_rows to resize.
begin;
select plan(9);

select set_config('bsb.n', coalesce(nullif(current_setting('bsb.scale_rows', true), ''), '12000'), true);

create function pg_temp.plan_of(text) returns jsonb language plpgsql as $$
declare result jsonb;
begin
  execute 'explain (format json, buffers, summary) ' || $1 into result;
  return result;
end $$;
grant execute on function pg_temp.plan_of(text) to public;

insert into public.customers (organization_id, name)
select '00000000-0000-4000-8000-000000000001', 'Gate ' || g
from generate_series(1, current_setting('bsb.n')::int) g;

insert into better_supabase.funding_products (id, tenant_id, code, title, unit, rate, currency)
values ('00000000-0000-4000-8000-00000000f001', '00000000-0000-4000-8000-000000000001', 'GATE', 'Gate', 'hour', 100, 'EUR');

insert into better_supabase.funding_awards (tenant_id, subject_type, subject_id, funder_id, product_id, units, period, starts_on)
select '00000000-0000-4000-8000-000000000001', 'customer', c.id::text, gen_random_uuid(), '00000000-0000-4000-8000-00000000f001', 1, 'month', current_date
from public.customers c where c.name like 'Gate %';

analyze public.customers;
analyze better_supabase.funding_awards;

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}', true);
set local role authenticated;

-- One plan per fix. The planning buffers were 7,600 to 9,800 with the CASE and are about 1,200 now.
select cmp_ok(
  (pg_temp.plan_of('select id from better_supabase.funding_awards')->0->'Planning'->>'Shared Hit Blocks')::int,
  '<', 3000, 'funding_awards plans in under 3,000 buffers');
select cmp_ok(
  (pg_temp.plan_of('select id from better_supabase.medication_orders')->0->'Planning'->>'Shared Hit Blocks')::int,
  '<', 3000, 'medication_orders plans in under 3,000 buffers');
select cmp_ok(
  (pg_temp.plan_of('select id from better_supabase.observations')->0->'Planning'->>'Shared Hit Blocks')::int,
  '<', 3000, 'observations plans in under 3,000 buffers');
select cmp_ok(
  (pg_temp.plan_of('select id from better_supabase.consents')->0->'Planning'->>'Shared Hit Blocks')::int,
  '<', 3000, 'consents plans in under 3,000 buffers');
select cmp_ok(
  (pg_temp.plan_of('select id from better_supabase.field_changes')->0->'Planning'->>'Shared Hit Blocks')::int,
  '<', 3000, 'field_changes plans in under 3,000 buffers');

select cmp_ok(
  (pg_temp.plan_of('select id from better_supabase.funding_deliveries')->0->'Planning'->>'Shared Hit Blocks')::int,
  '<', 3000, 'funding_deliveries plans in under 3,000 buffers');
select cmp_ok(
  (pg_temp.plan_of('select id from better_supabase.deadlines')->0->'Planning'->>'Shared Hit Blocks')::int,
  '<', 3000, 'deadlines plans in under 3,000 buffers');

create temp table t0 as select clock_timestamp() as t;
grant all on t0 to public;

select count(*)::bigint as awards_gated from better_supabase.funding_awards
where product_id = '00000000-0000-4000-8000-00000000f001' \gset
select diag('SCALE_MS funding_awards_gate=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));

update t0 set t = clock_timestamp();
select count(*)::bigint as awards_perrow from better_supabase.funding_awards
where product_id = '00000000-0000-4000-8000-00000000f001' and better_supabase.can_subject(subject_type, subject_id, 'read') \gset
select diag('SCALE_MS funding_awards_can_subject_per_row=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));

select is(:awards_gated::bigint, current_setting('bsb.n')::bigint, 'the member reads every award on a customer they can read');
select is(:awards_perrow::bigint, :awards_gated::bigint, 'can_subject sees the same awards');

select * from finish();
rollback;
