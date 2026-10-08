import type { ModuleContext, ModuleNames } from "../context.ts";
import type { ModuleDefinition, ModuleLayout } from "../registry.ts";

import { sqlString } from "../../core/template.ts";
import { schemaPreamble, SERVICE_CALLER, tenantIn } from "../shared.ts";
import { vectorSchemaOf } from "../vector-schema.ts";
import { MODULE_PERMISSIONS } from "./access-model.ts";
import { canIn, raise, serviceGrant, userGrant } from "./ai-chat-sql.ts";

const DOCUMENTS = {
  id: "id",
  tenant: "organization_id",
  owner: "owner_id",
  scope: "scope",
  scopeId: "scope_id",
  file: "file_id",
  title: "title",
  source: "source",
  metadata: "metadata",
  status: "status",
  error: "error",
  chunkCount: "chunk_count",
  model: "embedding_model",
  createdAt: "created_at",
  updatedAt: "updated_at",
} as const;

const CHUNKS = {
  document: "document_id",
  index: "idx",
  content: "content",
  tokens: "token_count",
  embedding: "embedding",
  hash: "embedding_hash",
  metadata: "metadata",
  tsv: "tsv",
} as const;

const NAMES: ModuleNames = {
  options: ["dimensions", "type", "textSearch", "embedQueue"],
  tables: {
    documents: {
      name: "knowledge_documents",
      columns: DOCUMENTS,
      lifecycle: { user: "owner", tenant: "tenant" },
    },
    chunks: { name: "knowledge_chunks", columns: CHUNKS },
  },
};

/** The most dimensions an hnsw index takes for each type. */
const MAX_DIMENSIONS = { vector: 2000, halfvec: 4000 } as const;
const REGCONFIG = /^[a-z_]+$/;
const QUEUE = /^[a-z_][a-z0-9_]{0,46}$/;

export interface EmbeddingColumn {
  /** The quoted vector type with its dimensions, e.g. `extensions.vector(1536)`. */
  readonly column: string;
  /** The quoted type without dimensions, for function arguments. */
  readonly type: string;
  /** The hnsw operator class for cosine distance. */
  readonly opclass: string;
  /** The cosine distance operator. */
  readonly distance: string;
  readonly dimensions: number;
}

/** The embedding column a module's `dimensions` and `type` options describe. */
export function embeddingColumn(
  ctx: ModuleContext,
  layout: ModuleLayout,
): EmbeddingColumn {
  const vector = vectorSchemaOf(layout);
  const type = ctx.text("type", "vector");
  if (type !== "vector" && type !== "halfvec") {
    throw new TypeError(
      `sql.modules.${ctx.module}.options.type must be "vector" or "halfvec"`,
    );
  }
  const dimensions = ctx.number("dimensions", 1536);
  if (
    !Number.isInteger(dimensions) ||
    dimensions < 1 ||
    dimensions > MAX_DIMENSIONS[type]
  ) {
    throw new TypeError(
      `sql.modules.${ctx.module}.options.dimensions must be a whole number from 1 to ${String(MAX_DIMENSIONS[type])} for ${type}`,
    );
  }
  return {
    column: `${vector}.${type}(${String(dimensions)})`,
    type: `${vector}.${type}`,
    opclass: `${vector}.${type}_cosine_ops`,
    distance: `operator(${vector}.<=>)`,
    dimensions,
  };
}

/** `sql.modules.<name>.options.textSearch`: the text search configuration. */
export function textSearchConfig(ctx: ModuleContext): string {
  const config = ctx.text("textSearch", "simple");
  if (!REGCONFIG.test(config)) {
    throw new TypeError(
      `sql.modules.${ctx.module}.options.textSearch must be a text search configuration name, such as "english"`,
    );
  }
  return config;
}

type Columns<T> = { readonly [K in keyof T]: string };

function columnsOf<T extends Readonly<Record<string, string>>>(
  ctx: ModuleContext,
  table: string,
  spec: T,
): Columns<T> {
  // SAFETY: the keys are spec's own keys, each mapped to its quoted name.
  return Object.fromEntries(
    Object.keys(spec).map((key) => [key, ctx.col(table, key)]),
  ) as Columns<T>;
}

function build(ctx: ModuleContext, layout: ModuleLayout): string {
  const id = ctx.idType;
  const fn = (name: string): string => ctx.fn(name);
  const d = columnsOf(ctx, "documents", DOCUMENTS);
  const c = columnsOf(ctx, "chunks", CHUNKS);
  const documents = ctx.table("documents");
  const chunks = ctx.table("chunks");
  const permissions = MODULE_PERMISSIONS.knowledge;
  const read = ctx.permission("read", permissions.read);
  const write = ctx.permission("write", permissions.write);
  const manage = ctx.permission("manage", permissions.manage);
  const embedding = embeddingColumn(ctx, layout);
  const config = sqlString(textSearchConfig(ctx));
  const queue = ctx.text("embedQueue", "knowledge_embed");
  if (!QUEUE.test(queue)) {
    throw new TypeError(
      "sql.modules.knowledge.options.embedQueue must be a lowercase queue name of at most 47 characters",
    );
  }
  const chat = ctx.installed("ai-chat") ? ctx.of("ai-chat") : undefined;
  const chatReadable = chat
    ? (column: string): string =>
        `(${column} is not null and ${chat.fn("ai_chat_can_read")}(${column}))`
    : (): string => "false";
  const files = ctx.installed("ai-files") ? ctx.of("ai-files") : undefined;
  const fileReference = files
    ? ` references ${files.table("files")} (${files.col("files", "id")}) on delete cascade`
    : "";
  const fileCheck = files
    ? `
  if file_id is not null and not exists (
    select 1 from ${files.table("files")} x
    where x.${files.col("files", "id")} = create_knowledge_document.file_id
      and x.${files.col("files", "tenant")} = create_knowledge_document.tenant
      and x.${files.col("files", "status")} = 'ready'
      and (${SERVICE_CALLER} or x.${files.col("files", "owner")} = auth.uid() or ${canIn("create_knowledge_document.tenant", manage)})
  ) then
    ${raise("file % not found", "P0002", "AI_FILE_NOT_FOUND", "file_id")}
  end if;`
    : "";
  const enqueue = (document: string): string =>
    ctx.installed("jobs")
      ? `
  perform ${ctx.of("jobs").fn("enqueue_job")}(queue => ${sqlString(queue)}, payload => jsonb_build_object('document_id', ${document}), dedupe_key => 'knowledge:' || ${document}::text, dedupe_running => false);`
      : "";
  const documentJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${d.id}, 'organization_id', ${row}.${d.tenant}, 'owner_id', ${row}.${d.owner}, 'scope', ${row}.${d.scope}, 'scope_id', ${row}.${d.scopeId}, 'file_id', ${row}.${d.file}, 'title', ${row}.${d.title}, 'source', ${row}.${d.source}, 'metadata', ${row}.${d.metadata}, 'status', ${row}.${d.status}, 'error', ${row}.${d.error}, 'chunk_count', ${row}.${d.chunkCount}, 'embedding_model', ${row}.${d.model}, 'created_at', ${row}.${d.createdAt}, 'updated_at', ${row}.${d.updatedAt})`;
  // Organization and agent knowledge is shared with readers of the
  // organization, chat knowledge with readers of the chat, user and project
  // knowledge stays with its owner. Admins see everything in their tenant.
  const readable = `(${d.owner} = (select auth.uid()) or (${d.scope} in ('organization', 'agent') and ${tenantIn(d.tenant, read)}) or ${tenantIn(d.tenant, manage)} or (${d.scope} = 'chat' and ${chatReadable(d.scopeId)}))`;
  const ownDocument = (row: string): string =>
    `(${SERVICE_CALLER} or ${row}.${d.owner} = auth.uid() or ${canIn(`${row}.${d.tenant}`, manage)})`;
  const notFound = raise(
    "document % not found",
    "P0002",
    "KNOWLEDGE_NOT_FOUND",
    "document_id",
  );

  return `${schemaPreamble(ctx)}
-- Documents for retrieval: uploaded files, pasted text and synced rows, split
-- into chunks with an embedding and a tsvector each. The app chunks and
-- embeds; the database stores, scopes and searches.
create table if not exists ${documents} (
  ${d.id} uuid primary key default gen_random_uuid(),
  ${d.tenant} ${id} not null,
  ${d.owner} uuid references auth.users (id) on delete cascade,
  ${d.scope} text not null default 'user' check (${d.scope} in ('organization', 'agent', 'project', 'chat', 'user')),
  ${d.scopeId} uuid,
  ${d.file} uuid${fileReference},
  ${d.title} text not null check (length(${d.title}) between 1 and 500),
  ${d.source} text,
  ${d.metadata} jsonb not null default '{}' check (jsonb_typeof(${d.metadata}) = 'object'),
  ${d.status} text not null default 'pending' check (${d.status} in ('pending', 'ready', 'failed')),
  ${d.error} text,
  ${d.chunkCount} integer not null default 0,
  ${d.model} text,
  ${d.createdAt} timestamptz not null default now(),
  ${d.updatedAt} timestamptz not null default now(),
  check ((${d.scope} = 'organization') = (${d.scopeId} is null))
);
create index if not exists knowledge_documents_tenant_idx on ${documents} (${d.tenant}, ${d.scope}, ${d.scopeId});
create index if not exists knowledge_documents_owner_idx on ${documents} (${d.owner}) where ${d.owner} is not null;
create index if not exists knowledge_documents_file_idx on ${documents} (${d.file}) where ${d.file} is not null;
create index if not exists knowledge_documents_pending_idx on ${documents} (${d.updatedAt}) where ${d.status} = 'pending';
alter table ${documents} enable row level security;
revoke all on ${documents} from anon, authenticated;
grant select on ${documents} to authenticated;
grant all on ${documents} to service_role;
drop policy if exists knowledge_documents_read on ${documents};
create policy knowledge_documents_read on ${documents} for select to authenticated
  using (${readable});

-- A chunk is visible when its document is, so search inherits the scopes.
create table if not exists ${chunks} (
  ${c.document} uuid not null references ${documents} (${d.id}) on delete cascade,
  ${c.index} integer not null check (${c.index} >= 0),
  ${c.content} text not null check (length(${c.content}) > 0),
  ${c.tokens} integer,
  ${c.embedding} ${embedding.column},
  ${c.hash} text,
  ${c.metadata} jsonb not null default '{}',
  ${c.tsv} tsvector generated always as (to_tsvector(${config}::regconfig, ${c.content})) stored,
  primary key (${c.document}, ${c.index})
);
create index if not exists knowledge_chunks_embedding_idx on ${chunks} using hnsw (${c.embedding} ${embedding.opclass});
create index if not exists knowledge_chunks_tsv_idx on ${chunks} using gin (${c.tsv});
create index if not exists knowledge_chunks_pending_idx on ${chunks} (${c.document}, ${c.index}) where ${c.embedding} is null;
alter table ${chunks} enable row level security;
revoke all on ${chunks} from anon, authenticated;
grant select on ${chunks} to authenticated;
grant all on ${chunks} to service_role;
drop policy if exists knowledge_chunks_read on ${chunks};
create policy knowledge_chunks_read on ${chunks} for select to authenticated
  using (exists (select 1 from ${documents} doc where doc.${d.id} = ${c.document}));

-- Creates a document for the caller (or for owner, as the service role).
-- Organization and agent knowledge needs the manage permission.
create or replace function ${fn("create_knowledge_document")}(
  tenant ${id},
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
  v_owner uuid := case when ${SERVICE_CALLER} then create_knowledge_document.owner else auth.uid() end;
  v_scope_id uuid := create_knowledge_document.scope_id;
  v_row ${documents}%rowtype;
begin
  if not ${SERVICE_CALLER} and (auth.uid() is null or not ${canIn("create_knowledge_document.tenant", write)}) then
    ${raise("you may not add knowledge here", "42501", "KNOWLEDGE_FORBIDDEN")}
  end if;
  if create_knowledge_document.scope in ('organization', 'agent') and not (${SERVICE_CALLER} or ${canIn("create_knowledge_document.tenant", manage)}) then
    ${raise("only admins add % knowledge", "42501", "KNOWLEDGE_FORBIDDEN", "create_knowledge_document.scope")}
  end if;
  if create_knowledge_document.scope = 'user' then
    v_scope_id := coalesce(v_scope_id, v_owner);
    if v_scope_id is null or v_scope_id is distinct from v_owner then
      ${raise("user knowledge belongs to its owner", "22023", "KNOWLEDGE_SCOPE")}
    end if;
  end if;
  if create_knowledge_document.scope is null
    or create_knowledge_document.scope not in ('organization', 'agent', 'project', 'chat', 'user')
    or (create_knowledge_document.scope = 'organization') <> (v_scope_id is null) then
    ${raise("% knowledge needs %", "22023", "KNOWLEDGE_SCOPE", "create_knowledge_document.scope", "case when create_knowledge_document.scope = 'organization' then 'no scope_id' else 'a scope_id' end")}
  end if;
  if create_knowledge_document.scope = 'chat' and not (${SERVICE_CALLER} or ${chatReadable("v_scope_id")}) then
    ${raise("chat % not found", "P0002", "AI_CHAT_NOT_FOUND", "v_scope_id")}
  end if;${fileCheck}
  insert into ${documents} (${d.tenant}, ${d.owner}, ${d.scope}, ${d.scopeId}, ${d.file}, ${d.title}, ${d.source}, ${d.metadata})
  values (create_knowledge_document.tenant, v_owner, create_knowledge_document.scope, v_scope_id, create_knowledge_document.file_id, create_knowledge_document.title, create_knowledge_document.source, coalesce(create_knowledge_document.metadata, '{}'))
  returning * into v_row;
  return ${documentJson("v_row")};
end;
$$;
${userGrant(`${fn("create_knowledge_document")}(${id}, text, text, uuid, uuid, text, jsonb, uuid)`)}

-- Replaces a document's chunks. A chunk whose text is unchanged keeps its
-- embedding unless the model changed; the rest wait for the embed job.
-- chunks is a list of {content, tokens, metadata}, or {"items": list}.
create or replace function ${fn("write_knowledge_chunks")}(document_id uuid, chunks jsonb, model text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${documents}%rowtype;
  v_count integer;
  v_keep boolean;
  v_items jsonb := case when jsonb_typeof(write_knowledge_chunks.chunks) = 'object' then write_knowledge_chunks.chunks -> 'items' else write_knowledge_chunks.chunks end;
begin
  select * into v_row from ${documents} x where x.${d.id} = write_knowledge_chunks.document_id for update;
  if not found or not ${ownDocument("v_row")} then
    ${notFound}
  end if;
  if coalesce(jsonb_typeof(v_items), '') <> 'array' or jsonb_array_length(v_items) > 10000 then
    ${raise("chunks must be an array of at most 10000 chunks", "22023", "KNOWLEDGE_CHUNKS")}
  end if;
  v_count := jsonb_array_length(v_items);
  v_keep := write_knowledge_chunks.model is not distinct from v_row.${d.model} or write_knowledge_chunks.model is null;
  insert into ${chunks} as t (${c.document}, ${c.index}, ${c.content}, ${c.tokens}, ${c.metadata})
  select v_row.${d.id}, (e.ord - 1)::integer, e.value ->> 'content', (e.value ->> 'tokens')::integer, coalesce(e.value -> 'metadata', '{}')
  from jsonb_array_elements(v_items) with ordinality e(value, ord)
  on conflict (${c.document}, ${c.index}) do update set
    ${c.content} = excluded.${c.content},
    ${c.tokens} = excluded.${c.tokens},
    ${c.metadata} = excluded.${c.metadata},
    ${c.embedding} = case when v_keep and t.${c.hash} = md5(excluded.${c.content}) then t.${c.embedding} end,
    ${c.hash} = case when v_keep and t.${c.hash} = md5(excluded.${c.content}) then t.${c.hash} end;
  delete from ${chunks} x where x.${c.document} = v_row.${d.id} and x.${c.index} >= v_count;
  update ${documents} x set
    ${d.status} = case when exists (select 1 from ${chunks} p where p.${c.document} = x.${d.id} and p.${c.embedding} is null) then 'pending' else 'ready' end,
    ${d.error} = null,
    ${d.chunkCount} = v_count,
    ${d.model} = coalesce(write_knowledge_chunks.model, x.${d.model}),
    ${d.updatedAt} = now()
  where x.${d.id} = v_row.${d.id}
  returning * into v_row;
  if v_row.${d.status} = 'pending' then${enqueue(`v_row.${d.id}`) || "\n    null;"}
  end if;
  return ${documentJson("v_row")};
end;
$$;
${userGrant(`${fn("write_knowledge_chunks")}(uuid, jsonb, text)`)}

create or replace function ${fn("get_knowledge_document")}(document_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select ${documentJson("x")} from ${documents} x where x.${d.id} = get_knowledge_document.document_id
$$;
${userGrant(`${fn("get_knowledge_document")}(uuid)`)}

-- The documents the caller can read in a tenant, newest first.
create or replace function ${fn("list_knowledge_documents")}(
  tenant ${id},
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
  select coalesce(jsonb_agg(${documentJson("x")} order by x.${d.createdAt} desc), '[]')
  from (
    select * from ${documents} y
    where y.${d.tenant} = list_knowledge_documents.tenant
      and (list_knowledge_documents.scope is null or y.${d.scope} = list_knowledge_documents.scope)
      and (list_knowledge_documents.scope_id is null or y.${d.scopeId} = list_knowledge_documents.scope_id)
    order by y.${d.createdAt} desc
    limit least(greatest(list_knowledge_documents.max_rows, 1), 1000)
  ) x
$$;
${userGrant(`${fn("list_knowledge_documents")}(${id}, text, uuid, integer)`)}

create or replace function ${fn("delete_knowledge_document")}(document_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${documents}%rowtype;
begin
  select * into v_row from ${documents} x where x.${d.id} = delete_knowledge_document.document_id;
  if not found or not ${ownDocument("v_row")} then
    return false;
  end if;
  delete from ${documents} x where x.${d.id} = v_row.${d.id};
  return true;
end;
$$;
${userGrant(`${fn("delete_knowledge_document")}(uuid)`)}

-- Hybrid search over the chunks the caller can read: the vector and the
-- full-text rankings fused with reciprocal rank fusion (k = 60). Iterative
-- index scans keep looking until enough visible chunks turn up. scopes is a
-- list of {"scope", "id"} objects, or {"items": list}; null searches every
-- scope. Returns a JSON array of {document_id, idx, content, metadata,
-- title, score}.
create or replace function ${fn("knowledge_search")}(
  tenant ${id},
  query_embedding ${embedding.type} default null,
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
    select x.${d.id} as id, x.${d.title} as title from ${documents} x
    where x.${d.tenant} = knowledge_search.tenant
      and (v_scopes is null or exists (
        select 1 from jsonb_array_elements(v_scopes) s
        where s.value ->> 'scope' = x.${d.scope}
          and (s.value ->> 'id' is null or (s.value ->> 'id')::uuid = x.${d.scopeId})
      ))
      and (knowledge_search.filter is null or x.${d.metadata} @> knowledge_search.filter)
  ),
  vector_hits as materialized (
    select t.${c.document} as document_id, t.${c.index} as idx, t.${c.embedding} ${embedding.distance} knowledge_search.query_embedding as distance
    from ${chunks} t
    where knowledge_search.query_embedding is not null and t.${c.embedding} is not null
      and t.${c.document} in (select docs.id from docs)
    order by t.${c.embedding} ${embedding.distance} knowledge_search.query_embedding
    limit v_candidates
  ),
  vector_ranked as (
    select h.document_id, h.idx, row_number() over (order by h.distance) as rank from vector_hits h
  ),
  text_hits as materialized (
    select t.${c.document} as document_id, t.${c.index} as idx, ts_rank_cd(t.${c.tsv}, q) as text_score
    from ${chunks} t, websearch_to_tsquery(${config}::regconfig, knowledge_search.query_text) q
    where knowledge_search.query_text is not null and t.${c.tsv} @@ q
      and t.${c.document} in (select docs.id from docs)
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
    select f.document_id, f.idx, t.${c.content} as content, t.${c.metadata} as metadata, docs.title, f.score
    from fused f
    join ${chunks} t on t.${c.document} = f.document_id and t.${c.index} = f.idx
    join docs on docs.id = f.document_id
    order by f.score desc, f.document_id, f.idx
    limit least(greatest(knowledge_search.k, 1), 100)
  ) r;
  perform set_config('hnsw.iterative_scan', coalesce(previous_scan, 'off'), true);
  return v_rows;
end;
$$;
${userGrant(`${fn("knowledge_search")}(${id}, ${embedding.type}, text, jsonb, integer, jsonb)`)}

-- The chunks of a document still waiting for an embedding, for the worker.
create or replace function ${fn("pending_knowledge_chunks")}(document_id uuid, batch integer default 64)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('idx', x.${c.index}, 'content', x.${c.content}) order by x.${c.index}), '[]')
  from (
    select * from ${chunks} y
    where y.${c.document} = pending_knowledge_chunks.document_id and y.${c.embedding} is null
    order by y.${c.index}
    limit least(greatest(pending_knowledge_chunks.batch, 1), 2048)
  ) x
$$;
${serviceGrant(`${fn("pending_knowledge_chunks")}(uuid, integer)`)}

-- Stores embeddings ([{"idx", "embedding"}], or {"items": list}) and marks the document ready
-- once no chunk is missing one. Returns how many chunks still wait.
create or replace function ${fn("set_knowledge_embeddings")}(document_id uuid, embeddings jsonb, model text default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_remaining integer;
  v_items jsonb := case when jsonb_typeof(set_knowledge_embeddings.embeddings) = 'object' then set_knowledge_embeddings.embeddings -> 'items' else set_knowledge_embeddings.embeddings end;
begin
  update ${chunks} t set
    ${c.embedding} = (e.value ->> 'embedding')::${embedding.column},
    ${c.hash} = md5(t.${c.content})
  from jsonb_array_elements(coalesce(v_items, '[]')) e
  where t.${c.document} = set_knowledge_embeddings.document_id and t.${c.index} = (e.value ->> 'idx')::integer;
  select count(*)::integer into v_remaining from ${chunks} t
  where t.${c.document} = set_knowledge_embeddings.document_id and t.${c.embedding} is null;
  update ${documents} x set
    ${d.status} = case when v_remaining = 0 then 'ready' else x.${d.status} end,
    ${d.model} = coalesce(set_knowledge_embeddings.model, x.${d.model}),
    ${d.updatedAt} = now()
  where x.${d.id} = set_knowledge_embeddings.document_id;
  return v_remaining;
end;
$$;
${serviceGrant(`${fn("set_knowledge_embeddings")}(uuid, jsonb, text)`)}

create or replace function ${fn("fail_knowledge_document")}(document_id uuid, error text)
returns boolean
language sql
security definer
set search_path = ''
as $$
  update ${documents} x set ${d.status} = 'failed', ${d.error} = left(fail_knowledge_document.error, 2000), ${d.updatedAt} = now()
  where x.${d.id} = fail_knowledge_document.document_id
  returning true
$$;
${serviceGrant(`${fn("fail_knowledge_document")}(uuid, text)`)}

-- Documents waiting for embeddings, oldest first, for a drain without jobs.
create or replace function ${fn("pending_knowledge_documents")}(batch integer default 10)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(x.${d.id} order by x.${d.updatedAt}), '[]')
  from (
    select * from ${documents} y where y.${d.status} = 'pending'
    order by y.${d.updatedAt}
    limit least(greatest(pending_knowledge_documents.batch, 1), 1000)
  ) x
$$;
${serviceGrant(`${fn("pending_knowledge_documents")}(integer)`)}

-- Clears the embeddings of a tenant's documents (all tenants when null)
-- that another model embedded, so the worker embeds them again.
create or replace function ${fn("reembed_knowledge")}(tenant ${id} default null, model text default null)
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
    update ${documents} x set ${d.status} = 'pending', ${d.updatedAt} = now()
    where (reembed_knowledge.tenant is null or x.${d.tenant} = reembed_knowledge.tenant)
      and (reembed_knowledge.model is null or x.${d.model} is distinct from reembed_knowledge.model)
      and x.${d.chunkCount} > 0
    returning x.${d.id}
  loop
    update ${chunks} t set ${c.embedding} = null, ${c.hash} = null where t.${c.document} = v_id;${enqueue("v_id")}
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
${serviceGrant(`${fn("reembed_knowledge")}(${id}, text)`)}`;
}

export const KNOWLEDGE: ModuleDefinition = {
  name: "knowledge",
  title: "Knowledge",
  description:
    "Documents and chunks for retrieval with an embedding and a tsvector each, scoped to an organization, agent, project, chat or user; hybrid search with reciprocal rank fusion, chunks that keep their embedding when unchanged, and an embed job per document when jobs is installed.",
  requires: ["tenant", "access", "vector-search"],
  target: "schema",
  version: 1,
  names: NAMES,
  build,
};
