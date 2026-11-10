-- Search compares keys on their own type, and a watch trigger fires only when
-- a listed column changed. The source-view join can then use the id index.
begin;
select plan(5);

select ok(
  pg_get_functiondef('better_supabase.search_refresh(text, text)'::regprocedure) like '%f."id" = s."id"%',
  'search refresh joins the drive source view without casting the ids'
);

select ok(
  pg_get_functiondef('better_supabase.search_refresh(text, text)'::regprocedure) not like '%f."id"::text = s."id"::text%',
  'search refresh does not compare the source view key as text'
);

select ok(
  (
    select pg_get_triggerdef(oid) like '%UPDATE OF node_id, content%'
      and pg_get_triggerdef(oid) like '%IS DISTINCT FROM%'
    from pg_trigger
    where tgname = 'bsb_search_drive_node_watch_0_u'
  ),
  'the drive text watch fires only when the node or its text changed'
);

create function pg_temp.plan_of(query text) returns text
language plpgsql as $$
declare
  rec record;
  out text := '';
begin
  for rec in execute 'explain (format text) ' || query loop
    out := out || rec."QUERY PLAN" || E'\n';
  end loop;
  return out;
end;
$$;

set local enable_seqscan = off;

select matches(
  pg_temp.plan_of($q$select s.tenant_id from better_supabase.drive_nodes s join better_supabase.drive_node_search f on f.id = s.id where s.id = '00000000-0000-4000-8000-00000000d0e1'::uuid and f.id = '00000000-0000-4000-8000-00000000d0e1'::uuid$q$),
  'Index Scan',
  'the typed source join uses the node id index'
);

insert into better_supabase.attachments (id, tenant_id, name, mime_type, size)
values (
  '00000000-0000-4000-8000-00000000d0a1',
  '00000000-0000-4000-8000-000000000001',
  'note.txt',
  'text/plain',
  4
);

insert into better_supabase.drive_nodes (id, tenant_id, kind, name)
values (
  '00000000-0000-4000-8000-00000000d0e1',
  '00000000-0000-4000-8000-000000000001',
  'file',
  'note.txt'
);

insert into better_supabase.drive_node_texts (node_id, tenant_id, attachment_id, content)
values (
  '00000000-0000-4000-8000-00000000d0e1',
  '00000000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8000-00000000d0a1',
  'hello'
);

select set_config(
  'better_supabase.search_mark',
  pg_stat_get_xact_function_calls('better_supabase.search_refresh(text, text)'::regprocedure)::text,
  true
);

update better_supabase.drive_node_texts
set extractor = 'none'
where node_id = '00000000-0000-4000-8000-00000000d0e1';

select is(
  pg_stat_get_xact_function_calls('better_supabase.search_refresh(text, text)'::regprocedure),
  current_setting('better_supabase.search_mark')::bigint,
  'updating an unwatched text column does not re-index the node'
);

select * from finish();
rollback;
