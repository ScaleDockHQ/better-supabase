-- A 1,000-row customers import batch (ADR 0427): one import_upsert_batch call
-- as the service role, with the function-call counts of the triggers it fires.
-- The numbers go to SCALE_MS and SCALE_CALLS diag lines; the assertions hold
-- the trigger counts the scale work set (search once per record, no audit
-- function per row in summary mode).
begin;
select plan(4);

set local track_functions = 'all';
set constraints all immediate;

create function pg_temp.calls(fn regprocedure) returns int language sql as $$
  select coalesce(pg_stat_get_xact_function_calls(fn), 0)::int
$$;

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

select set_config('better_supabase.run', (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'scale-batch', '{}'::jsonb) ->> 'id'), true);
select better_supabase.mark_import_running(current_setting('better_supabase.run')::uuid);

create temp table marks (name text, t timestamptz, refresh int, audit int);
grant all on marks to public;
insert into marks values ('start', clock_timestamp(),
  pg_temp.calls('better_supabase.search_refresh(text, text)'::regprocedure),
  pg_temp.calls('better_supabase.audit_row_change()'::regprocedure));

select (better_supabase.import_upsert_batch(
  current_setting('better_supabase.run')::uuid, 'customer',
  (select jsonb_agg(jsonb_build_object('key', 'sb-' || g, 'scope', '', 'data', jsonb_build_object('name', 'Scale batch ' || g, 'kvk', 'k' || g), 'refs', '{}'::jsonb))
   from generate_series(1, 1000) g)
) ->> 'inserted')::int as inserted \gset

insert into marks values ('end', clock_timestamp(),
  pg_temp.calls('better_supabase.search_refresh(text, text)'::regprocedure),
  pg_temp.calls('better_supabase.audit_row_change()'::regprocedure));

select diag('SCALE_MS import_batch_1000=' || round(extract(epoch from (select t from marks where name = 'end') - (select t from marks where name = 'start')) * 1000));
select diag('SCALE_CALLS search_refresh=' || ((select refresh from marks where name = 'end') - (select refresh from marks where name = 'start'))
  || ' audit_row_change=' || ((select audit from marks where name = 'end') - (select audit from marks where name = 'start')));

select is(:inserted, 1000, 'the batch inserts 1,000 customers');
select is(
  (select refresh from marks where name = 'end') - (select refresh from marks where name = 'start'),
  1000,
  'search_refresh runs once per record'
);
select is(
  (select audit from marks where name = 'end') - (select audit from marks where name = 'start'),
  0,
  'no audit_row_change in a summary import'
);
select is(
  (select count(*)::int from better_supabase.search_documents where title like 'Scale batch %'),
  1000,
  'every record is indexed'
);

select * from finish();
rollback;
