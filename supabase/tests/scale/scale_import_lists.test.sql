-- The import issue and diff lists (ADR 0670) on the scale fixture: 60,000 issues and a 60,000 entry
-- diff in one run. A first page, a deep offset page and a deep keyset page, as SCALE_MS diag lines.
-- Set bsb.scale_rows to resize (default 60,000).
begin;
select plan(8);

select set_config('bsb.n', coalesce(nullif(current_setting('bsb.scale_rows', true), ''), '60000'), true);
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'scale-lists', '{}'::jsonb) ->> 'id') as run \gset
reset role;
set local session_replication_role = replica;

insert into better_supabase.import_run_issues (run_id, tenant_id, source, entity, key, kind, code, message, created_at)
select :'run', '00000000-0000-4000-8000-000000000001', 'scale-lists', case when g % 2 = 0 then 'customer' else 'contact' end,
  'k' || g, 'warning', 'W', 'm' || g, timestamptz '2026-01-01' + make_interval(secs => g)
from generate_series(1, current_setting('bsb.n')::int) g;

update better_supabase.import_runs set counts = '{"customer":{"inserted":1}}'::jsonb,
  diff = (select jsonb_agg(jsonb_build_object('entity', case when g % 2 = 0 then 'customer' else 'contact' end, 'key', 'k' || g, 'changes', '{}'::jsonb))
          from generate_series(1, current_setting('bsb.n')::int) g)
where id = :'run';

analyze better_supabase.import_run_issues;
set local role service_role;

create temp table marks (name text, ms numeric);
grant all on marks to public;

create function pg_temp.timed(name text, sql text) returns void language plpgsql as $$
declare t0 timestamptz; v jsonb;
begin
  t0 := clock_timestamp();
  execute sql into v;
  insert into marks values (name, round(extract(epoch from clock_timestamp() - t0) * 1000, 1));
end;
$$;

select pg_temp.timed('issues_first_page', format('select better_supabase.list_import_issues(%L::uuid, null, 50, 0)', :'run'));
select pg_temp.timed('issues_deep_offset', format('select better_supabase.list_import_issues(%L::uuid, null, 50, 59900)', :'run'));
select pg_temp.timed('issues_entity_deep_offset', format('select better_supabase.list_import_issues(%L::uuid, %L, 50, 29900)', :'run', 'customer'));
select pg_temp.timed('diff_first_page', format('select better_supabase.list_import_diff(%L::uuid, null, 50, 0)', :'run'));
select pg_temp.timed('diff_deep_offset', format('select better_supabase.list_import_diff(%L::uuid, null, 50, 59900)', :'run'));
select pg_temp.timed('diff_entity_deep_offset', format('select better_supabase.list_import_diff(%L::uuid, %L, 50, 29900)', :'run', 'customer'));

-- Walk to the last page by cursor, then time the deep keyset page.
create temp table walk (issues text, diff text);
grant all on walk to public;
insert into walk values (null, null);

do $$
declare
  v_run uuid := (select run_id from better_supabase.import_run_issues limit 1);
  v_page jsonb;
  v_cursor text;
  v_pages int := 0;
begin
  loop
    v_page := better_supabase.list_import_issues(v_run, null, 200, 0, v_cursor);
    v_cursor := v_page ->> 'next_cursor';
    exit when v_cursor is null;
    v_pages := v_pages + 1;
    if v_pages = 298 then
      update walk set issues = v_cursor;
    end if;
  end loop;
end;
$$;

select pg_temp.timed('issues_deep_keyset', format('select better_supabase.list_import_issues(%L::uuid, null, 50, 0, %L)', :'run', (select issues from walk)));

select diag('SCALE_MS ' || string_agg(name || '=' || ms, ' ' order by name)) from marks;

select is((better_supabase.list_import_issues(:'run'::uuid, null, 3, 0) -> 'total')::int, 10000, 'the offset path caps the total');
select is(jsonb_array_length(better_supabase.list_import_issues(:'run'::uuid, null, 3, 0) -> 'rows'), 3, 'the offset path returns a page');

select set_config('bsb.page1', better_supabase.list_import_issues(:'run'::uuid, null, 3, 0)::text, true);
select is(
  (select jsonb_agg(r ->> 'key') from jsonb_array_elements(better_supabase.list_import_issues(:'run'::uuid, null, 3, 0, current_setting('bsb.page1')::jsonb ->> 'next_cursor') -> 'rows') r),
  (select jsonb_agg(r ->> 'key') from jsonb_array_elements(better_supabase.list_import_issues(:'run'::uuid, null, 3, 3) -> 'rows') r),
  'a keyset page matches the same offset page'
);
select is(better_supabase.list_import_issues(:'run'::uuid, null, 3, 0, current_setting('bsb.page1')::jsonb ->> 'next_cursor') -> 'total', 'null'::jsonb, 'a keyset page has no total');
select is(
  (select jsonb_agg(r ->> 'key') from jsonb_array_elements(better_supabase.list_import_diff(:'run'::uuid, 'customer', 3, 0, (better_supabase.list_import_diff(:'run'::uuid, 'customer', 3, 0)) ->> 'next_cursor') -> 'rows') r),
  (select jsonb_agg(r ->> 'key') from jsonb_array_elements(better_supabase.list_import_diff(:'run'::uuid, 'customer', 3, 3) -> 'rows') r),
  'a diff keyset page matches the same offset page'
);
select throws_ok(
  format('select better_supabase.list_import_issues(%L::uuid, null, 3, 0, %L)', :'run', 'not a cursor'),
  '22023', null, 'a malformed cursor is refused'
);
select throws_ok(
  format('select better_supabase.list_import_diff(%L::uuid, null, 3, 0, %L)', :'run', 'x1'),
  '22023', null, 'a malformed diff cursor is refused'
);
select is(jsonb_array_length(better_supabase.list_import_diff(:'run'::uuid, null, 200, 59900) -> 'rows'), 100, 'the diff offset path returns the tail');

select * from finish();
