-- The command center's search on the scale fixture: one search call over the
-- documents of many subject types (ADR 0483). The index holds bsb.scale_rows
-- documents (default 20,000, tier M; set 200,000 for tier L) spread over 40
-- subject types, and the customers among them are real rows the caller can read.
-- Each call prints SCALE_MS.
begin;
select plan(6);

select set_config('bsb.n', coalesce(nullif(current_setting('bsb.scale_rows', true), ''), '20000'), true);

-- Triggers would make the seed the slow part; the index rows are written below.
set local session_replication_role = replica;

insert into public.customers (id, organization_id, name)
select gen_random_uuid(), '00000000-0000-4000-8000-000000000001', 'Scalesearch customer ' || g
from generate_series(1, 200) g;

insert into better_supabase.search_documents (tenant_id, subject_type, subject_id, title, title_search, body, url, tsv, content_hash)
select c.organization_id, 'customer', c.id::text, c.name,
  better_supabase.search_normalize(c.name), null, '/customers/' || c.id,
  to_tsvector('simple', better_supabase.search_normalize(c.name)), md5(c.name)
from public.customers c
where c.name like 'Scalesearch customer %';

-- Filler documents of 40 other types: they share the words the query looks for,
-- so the planner works through them and can_subject refuses what is not readable.
insert into better_supabase.search_documents (tenant_id, subject_type, subject_id, title, title_search, body, url, tsv, content_hash)
select '00000000-0000-4000-8000-000000000001', 'scale_type_' || (g % 40), gen_random_uuid()::text,
  'Scalesearch filler ' || g, better_supabase.search_normalize('Scalesearch filler ' || g),
  'Filler body ' || g, '/scale/' || g,
  to_tsvector('simple', better_supabase.search_normalize('Scalesearch filler ' || g)), md5(g::text)
from generate_series(1, current_setting('bsb.n')::int) g;

set local session_replication_role = origin;
analyze better_supabase.search_documents;

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}', true);
set local role authenticated;

create temp table t0 as select clock_timestamp() as t;
grant all on t0 to public;

select better_supabase.search('scalesearch customer 17') as hits \gset
select diag('SCALE_MS search_global=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000, 1));
select ok(jsonb_array_length(:'hits'::jsonb) > 0, 'a search over every type returns the readable customers');
select is(:'hits'::jsonb -> 0 ->> 'subjectType', 'customer', 'the first hit is a customer');

update t0 set t = clock_timestamp();
select better_supabase.search('scalesearch', null, null, 8) as page \gset
select diag('SCALE_MS search_global_prefix=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000, 1));
select ok(jsonb_array_length(:'page'::jsonb) <= 8, 'the page is capped at the requested size');

update t0 set t = clock_timestamp();
select better_supabase.search('scalesearch', array['customer']) as typed \gset
select diag('SCALE_MS search_global_typed=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000, 1));
select ok(jsonb_array_length(:'typed'::jsonb) > 0, 'a type facet narrows the search to that type');

update t0 set t = clock_timestamp();
select better_supabase.search('filler 7') as filler \gset
select diag('SCALE_MS search_global_unreadable=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000, 1));
select is(jsonb_array_length(:'filler'::jsonb), 0, 'documents of types the caller cannot read never appear');

select ok(
  (select provolatile = 's' from pg_proc where oid = 'better_supabase.search(text, text[], uuid, integer)'::regprocedure),
  'the search function is marked stable');

select * from finish();
rollback;

-- The statistics are not transactional; a doctor run after pgTAP would report this
-- fixture's temporary files (BS208).
select pg_stat_statements_reset() is not null as reset \gset
