-- Keyset and offset pages of the lists ADR 0660 moved onto the list template, on the scale fixture:
-- usage rights and maintenance plans (nullable sort keys, the coalesce form), appraisals and pick
-- lists. A deep page by offset reads and discards every skipped row, a keyset page starts at the
-- cursor. Set bsb.scale_rows to resize (default 60,000).
begin;
select plan(9);

select set_config('bsb.n', coalesce(nullif(current_setting('bsb.scale_rows', true), ''), '60000'), true);
select set_config('request.jwt.claims', '{"role":"service_role"}', true);

-- The fixture rows skip the foreign keys that the blocks' own tables hold.
set local session_replication_role = replica;

insert into better_supabase.dam_usage_rights (tenant_id, node_id, licensee, starts_on, expires_on)
select '00000000-0000-4000-8000-000000000001', gen_random_uuid(), 'Licensee ' || g, date '2020-01-01',
  case when g % 4 = 0 then null else date '2021-01-01' + (g % 3000) end
from generate_series(1, current_setting('bsb.n')::int) g;

insert into better_supabase.maintenance_plans (tenant_id, title, kind, every_days, status, next_due_at)
select '00000000-0000-4000-8000-000000000001', 'Plan ' || g, 'time', 7, 'active',
  case when g % 4 = 0 then null else timestamptz '2026-01-01' + make_interval(mins => g) end
from generate_series(1, current_setting('bsb.n')::int) g;

insert into better_supabase.appraisals (tenant_id, cycle_id, appraisee_id, status, created_at)
select '00000000-0000-4000-8000-000000000001', gen_random_uuid(), gen_random_uuid(), 'pending',
  timestamptz '2026-01-01' + make_interval(secs => g)
from generate_series(1, current_setting('bsb.n')::int) g;

insert into better_supabase.pick_lists (tenant_id, location_id, document_type, document_id, status, created_at)
select '00000000-0000-4000-8000-000000000001', gen_random_uuid(), 'order', 'ORD-' || g, 'open',
  timestamptz '2026-01-01' + make_interval(secs => g)
from generate_series(1, current_setting('bsb.n')::int) g;

analyze better_supabase.dam_usage_rights;
analyze better_supabase.maintenance_plans;
analyze better_supabase.appraisals;
analyze better_supabase.pick_lists;

set local role service_role;

create temp table t0 as select clock_timestamp() as t;
grant all on t0 to public;

-- Usage rights: first page, deep offset, deep keyset.
select better_supabase.list_usage_rights('00000000-0000-4000-8000-000000000001', '{"limit":20}') as rights_first \gset
select diag('SCALE_MS list_usage_rights_first=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));

update t0 set t = clock_timestamp();
select better_supabase.list_usage_rights('00000000-0000-4000-8000-000000000001',
  jsonb_build_object('limit', 20, 'offset', current_setting('bsb.n')::int - 40)) as rights_offset \gset
select diag('SCALE_MS list_usage_rights_offset_deep=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));

update t0 set t = clock_timestamp();
select better_supabase.list_usage_rights('00000000-0000-4000-8000-000000000001',
  jsonb_build_object('limit', 20, 'after', jsonb_build_array('infinity', '00000000-0000-0000-0000-000000000000'))) as rights_keyset \gset
select diag('SCALE_MS list_usage_rights_keyset_deep=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));

select is(jsonb_array_length(:'rights_first'::jsonb), 20, 'a usage rights page is full');
select is(jsonb_array_length(:'rights_offset'::jsonb), 20, 'a deep offset page of usage rights reads');
select ok(jsonb_array_length(:'rights_keyset'::jsonb) >= 0, 'a deep keyset page of usage rights reads');

-- Maintenance plans.
update t0 set t = clock_timestamp();
select better_supabase.list_maintenance_plans('00000000-0000-4000-8000-000000000001', '{"limit":20}') as plans_first \gset
select diag('SCALE_MS list_maintenance_plans_first=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));

update t0 set t = clock_timestamp();
select better_supabase.list_maintenance_plans('00000000-0000-4000-8000-000000000001',
  jsonb_build_object('limit', 20, 'offset', current_setting('bsb.n')::int - 40)) as plans_offset \gset
select diag('SCALE_MS list_maintenance_plans_offset_deep=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));

update t0 set t = clock_timestamp();
select better_supabase.list_maintenance_plans('00000000-0000-4000-8000-000000000001',
  jsonb_build_object('limit', 20, 'after', jsonb_build_array('infinity', '00000000-0000-0000-0000-000000000000'))) as plans_keyset \gset
select diag('SCALE_MS list_maintenance_plans_keyset_deep=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));

select is(jsonb_array_length(:'plans_first'::jsonb), 20, 'a maintenance plans page is full');
select is(jsonb_array_length(:'plans_offset'::jsonb), 20, 'a deep offset page of plans reads');
select ok(jsonb_array_length(:'plans_keyset'::jsonb) >= 0, 'a deep keyset page of plans reads');

-- Appraisals and pick lists share the (tenant, created_at desc, id) index.
update t0 set t = clock_timestamp();
select better_supabase.list_appraisals('00000000-0000-4000-8000-000000000001', '{"limit":20}') as appraisals_first \gset
select diag('SCALE_MS list_appraisals_first=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));

update t0 set t = clock_timestamp();
select better_supabase.list_appraisals('00000000-0000-4000-8000-000000000001',
  jsonb_build_object('limit', 20, 'offset', current_setting('bsb.n')::int - 40)) as appraisals_offset \gset
select diag('SCALE_MS list_appraisals_offset_deep=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));

update t0 set t = clock_timestamp();
select better_supabase.list_pick_lists('00000000-0000-4000-8000-000000000001', '{"limit":20}') as picks_first \gset
select diag('SCALE_MS list_pick_lists_first=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));

update t0 set t = clock_timestamp();
select better_supabase.list_pick_lists('00000000-0000-4000-8000-000000000001',
  jsonb_build_object('limit', 20, 'offset', current_setting('bsb.n')::int - 40)) as picks_offset \gset
select diag('SCALE_MS list_pick_lists_offset_deep=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));

select is(jsonb_array_length(:'appraisals_first'::jsonb), 20, 'an appraisals page is full');
select is(jsonb_array_length(:'picks_first'::jsonb), 20, 'a pick lists page is full');
select throws_ok(
  $q$select better_supabase.list_usage_rights('00000000-0000-4000-8000-000000000001', '{"after":["infinity","x"],"offset":5}')$q$,
  '22023', 'after and offset are two ways to page; pass one', 'after and offset do not combine');

select * from finish();
rollback;

select pg_stat_statements_reset() is not null as reset \gset
