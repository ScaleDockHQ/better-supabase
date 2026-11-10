-- The deferred search list on the scale fixture (ADR 0617): an import batch
-- notes 30,000 records through search_enqueue, then flushes them once. The
-- note used to rewrite one text setting per record (5,451 ms for 30,000 notes
-- before the change); it is now one note in a 256th of the list. Set
-- bsb.scale_rows to resize.
begin;
select plan(3);

select set_config('bsb.n', coalesce(nullif(current_setting('bsb.scale_rows', true), ''), '30000'), true);
select set_config('better_supabase.search_deferred', 'on', true);

create temp table t0 as select clock_timestamp() as t;

select better_supabase.search_enqueue('customer', md5(g::text)::uuid::text) from generate_series(1, current_setting('bsb.n')::int) g;
select diag('SCALE_MS search_enqueue_' || current_setting('bsb.n') || '=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));

select better_supabase.search_enqueue('customer', md5(g::text)::uuid::text) from generate_series(1, 1000) g;

select is(
  (select coalesce(sum(array_length(string_to_array(trim(both E'\n' from current_setting('better_supabase.search_dirty_' || b, true)), E'\n'), 1)), 0)::int
   from generate_series(0, 255) b where coalesce(current_setting('better_supabase.search_dirty_' || b, true), '') <> ''),
  current_setting('bsb.n')::int,
  'repeated notes keep one line per record'
);

select set_config('better_supabase.search_deferred', '', true);
update t0 set t = clock_timestamp();
select better_supabase.search_refresh_dirty() as flushed \gset
select diag('SCALE_MS search_flush_' || current_setting('bsb.n') || '=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));

select is(
  (select count(*)::int from generate_series(0, 255) b where coalesce(current_setting('better_supabase.search_dirty_' || b, true), '') <> ''),
  0,
  'the flush empties the list'
);
select is(:flushed::int, 0, 'ids of no customer index nothing');

select * from finish();
rollback;
