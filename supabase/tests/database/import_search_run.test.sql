-- ADR 0844: an import run notes the records it changes in
-- import_search_dirty and indexes each once when it closes. A dry run writes
-- no notes, a cancelled run still indexes what it wrote, and a write outside
-- a run indexes at once. customers is searched through statement triggers
-- (search.statement), which re-index only rows whose watched columns change.
begin;
select plan(11);
set local track_functions = 'all';

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

create function pg_temp.items(label text) returns jsonb language sql as $$
  select jsonb_agg(jsonb_build_object('key', 'isr-' || g, 'scope', '', 'data', jsonb_build_object('name', label || ' ' || g, 'kvk', 'isr' || g), 'refs', '{}'::jsonb))
  from generate_series(1, 3) g
$$;
create function pg_temp.notes(run text) returns int language sql as $$
  select count(*)::int from better_supabase.import_search_dirty where run_id = run::uuid
$$;

-- A dry run.
select set_config('test.dry', (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'isr-dry', '{"dryRun": true}'::jsonb) ->> 'id'), true);
select better_supabase.mark_import_running(current_setting('test.dry')::uuid);
select better_supabase.import_upsert_batch(current_setting('test.dry')::uuid, 'customer', pg_temp.items('Isr dry'));
select is(pg_temp.notes(current_setting('test.dry')), 0, 'a dry run notes nothing');
select is(
  (select count(*)::int from better_supabase.search_documents where title like 'Isr dry %'),
  0,
  'a dry run indexes nothing'
);

-- A run that is cancelled after a batch.
select set_config('test.cancel', (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'isr-cancel', '{}'::jsonb) ->> 'id'), true);
select better_supabase.mark_import_running(current_setting('test.cancel')::uuid);
select better_supabase.import_upsert_batch(current_setting('test.cancel')::uuid, 'customer', pg_temp.items('Isr cancel'));
select is(pg_temp.notes(current_setting('test.cancel')), 3, 'a batch notes each record it writes');
select is(
  (select count(*)::int from better_supabase.search_documents where title like 'Isr cancel %'),
  0,
  'a running import indexes nothing yet'
);
select better_supabase.cancel_import_run(current_setting('test.cancel')::uuid);
select is(pg_temp.notes(current_setting('test.cancel')), 0, 'cancel_import_run clears the notes');
select is(
  (select count(*)::int from better_supabase.search_documents where title like 'Isr cancel %'),
  3,
  'cancel_import_run indexes what the run wrote'
);

-- A write outside a run.
reset role;
insert into public.customers (organization_id, name, kvk)
select '00000000-0000-4000-8000-000000000001', 'Isr direct ' || g, 'isrd' || g from generate_series(1, 2) g;
select is(
  (select count(*)::int from better_supabase.search_documents where title like 'Isr direct %'),
  2,
  'a write outside a run indexes at once'
);
select is(
  (select count(*)::int from better_supabase.import_search_dirty),
  0,
  'a write outside a run notes nothing'
);


create temp table refresh_mark as
select coalesce(pg_stat_get_xact_function_calls('better_supabase.search_refresh(text, text)'::regprocedure), 0)::int as n;
update public.customers set kvk = kvk || 'x' where name like 'Isr direct %';
select is(
  coalesce(pg_stat_get_xact_function_calls('better_supabase.search_refresh(text, text)'::regprocedure), 0)::int - (select n from refresh_mark),
  0,
  'an update of an unwatched column indexes nothing'
);
update public.customers set name = replace(name, 'direct', 'renamed') where name like 'Isr direct %';
select is(
  (select count(*)::int from better_supabase.search_documents where title like 'Isr renamed %'),
  2,
  'one update statement re-indexes every renamed row'
);
delete from public.customers where name like 'Isr renamed %';
select is(
  (select count(*)::int from better_supabase.search_documents where title like 'Isr renamed %'),
  0,
  'one delete statement drops every row from the index'
);

select * from finish();
rollback;
