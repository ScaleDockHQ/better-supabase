-- A record type read through a search view (drive_node, search.from with
-- search.columns ["name"]) re-indexes only when a listed column changes value.
-- The insert and delete trigger and the update trigger are separate, and the
-- update trigger's when clause skips a column set to its own value.
begin;
select plan(6);

set local track_functions = 'all';

create function pg_temp.calls() returns int language sql as $$
  select coalesce(pg_stat_get_xact_function_calls('better_supabase.search_index_row()'::regprocedure), 0)::int
$$;

insert into better_supabase.drive_nodes (id, tenant_id, kind, name)
values ('00000000-0000-4000-8000-00000000d001', '00000000-0000-4000-8000-000000000001', 'folder', 'Contracts');

select is(pg_temp.calls(), 1, 'an insert indexes the node once');
select is(
  (select title from better_supabase.search_documents where subject_type = 'drive_node' and subject_id = '00000000-0000-4000-8000-00000000d001'),
  'Contracts',
  'the insert writes the search document'
);

update better_supabase.drive_nodes set lock_note = 'reviewing', updated_at = now() + interval '1 minute'
where id = '00000000-0000-4000-8000-00000000d001';
select is(pg_temp.calls(), 1, 'an update of an unlisted column does not re-index');

update better_supabase.drive_nodes set name = 'Contracts'
where id = '00000000-0000-4000-8000-00000000d001';
select is(pg_temp.calls(), 1, 'setting a listed column to its own value does not re-index');

update better_supabase.drive_nodes set name = 'Signed contracts'
where id = '00000000-0000-4000-8000-00000000d001';
select is(pg_temp.calls(), 2, 'an update of a listed column re-indexes once');
select is(
  (select title from better_supabase.search_documents where subject_type = 'drive_node' and subject_id = '00000000-0000-4000-8000-00000000d001'),
  'Signed contracts',
  'the re-index writes the new title'
);

select * from finish();
rollback;
