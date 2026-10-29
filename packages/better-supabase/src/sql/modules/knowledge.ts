import type { BlockSqlContext, BlockSqlNames } from "../context.ts";
import type { BlockSqlDefinition, BlockSqlLayout } from "../module-types.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  raise,
  schemaPreamble,
  SERVICE_CALLER,
  serviceGrant,
  userGrant,
  revokeTable,
} from "../shared.ts";
import { subjectReadable, subjectsOption } from "../subjects.ts";
import { vectorSchemaOf } from "../vector-schema.ts";
import {
  COLLECTION_GRANTS,
  COLLECTIONS,
  collectionPriority,
  collectionReadable,
  collectionSearched,
  knowledgeCollectionsSql,
  upgradeCollectionGrants,
} from "./knowledge-collections.ts";
import { asText } from "./over-app.ts";
import { moduleOperations } from "./permissions-model.ts";

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
  collection: "collection_id",
  subjectType: "subject_type",
  subjectId: "subject_id",
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

const NAMES: BlockSqlNames = {
  entities: {
    document: {
      table: "documents",
      singular: "knowledge_document",
      primary: true,
    },
  },
  options: ["dimensions", "type", "textSearch", "embedQueue", "ingestQueue"],
  tables: {
    documents: {
      name: "knowledge_documents",
      columns: DOCUMENTS,
      optional: [
        "file",
        "source",
        "metadata",
        "error",
        "chunkCount",
        "model",
        "collection",
        "subjectType",
        "subjectId",
        "createdAt",
      ],
      typed: ["scope", "status"],
      app: {},
      lifecycle: { user: "owner", tenant: "tenant" },
    },
    collections: {
      name: "knowledge_collections",
      columns: COLLECTIONS,
      app: {},
      lifecycle: { tenant: "tenant" },
      typed: ["visibility"],
    },
    collectionGrants: {
      name: "knowledge_collection_grants",
      columns: COLLECTION_GRANTS,
      app: {},
      lifecycle: { user: "user", tenant: "tenant" },
    },
    chunks: {
      name: "knowledge_chunks",
      columns: CHUNKS,
      optional: ["tokens", "hash", "metadata", "tsv"],
      app: {},
    },
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
  ctx: BlockSqlContext,
  layout: BlockSqlLayout,
): EmbeddingColumn {
  const vector = vectorSchemaOf(layout);
  const type = ctx.text("type", "vector");

  if (type !== "vector" && type !== "halfvec") {
    throw new TypeError(
      `blocks.${ctx.module}.options.type must be "vector" or "halfvec"`,
    );
  }

  const dimensions = ctx.number("dimensions", 1536);

  if (
    !Number.isInteger(dimensions) ||
    dimensions < 1 ||
    dimensions > MAX_DIMENSIONS[type]
  ) {
    throw new TypeError(
      `blocks.${ctx.module}.options.dimensions must be a whole number from 1 to ${String(MAX_DIMENSIONS[type])} for ${type}`,
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

/** `blocks.<name>.options.textSearch`: the text search configuration. */
export function textSearchConfig(ctx: BlockSqlContext): string {
  const config = ctx.text("textSearch", "simple");

  if (!REGCONFIG.test(config)) {
    throw new TypeError(
      `blocks.${ctx.module}.options.textSearch must be a text search configuration name, such as "english"`,
    );
  }

  return config;
}

type Columns<T> = { readonly [K in keyof T]: string };

/**
 * The quoted columns of `table`. A column the app's table lacks is empty, so
 * every use of an optional column checks `ctx.has` first.
 */
function presentColumns<T extends Readonly<Record<string, string>>>(
  ctx: BlockSqlContext,
  table: string,
  spec: T,
): Columns<T> {
  // SAFETY: the keys are spec's own keys, each mapped to its quoted name.
  return Object.fromEntries(
    Object.keys(spec).map((key) => [
      key,
      ctx.has(table, key) ? ctx.col(table, key) : "",
    ]),
  ) as Columns<T>;
}

function build(ctx: BlockSqlContext, layout: BlockSqlLayout): string {
  const id = ctx.idType;
  const fn = (name: string): string => ctx.fn(name);
  const d = presentColumns(ctx, "documents", DOCUMENTS);
  const c = presentColumns(ctx, "chunks", CHUNKS);

  const doc = (column: keyof typeof DOCUMENTS): boolean =>
    ctx.has("documents", column);

  const chunk = (column: keyof typeof CHUNKS): boolean =>
    ctx.has("chunks", column);

  const collected = doc("collection");

  const subjects = ctx.installed("subjects") ? ctx.of("subjects") : undefined;

  const subjectColumns = doc("subjectType") && doc("subjectId");

  const recordTypes = subjects
    ? subjectsOption(ctx, [], { registryOnly: true })
    : [];

  const subjectScoped = recordTypes.length > 0 && subjectColumns;

  const isSubject = (row: string): string =>
    `${asText(ctx, "documents", `${row}${d.scope}`)} = 'subject'`;

  const line = (present: boolean, definition: string): string =>
    present ? `\n  ${definition},` : "";

  const status = (value: string): string =>
    ctx.cast("documents", "status", value);

  const createdAt = (row: string): string =>
    `${row}.${doc("createdAt") ? d.createdAt : d.updatedAt}`;

  const documents = ctx.table("documents");
  const chunks = ctx.table("chunks");
  const permissions = moduleOperations("knowledge");
  const read = ctx.permission("read", permissions.read);
  const write = ctx.permission("write", permissions.write);
  const manage = ctx.permission("manage", permissions.manage);
  const embedding = embeddingColumn(ctx, layout);
  const config = sqlString(textSearchConfig(ctx));
  const queue = ctx.text("embedQueue", "knowledge_embed");

  if (!QUEUE.test(queue)) {
    throw new TypeError(
      "blocks.knowledge.options.embedQueue must be a lowercase queue name of at most 47 characters",
    );
  }

  const tsv = (row: string): string =>
    chunk("tsv")
      ? `${row}.${c.tsv}`
      : `to_tsvector(${config}::regconfig, ${row}.${c.content})`;

  const ingestQueue = ctx.text("ingestQueue", "knowledge_ingest");

  if (!QUEUE.test(ingestQueue)) {
    throw new TypeError(
      "blocks.knowledge.options.ingestQueue must be a lowercase queue name of at most 47 characters",
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
      and (${SERVICE_CALLER} or x.${files.col("files", "owner")} = auth.uid() or ${ctx.scope.can("create_knowledge_document.tenant", manage)})
  ) then
    ${raise("file % not found", "P0002", "AI_FILE_NOT_FOUND", "file_id")}
  end if;`
    : "";

  const enqueue = (document: string): string =>
    ctx.installed("queue")
      ? `
  ${ctx.enqueue(queue, `jsonb_build_object('document_id', ${document})`, `'knowledge:' || ${document}::text`)}`
      : "";

  const documentJson = (row: string): string => {
    const missing: Readonly<Record<string, string>> = {
      metadata: "'{}'::jsonb",
      chunkCount: `(select count(*)::integer from ${chunks} p where p.${c.document} = ${row}.${d.id})`,
      createdAt: `${row}.${d.updatedAt}`,
    };

    const pairs = Object.entries(DOCUMENTS).map(
      ([key, name]) =>
        `'${name}', ${ctx.has("documents", key) ? `${row}.${ctx.col("documents", key)}` : (missing[key] ?? "null")}`,
    );

    return `jsonb_build_object(${pairs.join(", ")})`;
  };

  const documentInsert = [
    [d.tenant, "create_knowledge_document.tenant"],
    [d.owner, "v_owner"],
    [
      d.scope,
      ctx.cast("documents", "scope", "create_knowledge_document.scope"),
    ],
    [d.scopeId, "v_scope_id"],
    ...(doc("file") ? [[d.file, "create_knowledge_document.file_id"]] : []),
    [d.title, "create_knowledge_document.title"],
    ...(collected
      ? [[d.collection, "create_knowledge_document.collection_id"]]
      : []),
    ...(doc("source") ? [[d.source, "create_knowledge_document.source"]] : []),
    ...(doc("metadata")
      ? [[d.metadata, "coalesce(create_knowledge_document.metadata, '{}')"]]
      : []),
    ...(subjectColumns
      ? [
          [d.subjectType, "create_knowledge_document.subject_type"],
          [d.subjectId, "create_knowledge_document.subject_id"],
        ]
      : []),
  ];

  const chunkInsert = [
    [c.document, `v_row.${d.id}`],
    [c.index, "(e.ord - 1)::integer"],
    [c.content, "e.value ->> 'content'"],
    ...(chunk("tokens") ? [[c.tokens, "(e.value ->> 'tokens')::integer"]] : []),
    ...(chunk("metadata")
      ? [[c.metadata, "coalesce(e.value -> 'metadata', '{}')"]]
      : []),
  ];

  // Without the hash column a chunk keeps its embedding while its text stays
  // the same, which the old row still holds during the conflict update.
  const unchanged = chunk("hash")
    ? `t.${c.hash} = md5(excluded.${c.content})`
    : `t.${c.content} = excluded.${c.content}`;

  const chunkUpdate = [
    `${c.content} = excluded.${c.content}`,
    ...(chunk("tokens") ? [`${c.tokens} = excluded.${c.tokens}`] : []),
    ...(chunk("metadata") ? [`${c.metadata} = excluded.${c.metadata}`] : []),
    `${c.embedding} = case when v_keep and ${unchanged} then t.${c.embedding} end`,
    ...(chunk("hash")
      ? [`${c.hash} = case when v_keep and ${unchanged} then t.${c.hash} end`]
      : []),
  ];

  const writeUpdate = [
    `${d.status} = ${status(`case when exists (select 1 from ${chunks} p where p.${c.document} = x.${d.id} and p.${c.embedding} is null) then 'pending' else 'ready' end`)}`,
    ...(doc("error") ? [`${d.error} = null`] : []),
    ...(doc("chunkCount") ? [`${d.chunkCount} = v_count`] : []),
    ...(doc("model")
      ? [`${d.model} = coalesce(write_knowledge_chunks.model, x.${d.model})`]
      : []),
    `${d.updatedAt} = now()`,
  ];

  const unique = (table: string, what: string, columns: string): string =>
    ctx.owns(table)
      ? ""
      : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName(table).name}_${what}_key`)} on ${ctx.table(table)} (${columns});`;

  // Organization and agent knowledge is shared with readers of the
  // organization, chat knowledge with readers of the chat, user and project
  // knowledge stays with its owner. Admins see everything in their tenant.
  // A system document (no tenant) is shared with everyone. A document in a
  // collection also needs the collection to be readable. Subject knowledge is
  // read only by those who can read its record, owners and admins included.
  const inCollection = collected
    ? ` and (${d.collection} is null or ${collectionReadable(ctx, d.collection)})`
    : "";

  const scoped = `${d.owner} = (select auth.uid()) or (${d.scope} in ('organization', 'agent') and ${ctx.scope.check(d.tenant, read)}) or ${ctx.scope.check(d.tenant, manage)} or (${d.scope} = 'chat' and ${chatReadable(d.scopeId)})`;

  const readable = `(${d.tenant} is null or ${
    subjectColumns
      ? `case when ${isSubject("")} then ${subjectScoped ? `${fn("knowledge_subject_readable")}(${d.subjectType}, ${d.subjectId})` : "false"} else (${scoped}) end`
      : scoped
  })${inCollection}`;

  const { name: documentsName } = ctx.tableName("documents");

  const constraint = (suffix: string): string =>
    sqlIdent(`${documentsName}_${suffix}`);

  // The record knowledge is about, with the checks that keep scope 'subject'
  // and the record columns together. An adopted table keeps its own checks.
  const subjectDdl = ctx.owns("documents")
    ? `
alter table ${documents} add column if not exists ${d.subjectType} text check (length(${d.subjectType}) between 1 and 100);
alter table ${documents} add column if not exists ${d.subjectId} text check (length(${d.subjectId}) between 1 and 200);
alter table ${documents} drop constraint if exists ${constraint(`${ctx.colName("documents", "scope")}_check`)};
alter table ${documents} add constraint ${constraint(`${ctx.colName("documents", "scope")}_check`)} check (${d.scope} in ('organization', 'agent', 'project', 'chat', 'user', 'subject'));
alter table ${documents} drop constraint if exists ${constraint("check")};
alter table ${documents} add constraint ${constraint("check")} check ((${d.scope} in ('organization', 'subject')) = (${d.scopeId} is null));
alter table ${documents} drop constraint if exists ${ctx.naming.rename("knowledge_documents_subject_check")};
alter table ${documents} add constraint ${ctx.naming.rename("knowledge_documents_subject_check")} check ((${d.scope} = 'subject') = (${d.subjectType} is not null and ${d.subjectId} is not null));
create index if not exists ${ctx.naming.rename("knowledge_documents_subject_idx")} on ${documents} (${d.subjectType}, ${d.subjectId}) where ${d.subjectType} is not null;`
    : "";

  // Runs as the caller, so can_subject sees the record through its policies.
  // plpgsql binds the subjects function at call time, so the policy can name
  // this function before the subjects module is installed.
  const subjectReadableFn =
    subjects && subjectScoped
      ? `
-- True when the caller can read the record subject knowledge is about.
create or replace function ${fn("knowledge_subject_readable")}(subject_type text, subject_id text)
returns boolean
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return coalesce(${subjects.fn("can_subject")}(knowledge_subject_readable.subject_type, knowledge_subject_readable.subject_id, 'read'), false);
end;
$$;
${userGrant(`${fn("knowledge_subject_readable")}(text, text)`)}
`
      : "";

  const ownDocument = (row: string): string =>
    `(${SERVICE_CALLER} or coalesce(${row}.${d.owner} = auth.uid(), false) or ${ctx.scope.can(`${row}.${d.tenant}`, manage)})`;

  const notFound = raise(
    "document % not found",
    "P0002",
    "KNOWLEDGE_NOT_FOUND",
    "document_id",
  );

  return `${schemaPreamble(ctx)}
${knowledgeCollectionsSql(ctx)}
-- Documents for retrieval: uploaded files, pasted text and synced rows, split
-- into chunks with an embedding and a tsvector each. The app chunks and
-- embeds; the database stores, scopes and searches.
create table if not exists ${documents} (
  ${d.id} uuid primary key default gen_random_uuid(),
  ${d.tenant} ${id},
  ${d.owner} uuid references auth.users (id) on delete cascade,
  ${d.scope} text not null default 'user' check (${d.scope} in ('organization', 'agent', 'project', 'chat', 'user')),
  ${d.scopeId} uuid,${line(doc("file"), `${d.file} uuid${fileReference}`)}
  ${d.title} text not null check (length(${d.title}) between 1 and 500),${line(doc("source"), `${d.source} text`)}${line(doc("metadata"), `${d.metadata} jsonb not null default '{}' check (jsonb_typeof(${d.metadata}) = 'object')`)}
  ${d.status} text not null default 'pending' check (${d.status} in ('pending', 'ready', 'failed')),${line(doc("error"), `${d.error} text`)}${line(doc("chunkCount"), `${d.chunkCount} integer not null default 0`)}${line(doc("model"), `${d.model} text`)}${line(doc("createdAt"), `${d.createdAt} timestamptz not null default now()`)}
  ${d.updatedAt} timestamptz not null default now(),
  check ((${d.scope} = 'organization') = (${d.scopeId} is null)),
  constraint ${ctx.naming.rename("knowledge_documents_system_check")} check (${d.tenant} is not null or (${d.scope} = 'organization' and ${d.owner} is null))
);${
    ctx.owns("documents")
      ? `
alter table ${documents} add column if not exists ${d.collection} uuid references ${ctx.table("collections")} (${ctx.col("collections", "id")}) on delete set null;`
      : ""
  }${subjectDdl}
create index if not exists ${ctx.naming.rename("knowledge_documents_tenant_idx")} on ${documents} (${d.tenant}, ${d.scope}, ${d.scopeId});
create index if not exists ${ctx.naming.rename("knowledge_documents_owner_idx")} on ${documents} (${d.owner}) where ${d.owner} is not null;
${collected ? `create index if not exists ${ctx.naming.rename("knowledge_documents_collection_idx")} on ${documents} (${d.collection}) where ${d.collection} is not null;\n` : ""}${doc("file") ? `create index if not exists ${ctx.naming.rename("knowledge_documents_file_idx")} on ${documents} (${d.file}) where ${d.file} is not null;\n` : ""}create index if not exists ${ctx.naming.rename("knowledge_documents_pending_idx")} on ${documents} (${d.updatedAt}) where ${d.status} = 'pending';
alter table ${documents} enable row level security;
${revokeTable(documents)}
grant select on ${documents} to authenticated;
grant all on ${documents} to service_role;${subjectReadableFn}
${renderPolicy(makePolicy({ table: documents, name: ctx.naming.rename("knowledge_documents_read"), command: "select", roles: ["authenticated"], using: readable }), { drop: true, target: documents })}

-- A chunk is visible when its document is, so search inherits the scopes.
create table if not exists ${chunks} (
  ${c.document} uuid not null references ${documents} (${d.id}) on delete cascade,
  ${c.index} integer not null check (${c.index} >= 0),
  ${c.content} text not null check (length(${c.content}) > 0),${line(chunk("tokens"), `${c.tokens} integer`)}
  ${c.embedding} ${embedding.column},${line(chunk("hash"), `${c.hash} text`)}${line(chunk("metadata"), `${c.metadata} jsonb not null default '{}'`)}${line(chunk("tsv"), `${c.tsv} tsvector generated always as (to_tsvector(${config}::regconfig, ${c.content})) stored`)}
  primary key (${c.document}, ${c.index})
);${unique("chunks", "index", `${c.document}, ${c.index}`)}
create index if not exists knowledge_chunks_embedding_idx on ${chunks} using hnsw (${c.embedding} ${embedding.opclass});
${chunk("tsv") ? `create index if not exists knowledge_chunks_tsv_idx on ${chunks} using gin (${c.tsv});\n` : ""}create index if not exists knowledge_chunks_pending_idx on ${chunks} (${c.document}, ${c.index}) where ${c.embedding} is null;
alter table ${chunks} enable row level security;
${revokeTable(chunks)}
grant select on ${chunks} to authenticated;
grant all on ${chunks} to service_role;
${renderPolicy(makePolicy({ table: chunks, name: "knowledge_chunks_read", command: "select", roles: ["authenticated"], using: `exists (select 1 from ${documents} doc where doc.${d.id} = ${c.document})` }), { drop: true, target: chunks })}

-- Creates a document for the caller (or for owner, as the service role).
-- Organization and agent knowledge needs the manage permission. Only the
-- service role creates a system document (tenant null, organization scope).
-- A document joins a collection of its tenant, or a system collection.
-- Subject knowledge names a record (subject_type, subject_id) of the tenant
-- that the caller can read, and is read only by those who can read it.
drop function if exists ${fn("create_knowledge_document")}(${id}, text, text, uuid, uuid, text, jsonb, uuid);
drop function if exists ${fn("create_knowledge_document")}(${id}, text, text, uuid, uuid, text, jsonb, uuid, uuid);
create or replace function ${fn("create_knowledge_document")}(
  tenant ${id},
  title text,
  scope text default 'user',
  scope_id uuid default null,
  file_id uuid default null,
  source text default null,
  metadata jsonb default '{}',
  owner uuid default null,
  collection_id uuid default null,
  subject_type text default null,
  subject_id text default null
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
  if not ${SERVICE_CALLER} and (auth.uid() is null or create_knowledge_document.tenant is null or not ${ctx.scope.can("create_knowledge_document.tenant", write)}) then
    ${raise("you may not add knowledge here", "42501", "KNOWLEDGE_FORBIDDEN")}
  end if;
  if create_knowledge_document.tenant is null then
    v_owner := null;
  end if;
  if create_knowledge_document.collection_id is not null and not exists (
    select 1 from ${ctx.table("collections")} kc
    where kc.${ctx.col("collections", "id")} = create_knowledge_document.collection_id
      and (kc.${ctx.col("collections", "tenant")} is null or kc.${ctx.col("collections", "tenant")} = create_knowledge_document.tenant)
      and ${collectionReadable(ctx, `kc.${ctx.col("collections", "id")}`)}
  )${collected ? "" : " or create_knowledge_document.collection_id is not null"} then
    ${raise("collection % not found", "P0002", "KNOWLEDGE_COLLECTION_NOT_FOUND", "create_knowledge_document.collection_id")}
  end if;
  if create_knowledge_document.scope in ('organization', 'agent') and not (${SERVICE_CALLER} or ${ctx.scope.can("create_knowledge_document.tenant", manage)}) then
    ${raise("only admins add % knowledge", "42501", "KNOWLEDGE_FORBIDDEN", "create_knowledge_document.scope")}
  end if;
  if create_knowledge_document.scope = 'user' then
    v_scope_id := coalesce(v_scope_id, v_owner);
    if v_scope_id is null or v_scope_id is distinct from v_owner then
      ${raise("user knowledge belongs to its owner", "22023", "KNOWLEDGE_SCOPE")}
    end if;
  end if;
  if create_knowledge_document.scope is null
    or create_knowledge_document.scope not in ('organization', 'agent', 'project', 'chat', 'user'${subjectScoped ? ", 'subject'" : ""})
    or (create_knowledge_document.scope in ('organization', 'subject')) <> (v_scope_id is null) then
    ${raise("% knowledge needs %", "22023", "KNOWLEDGE_SCOPE", "create_knowledge_document.scope", "case when create_knowledge_document.scope in ('organization', 'subject') then 'no scope_id' else 'a scope_id' end")}
  end if;
  if (create_knowledge_document.scope = 'subject') <> (create_knowledge_document.subject_type is not null and create_knowledge_document.subject_id is not null)
    or (create_knowledge_document.scope <> 'subject' and (create_knowledge_document.subject_type is not null or create_knowledge_document.subject_id is not null)) then
    ${raise("subject knowledge needs subject_type and subject_id, and other scopes neither", "22023", "KNOWLEDGE_DOCUMENT_INVALID")}
  end if;${
    subjectScoped
      ? `
  if create_knowledge_document.scope = 'subject' and not (${SERVICE_CALLER} or ${subjectReadable(
    ctx,
    recordTypes,
    {
      type: "create_knowledge_document.subject_type",
      id: "create_knowledge_document.subject_id",
      tenant: "create_knowledge_document.tenant",
    },
  )}) then
    ${raise("record %:% not found", "P0002", "KNOWLEDGE_DOCUMENT_SUBJECT_NOT_FOUND", "create_knowledge_document.subject_type", "create_knowledge_document.subject_id")}
  end if;`
      : ""
  }
  if create_knowledge_document.scope = 'chat' and not (${SERVICE_CALLER} or ${chatReadable("v_scope_id")}) then
    ${raise("chat % not found", "P0002", "AI_CHAT_NOT_FOUND", "v_scope_id")}
  end if;${fileCheck}
  insert into ${documents} (${documentInsert.map(([column]) => column).join(", ")})
  values (${documentInsert.map(([, value]) => value).join(", ")})
  returning * into v_row;
  return ${documentJson("v_row")};
end;
$$;
${userGrant(`${fn("create_knowledge_document")}(${id}, text, text, uuid, uuid, text, jsonb, uuid, uuid, text, text)`)}

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
  v_keep := ${doc("model") ? `write_knowledge_chunks.model is not distinct from v_row.${d.model} or ` : ""}write_knowledge_chunks.model is null;
  insert into ${chunks} as t (${chunkInsert.map(([column]) => column).join(", ")})
  select ${chunkInsert.map(([, value]) => value).join(", ")}
  from jsonb_array_elements(v_items) with ordinality e(value, ord)
  on conflict (${c.document}, ${c.index}) do update set
    ${chunkUpdate.join(",\n    ")};
  delete from ${chunks} x where x.${c.document} = v_row.${d.id} and x.${c.index} >= v_count;
  update ${documents} x set
    ${writeUpdate.join(",\n    ")}
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

-- The documents the caller can read in a tenant, newest first. With a
-- collection, its documents, system ones included. With a record, the
-- subject knowledge about it.
drop function if exists ${fn("list_knowledge_documents")}(${id}, text, uuid, integer);
drop function if exists ${fn("list_knowledge_documents")}(${id}, text, uuid, integer, uuid);
create or replace function ${fn("list_knowledge_documents")}(
  tenant ${id},
  scope text default null,
  scope_id uuid default null,
  max_rows integer default 100,
  collection_id uuid default null,
  subject_type text default null,
  subject_id text default null
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${documentJson("x")} order by ${createdAt("x")} desc), '[]')
  from (
    select * from ${documents} y
    where ${
      collected
        ? `(y.${d.tenant} = list_knowledge_documents.tenant or (y.${d.tenant} is null and list_knowledge_documents.collection_id is not null))
      and (list_knowledge_documents.collection_id is null or y.${d.collection} = list_knowledge_documents.collection_id)`
        : `y.${d.tenant} = list_knowledge_documents.tenant
      and list_knowledge_documents.collection_id is null`
    }
      and (list_knowledge_documents.scope is null or ${asText(ctx, "documents", `y.${d.scope}`)} = list_knowledge_documents.scope)
      and (list_knowledge_documents.scope_id is null or y.${d.scopeId} = list_knowledge_documents.scope_id)${
        subjectColumns
          ? `
      and (list_knowledge_documents.subject_type is null or y.${d.subjectType} = list_knowledge_documents.subject_type)
      and (list_knowledge_documents.subject_id is null or y.${d.subjectId} = list_knowledge_documents.subject_id)`
          : `
      and list_knowledge_documents.subject_type is null and list_knowledge_documents.subject_id is null`
      }
    order by ${createdAt("y")} desc
    limit least(greatest(list_knowledge_documents.max_rows, 1), 1000)
  ) x
$$;
${userGrant(`${fn("list_knowledge_documents")}(${id}, text, uuid, integer, uuid, text, text)`)}

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
-- list of {"scope", "id"} objects ({"scope": "subject", "type", "id"} for a
-- record), or {"items": list}; null searches every scope. collections limits it to those collections. System documents count
-- in every tenant, disabled collections in none, and a collection with a
-- higher priority ranks its chunks first. Returns a JSON array of
-- {document_id, idx, content, metadata, title, score}.
drop function if exists ${fn("knowledge_search")}(${id}, ${embedding.type}, text, jsonb, integer, jsonb);
create or replace function ${fn("knowledge_search")}(
  tenant ${id},
  query_embedding ${embedding.type} default null,
  query_text text default null,
  scopes jsonb default null,
  k integer default 8,
  filter jsonb default null,
  collections uuid[] default null
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
    select x.${d.id} as id, x.${d.title} as title, ${collected ? collectionPriority(ctx, `x.${d.collection}`) : "0"} as priority from ${documents} x
    where (x.${d.tenant} = knowledge_search.tenant or x.${d.tenant} is null)${
      collected
        ? `
      and (x.${d.collection} is null or ${collectionSearched(ctx, `x.${d.collection}`)})
      and (knowledge_search.collections is null or x.${d.collection} = any(knowledge_search.collections))`
        : `
      and knowledge_search.collections is null`
    }
      and (v_scopes is null or exists (
        select 1 from jsonb_array_elements(v_scopes) s
        where s.value ->> 'scope' = ${asText(ctx, "documents", `x.${d.scope}`)}${
          subjectColumns
            ? `
          and (s.value ->> 'scope' = 'subject' or s.value ->> 'id' is null or (s.value ->> 'id')::uuid = x.${d.scopeId})
          and (s.value ->> 'scope' <> 'subject' or ((s.value ->> 'type' is null or s.value ->> 'type' = x.${d.subjectType}) and (s.value ->> 'id' is null or s.value ->> 'id' = x.${d.subjectId})))`
            : `
          and (s.value ->> 'id' is null or (s.value ->> 'id')::uuid = x.${d.scopeId})`
        }
      ))
      and (knowledge_search.filter is null${doc("metadata") ? ` or x.${d.metadata} @> knowledge_search.filter` : ""})
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
    select t.${c.document} as document_id, t.${c.index} as idx, ts_rank_cd(${tsv("t")}, q) as text_score
    from ${chunks} t, websearch_to_tsquery(${config}::regconfig, knowledge_search.query_text) q
    where knowledge_search.query_text is not null and ${tsv("t")} @@ q
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
  select coalesce(jsonb_agg(jsonb_build_object('document_id', r.document_id, 'idx', r.idx, 'content', r.content, 'metadata', r.metadata, 'title', r.title, 'score', r.score) order by r.priority desc, r.score desc, r.document_id, r.idx), '[]')
  into v_rows
  from (
    select f.document_id, f.idx, t.${c.content} as content, ${chunk("metadata") ? `t.${c.metadata}` : "'{}'::jsonb"} as metadata, docs.title, docs.priority, f.score
    from fused f
    join ${chunks} t on t.${c.document} = f.document_id and t.${c.index} = f.idx
    join docs on docs.id = f.document_id
    order by docs.priority desc, f.score desc, f.document_id, f.idx
    limit least(greatest(knowledge_search.k, 1), 100)
  ) r;
  perform set_config('hnsw.iterative_scan', coalesce(previous_scan, 'off'), true);
  return v_rows;
end;
$$;
${userGrant(`${fn("knowledge_search")}(${id}, ${embedding.type}, text, jsonb, integer, jsonb, uuid[])`)}

-- The chunks of a document still waiting for an embedding, for the worker,
-- with the md5 of each content it passes back to set_knowledge_embeddings.
create or replace function ${fn("pending_knowledge_chunks")}(document_id uuid, batch integer default 64)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('idx', x.${c.index}, 'content', x.${c.content}, 'hash', md5(x.${c.content})) order by x.${c.index}), '[]')
  from (
    select * from ${chunks} y
    where y.${c.document} = pending_knowledge_chunks.document_id and y.${c.embedding} is null
    order by y.${c.index}
    limit least(greatest(pending_knowledge_chunks.batch, 1), 2048)
  ) x
$$;
${serviceGrant(`${fn("pending_knowledge_chunks")}(uuid, integer)`)}

-- Stores embeddings ([{"idx", "hash", "embedding"}], or {"items": list}) and marks the
-- document ready once no chunk is missing one. Returns how many chunks still wait.
-- hash is the md5 of the content that was embedded: a chunk rewritten since
-- then keeps waiting instead of taking a vector of its old text.
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
    ${c.embedding} = (e.value ->> 'embedding')::${embedding.column}${chunk("hash") ? `,\n    ${c.hash} = e.value ->> 'hash'` : ""}
  from jsonb_array_elements(coalesce(v_items, '[]')) e
  where t.${c.document} = set_knowledge_embeddings.document_id and t.${c.index} = (e.value ->> 'idx')::integer
    and md5(t.${c.content}) = e.value ->> 'hash';
  select count(*)::integer into v_remaining from ${chunks} t
  where t.${c.document} = set_knowledge_embeddings.document_id and t.${c.embedding} is null;
  update ${documents} x set
    ${d.status} = ${status(`case when v_remaining = 0 then 'ready' else ${asText(ctx, "documents", `x.${d.status}`)} end`)},${doc("model") ? `\n    ${d.model} = coalesce(set_knowledge_embeddings.model, x.${d.model}),` : ""}
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
  update ${documents} x set ${d.status} = 'failed',${doc("error") ? ` ${d.error} = left(fail_knowledge_document.error, 2000),` : ""} ${d.updatedAt} = now()
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

${
  files && ctx.installed("queue") && doc("file")
    ? `-- Creates a pending document for a ready ai-files file and enqueues its
-- ingestion on options.ingestQueue: the job reads the file, extracts its
-- text and writes the chunks, which enqueues their embedding.
create or replace function ${fn("queue_knowledge_file")}(
  tenant ${id},
  file_id uuid,
  title text default null,
  scope text default 'user',
  scope_id uuid default null,
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
  v_name text;
  v_document jsonb;
begin
  select x.${files.col("files", "filename")} into v_name from ${files.table("files")} x
  where x.${files.col("files", "id")} = queue_knowledge_file.file_id and x.${files.col("files", "tenant")} = queue_knowledge_file.tenant;
  if not found then
    ${raise("file % not found", "P0002", "AI_FILE_NOT_FOUND", "queue_knowledge_file.file_id")}
  end if;
  v_document := ${fn("create_knowledge_document")}(queue_knowledge_file.tenant, coalesce(queue_knowledge_file.title, v_name), queue_knowledge_file.scope, queue_knowledge_file.scope_id, queue_knowledge_file.file_id, coalesce(queue_knowledge_file.source, v_name), queue_knowledge_file.metadata, queue_knowledge_file.owner);
  ${ctx.enqueue(ingestQueue, `jsonb_build_object('document_id', v_document ->> 'id')`, `'knowledge-ingest:' || (v_document ->> 'id')`)}
  return v_document;
end;
$$;
${userGrant(`${fn("queue_knowledge_file")}(${id}, uuid, text, text, uuid, text, jsonb, uuid)`)}

`
    : ""
}-- Clears the embeddings of a tenant's documents (all tenants when null)
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
      ${doc("model") ? `and (reembed_knowledge.model is null or x.${d.model} is distinct from reembed_knowledge.model)\n      ` : ""}and ${doc("chunkCount") ? `x.${d.chunkCount} > 0` : `exists (select 1 from ${chunks} p where p.${c.document} = x.${d.id})`}
    returning x.${d.id}
  loop
    update ${chunks} t set ${c.embedding} = null${chunk("hash") ? `, ${c.hash} = null` : ""} where t.${c.document} = v_id;${enqueue("v_id")}
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
${serviceGrant(`${fn("reembed_knowledge")}(${id}, text)`)}`;
}

export const KNOWLEDGE: BlockSqlDefinition = {
  name: "knowledge",
  scopes: ["tenant"],
  title: "Knowledge",
  description:
    "Documents and chunks for retrieval with an embedding and a tsvector each, scoped to an organization, agent, project, chat, user or record (subject) and grouped into collections with a visibility, a priority and grants, plus system documents shared with every tenant; hybrid search with reciprocal rank fusion, chunks that keep their embedding when unchanged, and an embed job per document when jobs is installed. With ai-files and jobs, queue_knowledge_file ingests a file through a job.",
  requires: ["memberships", "permissions", "vector-search"],
  integrates: ["ai-chat", "ai-files", "queue", "subjects", "teams"],
  target: "schema",
  version: 5,
  upgrades: [
    {
      from: 1,
      description:
        "With ai-files and jobs, queue_knowledge_file creates a pending document for a file and enqueues its ingestion on options.ingestQueue (default knowledge_ingest).",
      sql: () => "",
    },
    {
      from: 2,
      description:
        "Knowledge collections with a visibility, a priority and grants to users or teams; documents join a collection, and system documents without a tenant are shared with every tenant.",
      sql: (ctx) =>
        ctx.owns("documents")
          ? `alter table ${ctx.table("documents")} alter column ${ctx.col("documents", "tenant")} drop not null;`
          : "",
    },
    {
      from: 3,
      description:
        "Subject knowledge: scope 'subject' with subject_type and subject_id names a record, and only those who can read the record (can_subject) read the document, with the subjects block.",
      sql: () => "",
    },
    {
      from: 4,
      description:
        "Collection grants gain the collection's tenant (organization_id, filled from the collection), and team_id takes the teams id type when teams is installed.",
      sql: upgradeCollectionGrants,
    },
  ],
  names: NAMES,
  build,
};
