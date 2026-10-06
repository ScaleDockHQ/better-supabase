-- better-supabase block: vector-search (0.5.1)
-- @bs-block vector-search@1 managed
-- search_<table>(query, k) for each table in vectorSearch: the k nearest rows the caller can read, with pgvector iterative index scans so RLS filters still return k rows.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists vector with schema extensions;

-- Functions for the tables in `vectorSearch` (better-supabase.config.ts); `sql sync` rewrites them.
-- They are security invoker, so RLS (a tenant policy, say) filters inside the
-- index scan. hnsw.iterative_scan keeps scanning until k visible rows are found
-- (pgvector 0.8+) instead of returning fewer.

-- config.vectorSearch
-- notes.embedding (cosine)
create or replace function "public"."search_notes"(query extensions.vector, k integer default 10)
returns setof "public"."notes"
language sql
stable
security invoker
set search_path = ''
set hnsw.iterative_scan = 'strict_order'
as $$
  select t.* from "public"."notes" t
  where t."embedding" is not null
  order by t."embedding" operator(extensions.<=>) query
  limit least(greatest(k, 1), 1000)
$$;

revoke execute on function "public"."search_notes"(extensions.vector, integer) from public, anon;
grant execute on function "public"."search_notes"(extensions.vector, integer) to authenticated, service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.block_modules (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.block_modules enable row level security;
revoke all on better_supabase.block_modules from anon, authenticated;
grant select on better_supabase.block_modules to service_role;
