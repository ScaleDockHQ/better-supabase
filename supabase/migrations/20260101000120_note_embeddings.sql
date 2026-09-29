-- Note embeddings and the vector-search SQL kit module for apps/examples/nextjs
-- (better-supabase sql add vector-search, with `vectorSearch: { notes: 'embedding' }`).
-- Three dimensions keep the seed readable; real embedding models use hundreds.
create extension if not exists vector with schema extensions;

alter table public.notes add column if not exists embedding extensions.vector(3);

create index if not exists notes_embedding_idx
  on public.notes using hnsw (embedding extensions.vector_cosine_ops);

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
