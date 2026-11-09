-- 3,000 new customers through the set-based batch target and through the
-- one-row target (ADR 0436). Timings print as SCALE_MS lines.
begin;
select plan(2);

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

create function pg_temp.items(prefix text) returns jsonb language sql as $$
  select jsonb_agg(jsonb_build_object('key', prefix || g, 'scope', '', 'data', jsonb_build_object('name', 'Target ' || g, 'kvk', prefix || g), 'refs', '{}'::jsonb))
  from generate_series(1, 3000) g
$$;

create temp table t0 (t timestamptz);
grant all on t0 to public;

select set_config('bsb.a', (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'target-batch', '{}'::jsonb) ->> 'id'), true);
select better_supabase.mark_import_running(current_setting('bsb.a')::uuid);
insert into t0 values (clock_timestamp());
select (better_supabase.import_upsert_batch(current_setting('bsb.a')::uuid, 'customer', pg_temp.items('b')) ->> 'inserted')::int as batch_inserted \gset
select diag('SCALE_MS import_batch_target_3000=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));

select set_config('bsb.b', (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'target-row', '{}'::jsonb) ->> 'id'), true);
select better_supabase.mark_import_running(current_setting('bsb.b')::uuid);
delete from t0;
insert into t0 values (clock_timestamp());
select (better_supabase.import_upsert_batch(current_setting('bsb.b')::uuid, 'customer_row', pg_temp.items('r')) ->> 'inserted')::int as row_inserted \gset
select diag('SCALE_MS import_row_target_3000=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));

select is(:batch_inserted, 3000, 'the batch target inserted every item');
select is(:row_inserted, 3000, 'the row target inserted every item');

select * from finish();
rollback;

-- The statistics are not transactional; a doctor run after pgTAP would report this
-- fixture's temporary files (BS208).
select pg_stat_statements_reset() is not null as reset \gset
