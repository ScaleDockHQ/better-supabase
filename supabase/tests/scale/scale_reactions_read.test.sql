-- Reaction reads on the scale fixture (ADR 0606): 60,000 customers and 12,000
-- reactions on them, read as a signed-in member. The read policy inlines the
-- subject check, so the planner reads the customers by key and checks the tenant
-- permission once. The same count through reaction_subject_visible per row
-- (the form before the change) prints beside it. Set bsb.scale_rows to resize.
begin;
select plan(2);

select set_config('bsb.n', coalesce(nullif(current_setting('bsb.scale_rows', true), ''), '60000'), true);

insert into public.customers (organization_id, name)
select '00000000-0000-4000-8000-000000000001', 'React ' || g
from generate_series(1, current_setting('bsb.n')::int) g;

insert into better_supabase.reactions (tenant_id, subject_type, subject_id, actor, emoji)
select '00000000-0000-4000-8000-000000000001', 'customer', c.id::text, 'a' || row_number() over (), 'x'
from (select id from public.customers where name like 'React %' limit current_setting('bsb.n')::int / 5) c;
analyze public.customers;
analyze better_supabase.reactions;

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}', true);
set local role authenticated;

create temp table t0 as select clock_timestamp() as t;
grant all on t0 to public;

select count(*)::bigint as inlined from better_supabase.reactions where emoji = 'x' \gset
select diag('SCALE_MS reactions_policy_inlined=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));

update t0 set t = clock_timestamp();
select count(*)::bigint as perrow from better_supabase.reactions
where emoji = 'x' and better_supabase.reaction_subject_visible(subject_type, subject_id, tenant_id) \gset
select diag('SCALE_MS reactions_function_per_row=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));

select is(:inlined::bigint, (current_setting('bsb.n')::bigint / 5), 'the member reads every reaction on a customer they can read');
select is(:perrow::bigint, :inlined::bigint, 'the per-row function sees the same reactions');

select * from finish();
rollback;

-- The statistics are not transactional; a doctor run after pgTAP would report this
-- fixture's temporary files (BS208).
select pg_stat_statements_reset() is not null as reset \gset
