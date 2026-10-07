-- better-supabase module: vector-search (0.5.1)
-- @bs-module vector-search@1 managed
-- search_<table>(query, k) for each table in vectorSearch: the k nearest rows the caller can read, with pgvector iterative index scans so RLS filters still return k rows.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists vector with schema extensions;

-- Functions for the tables in `vectorSearch` (better-supabase.config.ts); `sql sync` rewrites them.
-- They are security invoker, so RLS (a tenant policy, say) filters inside the
-- index scan. hnsw.iterative_scan keeps scanning until k visible rows are found
-- (pgvector 0.8+) instead of returning fewer.

-- config.vectorSearch
-- notes.embedding (cosine)
drop function if exists "public"."search_notes"(extensions.vector, integer, jsonb, text);
drop function if exists "public"."search_notes_scores"(extensions.vector, integer, jsonb, text);
create or replace function "public"."search_notes"(query extensions.vector, k integer default 10)
returns setof "public"."notes"
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  previous_scan text := current_setting('hnsw.iterative_scan', true);
begin
  perform set_config('hnsw.iterative_scan', 'strict_order', true);
  return query select t.* from "public"."notes" t
  where t."embedding" is not null
  order by t."embedding" operator(extensions.<=>) query
  limit least(greatest(k, 1), 1000);
  perform set_config('hnsw.iterative_scan', coalesce(previous_scan, 'off'), true);
end;
$$;
revoke execute on function "public"."search_notes"(extensions.vector, integer) from public, anon;
grant execute on function "public"."search_notes"(extensions.vector, integer) to authenticated, service_role;

-- The ids and scores of the same search, best first, for db.$search({ score: true }).
create or replace function "public"."search_notes_scores"(query extensions.vector, k integer default 10)
returns table (id jsonb, score double precision)
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  previous_scan text := current_setting('hnsw.iterative_scan', true);
begin
  perform set_config('hnsw.iterative_scan', 'strict_order', true);
  return query select to_jsonb(r.id), r.score from (
  with vector_hits as materialized (
    select t."id" as id, t."embedding" operator(extensions.<=>) query as distance
    from "public"."notes" t
    where t."embedding" is not null
    order by t."embedding" operator(extensions.<=>) query
    limit least(greatest(k, 1), 1000)
  ),
  vector_ranked as (
    select h.id, h.distance, row_number() over (order by h.distance) as rank from vector_hits h
  ),
  fused as (
    select v.id, 1 - v.distance as score from vector_ranked v
  )
  select f.id, f.score::double precision as score, row_number() over (order by f.score::double precision desc) as ord from fused f
  order by ord
  limit least(greatest(k, 1), 1000)
  ) r
  order by r.ord;
  perform set_config('hnsw.iterative_scan', coalesce(previous_scan, 'off'), true);
end;
$$;
revoke execute on function "public"."search_notes_scores"(extensions.vector, integer) from public, anon;
grant execute on function "public"."search_notes_scores"(extensions.vector, integer) to authenticated, service_role;
do $$
begin
  if not exists (
    select 1
    from pg_catalog.pg_index i
    join pg_catalog.pg_class c on c.oid = i.indexrelid
    join pg_catalog.pg_am am on am.oid = c.relam
    join pg_catalog.pg_opclass oc on oc.oid = i.indclass[0]
    join pg_catalog.pg_attribute a on a.attrelid = i.indrelid and a.attnum = i.indkey[0]
    where i.indrelid = '"public"."notes"'::regclass
      and a.attname = 'embedding'
      and am.amname in ('hnsw', 'ivfflat')
      and oc.opcname = 'vector_cosine_ops'
  ) then
    raise notice '%', 'notes.embedding has no hnsw or ivfflat index with vector_cosine_ops, so search_notes scans the table';
  end if;
end;
$$;

create schema if not exists better_supabase;
create table if not exists better_supabase.modules (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.modules enable row level security;
revoke all on better_supabase.modules from anon, authenticated;
grant select on better_supabase.modules to service_role;
