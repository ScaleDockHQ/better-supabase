-- 1,000 drive nodes, a view-backed search type (search.from with
-- search.columns). An update of an unindexed column writes no search document
-- and calls no index trigger; an update of the indexed name re-indexes each
-- row once. The times go to SCALE_MS diag lines, the trigger calls to
-- SCALE_CALLS.
begin;
select plan(2);

set local track_functions = 'all';

create function pg_temp.calls() returns int language sql as $$
  select coalesce(pg_stat_get_xact_function_calls('better_supabase.search_index_row()'::regprocedure), 0)::int
$$;

insert into better_supabase.drive_nodes (tenant_id, kind, name)
select '00000000-0000-4000-8000-000000000001', 'folder', 'scale folder ' || g
from generate_series(1, 1000) g;

create temp table marks (name text, t timestamptz, calls int, docs timestamptz);
insert into marks values ('start', clock_timestamp(), pg_temp.calls(), null);

update better_supabase.drive_nodes set lock_note = 'scale' where name like 'scale folder %';
insert into marks values ('unindexed', clock_timestamp(), pg_temp.calls(), null);

update better_supabase.drive_nodes set name = name || ' renamed' where name like 'scale folder %';
insert into marks values ('indexed', clock_timestamp(), pg_temp.calls(), null);

select is(
  (select calls from marks where name = 'unindexed') - (select calls from marks where name = 'start'),
  0,
  'an update of an unindexed column of 1,000 rows calls no index trigger'
);
select is(
  (select calls from marks where name = 'indexed') - (select calls from marks where name = 'unindexed'),
  1000,
  'an update of the indexed column re-indexes each row once'
);

select diag('SCALE_MS search_view_unindexed_update_1000=' || round(extract(epoch from (select t from marks where name = 'unindexed') - (select t from marks where name = 'start')) * 1000));
select diag('SCALE_MS search_view_indexed_update_1000=' || round(extract(epoch from (select t from marks where name = 'indexed') - (select t from marks where name = 'unindexed')) * 1000));
select diag('SCALE_CALLS search_view_unindexed_update_1000=' || ((select calls from marks where name = 'unindexed') - (select calls from marks where name = 'start')));

select * from finish();
rollback;
