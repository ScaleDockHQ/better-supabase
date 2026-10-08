-- better-supabase module: knowledge (0.5.1)
-- @bs-module knowledge@1 managed
-- Documents and chunks for retrieval with an embedding and a tsvector each, scoped to an organization, agent, project, chat or user; hybrid search with reciprocal rank fusion, chunks that keep their embedding when unchanged, and an embed job per document when jobs is installed.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Documents for retrieval: uploaded files, pasted text and synced rows, split
-- into chunks with an embedding and a tsvector each. The app chunks and
-- embeds; the database stores, scopes and searches.
create table if not exists "better_supabase"."knowledge_documents" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null,
  "owner_id" uuid references auth.users (id) on delete cascade,
  "scope" text not null default 'user' check ("scope" in ('organization', 'agent', 'project', 'chat', 'user')),
  "scope_id" uuid,
  "file_id" uuid references "better_supabase"."ai_files" ("id") on delete cascade,
  "title" text not null check (length("title") between 1 and 500),
  "source" text,
  "metadata" jsonb not null default '{}' check (jsonb_typeof("metadata") = 'object'),
  "status" text not null default 'pending' check ("status" in ('pending', 'ready', 'failed')),
  "error" text,
  "chunk_count" integer not null default 0,
  "embedding_model" text,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check (("scope" = 'organization') = ("scope_id" is null))
);
create index if not exists knowledge_documents_tenant_idx on "better_supabase"."knowledge_documents" ("organization_id", "scope", "scope_id");
create index if not exists knowledge_documents_owner_idx on "better_supabase"."knowledge_documents" ("owner_id") where "owner_id" is not null;
create index if not exists knowledge_documents_file_idx on "better_supabase"."knowledge_documents" ("file_id") where "file_id" is not null;
create index if not exists knowledge_documents_pending_idx on "better_supabase"."knowledge_documents" ("updated_at") where "status" = 'pending';
alter table "better_supabase"."knowledge_documents" enable row level security;
revoke all on "better_supabase"."knowledge_documents" from anon, authenticated;
grant select on "better_supabase"."knowledge_documents" to authenticated;
grant all on "better_supabase"."knowledge_documents" to service_role;
drop policy if exists knowledge_documents_read on "better_supabase"."knowledge_documents";
create policy knowledge_documents_read on "better_supabase"."knowledge_documents" for select to authenticated
  using (("owner_id" = (select auth.uid()) or ("scope" in ('organization', 'agent') and "organization_id" in (select better_supabase.tenant_ids_with('ai_chat.read'))) or "organization_id" in (select better_supabase.tenant_ids_with('ai_chat.admin')) or ("scope" = 'chat' and ("scope_id" is not null and "better_supabase"."ai_chat_can_read"("scope_id")))));

-- A chunk is visible when its document is, so search inherits the scopes.
create table if not exists "better_supabase"."knowledge_chunks" (
  "document_id" uuid not null references "better_supabase"."knowledge_documents" ("id") on delete cascade,
  "idx" integer not null check ("idx" >= 0),
  "content" text not null check (length("content") > 0),
  "token_count" integer,
  "embedding" extensions.vector(1536),
  "embedding_hash" text,
  "metadata" jsonb not null default '{}',
  "tsv" tsvector generated always as (to_tsvector('simple'::regconfig, "content")) stored,
  primary key ("document_id", "idx")
);
create index if not exists knowledge_chunks_embedding_idx on "better_supabase"."knowledge_chunks" using hnsw ("embedding" extensions.vector_cosine_ops);
create index if not exists knowledge_chunks_tsv_idx on "better_supabase"."knowledge_chunks" using gin ("tsv");
create index if not exists knowledge_chunks_pending_idx on "better_supabase"."knowledge_chunks" ("document_id", "idx") where "embedding" is null;
alter table "better_supabase"."knowledge_chunks" enable row level security;
revoke all on "better_supabase"."knowledge_chunks" from anon, authenticated;
grant select on "better_supabase"."knowledge_chunks" to authenticated;
grant all on "better_supabase"."knowledge_chunks" to service_role;
drop policy if exists knowledge_chunks_read on "better_supabase"."knowledge_chunks";
create policy knowledge_chunks_read on "better_supabase"."knowledge_chunks" for select to authenticated
  using (exists (select 1 from "better_supabase"."knowledge_documents" doc where doc."id" = "document_id"));

-- Creates a document for the caller (or for owner, as the service role).
-- Organization and agent knowledge needs the manage permission.
create or replace function "better_supabase"."create_knowledge_document"(
  tenant uuid,
  title text,
  scope text default 'user',
  scope_id uuid default null,
  file_id uuid default null,
  source text default null,
  metadata jsonb default '{}',
  owner uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner uuid := case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then create_knowledge_document.owner else auth.uid() end;
  v_scope_id uuid := create_knowledge_document.scope_id;
  v_row "better_supabase"."knowledge_documents"%rowtype;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (auth.uid() is null or not coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'ai_chat.create'), false)) then
    raise exception 'you may not add knowledge here' using errcode = '42501', hint = 'KNOWLEDGE_FORBIDDEN';
  end if;
  if create_knowledge_document.scope in ('organization', 'agent') and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'ai_chat.admin'), false)) then
    raise exception 'only admins add % knowledge', create_knowledge_document.scope using errcode = '42501', hint = 'KNOWLEDGE_FORBIDDEN';
  end if;
  if create_knowledge_document.scope = 'user' then
    v_scope_id := coalesce(v_scope_id, v_owner);
    if v_scope_id is null or v_scope_id is distinct from v_owner then
      raise exception 'user knowledge belongs to its owner' using errcode = '22023', hint = 'KNOWLEDGE_SCOPE';
    end if;
  end if;
  if create_knowledge_document.scope is null
    or create_knowledge_document.scope not in ('organization', 'agent', 'project', 'chat', 'user')
    or (create_knowledge_document.scope = 'organization') <> (v_scope_id is null) then
    raise exception '% knowledge needs %', create_knowledge_document.scope, case when create_knowledge_document.scope = 'organization' then 'no scope_id' else 'a scope_id' end using errcode = '22023', hint = 'KNOWLEDGE_SCOPE';
  end if;
  if create_knowledge_document.scope = 'chat' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_scope_id is not null and "better_supabase"."ai_chat_can_read"(v_scope_id))) then
    raise exception 'chat % not found', v_scope_id using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  if file_id is not null and not exists (
    select 1 from "better_supabase"."ai_files" x
    where x."id" = create_knowledge_document.file_id
      and x."organization_id" = create_knowledge_document.tenant
      and x."status" = 'ready'
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or x."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'ai_chat.admin'), false))
  ) then
    raise exception 'file % not found', file_id using errcode = 'P0002', hint = 'AI_FILE_NOT_FOUND';
  end if;
  insert into "better_supabase"."knowledge_documents" ("organization_id", "owner_id", "scope", "scope_id", "file_id", "title", "source", "metadata")
  values (create_knowledge_document.tenant, v_owner, create_knowledge_document.scope, v_scope_id, create_knowledge_document.file_id, create_knowledge_document.title, create_knowledge_document.source, coalesce(create_knowledge_document.metadata, '{}'))
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'scope', v_row."scope", 'scope_id', v_row."scope_id", 'file_id', v_row."file_id", 'title', v_row."title", 'source', v_row."source", 'metadata', v_row."metadata", 'status', v_row."status", 'error', v_row."error", 'chunk_count', v_row."chunk_count", 'embedding_model', v_row."embedding_model", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."create_knowledge_document"(uuid, text, text, uuid, uuid, text, jsonb, uuid) from public, anon;
grant execute on function "better_supabase"."create_knowledge_document"(uuid, text, text, uuid, uuid, text, jsonb, uuid) to authenticated, service_role;

-- Replaces a document's chunks. A chunk whose text is unchanged keeps its
-- embedding unless the model changed; the rest wait for the embed job.
-- chunks is a list of {content, tokens, metadata}, or {"items": list}.
create or replace function "better_supabase"."write_knowledge_chunks"(document_id uuid, chunks jsonb, model text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."knowledge_documents"%rowtype;
  v_count integer;
  v_keep boolean;
  v_items jsonb := case when jsonb_typeof(write_knowledge_chunks.chunks) = 'object' then write_knowledge_chunks.chunks -> 'items' else write_knowledge_chunks.chunks end;
begin
  select * into v_row from "better_supabase"."knowledge_documents" x where x."id" = write_knowledge_chunks.document_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai_chat.admin'), false)) then
    raise exception 'document % not found', document_id using errcode = 'P0002', hint = 'KNOWLEDGE_NOT_FOUND';
  end if;
  if coalesce(jsonb_typeof(v_items), '') <> 'array' or jsonb_array_length(v_items) > 10000 then
    raise exception 'chunks must be an array of at most 10000 chunks' using errcode = '22023', hint = 'KNOWLEDGE_CHUNKS';
  end if;
  v_count := jsonb_array_length(v_items);
  v_keep := write_knowledge_chunks.model is not distinct from v_row."embedding_model" or write_knowledge_chunks.model is null;
  insert into "better_supabase"."knowledge_chunks" as t ("document_id", "idx", "content", "token_count", "metadata")
  select v_row."id", (e.ord - 1)::integer, e.value ->> 'content', (e.value ->> 'tokens')::integer, coalesce(e.value -> 'metadata', '{}')
  from jsonb_array_elements(v_items) with ordinality e(value, ord)
  on conflict ("document_id", "idx") do update set
    "content" = excluded."content",
    "token_count" = excluded."token_count",
    "metadata" = excluded."metadata",
    "embedding" = case when v_keep and t."embedding_hash" = md5(excluded."content") then t."embedding" end,
    "embedding_hash" = case when v_keep and t."embedding_hash" = md5(excluded."content") then t."embedding_hash" end;
  delete from "better_supabase"."knowledge_chunks" x where x."document_id" = v_row."id" and x."idx" >= v_count;
  update "better_supabase"."knowledge_documents" x set
    "status" = case when exists (select 1 from "better_supabase"."knowledge_chunks" p where p."document_id" = x."id" and p."embedding" is null) then 'pending' else 'ready' end,
    "error" = null,
    "chunk_count" = v_count,
    "embedding_model" = coalesce(write_knowledge_chunks.model, x."embedding_model"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if v_row."status" = 'pending' then
  perform "better_supabase"."enqueue_job"(queue => 'knowledge_embed', payload => jsonb_build_object('document_id', v_row."id"), dedupe_key => 'knowledge:' || v_row."id"::text, dedupe_running => false);
  end if;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'scope', v_row."scope", 'scope_id', v_row."scope_id", 'file_id', v_row."file_id", 'title', v_row."title", 'source', v_row."source", 'metadata', v_row."metadata", 'status', v_row."status", 'error', v_row."error", 'chunk_count', v_row."chunk_count", 'embedding_model', v_row."embedding_model", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."write_knowledge_chunks"(uuid, jsonb, text) from public, anon;
grant execute on function "better_supabase"."write_knowledge_chunks"(uuid, jsonb, text) to authenticated, service_role;

create or replace function "better_supabase"."get_knowledge_document"(document_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'owner_id', x."owner_id", 'scope', x."scope", 'scope_id', x."scope_id", 'file_id', x."file_id", 'title', x."title", 'source', x."source", 'metadata', x."metadata", 'status', x."status", 'error', x."error", 'chunk_count', x."chunk_count", 'embedding_model', x."embedding_model", 'created_at', x."created_at", 'updated_at', x."updated_at") from "better_supabase"."knowledge_documents" x where x."id" = get_knowledge_document.document_id
$$;
revoke execute on function "better_supabase"."get_knowledge_document"(uuid) from public, anon;
grant execute on function "better_supabase"."get_knowledge_document"(uuid) to authenticated, service_role;

-- The documents the caller can read in a tenant, newest first.
create or replace function "better_supabase"."list_knowledge_documents"(
  tenant uuid,
  scope text default null,
  scope_id uuid default null,
  max_rows integer default 100
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'owner_id', x."owner_id", 'scope', x."scope", 'scope_id', x."scope_id", 'file_id', x."file_id", 'title', x."title", 'source', x."source", 'metadata', x."metadata", 'status', x."status", 'error', x."error", 'chunk_count', x."chunk_count", 'embedding_model', x."embedding_model", 'created_at', x."created_at", 'updated_at', x."updated_at") order by x."created_at" desc), '[]')
  from (
    select * from "better_supabase"."knowledge_documents" y
    where y."organization_id" = list_knowledge_documents.tenant
      and (list_knowledge_documents.scope is null or y."scope" = list_knowledge_documents.scope)
      and (list_knowledge_documents.scope_id is null or y."scope_id" = list_knowledge_documents.scope_id)
    order by y."created_at" desc
    limit least(greatest(list_knowledge_documents.max_rows, 1), 1000)
  ) x
$$;
revoke execute on function "better_supabase"."list_knowledge_documents"(uuid, text, uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_knowledge_documents"(uuid, text, uuid, integer) to authenticated, service_role;

create or replace function "better_supabase"."delete_knowledge_document"(document_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."knowledge_documents"%rowtype;
begin
  select * into v_row from "better_supabase"."knowledge_documents" x where x."id" = delete_knowledge_document.document_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai_chat.admin'), false)) then
    return false;
  end if;
  delete from "better_supabase"."knowledge_documents" x where x."id" = v_row."id";
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_knowledge_document"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_knowledge_document"(uuid) to authenticated, service_role;

-- Hybrid search over the chunks the caller can read: the vector and the
-- full-text rankings fused with reciprocal rank fusion (k = 60). Iterative
-- index scans keep looking until enough visible chunks turn up. scopes is a
-- list of {"scope", "id"} objects, or {"items": list}; null searches every
-- scope. Returns a JSON array of {document_id, idx, content, metadata,
-- title, score}.
create or replace function "better_supabase"."knowledge_search"(
  tenant uuid,
  query_embedding extensions.vector default null,
  query_text text default null,
  scopes jsonb default null,
  k integer default 8,
  filter jsonb default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  previous_scan text := current_setting('hnsw.iterative_scan', true);
  v_candidates integer := least(greatest(knowledge_search.k, 1) * 4, 400);
  v_scopes jsonb := case when jsonb_typeof(knowledge_search.scopes) = 'object' then knowledge_search.scopes -> 'items' else knowledge_search.scopes end;
  v_rows jsonb;
begin
  perform set_config('hnsw.iterative_scan', 'relaxed_order', true);
  with docs as materialized (
    select x."id" as id, x."title" as title from "better_supabase"."knowledge_documents" x
    where x."organization_id" = knowledge_search.tenant
      and (v_scopes is null or exists (
        select 1 from jsonb_array_elements(v_scopes) s
        where s.value ->> 'scope' = x."scope"
          and (s.value ->> 'id' is null or (s.value ->> 'id')::uuid = x."scope_id")
      ))
      and (knowledge_search.filter is null or x."metadata" @> knowledge_search.filter)
  ),
  vector_hits as materialized (
    select t."document_id" as document_id, t."idx" as idx, t."embedding" operator(extensions.<=>) knowledge_search.query_embedding as distance
    from "better_supabase"."knowledge_chunks" t
    where knowledge_search.query_embedding is not null and t."embedding" is not null
      and t."document_id" in (select docs.id from docs)
    order by t."embedding" operator(extensions.<=>) knowledge_search.query_embedding
    limit v_candidates
  ),
  vector_ranked as (
    select h.document_id, h.idx, row_number() over (order by h.distance) as rank from vector_hits h
  ),
  text_hits as materialized (
    select t."document_id" as document_id, t."idx" as idx, ts_rank_cd(t."tsv", q) as text_score
    from "better_supabase"."knowledge_chunks" t, websearch_to_tsquery('simple'::regconfig, knowledge_search.query_text) q
    where knowledge_search.query_text is not null and t."tsv" @@ q
      and t."document_id" in (select docs.id from docs)
    order by text_score desc
    limit v_candidates
  ),
  text_ranked as (
    select x.document_id, x.idx, row_number() over (order by x.text_score desc) as rank from text_hits x
  ),
  fused as (
    select coalesce(v.document_id, x.document_id) as document_id, coalesce(v.idx, x.idx) as idx,
      coalesce(1.0 / (60 + v.rank), 0) + coalesce(1.0 / (60 + x.rank), 0) as score
    from vector_ranked v full join text_ranked x on x.document_id = v.document_id and x.idx = v.idx
  )
  select coalesce(jsonb_agg(jsonb_build_object('document_id', r.document_id, 'idx', r.idx, 'content', r.content, 'metadata', r.metadata, 'title', r.title, 'score', r.score) order by r.score desc, r.document_id, r.idx), '[]')
  into v_rows
  from (
    select f.document_id, f.idx, t."content" as content, t."metadata" as metadata, docs.title, f.score
    from fused f
    join "better_supabase"."knowledge_chunks" t on t."document_id" = f.document_id and t."idx" = f.idx
    join docs on docs.id = f.document_id
    order by f.score desc, f.document_id, f.idx
    limit least(greatest(knowledge_search.k, 1), 100)
  ) r;
  perform set_config('hnsw.iterative_scan', coalesce(previous_scan, 'off'), true);
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."knowledge_search"(uuid, extensions.vector, text, jsonb, integer, jsonb) from public, anon;
grant execute on function "better_supabase"."knowledge_search"(uuid, extensions.vector, text, jsonb, integer, jsonb) to authenticated, service_role;

-- The chunks of a document still waiting for an embedding, for the worker.
create or replace function "better_supabase"."pending_knowledge_chunks"(document_id uuid, batch integer default 64)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('idx', x."idx", 'content', x."content") order by x."idx"), '[]')
  from (
    select * from "better_supabase"."knowledge_chunks" y
    where y."document_id" = pending_knowledge_chunks.document_id and y."embedding" is null
    order by y."idx"
    limit least(greatest(pending_knowledge_chunks.batch, 1), 2048)
  ) x
$$;
revoke execute on function "better_supabase"."pending_knowledge_chunks"(uuid, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."pending_knowledge_chunks"(uuid, integer) to service_role;

-- Stores embeddings ([{"idx", "embedding"}], or {"items": list}) and marks the document ready
-- once no chunk is missing one. Returns how many chunks still wait.
create or replace function "better_supabase"."set_knowledge_embeddings"(document_id uuid, embeddings jsonb, model text default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_remaining integer;
  v_items jsonb := case when jsonb_typeof(set_knowledge_embeddings.embeddings) = 'object' then set_knowledge_embeddings.embeddings -> 'items' else set_knowledge_embeddings.embeddings end;
begin
  update "better_supabase"."knowledge_chunks" t set
    "embedding" = (e.value ->> 'embedding')::extensions.vector(1536),
    "embedding_hash" = md5(t."content")
  from jsonb_array_elements(coalesce(v_items, '[]')) e
  where t."document_id" = set_knowledge_embeddings.document_id and t."idx" = (e.value ->> 'idx')::integer;
  select count(*)::integer into v_remaining from "better_supabase"."knowledge_chunks" t
  where t."document_id" = set_knowledge_embeddings.document_id and t."embedding" is null;
  update "better_supabase"."knowledge_documents" x set
    "status" = case when v_remaining = 0 then 'ready' else x."status" end,
    "embedding_model" = coalesce(set_knowledge_embeddings.model, x."embedding_model"),
    "updated_at" = now()
  where x."id" = set_knowledge_embeddings.document_id;
  return v_remaining;
end;
$$;
revoke execute on function "better_supabase"."set_knowledge_embeddings"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."set_knowledge_embeddings"(uuid, jsonb, text) to service_role;

create or replace function "better_supabase"."fail_knowledge_document"(document_id uuid, error text)
returns boolean
language sql
security definer
set search_path = ''
as $$
  update "better_supabase"."knowledge_documents" x set "status" = 'failed', "error" = left(fail_knowledge_document.error, 2000), "updated_at" = now()
  where x."id" = fail_knowledge_document.document_id
  returning true
$$;
revoke execute on function "better_supabase"."fail_knowledge_document"(uuid, text) from public, anon, authenticated;
grant execute on function "better_supabase"."fail_knowledge_document"(uuid, text) to service_role;

-- Documents waiting for embeddings, oldest first, for a drain without jobs.
create or replace function "better_supabase"."pending_knowledge_documents"(batch integer default 10)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(x."id" order by x."updated_at"), '[]')
  from (
    select * from "better_supabase"."knowledge_documents" y where y."status" = 'pending'
    order by y."updated_at"
    limit least(greatest(pending_knowledge_documents.batch, 1), 1000)
  ) x
$$;
revoke execute on function "better_supabase"."pending_knowledge_documents"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."pending_knowledge_documents"(integer) to service_role;

-- Clears the embeddings of a tenant's documents (all tenants when null)
-- that another model embedded, so the worker embeds them again.
create or replace function "better_supabase"."reembed_knowledge"(tenant uuid default null, model text default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_count integer := 0;
begin
  for v_id in
    update "better_supabase"."knowledge_documents" x set "status" = 'pending', "updated_at" = now()
    where (reembed_knowledge.tenant is null or x."organization_id" = reembed_knowledge.tenant)
      and (reembed_knowledge.model is null or x."embedding_model" is distinct from reembed_knowledge.model)
      and x."chunk_count" > 0
    returning x."id"
  loop
    update "better_supabase"."knowledge_chunks" t set "embedding" = null, "embedding_hash" = null where t."document_id" = v_id;
  perform "better_supabase"."enqueue_job"(queue => 'knowledge_embed', payload => jsonb_build_object('document_id', v_id), dedupe_key => 'knowledge:' || v_id::text, dedupe_running => false);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."reembed_knowledge"(uuid, text) from public, anon, authenticated;
grant execute on function "better_supabase"."reembed_knowledge"(uuid, text) to service_role;

-- sql.modules.knowledge.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."create_knowledge_document"(tenant uuid, title text, scope text default 'user', scope_id uuid default null, file_id uuid default null, source text default null, metadata jsonb default '{}', owner uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_knowledge_document"($1, $2, $3, $4, $5, $6, $7, $8) $$;
revoke execute on function "api"."create_knowledge_document"(uuid, text, text, uuid, uuid, text, jsonb, uuid) from public, anon;
grant execute on function "api"."create_knowledge_document"(uuid, text, text, uuid, uuid, text, jsonb, uuid) to authenticated, service_role;

create or replace function "api"."write_knowledge_chunks"(document_id uuid, chunks jsonb, model text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."write_knowledge_chunks"($1, $2, $3) $$;
revoke execute on function "api"."write_knowledge_chunks"(uuid, jsonb, text) from public, anon;
grant execute on function "api"."write_knowledge_chunks"(uuid, jsonb, text) to authenticated, service_role;

create or replace function "api"."get_knowledge_document"(document_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_knowledge_document"($1) $$;
revoke execute on function "api"."get_knowledge_document"(uuid) from public, anon;
grant execute on function "api"."get_knowledge_document"(uuid) to authenticated, service_role;

create or replace function "api"."list_knowledge_documents"(tenant uuid, scope text default null, scope_id uuid default null, max_rows integer default 100)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_knowledge_documents"($1, $2, $3, $4) $$;
revoke execute on function "api"."list_knowledge_documents"(uuid, text, uuid, integer) from public, anon;
grant execute on function "api"."list_knowledge_documents"(uuid, text, uuid, integer) to authenticated, service_role;

create or replace function "api"."delete_knowledge_document"(document_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_knowledge_document"($1) $$;
revoke execute on function "api"."delete_knowledge_document"(uuid) from public, anon;
grant execute on function "api"."delete_knowledge_document"(uuid) to authenticated, service_role;

create or replace function "api"."knowledge_search"(tenant uuid, query_embedding extensions.vector default null, query_text text default null, scopes jsonb default null, k integer default 8, filter jsonb default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."knowledge_search"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."knowledge_search"(uuid, extensions.vector, text, jsonb, integer, jsonb) from public, anon;
grant execute on function "api"."knowledge_search"(uuid, extensions.vector, text, jsonb, integer, jsonb) to authenticated, service_role;

create or replace function "api"."pending_knowledge_chunks"(document_id uuid, batch integer default 64)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."pending_knowledge_chunks"($1, $2) $$;
revoke execute on function "api"."pending_knowledge_chunks"(uuid, integer) from public, anon, authenticated;
grant execute on function "api"."pending_knowledge_chunks"(uuid, integer) to service_role;

create or replace function "api"."set_knowledge_embeddings"(document_id uuid, embeddings jsonb, model text default null)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_knowledge_embeddings"($1, $2, $3) $$;
revoke execute on function "api"."set_knowledge_embeddings"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "api"."set_knowledge_embeddings"(uuid, jsonb, text) to service_role;

create or replace function "api"."fail_knowledge_document"(document_id uuid, error text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."fail_knowledge_document"($1, $2) $$;
revoke execute on function "api"."fail_knowledge_document"(uuid, text) from public, anon, authenticated;
grant execute on function "api"."fail_knowledge_document"(uuid, text) to service_role;

create or replace function "api"."pending_knowledge_documents"(batch integer default 10)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."pending_knowledge_documents"($1) $$;
revoke execute on function "api"."pending_knowledge_documents"(integer) from public, anon, authenticated;
grant execute on function "api"."pending_knowledge_documents"(integer) to service_role;

create or replace function "api"."reembed_knowledge"(tenant uuid default null, model text default null)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."reembed_knowledge"($1, $2) $$;
revoke execute on function "api"."reembed_knowledge"(uuid, text) from public, anon, authenticated;
grant execute on function "api"."reembed_knowledge"(uuid, text) to service_role;

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
