-- While an import batch runs, the search triggers note each touched record once
-- and search_refresh_dirty indexes it once at the end; outside a batch every
-- change indexes at once, and an unchanged document is not rewritten.
begin;
select plan(9);

set local track_functions = 'all';

-- Outside an import: one insert, one refresh call.
insert into public.customers (id, organization_id, name)
values ('00000000-0000-4000-8000-00000000c001', '00000000-0000-4000-8000-000000000001', 'Indexed now');
select is(
  coalesce(pg_stat_get_xact_function_calls('better_supabase.search_refresh(text, text)'::regprocedure), 0)::int,
  1,
  'a change outside an import indexes the record at once'
);

-- An unchanged document keeps its updated_at.
create temp table before_touch as
  select updated_at from better_supabase.search_documents where subject_id = '00000000-0000-4000-8000-00000000c001';
select pg_sleep(0.01);
select better_supabase.search_refresh('customer', '00000000-0000-4000-8000-00000000c001');
select is(
  (select updated_at from better_supabase.search_documents where subject_id = '00000000-0000-4000-8000-00000000c001'),
  (select updated_at from before_touch),
  'refreshing an unchanged record leaves the document as it is'
);

-- Inside a batch: three inserts and two renames each, no refresh call yet.
select set_config('better_supabase.search_deferred', 'on', true);

insert into public.customers (id, organization_id, name)
select ('00000000-0000-4000-8000-00000000c1' || lpad(n::text, 2, '0'))::uuid, '00000000-0000-4000-8000-000000000001', 'Batch ' || n
from generate_series(1, 3) n;
update public.customers set name = name || ' one' where id::text like '00000000-0000-4000-8000-00000000c1%';
update public.customers set name = name || ' two' where id::text like '00000000-0000-4000-8000-00000000c1%';

select is(
  coalesce(pg_stat_get_xact_function_calls('better_supabase.search_refresh(text, text)'::regprocedure), 0)::int,
  2,
  'a deferred batch adds no search_refresh call (the earlier two are above)'
);
select is(
  (select count(*)::int from better_supabase.search_documents where subject_id like '00000000-0000-4000-8000-00000000c1%'),
  0,
  'the batch rows are not indexed before the flush'
);

select is(better_supabase.search_refresh_dirty(), 3, 'the flush indexes each touched record once');
select is(
  coalesce(pg_stat_get_xact_function_calls('better_supabase.search_refresh(text, text)'::regprocedure), 0)::int,
  5,
  'the flush made one refresh call per record'
);
select is(
  (select title from better_supabase.search_documents where subject_id = '00000000-0000-4000-8000-00000000c101'),
  'Batch 1 one two',
  'the index holds the final title'
);
select is(better_supabase.search_refresh_dirty(), 0, 'a second flush has nothing left');

select set_config('better_supabase.search_deferred', '', true);
delete from public.customers where id = '00000000-0000-4000-8000-00000000c001';
select is(
  (select count(*)::int from better_supabase.search_documents where subject_id = '00000000-0000-4000-8000-00000000c001'),
  0,
  'outside a batch a delete drops the document at once'
);

select * from finish();
rollback;
