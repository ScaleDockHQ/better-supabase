-- A 1,000-row customers import run (ADR 0427, ADR 0844): three
-- import_upsert_batch calls as the service role that touch the same records,
-- then finish_import_run, with the function-call counts of the triggers they
-- fire. customers is searched through statement triggers (search.statement)
-- and audited with audit(statement => true) for this test only. The numbers go
-- to SCALE_MS and SCALE_CALLS diag lines; the assertions hold the counts the
-- scale work set: no search_refresh during the batches, one per record when
-- the run closes, and no row-level audit or search trigger.
begin;
select plan(8);

set local track_functions = 'all';
set constraints all immediate;

create function pg_temp.calls(fn regprocedure) returns int language sql as $$
  select coalesce(pg_stat_get_xact_function_calls(fn), 0)::int
$$;

select better_supabase.audit('public.customers', ignore => '{updated_at}', statement => true);

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

select set_config('better_supabase.run', (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'scale-batch', '{}'::jsonb) ->> 'id'), true);
select better_supabase.mark_import_running(current_setting('better_supabase.run')::uuid);

create temp table marks (name text, t timestamptz, refresh int, row_audit int, row_search int, stmt_search int);
grant all on marks to public;
create function pg_temp.mark(label text) returns void language sql as $$
  insert into marks values (label, clock_timestamp(),
    pg_temp.calls('better_supabase.search_refresh(text, text)'::regprocedure),
    pg_temp.calls('better_supabase.audit_row_change()'::regprocedure),
    pg_temp.calls('better_supabase.search_index_row()'::regprocedure),
    pg_temp.calls('better_supabase.search_index_stmt()'::regprocedure))
$$;
create function pg_temp.batch(label text) returns jsonb language sql as $$
  select better_supabase.import_upsert_batch(
    current_setting('better_supabase.run')::uuid, 'customer',
    (select jsonb_agg(jsonb_build_object('key', 'sb-' || g, 'scope', '', 'data', jsonb_build_object('name', label || ' ' || g, 'kvk', 'k' || g), 'refs', '{}'::jsonb))
     from generate_series(1, 1000) g)
  )
$$;
create function pg_temp.delta(fn text, a text, b text) returns int language plpgsql as $$
declare v int;
begin
  execute format('select (select %1$I from marks where name = %3$L) - (select %1$I from marks where name = %2$L)', fn, a, b) into v;
  return v;
end;
$$;

select pg_temp.mark('start');
select pg_temp.batch('Scale batch');
select pg_temp.batch('Scale batch renamed');
select pg_temp.batch('Scale batch final');
select pg_temp.mark('batches');
select better_supabase.finish_import_run(current_setting('better_supabase.run')::uuid);
select pg_temp.mark('end');

select diag('SCALE_MS import_batch_3x1000=' || round(extract(epoch from (select t from marks where name = 'batches') - (select t from marks where name = 'start')) * 1000)
  || ' finish_import_run=' || round(extract(epoch from (select t from marks where name = 'end') - (select t from marks where name = 'batches')) * 1000));
select diag('SCALE_CALLS search_refresh=' || pg_temp.delta('refresh', 'start', 'end')
  || ' search_index_stmt=' || pg_temp.delta('stmt_search', 'start', 'end')
  || ' audit_row_change=' || pg_temp.delta('row_audit', 'start', 'end'));

select is(
  (select count(*)::int from public.customers where name like 'Scale batch final %'),
  1000,
  'the run writes 1,000 customers'
);
select is(pg_temp.delta('refresh', 'start', 'batches'), 0, 'no search_refresh during the batches');
select is(pg_temp.delta('refresh', 'batches', 'end'), 1000, 'finish_import_run runs search_refresh once per record');
select is(pg_temp.delta('row_search', 'start', 'end'), 0, 'no row-level search trigger on customers');
select ok(pg_temp.delta('stmt_search', 'start', 'end') <= 6, 'the search statement triggers run once per statement');
select is(pg_temp.delta('row_audit', 'start', 'end'), 0, 'no audit_row_change in a statement-audited import');
select is(
  (select count(*)::int from better_supabase.search_documents where title like 'Scale batch final %'),
  1000,
  'every record is indexed with its last name'
);
select is(
  (select count(*)::int from better_supabase.import_search_dirty where run_id = current_setting('better_supabase.run')::uuid),
  0,
  'finish_import_run clears the run''s search notes'
);

select * from finish();
rollback;

-- The statistics are not transactional; a doctor run after pgTAP would report this
-- fixture's temporary files (BS208).
select pg_stat_statements_reset() is not null as reset \gset
