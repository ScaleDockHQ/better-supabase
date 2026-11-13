-- search_page browses by (sort_key, subject_id) without a query and pages the
-- ranked matches with an opaque cursor with one; facets filter both, the
-- candidate pool stops at 500, and search() is unchanged. Acme (…0001) has a
-- member a2 who reads customers (supabase/seed.sql).
begin;
select plan(17);

insert into public.customers (id, organization_id, name, status)
select ('00000000-0000-4000-8000-00000000d' || lpad(n::text, 3, '0'))::uuid,
  '00000000-0000-4000-8000-000000000001',
  'Paged ' || lpad(n::text, 2, '0'),
  case when n % 2 = 0 then 'active' else 'lead' end
from generate_series(1, 7) n;

insert into public.customers (id, organization_id, name)
select ('00000000-0000-4000-8000-00000000e' || lpad(n::text, 3, '0'))::uuid,
  '00000000-0000-4000-8000-000000000001',
  'Capped item ' || n
from generate_series(1, 520) n;

-- Pages through a query and returns every title in order, or the page count.
create function pg_temp.walk(p_q text, p_size integer, p_filter jsonb default null, p_types text[] default array['customer'])
returns jsonb
language plpgsql
as $$
declare
  v_cursor text;
  v_page jsonb;
  v_titles jsonb := '[]'::jsonb;
  v_pages integer := 0;
begin
  loop
    v_page := better_supabase.search_page(p_q, p_types, null, p_filter, v_cursor, p_size);
    v_pages := v_pages + 1;
    v_titles := v_titles || (select coalesce(jsonb_agg(i ->> 'title'), '[]'::jsonb) from jsonb_array_elements(v_page -> 'items') i);
    v_cursor := v_page ->> 'nextCursor';
    exit when v_cursor is null or v_pages > 20;
  end loop;
  return jsonb_build_object('titles', v_titles, 'pages', v_pages);
end;
$$;

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

-- Browse.
select is(
  jsonb_array_length(better_supabase.search_page(null, array['customer'], null, '{"status":"lead"}', null, 2) -> 'items'),
  2,
  'browse returns page_size items'
);
select isnt(
  better_supabase.search_page(null, array['customer'], null, '{"status":"lead"}', null, 2) ->> 'nextCursor',
  null,
  'browse returns a cursor while more rows follow'
);
select is(
  pg_temp.walk('', 3, '{"status":"active"}') -> 'titles',
  (select jsonb_agg(title order by sort_key, subject_id) from better_supabase.search_documents
    where subject_type = 'customer' and facets @> '{"status":"active"}'),
  'paging browse by cursor visits each active customer once, in sort_key order'
);
select is(
  (pg_temp.walk('', 100, '{"status":"active"}') -> 'pages')::int,
  1,
  'a page larger than the result ends with no cursor'
);
select is(
  (select count(*)::int from jsonb_array_elements(
    better_supabase.search_page(null, array['customer'], null, '{"status":"active"}', null, 100) -> 'items') i
    where i -> 'facets' ->> 'status' <> 'active'),
  0,
  'the facet filter keeps only matching documents'
);
select is(
  better_supabase.search_page(null, array['customer'], null, '{"status":"nope"}', null, 10),
  '{"items": [], "nextCursor": null}'::jsonb,
  'a filter that matches nothing returns an empty page'
);
select is(
  (select count(*)::int from jsonb_array_elements(
    better_supabase.search_page(null, array['customer'], null, null, null, 100) -> 'items') i
    where i ->> 'title' = 'Initech'),
  0,
  'another tenant''s documents stay out'
);

-- Search.
select is(
  pg_temp.walk('paged', 2) -> 'titles',
  (select jsonb_agg(t order by t) from (select distinct title t from better_supabase.search_documents where title like 'Paged %') x),
  'paging a query by cursor visits each match once, in score then id order'
);
select is(
  (pg_temp.walk('capped', 100) -> 'pages')::int,
  5,
  'the ranked pool stops at 500 candidates (520 match, five pages)'
);
select is(
  jsonb_array_length(pg_temp.walk('capped', 100) -> 'titles'),
  500,
  'a query pages through at most 500 documents'
);

-- Cursors and input.
select throws_ok(
  $$select better_supabase.search_page('paged', null, null, null,
    better_supabase.search_page(null, null, null, null, null, 1) ->> 'nextCursor', 5)$$,
  '22023',
  'this cursor does not belong to this query',
  'a browse cursor is rejected for a query'
);
select throws_ok(
  $$select better_supabase.search_page('capped', null, null, null,
    better_supabase.search_page('paged', null, null, null, null, 1) ->> 'nextCursor', 5)$$,
  '22023',
  'this cursor does not belong to this query',
  'a cursor of another query is rejected'
);
select throws_ok(
  $$select better_supabase.search_page(null, null, null, null, 'not-a-cursor', 5)$$,
  '22023',
  'this cursor does not belong to this query',
  'a malformed cursor is rejected'
);
select throws_ok(
  $$select better_supabase.search_page(null, null, null, '[]'::jsonb, null, 5)$$,
  '22023',
  'filter must be a JSON object of facet values',
  'a filter that is not an object is rejected'
);
select is(
  jsonb_array_length(better_supabase.search_page(null, null, null, null, null, 1000) -> 'items'),
  100,
  'page_size is capped at 100'
);

-- search() keeps its shape.
select is(
  jsonb_typeof(better_supabase.search('paged')),
  'array',
  'search still returns an array of hits'
);
select ok(
  (better_supabase.search('paged', array['customer'], null, 3) -> 0) ?& array['organizationId', 'subjectType', 'subjectId', 'title', 'score'],
  'a search hit keeps its fields'
);

select * from finish();
rollback;
