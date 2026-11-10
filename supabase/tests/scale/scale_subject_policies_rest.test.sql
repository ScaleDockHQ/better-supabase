-- Field history and observation reads on the scale fixture (ADR 0617): 60,000
-- customers with 12,000 field changes and 12,000 observations on them, read
-- as a signed-in member. The read policies inline the subject check. The same
-- counts through the earlier policy form (can_subject per row, recreated
-- inside the transaction) print beside them. Set bsb.scale_rows to resize.
begin;
select plan(4);

select set_config('bsb.n', coalesce(nullif(current_setting('bsb.scale_rows', true), ''), '60000'), true);

insert into public.customers (organization_id, name)
select '00000000-0000-4000-8000-000000000001', 'Policy ' || g
from generate_series(1, current_setting('bsb.n')::int) g;

create temp table picked as
select id from public.customers where name like 'Policy %' limit current_setting('bsb.n')::int / 5;

insert into better_supabase.field_changes (tenant_id, subject_type, subject_id, field, old_value, new_value)
select '00000000-0000-4000-8000-000000000001', 'customer', id::text, 'name', '"a"', '"b"' from picked;

insert into better_supabase.observations (tenant_id, definition_id, subject_type, subject_id, value_number)
select '00000000-0000-4000-8000-000000000001', (select id from better_supabase.observation_definitions where key = 'heart_rate' and tenant_id is null),
  'customer', id::text, 70
from picked;

analyze public.customers;
analyze better_supabase.field_changes;
analyze better_supabase.observations;

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}', true);
set local role authenticated;

create temp table t0 as select clock_timestamp() as t;
grant all on t0 to public;

select count(*)::bigint as history_inlined from better_supabase.field_changes where field = 'name' \gset
select diag('SCALE_MS field_changes_policy_inlined=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));

update t0 set t = clock_timestamp();
select count(*)::bigint as obs_inlined from better_supabase.observations where value_number = 70 \gset
select diag('SCALE_MS observations_policy_inlined=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));

reset role;
drop policy bsb_field_changes_read on better_supabase.field_changes;
create policy bsb_field_changes_read on better_supabase.field_changes for select to authenticated
  using (tenant_id in (select better_supabase.tenant_ids_with('field_history.read')) and coalesce(better_supabase.can_subject(subject_type, subject_id, 'read'), false));
drop policy bsb_observations_read on better_supabase.observations;
create policy bsb_observations_read on better_supabase.observations for select to authenticated
  using (tenant_id in (select better_supabase.tenant_ids_with('observations.read')) and coalesce(better_supabase.can_subject(subject_type, subject_id, 'read'), false));
set local role authenticated;

update t0 set t = clock_timestamp();
select count(*)::bigint as history_perrow from better_supabase.field_changes where field = 'name' \gset
select diag('SCALE_MS field_changes_policy_per_row=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));

update t0 set t = clock_timestamp();
select count(*)::bigint as obs_perrow from better_supabase.observations where value_number = 70 \gset
select diag('SCALE_MS observations_policy_per_row=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));

select is(:history_inlined::bigint, (current_setting('bsb.n')::bigint / 5), 'the member reads every field change on a customer they can read');
select is(:history_perrow::bigint, :history_inlined::bigint, 'the per-row policy sees the same field changes');
select is(:obs_inlined::bigint, (current_setting('bsb.n')::bigint / 5), 'the member reads every observation on a customer they can read');
select is(:obs_perrow::bigint, :obs_inlined::bigint, 'the per-row policy sees the same observations');

select * from finish();
rollback;

select pg_stat_statements_reset() is not null as reset \gset
