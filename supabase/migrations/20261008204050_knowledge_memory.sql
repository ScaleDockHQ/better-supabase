SET local check_function_bodies = off;

ALTER TABLE "better_supabase"."ai_files"
  DROP CONSTRAINT "ai_files_filename_check";

CREATE TABLE "better_supabase"."ai_message_embeddings" (
  "chat_id"         uuid                     NOT NULL,
  "message_id"      text                     NOT NULL,
  "user_id"         uuid                     NOT NULL,
  "organization_id" uuid                     NOT NULL,
  "embedding"       extensions.vector(1536)  NOT NULL,
  "embedding_model" text,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "ai_message_embeddings_pkey" PRIMARY KEY (chat_id, message_id)
);

ALTER TABLE "better_supabase"."ai_message_embeddings"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."knowledge_chunks" (
  "document_id"    uuid                    NOT NULL,
  "idx"            integer                 NOT NULL,
  "content"        text                    NOT NULL,
  "token_count"    integer,
  "embedding"      extensions.vector(1536),
  "embedding_hash" text,
  "metadata"       jsonb                   NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT "knowledge_chunks_content_check" CHECK ((length(content) > 0)),
  CONSTRAINT "knowledge_chunks_idx_check" CHECK ((idx >= 0)),
  CONSTRAINT "knowledge_chunks_pkey" PRIMARY KEY (document_id, idx)
);

ALTER TABLE "better_supabase"."knowledge_chunks"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."knowledge_documents" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "organization_id" uuid                     NOT NULL,
  "owner_id"        uuid,
  "scope"           text                     NOT NULL DEFAULT 'user'::text,
  "scope_id"        uuid,
  "file_id"         uuid,
  "title"           text                     NOT NULL,
  "source"          text,
  "metadata"        jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "status"          text                     NOT NULL DEFAULT 'pending'::text,
  "error"           text,
  "chunk_count"     integer                  NOT NULL DEFAULT 0,
  "embedding_model" text,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "knowledge_documents_check" CHECK (((scope = 'organization'::text) = (scope_id IS NULL))),
  CONSTRAINT "knowledge_documents_metadata_check" CHECK ((jsonb_typeof(metadata) = 'object'::text)),
  CONSTRAINT "knowledge_documents_pkey" PRIMARY KEY (id),
  CONSTRAINT "knowledge_documents_scope_check" CHECK ((scope = ANY (ARRAY['organization'::text, 'agent'::text, 'project'::text, 'chat'::text, 'user'::text]))),
  CONSTRAINT "knowledge_documents_status_check" CHECK ((status = ANY (ARRAY['pending'::text, 'ready'::text, 'failed'::text]))),
  CONSTRAINT "knowledge_documents_title_check" CHECK (((length(title) >= 1) AND (length(title) <= 500)))
);

ALTER TABLE "better_supabase"."knowledge_documents"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."memories" (
  "id"                uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "organization_id"   uuid                     NOT NULL,
  "owner_id"          uuid,
  "scope"             text                     NOT NULL DEFAULT 'user'::text,
  "agent_id"          uuid,
  "chat_id"           uuid,
  "kind"              text                     NOT NULL,
  "path"              text,
  "content"           text                     NOT NULL,
  "version"           integer                  NOT NULL DEFAULT 1,
  "embedding"         extensions.vector(1536),
  "embedding_model"   text,
  "source_message_id" text,
  "superseded_by"     uuid,
  "created_at"        timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"        timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "memories_check1" CHECK (((scope = 'organization'::text) = (owner_id IS NULL))),
  CONSTRAINT "memories_check" CHECK (((kind = 'core'::text) = (path IS NOT NULL))),
  CONSTRAINT "memories_content_check" CHECK ((length(content) <= 100000)),
  CONSTRAINT "memories_kind_check" CHECK ((kind = ANY (ARRAY['core'::text, 'archival'::text]))),
  CONSTRAINT "memories_path_check" CHECK (((path ~ '^/memories(/[A-Za-z0-9._ -]+)*$'::text) AND (path !~ '(^|/)[.]{1,2}(/|$)'::text))),
  CONSTRAINT "memories_pkey" PRIMARY KEY (id),
  CONSTRAINT "memories_scope_check" CHECK ((scope = ANY (ARRAY['user'::text, 'agent'::text, 'chat'::text, 'organization'::text])))
);

ALTER TABLE "better_supabase"."memories"
  ENABLE ROW LEVEL SECURITY;

ALTER TABLE "better_supabase"."knowledge_chunks"
  ADD COLUMN "tsv" tsvector GENERATED ALWAYS AS (to_tsvector('simple'::regconfig, content)) STORED;

ALTER TABLE "better_supabase"."memories"
  ADD COLUMN "tsv" tsvector GENERATED ALWAYS AS (to_tsvector('simple'::regconfig, content)) STORED;

CREATE OR REPLACE FUNCTION api.create_knowledge_document (
  tenant   uuid,
  title    text,
  scope    text  DEFAULT 'user'::text,
  scope_id uuid  DEFAULT NULL::uuid,
  file_id  uuid  DEFAULT NULL::uuid,
  source   text  DEFAULT NULL::text,
  metadata jsonb DEFAULT '{}'::jsonb,
  owner    uuid  DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."create_knowledge_document"($1, $2, $3, $4, $5, $6, $7, $8) $function$;

CREATE OR REPLACE FUNCTION api.delete_knowledge_document (
  document_id uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."delete_knowledge_document"($1) $function$;

CREATE OR REPLACE FUNCTION api.fail_knowledge_document (
  document_id uuid,
  error       text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."fail_knowledge_document"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.get_knowledge_document (
  document_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_knowledge_document"($1) $function$;

CREATE OR REPLACE FUNCTION api.knowledge_search (
  tenant          uuid,
  query_embedding extensions.vector DEFAULT NULL::extensions.vector,
  query_text      text              DEFAULT NULL::text,
  scopes          jsonb             DEFAULT NULL::jsonb,
  k               integer           DEFAULT 8,
  filter          jsonb             DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."knowledge_search"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.list_knowledge_documents (
  tenant   uuid,
  scope    text    DEFAULT NULL::text,
  scope_id uuid    DEFAULT NULL::uuid,
  max_rows integer DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_knowledge_documents"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.memory_create (
  tenant           uuid,
  path             text,
  content          text,
  ns               jsonb   DEFAULT '{}'::jsonb,
  expected_version integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."memory_create"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.memory_delete (
  tenant uuid,
  path   text,
  ns     jsonb DEFAULT '{}'::jsonb
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."memory_delete"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.memory_forget (
  memory_id     uuid,
  superseded_by uuid DEFAULT NULL::uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."memory_forget"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.memory_insert (
  tenant      uuid,
  path        text,
  insert_line integer,
  insert_text text,
  ns          jsonb   DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."memory_insert"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.memory_list (
  tenant   uuid,
  ns       jsonb   DEFAULT '{}'::jsonb,
  kind     text    DEFAULT 'core'::text,
  max_rows integer DEFAULT 200
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."memory_list"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.memory_rename (
  tenant   uuid,
  old_path text,
  new_path text,
  ns       jsonb DEFAULT '{}'::jsonb
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."memory_rename"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.memory_save (
  tenant            uuid,
  content           text,
  ns                jsonb             DEFAULT '{}'::jsonb,
  embedding         extensions.vector DEFAULT NULL::extensions.vector,
  model             text              DEFAULT NULL::text,
  source_message_id text              DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."memory_save"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.memory_search (
  tenant          uuid,
  query_embedding extensions.vector DEFAULT NULL::extensions.vector,
  query_text      text              DEFAULT NULL::text,
  ns              jsonb             DEFAULT '{}'::jsonb,
  k               integer           DEFAULT 8
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."memory_search"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.memory_str_replace (
  tenant   uuid,
  path     text,
  old_text text,
  new_text text,
  ns       jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."memory_str_replace"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.memory_view (
  tenant uuid,
  path   text  DEFAULT '/memories'::text,
  ns     jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."memory_view"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.pending_knowledge_chunks (
  document_id uuid,
  batch       integer DEFAULT 64
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."pending_knowledge_chunks"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.pending_knowledge_documents (
  batch integer DEFAULT 10
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."pending_knowledge_documents"($1) $function$;

CREATE OR REPLACE FUNCTION api.pending_memory_embeddings (
  batch integer DEFAULT 64
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."pending_memory_embeddings"($1) $function$;

CREATE OR REPLACE FUNCTION api.recall_ai_messages (
  tenant          uuid,
  query_embedding extensions.vector,
  k               integer           DEFAULT 5,
  exclude_chat    uuid              DEFAULT NULL::uuid,
  owner           uuid              DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."recall_ai_messages"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.reembed_knowledge (
  tenant uuid DEFAULT NULL::uuid,
  model  text DEFAULT NULL::text
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."reembed_knowledge"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.set_ai_message_embedding (
  chat_id    uuid,
  message_id text,
  user_id    uuid,
  tenant     uuid,
  embedding  extensions.vector,
  model      text              DEFAULT NULL::text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_ai_message_embedding"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.set_knowledge_embeddings (
  document_id uuid,
  embeddings  jsonb,
  model       text  DEFAULT NULL::text
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_knowledge_embeddings"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.set_memory_embedding (
  memory_id uuid,
  embedding extensions.vector,
  model     text              DEFAULT NULL::text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_memory_embedding"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.write_knowledge_chunks (
  document_id uuid,
  chunks      jsonb,
  model       text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."write_knowledge_chunks"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION better_supabase.create_knowledge_document (
  tenant   uuid,
  title    text,
  scope    text  DEFAULT 'user'::text,
  scope_id uuid  DEFAULT NULL::uuid,
  file_id  uuid  DEFAULT NULL::uuid,
  source   text  DEFAULT NULL::text,
  metadata jsonb DEFAULT '{}'::jsonb,
  owner    uuid  DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_knowledge_document (
  document_id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.fail_knowledge_document (
  document_id uuid,
  error       text
)
  RETURNS boolean
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  update "better_supabase"."knowledge_documents" x set "status" = 'failed', "error" = left(fail_knowledge_document.error, 2000), "updated_at" = now()
  where x."id" = fail_knowledge_document.document_id
  returning true
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_knowledge_document (
  document_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'owner_id', x."owner_id", 'scope', x."scope", 'scope_id', x."scope_id", 'file_id', x."file_id", 'title', x."title", 'source', x."source", 'metadata', x."metadata", 'status', x."status", 'error', x."error", 'chunk_count', x."chunk_count", 'embedding_model', x."embedding_model", 'created_at', x."created_at", 'updated_at', x."updated_at") from "better_supabase"."knowledge_documents" x where x."id" = get_knowledge_document.document_id
$function$;

CREATE OR REPLACE FUNCTION better_supabase.knowledge_search (
  tenant          uuid,
  query_embedding extensions.vector DEFAULT NULL::extensions.vector,
  query_text      text              DEFAULT NULL::text,
  scopes          jsonb             DEFAULT NULL::jsonb,
  k               integer           DEFAULT 8,
  filter          jsonb             DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_knowledge_documents (
  tenant   uuid,
  scope    text    DEFAULT NULL::text,
  scope_id uuid    DEFAULT NULL::uuid,
  max_rows integer DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'owner_id', x."owner_id", 'scope', x."scope", 'scope_id', x."scope_id", 'file_id', x."file_id", 'title', x."title", 'source', x."source", 'metadata', x."metadata", 'status', x."status", 'error', x."error", 'chunk_count', x."chunk_count", 'embedding_model', x."embedding_model", 'created_at', x."created_at", 'updated_at', x."updated_at") order by x."created_at" desc), '[]')
  from (
    select * from "better_supabase"."knowledge_documents" y
    where y."organization_id" = list_knowledge_documents.tenant
      and (list_knowledge_documents.scope is null or y."scope" = list_knowledge_documents.scope)
      and (list_knowledge_documents.scope_id is null or y."scope_id" = list_knowledge_documents.scope_id)
    order by y."created_at" desc
    limit least(greatest(list_knowledge_documents.max_rows, 1), 1000)
  ) x
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memory_create (
  tenant           uuid,
  path             text,
  content          text,
  ns               jsonb   DEFAULT '{}'::jsonb,
  expected_version integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_scope text;
  v_agent uuid;
  v_chat uuid;
  v_owner uuid;
  v_row "better_supabase"."memories"%rowtype;
begin
  v_scope := coalesce(memory_create.ns ->> 'scope', 'user');
  v_agent := (memory_create.ns ->> 'agent_id')::uuid;
  v_chat := (memory_create.ns ->> 'chat_id')::uuid;
  v_owner := case when v_scope = 'organization' then null when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then (memory_create.ns ->> 'owner_id')::uuid else auth.uid() end;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (auth.uid() is null or not coalesce(better_supabase.can('tenant', memory_create.tenant, 'ai_chat.read'), false)) then
    raise exception 'you may not use memory here' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if v_scope not in ('user', 'agent', 'chat', 'organization')
    or (v_scope = 'agent') <> (v_agent is not null)
    or (v_scope = 'chat') <> (v_chat is not null)
    or (v_scope <> 'organization' and v_owner is null) then
    raise exception 'ns % is not a memory namespace', memory_create.ns using errcode = '22023', hint = 'MEMORY_NAMESPACE';
  end if;
  if v_scope = 'organization' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', memory_create.tenant, 'ai_chat.admin'), false)) then
    raise exception 'only admins change organization memory' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if memory_create.path is null or length(memory_create.path) > 500 or memory_create.path !~ '^/memories(/[A-Za-z0-9._ -]+)*$' or memory_create.path ~ '(^|/)[.]{1,2}(/|$)' then
    raise exception '% is not a path under /memories', memory_create.path using errcode = '22023', hint = 'MEMORY_PATH';
  end if;
  if length(memory_create.content) > 100000 then
    raise exception 'memory content is limited to % characters', 100000 using errcode = '22023', hint = 'MEMORY_TOO_LARGE';
  end if;
  select * into v_row from "better_supabase"."memories" x
  where x."organization_id" = memory_create.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."superseded_by" is null and x."path" = memory_create.path
  for update;
  if found then
    if memory_create.expected_version is not null and memory_create.expected_version <> v_row."version" then
      raise exception '% changed since version %', memory_create.path, memory_create.expected_version using errcode = '40001', hint = 'MEMORY_CONFLICT';
    end if;
    update "better_supabase"."memories" x set "content" = memory_create.content, "version" = x."version" + 1, "embedding" = null, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  else
    if coalesce(memory_create.expected_version, 0) <> 0 then
      raise exception '% not found', memory_create.path using errcode = 'P0002', hint = 'MEMORY_NOT_FOUND';
    end if;
    insert into "better_supabase"."memories" ("organization_id", "owner_id", "scope", "agent_id", "chat_id", "kind", "path", "content")
    values (memory_create.tenant, v_owner, v_scope, v_agent, v_chat, 'core', memory_create.path, memory_create.content)
    returning * into v_row;
  end if;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'scope', v_row."scope", 'agent_id', v_row."agent_id", 'chat_id', v_row."chat_id", 'kind', v_row."kind", 'path', v_row."path", 'content', v_row."content", 'version', v_row."version", 'embedding_model', v_row."embedding_model", 'source_message_id', v_row."source_message_id", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memory_delete (
  tenant uuid,
  path   text,
  ns     jsonb DEFAULT '{}'::jsonb
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_scope text;
  v_agent uuid;
  v_chat uuid;
  v_owner uuid;
  v_count integer;
begin
  v_scope := coalesce(memory_delete.ns ->> 'scope', 'user');
  v_agent := (memory_delete.ns ->> 'agent_id')::uuid;
  v_chat := (memory_delete.ns ->> 'chat_id')::uuid;
  v_owner := case when v_scope = 'organization' then null when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then (memory_delete.ns ->> 'owner_id')::uuid else auth.uid() end;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (auth.uid() is null or not coalesce(better_supabase.can('tenant', memory_delete.tenant, 'ai_chat.read'), false)) then
    raise exception 'you may not use memory here' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if v_scope not in ('user', 'agent', 'chat', 'organization')
    or (v_scope = 'agent') <> (v_agent is not null)
    or (v_scope = 'chat') <> (v_chat is not null)
    or (v_scope <> 'organization' and v_owner is null) then
    raise exception 'ns % is not a memory namespace', memory_delete.ns using errcode = '22023', hint = 'MEMORY_NAMESPACE';
  end if;
  if v_scope = 'organization' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', memory_delete.tenant, 'ai_chat.admin'), false)) then
    raise exception 'only admins change organization memory' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if memory_delete.path is null or length(memory_delete.path) > 500 or memory_delete.path !~ '^/memories(/[A-Za-z0-9._ -]+)*$' or memory_delete.path ~ '(^|/)[.]{1,2}(/|$)' then
    raise exception '% is not a path under /memories', memory_delete.path using errcode = '22023', hint = 'MEMORY_PATH';
  end if;
  delete from "better_supabase"."memories" x
  where x."organization_id" = memory_delete.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."superseded_by" is null
    and (x."path" = memory_delete.path or x."path" like replace(replace(memory_delete.path, '_', '\_'), '%', '\%') || '/%');
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memory_forget (
  memory_id     uuid,
  superseded_by uuid DEFAULT NULL::uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."memories"%rowtype;
begin
  select * into v_row from "better_supabase"."memories" x where x."id" = memory_forget.memory_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = auth.uid() or (v_row."scope" = 'organization' and coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai_chat.admin'), false))) then
    return false;
  end if;
  if memory_forget.superseded_by is null then
    delete from "better_supabase"."memories" x where x."id" = v_row."id";
  else
    update "better_supabase"."memories" x set "superseded_by" = memory_forget.superseded_by, "updated_at" = now() where x."id" = v_row."id";
  end if;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memory_insert (
  tenant      uuid,
  path        text,
  insert_line integer,
  insert_text text,
  ns          jsonb   DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_scope text;
  v_agent uuid;
  v_chat uuid;
  v_owner uuid;
  v_row "better_supabase"."memories"%rowtype;
  v_lines text[];
  v_content text;
begin
  v_scope := coalesce(memory_insert.ns ->> 'scope', 'user');
  v_agent := (memory_insert.ns ->> 'agent_id')::uuid;
  v_chat := (memory_insert.ns ->> 'chat_id')::uuid;
  v_owner := case when v_scope = 'organization' then null when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then (memory_insert.ns ->> 'owner_id')::uuid else auth.uid() end;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (auth.uid() is null or not coalesce(better_supabase.can('tenant', memory_insert.tenant, 'ai_chat.read'), false)) then
    raise exception 'you may not use memory here' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if v_scope not in ('user', 'agent', 'chat', 'organization')
    or (v_scope = 'agent') <> (v_agent is not null)
    or (v_scope = 'chat') <> (v_chat is not null)
    or (v_scope <> 'organization' and v_owner is null) then
    raise exception 'ns % is not a memory namespace', memory_insert.ns using errcode = '22023', hint = 'MEMORY_NAMESPACE';
  end if;
  if v_scope = 'organization' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', memory_insert.tenant, 'ai_chat.admin'), false)) then
    raise exception 'only admins change organization memory' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if memory_insert.path is null or length(memory_insert.path) > 500 or memory_insert.path !~ '^/memories(/[A-Za-z0-9._ -]+)*$' or memory_insert.path ~ '(^|/)[.]{1,2}(/|$)' then
    raise exception '% is not a path under /memories', memory_insert.path using errcode = '22023', hint = 'MEMORY_PATH';
  end if;
  select * into v_row from "better_supabase"."memories" x
  where x."organization_id" = memory_insert.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."superseded_by" is null and x."path" = memory_insert.path
  for update;
  if not found then
    raise exception '% not found', memory_insert.path using errcode = 'P0002', hint = 'MEMORY_NOT_FOUND';
  end if;
  v_lines := case when v_row."content" = '' then '{}'::text[] else string_to_array(v_row."content", E'\n') end;
  if memory_insert.insert_line < 0 or memory_insert.insert_line > coalesce(array_length(v_lines, 1), 0) then
    raise exception 'line % is outside the file', memory_insert.insert_line using errcode = '22023', hint = 'MEMORY_LINE';
  end if;
  v_content := array_to_string(v_lines[1:memory_insert.insert_line] || string_to_array(coalesce(memory_insert.insert_text, ''), E'\n') || v_lines[memory_insert.insert_line + 1:], E'\n');
  if length(v_content) > 100000 then
    raise exception 'memory content is limited to % characters', 100000 using errcode = '22023', hint = 'MEMORY_TOO_LARGE';
  end if;
  update "better_supabase"."memories" x set "content" = v_content, "version" = x."version" + 1, "embedding" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'scope', v_row."scope", 'agent_id', v_row."agent_id", 'chat_id', v_row."chat_id", 'kind', v_row."kind", 'path', v_row."path", 'content', v_row."content", 'version', v_row."version", 'embedding_model', v_row."embedding_model", 'source_message_id', v_row."source_message_id", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memory_list (
  tenant   uuid,
  ns       jsonb   DEFAULT '{}'::jsonb,
  kind     text    DEFAULT 'core'::text,
  max_rows integer DEFAULT 200
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_scope text;
  v_agent uuid;
  v_chat uuid;
  v_owner uuid;
  v_rows jsonb;
begin
  v_scope := coalesce(memory_list.ns ->> 'scope', 'user');
  v_agent := (memory_list.ns ->> 'agent_id')::uuid;
  v_chat := (memory_list.ns ->> 'chat_id')::uuid;
  v_owner := case when v_scope = 'organization' then null when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then (memory_list.ns ->> 'owner_id')::uuid else auth.uid() end;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (auth.uid() is null or not coalesce(better_supabase.can('tenant', memory_list.tenant, 'ai_chat.read'), false)) then
    raise exception 'you may not use memory here' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if v_scope not in ('user', 'agent', 'chat', 'organization')
    or (v_scope = 'agent') <> (v_agent is not null)
    or (v_scope = 'chat') <> (v_chat is not null)
    or (v_scope <> 'organization' and v_owner is null) then
    raise exception 'ns % is not a memory namespace', memory_list.ns using errcode = '22023', hint = 'MEMORY_NAMESPACE';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'owner_id', x."owner_id", 'scope', x."scope", 'agent_id', x."agent_id", 'chat_id', x."chat_id", 'kind', x."kind", 'path', x."path", 'content', x."content", 'version', x."version", 'embedding_model', x."embedding_model", 'source_message_id', x."source_message_id", 'created_at', x."created_at", 'updated_at', x."updated_at") order by x."path", x."created_at" desc), '[]') into v_rows
  from (
    select * from "better_supabase"."memories" y
    where y."organization_id" = memory_list.tenant and y."owner_id" is not distinct from v_owner and y."scope" = v_scope and y."agent_id" is not distinct from v_agent and y."chat_id" is not distinct from v_chat and y."superseded_by" is null and y."kind" = memory_list.kind
    order by y."path", y."created_at" desc
    limit least(greatest(memory_list.max_rows, 1), 1000)
  ) x;
  return v_rows;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memory_rename (
  tenant   uuid,
  old_path text,
  new_path text,
  ns       jsonb DEFAULT '{}'::jsonb
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_scope text;
  v_agent uuid;
  v_chat uuid;
  v_owner uuid;
  v_count integer;
  v_prefix text := replace(replace(memory_rename.old_path, '_', '\_'), '%', '\%') || '/%';
begin
  v_scope := coalesce(memory_rename.ns ->> 'scope', 'user');
  v_agent := (memory_rename.ns ->> 'agent_id')::uuid;
  v_chat := (memory_rename.ns ->> 'chat_id')::uuid;
  v_owner := case when v_scope = 'organization' then null when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then (memory_rename.ns ->> 'owner_id')::uuid else auth.uid() end;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (auth.uid() is null or not coalesce(better_supabase.can('tenant', memory_rename.tenant, 'ai_chat.read'), false)) then
    raise exception 'you may not use memory here' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if v_scope not in ('user', 'agent', 'chat', 'organization')
    or (v_scope = 'agent') <> (v_agent is not null)
    or (v_scope = 'chat') <> (v_chat is not null)
    or (v_scope <> 'organization' and v_owner is null) then
    raise exception 'ns % is not a memory namespace', memory_rename.ns using errcode = '22023', hint = 'MEMORY_NAMESPACE';
  end if;
  if v_scope = 'organization' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', memory_rename.tenant, 'ai_chat.admin'), false)) then
    raise exception 'only admins change organization memory' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if memory_rename.old_path is null or length(memory_rename.old_path) > 500 or memory_rename.old_path !~ '^/memories(/[A-Za-z0-9._ -]+)*$' or memory_rename.old_path ~ '(^|/)[.]{1,2}(/|$)' then
    raise exception '% is not a path under /memories', memory_rename.old_path using errcode = '22023', hint = 'MEMORY_PATH';
  end if;
  if memory_rename.new_path is null or length(memory_rename.new_path) > 500 or memory_rename.new_path !~ '^/memories(/[A-Za-z0-9._ -]+)*$' or memory_rename.new_path ~ '(^|/)[.]{1,2}(/|$)' then
    raise exception '% is not a path under /memories', memory_rename.new_path using errcode = '22023', hint = 'MEMORY_PATH';
  end if;
  if memory_rename.new_path = memory_rename.old_path or memory_rename.new_path like v_prefix then
    raise exception 'cannot move % into itself', memory_rename.old_path using errcode = '22023', hint = 'MEMORY_PATH';
  end if;
  if exists (
    select 1 from "better_supabase"."memories" x
    where x."organization_id" = memory_rename.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."superseded_by" is null
      and (x."path" = memory_rename.new_path or x."path" like replace(replace(memory_rename.new_path, '_', '\_'), '%', '\%') || '/%')
  ) then
    raise exception '% already exists', memory_rename.new_path using errcode = '23505', hint = 'MEMORY_EXISTS';
  end if;
  update "better_supabase"."memories" x set
    "path" = memory_rename.new_path || substr(x."path", length(memory_rename.old_path) + 1),
    "version" = x."version" + 1, "updated_at" = now()
  where x."organization_id" = memory_rename.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."superseded_by" is null
    and (x."path" = memory_rename.old_path or x."path" like v_prefix);
  get diagnostics v_count = row_count;
  if v_count = 0 then
    raise exception '% not found', memory_rename.old_path using errcode = 'P0002', hint = 'MEMORY_NOT_FOUND';
  end if;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memory_save (
  tenant            uuid,
  content           text,
  ns                jsonb             DEFAULT '{}'::jsonb,
  embedding         extensions.vector DEFAULT NULL::extensions.vector,
  model             text              DEFAULT NULL::text,
  source_message_id text              DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_scope text;
  v_agent uuid;
  v_chat uuid;
  v_owner uuid;
  v_row "better_supabase"."memories"%rowtype;
begin
  v_scope := coalesce(memory_save.ns ->> 'scope', 'user');
  v_agent := (memory_save.ns ->> 'agent_id')::uuid;
  v_chat := (memory_save.ns ->> 'chat_id')::uuid;
  v_owner := case when v_scope = 'organization' then null when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then (memory_save.ns ->> 'owner_id')::uuid else auth.uid() end;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (auth.uid() is null or not coalesce(better_supabase.can('tenant', memory_save.tenant, 'ai_chat.read'), false)) then
    raise exception 'you may not use memory here' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if v_scope not in ('user', 'agent', 'chat', 'organization')
    or (v_scope = 'agent') <> (v_agent is not null)
    or (v_scope = 'chat') <> (v_chat is not null)
    or (v_scope <> 'organization' and v_owner is null) then
    raise exception 'ns % is not a memory namespace', memory_save.ns using errcode = '22023', hint = 'MEMORY_NAMESPACE';
  end if;
  if v_scope = 'organization' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', memory_save.tenant, 'ai_chat.admin'), false)) then
    raise exception 'only admins change organization memory' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if coalesce(length(memory_save.content), 0) = 0 then
    raise exception 'memory content is empty' using errcode = '22023', hint = 'MEMORY_EMPTY';
  end if;
  if length(memory_save.content) > 100000 then
    raise exception 'memory content is limited to % characters', 100000 using errcode = '22023', hint = 'MEMORY_TOO_LARGE';
  end if;
  insert into "better_supabase"."memories" ("organization_id", "owner_id", "scope", "agent_id", "chat_id", "kind", "content", "embedding", "embedding_model", "source_message_id")
  values (memory_save.tenant, v_owner, v_scope, v_agent, v_chat, 'archival', memory_save.content, memory_save.embedding, memory_save.model, memory_save.source_message_id)
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'scope', v_row."scope", 'agent_id', v_row."agent_id", 'chat_id', v_row."chat_id", 'kind', v_row."kind", 'path', v_row."path", 'content', v_row."content", 'version', v_row."version", 'embedding_model', v_row."embedding_model", 'source_message_id', v_row."source_message_id", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memory_search (
  tenant          uuid,
  query_embedding extensions.vector DEFAULT NULL::extensions.vector,
  query_text      text              DEFAULT NULL::text,
  ns              jsonb             DEFAULT '{}'::jsonb,
  k               integer           DEFAULT 8
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_scope text;
  v_agent uuid;
  v_chat uuid;
  v_owner uuid;
  v_rows jsonb;
  v_candidates integer := least(greatest(memory_search.k, 1) * 4, 400);
begin
  v_scope := coalesce(memory_search.ns ->> 'scope', 'user');
  v_agent := (memory_search.ns ->> 'agent_id')::uuid;
  v_chat := (memory_search.ns ->> 'chat_id')::uuid;
  v_owner := case when v_scope = 'organization' then null when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then (memory_search.ns ->> 'owner_id')::uuid else auth.uid() end;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (auth.uid() is null or not coalesce(better_supabase.can('tenant', memory_search.tenant, 'ai_chat.read'), false)) then
    raise exception 'you may not use memory here' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if v_scope not in ('user', 'agent', 'chat', 'organization')
    or (v_scope = 'agent') <> (v_agent is not null)
    or (v_scope = 'chat') <> (v_chat is not null)
    or (v_scope <> 'organization' and v_owner is null) then
    raise exception 'ns % is not a memory namespace', memory_search.ns using errcode = '22023', hint = 'MEMORY_NAMESPACE';
  end if;
  perform set_config('hnsw.iterative_scan', 'relaxed_order', true);
  with scoped as materialized (
    select x."id" as id from "better_supabase"."memories" x
    where x."organization_id" = memory_search.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."superseded_by" is null and x."kind" = 'archival'
  ),
  vector_hits as materialized (
    select t."id" as id, t."embedding" operator(extensions.<=>) memory_search.query_embedding as distance
    from "better_supabase"."memories" t
    where memory_search.query_embedding is not null and t."embedding" is not null and t."id" in (select scoped.id from scoped)
    order by t."embedding" operator(extensions.<=>) memory_search.query_embedding
    limit v_candidates
  ),
  vector_ranked as (
    select h.id, h.distance, row_number() over (order by h.distance) as rank from vector_hits h
  ),
  text_ranked as (
    select t."id" as id, row_number() over (order by ts_rank_cd(t."tsv", q) desc) as rank
    from "better_supabase"."memories" t, websearch_to_tsquery('simple'::regconfig, memory_search.query_text) q
    where memory_search.query_text is not null and t."tsv" @@ q and t."id" in (select scoped.id from scoped)
    limit v_candidates
  ),
  fused as (
    select coalesce(v.id, x.id) as id, v.distance,
      coalesce(1.0 / (60 + v.rank), 0) + coalesce(1.0 / (60 + x.rank), 0) as score
    from vector_ranked v full join text_ranked x on x.id = v.id
    order by score desc
    limit least(greatest(memory_search.k, 1), 100)
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', t."id", 'organization_id', t."organization_id", 'owner_id', t."owner_id", 'scope', t."scope", 'agent_id', t."agent_id", 'chat_id', t."chat_id", 'kind', t."kind", 'path', t."path", 'content', t."content", 'version', t."version", 'embedding_model', t."embedding_model", 'source_message_id', t."source_message_id", 'created_at', t."created_at", 'updated_at', t."updated_at") || jsonb_build_object('score', f.score, 'similarity', 1 - f.distance) order by f.score desc), '[]')
  into v_rows
  from fused f join "better_supabase"."memories" t on t."id" = f.id;
  return v_rows;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memory_str_replace (
  tenant   uuid,
  path     text,
  old_text text,
  new_text text,
  ns       jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_scope text;
  v_agent uuid;
  v_chat uuid;
  v_owner uuid;
  v_row "better_supabase"."memories"%rowtype;
  v_matches integer;
begin
  v_scope := coalesce(memory_str_replace.ns ->> 'scope', 'user');
  v_agent := (memory_str_replace.ns ->> 'agent_id')::uuid;
  v_chat := (memory_str_replace.ns ->> 'chat_id')::uuid;
  v_owner := case when v_scope = 'organization' then null when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then (memory_str_replace.ns ->> 'owner_id')::uuid else auth.uid() end;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (auth.uid() is null or not coalesce(better_supabase.can('tenant', memory_str_replace.tenant, 'ai_chat.read'), false)) then
    raise exception 'you may not use memory here' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if v_scope not in ('user', 'agent', 'chat', 'organization')
    or (v_scope = 'agent') <> (v_agent is not null)
    or (v_scope = 'chat') <> (v_chat is not null)
    or (v_scope <> 'organization' and v_owner is null) then
    raise exception 'ns % is not a memory namespace', memory_str_replace.ns using errcode = '22023', hint = 'MEMORY_NAMESPACE';
  end if;
  if v_scope = 'organization' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', memory_str_replace.tenant, 'ai_chat.admin'), false)) then
    raise exception 'only admins change organization memory' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if memory_str_replace.path is null or length(memory_str_replace.path) > 500 or memory_str_replace.path !~ '^/memories(/[A-Za-z0-9._ -]+)*$' or memory_str_replace.path ~ '(^|/)[.]{1,2}(/|$)' then
    raise exception '% is not a path under /memories', memory_str_replace.path using errcode = '22023', hint = 'MEMORY_PATH';
  end if;
  select * into v_row from "better_supabase"."memories" x
  where x."organization_id" = memory_str_replace.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."superseded_by" is null and x."path" = memory_str_replace.path
  for update;
  if not found then
    raise exception '% not found', memory_str_replace.path using errcode = 'P0002', hint = 'MEMORY_NOT_FOUND';
  end if;
  if coalesce(length(memory_str_replace.old_text), 0) = 0 then
    raise exception 'old_text is empty' using errcode = '22023', hint = 'MEMORY_NO_MATCH';
  end if;
  v_matches := (length(v_row."content") - length(replace(v_row."content", memory_str_replace.old_text, ''))) / length(memory_str_replace.old_text);
  if v_matches = 0 then
    raise exception 'old_text does not appear in %', memory_str_replace.path using errcode = '22023', hint = 'MEMORY_NO_MATCH';
  elsif v_matches > 1 then
    raise exception 'old_text appears % times in %', v_matches, memory_str_replace.path using errcode = '22023', hint = 'MEMORY_AMBIGUOUS';
  end if;
  if length(replace(v_row."content", memory_str_replace.old_text, coalesce(memory_str_replace.new_text, ''))) > 100000 then
    raise exception 'memory content is limited to % characters', 100000 using errcode = '22023', hint = 'MEMORY_TOO_LARGE';
  end if;
  update "better_supabase"."memories" x set
    "content" = replace(x."content", memory_str_replace.old_text, coalesce(memory_str_replace.new_text, '')),
    "version" = x."version" + 1, "embedding" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'scope', v_row."scope", 'agent_id', v_row."agent_id", 'chat_id', v_row."chat_id", 'kind', v_row."kind", 'path', v_row."path", 'content', v_row."content", 'version', v_row."version", 'embedding_model', v_row."embedding_model", 'source_message_id', v_row."source_message_id", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memory_view (
  tenant uuid,
  path   text  DEFAULT '/memories'::text,
  ns     jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_scope text;
  v_agent uuid;
  v_chat uuid;
  v_owner uuid;
  v_row "better_supabase"."memories"%rowtype;
  v_entries jsonb;
begin
  v_scope := coalesce(memory_view.ns ->> 'scope', 'user');
  v_agent := (memory_view.ns ->> 'agent_id')::uuid;
  v_chat := (memory_view.ns ->> 'chat_id')::uuid;
  v_owner := case when v_scope = 'organization' then null when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then (memory_view.ns ->> 'owner_id')::uuid else auth.uid() end;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (auth.uid() is null or not coalesce(better_supabase.can('tenant', memory_view.tenant, 'ai_chat.read'), false)) then
    raise exception 'you may not use memory here' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if v_scope not in ('user', 'agent', 'chat', 'organization')
    or (v_scope = 'agent') <> (v_agent is not null)
    or (v_scope = 'chat') <> (v_chat is not null)
    or (v_scope <> 'organization' and v_owner is null) then
    raise exception 'ns % is not a memory namespace', memory_view.ns using errcode = '22023', hint = 'MEMORY_NAMESPACE';
  end if;
  if memory_view.path is null or length(memory_view.path) > 500 or memory_view.path !~ '^/memories(/[A-Za-z0-9._ -]+)*$' or memory_view.path ~ '(^|/)[.]{1,2}(/|$)' then
    raise exception '% is not a path under /memories', memory_view.path using errcode = '22023', hint = 'MEMORY_PATH';
  end if;
  select * into v_row from "better_supabase"."memories" x
  where x."organization_id" = memory_view.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."superseded_by" is null and x."path" = memory_view.path;
  if found then
    return jsonb_build_object('type', 'file', 'path', v_row."path", 'content', v_row."content", 'version', v_row."version", 'updated_at', v_row."updated_at");
  end if;
  select jsonb_agg(jsonb_build_object('path', x."path", 'size', length(x."content"), 'updated_at', x."updated_at") order by x."path")
  into v_entries
  from "better_supabase"."memories" x
  where x."organization_id" = memory_view.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."superseded_by" is null and x."path" like replace(replace(memory_view.path, '_', '\_'), '%', '\%') || '/%';
  if v_entries is null and memory_view.path <> '/memories' then
    return null;
  end if;
  return jsonb_build_object('type', 'directory', 'path', memory_view.path, 'entries', coalesce(v_entries, '[]'));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.pending_knowledge_chunks (
  document_id uuid,
  batch       integer DEFAULT 64
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('idx', x."idx", 'content', x."content") order by x."idx"), '[]')
  from (
    select * from "better_supabase"."knowledge_chunks" y
    where y."document_id" = pending_knowledge_chunks.document_id and y."embedding" is null
    order by y."idx"
    limit least(greatest(pending_knowledge_chunks.batch, 1), 2048)
  ) x
$function$;

CREATE OR REPLACE FUNCTION better_supabase.pending_knowledge_documents (
  batch integer DEFAULT 10
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(x."id" order by x."updated_at"), '[]')
  from (
    select * from "better_supabase"."knowledge_documents" y where y."status" = 'pending'
    order by y."updated_at"
    limit least(greatest(pending_knowledge_documents.batch, 1), 1000)
  ) x
$function$;

CREATE OR REPLACE FUNCTION better_supabase.pending_memory_embeddings (
  batch integer DEFAULT 64
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'content', x."content")), '[]')
  from (
    select * from "better_supabase"."memories" y where y."embedding" is null and y."superseded_by" is null
    order by y."updated_at"
    limit least(greatest(pending_memory_embeddings.batch, 1), 2048)
  ) x
$function$;

CREATE OR REPLACE FUNCTION better_supabase.recall_ai_messages (
  tenant          uuid,
  query_embedding extensions.vector,
  k               integer           DEFAULT 5,
  exclude_chat    uuid              DEFAULT NULL::uuid,
  owner           uuid              DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_user uuid := case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then recall_ai_messages.owner else auth.uid() end;
  v_rows jsonb;
begin
  if v_user is null then
    return '[]';
  end if;
  perform set_config('hnsw.iterative_scan', 'relaxed_order', true);
  select coalesce(jsonb_agg(jsonb_build_object('chat_id', r.chat_id, 'message_id', r.message_id, 'similarity', 1 - r.distance) order by r.distance), '[]')
  into v_rows
  from (
    select x."chat_id" as chat_id, x."message_id" as message_id, x."embedding" operator(extensions.<=>) recall_ai_messages.query_embedding as distance
    from "better_supabase"."ai_message_embeddings" x
    where x."user_id" = v_user and x."organization_id" = recall_ai_messages.tenant
      and x."chat_id" is distinct from recall_ai_messages.exclude_chat
    order by x."embedding" operator(extensions.<=>) recall_ai_messages.query_embedding
    limit least(greatest(recall_ai_messages.k, 1), 50)
  ) r;
  return v_rows;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.reembed_knowledge (
  tenant uuid DEFAULT NULL::uuid,
  model  text DEFAULT NULL::text
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_ai_message_embedding (
  chat_id    uuid,
  message_id text,
  user_id    uuid,
  tenant     uuid,
  embedding  extensions.vector,
  model      text              DEFAULT NULL::text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  if exists (select 1 from "better_supabase"."ai_chats" x where x."id" = set_ai_message_embedding.chat_id and x."is_temporary") then
    return false;
  end if;
  insert into "better_supabase"."ai_message_embeddings" ("chat_id", "message_id", "user_id", "organization_id", "embedding", "embedding_model")
  values (set_ai_message_embedding.chat_id, set_ai_message_embedding.message_id, set_ai_message_embedding.user_id, set_ai_message_embedding.tenant, set_ai_message_embedding.embedding, set_ai_message_embedding.model)
  on conflict ("chat_id", "message_id") do update set "embedding" = excluded."embedding", "embedding_model" = excluded."embedding_model";
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_knowledge_embeddings (
  document_id uuid,
  embeddings  jsonb,
  model       text  DEFAULT NULL::text
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_memory_embedding (
  memory_id uuid,
  embedding extensions.vector,
  model     text              DEFAULT NULL::text
)
  RETURNS boolean
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  update "better_supabase"."memories" x set "embedding" = set_memory_embedding.embedding, "embedding_model" = set_memory_embedding.model
  where x."id" = set_memory_embedding.memory_id
  returning true
$function$;

CREATE OR REPLACE FUNCTION better_supabase.write_knowledge_chunks (
  document_id uuid,
  chunks      jsonb,
  model       text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

ALTER TABLE "better_supabase"."ai_files"
  ADD CONSTRAINT "ai_files_filename_check"
    CHECK ((((length(filename) >= 1) AND (length(filename) <= 255)) AND (filename !~ '[/\\]'::text) AND (filename <> ALL (ARRAY['.'::text, '..'::text]))));

ALTER TABLE "better_supabase"."ai_message_embeddings"
  ADD CONSTRAINT "ai_message_embeddings_chat_id_fkey" FOREIGN KEY (chat_id) REFERENCES better_supabase.ai_chats(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."ai_message_embeddings"
  ADD CONSTRAINT "ai_message_embeddings_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."knowledge_documents"
  ADD CONSTRAINT "knowledge_documents_file_id_fkey" FOREIGN KEY (file_id) REFERENCES better_supabase.ai_files(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."knowledge_documents"
  ADD CONSTRAINT "knowledge_documents_owner_id_fkey" FOREIGN KEY (owner_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."knowledge_chunks"
  ADD CONSTRAINT "knowledge_chunks_document_id_fkey" FOREIGN KEY (document_id) REFERENCES better_supabase.knowledge_documents(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."memories"
  ADD CONSTRAINT "memories_chat_id_fkey" FOREIGN KEY (chat_id) REFERENCES better_supabase.ai_chats(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."memories"
  ADD CONSTRAINT "memories_owner_id_fkey" FOREIGN KEY (owner_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."memories"
  ADD CONSTRAINT "memories_superseded_by_fkey" FOREIGN KEY (superseded_by) REFERENCES better_supabase.memories(id) ON DELETE SET NULL;

CREATE INDEX ai_message_embeddings_embedding_idx ON better_supabase.ai_message_embeddings USING hnsw (embedding extensions.vector_cosine_ops);

CREATE INDEX ai_message_embeddings_user_idx ON better_supabase.ai_message_embeddings USING btree (user_id, organization_id);

CREATE INDEX knowledge_chunks_embedding_idx ON better_supabase.knowledge_chunks USING hnsw (embedding extensions.vector_cosine_ops);

CREATE INDEX knowledge_chunks_pending_idx ON better_supabase.knowledge_chunks USING btree (document_id, idx)
  WHERE (embedding IS NULL);

CREATE INDEX knowledge_chunks_tsv_idx ON better_supabase.knowledge_chunks USING gin (tsv);

CREATE INDEX knowledge_documents_file_idx ON better_supabase.knowledge_documents USING btree (file_id)
  WHERE (file_id IS NOT NULL);

CREATE INDEX knowledge_documents_owner_idx ON better_supabase.knowledge_documents USING btree (owner_id)
  WHERE (owner_id IS NOT NULL);

CREATE INDEX knowledge_documents_pending_idx ON better_supabase.knowledge_documents USING btree (updated_at)
  WHERE (status = 'pending'::text);

CREATE INDEX knowledge_documents_tenant_idx ON better_supabase.knowledge_documents USING btree (organization_id, scope, scope_id);

CREATE INDEX memories_chat_idx ON better_supabase.memories USING btree (chat_id)
  WHERE (chat_id IS NOT NULL);

CREATE INDEX memories_embedding_idx ON better_supabase.memories USING hnsw (embedding extensions.vector_cosine_ops);

CREATE INDEX memories_owner_idx ON better_supabase.memories USING btree (owner_id, organization_id)
  WHERE (owner_id IS NOT NULL);

CREATE UNIQUE INDEX memories_path_idx ON better_supabase.memories USING btree (organization_id, owner_id, scope, agent_id, chat_id, path) NULLS NOT DISTINCT
  WHERE ((path IS NOT NULL) AND (superseded_by IS NULL));

CREATE INDEX memories_superseded_idx ON better_supabase.memories USING btree (superseded_by)
  WHERE (superseded_by IS NOT NULL);

CREATE INDEX memories_tenant_idx ON better_supabase.memories USING btree (organization_id, scope);

CREATE INDEX memories_tsv_idx ON better_supabase.memories USING gin (tsv);

CREATE POLICY "ai_message_embeddings_read" ON "better_supabase"."ai_message_embeddings"
  FOR SELECT
  TO "authenticated"
  USING ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "knowledge_chunks_read" ON "better_supabase"."knowledge_chunks"
  FOR SELECT
  TO "authenticated"
  USING ((EXISTS ( SELECT 1
   FROM better_supabase.knowledge_documents doc
  WHERE (doc.id = knowledge_chunks.document_id))));

CREATE POLICY "knowledge_documents_read" ON "better_supabase"."knowledge_documents"
  FOR SELECT
  TO "authenticated"
  USING
    (((owner_id = ( SELECT auth.uid() AS uid)) OR ((scope = ANY (ARRAY['organization'::text, 'agent'::text])) AND (organization_id IN ( SELECT
    better_supabase.tenant_ids_with('ai_chat.read'::text) AS tenant_ids_with))) OR
    (organization_id IN ( SELECT better_supabase.tenant_ids_with('ai_chat.admin'::text) AS tenant_ids_with)) OR ((scope = 'chat'::text) AND ((scope_id IS
    NOT NULL) AND better_supabase.ai_chat_can_read(scope_id)))));

CREATE POLICY "memories_read" ON "better_supabase"."memories"
  FOR SELECT
  TO "authenticated"
  USING
    (((owner_id = ( SELECT auth.uid() AS uid)) OR ((scope = 'organization'::text) AND (organization_id IN ( SELECT better_supabase.tenant_ids_with('ai_chat.read'::text) AS
    tenant_ids_with)))));

REVOKE ALL ON FUNCTION "api"."create_knowledge_document"(uuid, text, text, uuid, uuid, text, jsonb, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."create_knowledge_document"(uuid, text, text, uuid, uuid, text, jsonb, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."delete_knowledge_document"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."delete_knowledge_document"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."fail_knowledge_document"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."fail_knowledge_document"(uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."get_knowledge_document"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_knowledge_document"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."knowledge_search"(uuid, extensions.vector, text, jsonb, integer, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."knowledge_search"(uuid, extensions.vector, text, jsonb, integer, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_knowledge_documents"(uuid, text, uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_knowledge_documents"(uuid, text, uuid, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."memory_create"(uuid, text, text, jsonb, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."memory_create"(uuid, text, text, jsonb, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."memory_delete"(uuid, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."memory_delete"(uuid, text, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."memory_forget"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."memory_forget"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."memory_insert"(uuid, text, integer, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."memory_insert"(uuid, text, integer, text, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."memory_list"(uuid, jsonb, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."memory_list"(uuid, jsonb, text, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."memory_rename"(uuid, text, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."memory_rename"(uuid, text, text, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."memory_save"(uuid, text, jsonb, extensions.vector, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."memory_save"(uuid, text, jsonb, extensions.vector, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."memory_search"(uuid, extensions.vector, text, jsonb, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."memory_search"(uuid, extensions.vector, text, jsonb, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."memory_str_replace"(uuid, text, text, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."memory_str_replace"(uuid, text, text, text, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."memory_view"(uuid, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."memory_view"(uuid, text, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."pending_knowledge_chunks"(uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."pending_knowledge_chunks"(uuid, integer) TO "service_role";

REVOKE ALL ON FUNCTION "api"."pending_knowledge_documents"(integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."pending_knowledge_documents"(integer) TO "service_role";

REVOKE ALL ON FUNCTION "api"."pending_memory_embeddings"(integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."pending_memory_embeddings"(integer) TO "service_role";

REVOKE ALL ON FUNCTION "api"."recall_ai_messages"(uuid, extensions.vector, integer, uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."recall_ai_messages"(uuid, extensions.vector, integer, uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."reembed_knowledge"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."reembed_knowledge"(uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."set_ai_message_embedding"(uuid, text, uuid, uuid, extensions.vector, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_ai_message_embedding"(uuid, text, uuid, uuid, extensions.vector, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."set_knowledge_embeddings"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_knowledge_embeddings"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."set_memory_embedding"(uuid, extensions.vector, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_memory_embedding"(uuid, extensions.vector, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."write_knowledge_chunks"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."write_knowledge_chunks"(uuid, jsonb, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."create_knowledge_document"(uuid, text, text, uuid, uuid, text, jsonb, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."create_knowledge_document"(uuid, text, text, uuid, uuid, text, jsonb, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."delete_knowledge_document"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_knowledge_document"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."fail_knowledge_document"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."fail_knowledge_document"(uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_knowledge_document"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_knowledge_document"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."knowledge_search"(uuid, extensions.vector, text, jsonb, integer, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."knowledge_search"(uuid, extensions.vector, text, jsonb, integer, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_knowledge_documents"(uuid, text, uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_knowledge_documents"(uuid, text, uuid, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."memory_create"(uuid, text, text, jsonb, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."memory_create"(uuid, text, text, jsonb, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."memory_delete"(uuid, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."memory_delete"(uuid, text, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."memory_forget"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."memory_forget"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."memory_insert"(uuid, text, integer, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."memory_insert"(uuid, text, integer, text, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."memory_list"(uuid, jsonb, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."memory_list"(uuid, jsonb, text, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."memory_rename"(uuid, text, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."memory_rename"(uuid, text, text, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."memory_save"(uuid, text, jsonb, extensions.vector, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."memory_save"(uuid, text, jsonb, extensions.vector, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."memory_search"(uuid, extensions.vector, text, jsonb, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."memory_search"(uuid, extensions.vector, text, jsonb, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."memory_str_replace"(uuid, text, text, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."memory_str_replace"(uuid, text, text, text, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."memory_view"(uuid, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."memory_view"(uuid, text, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."pending_knowledge_chunks"(uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."pending_knowledge_chunks"(uuid, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."pending_knowledge_documents"(integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."pending_knowledge_documents"(integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."pending_memory_embeddings"(integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."pending_memory_embeddings"(integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."recall_ai_messages"(uuid, extensions.vector, integer, uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."recall_ai_messages"(uuid, extensions.vector, integer, uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."reembed_knowledge"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."reembed_knowledge"(uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_ai_message_embedding"(uuid, text, uuid, uuid, extensions.vector, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_ai_message_embedding"(uuid, text, uuid, uuid, extensions.vector, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_knowledge_embeddings"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_knowledge_embeddings"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_memory_embedding"(uuid, extensions.vector, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_memory_embedding"(uuid, extensions.vector, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."write_knowledge_chunks"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."write_knowledge_chunks"(uuid, jsonb, text) TO "authenticated", "service_role";

GRANT SELECT ON TABLE "better_supabase"."ai_message_embeddings" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."ai_message_embeddings" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."knowledge_chunks" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."knowledge_chunks" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."knowledge_documents" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."knowledge_documents" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."memories" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."memories" TO "service_role";
