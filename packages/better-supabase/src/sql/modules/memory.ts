import type { BlockSqlContext, BlockSqlNames } from "../context.ts";
import type { BlockSqlDefinition, BlockSqlLayout } from "../module-types.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  raise,
  replaceColumnCheck,
  schemaPreamble,
  SERVICE_CALLER,
  serviceGrant,
  userGrant,
  revokeTable,
} from "../shared.ts";
import { tableMoves } from "../table-renames.ts";
import { embeddingColumn, textSearchConfig } from "./knowledge.ts";
import { DOCUMENTS, memoryDocumentsSql } from "./memory-documents.ts";
import {
  capSql,
  memoryLimits,
  purgeSql,
  SHARED,
  upgradeOwners,
} from "./memory-limits.ts";
import { asText } from "./over-app.ts";
import { moduleOperations } from "./permissions-model.ts";

const MEMORIES = {
  id: "id",
  tenant: "organization_id",
  owner: "owner_id",
  scope: "scope",
  agent: "agent_id",
  chat: "chat_id",
  project: "project_id",
  kind: "kind",
  path: "path",
  content: "content",
  version: "version",
  embedding: "embedding",
  model: "embedding_model",
  sourceMessage: "source_message_id",
  supersededBy: "superseded_by",
  subjectType: "subject_type",
  subjectId: "subject_id",
  category: "category",
  confidence: "confidence",
  expiresAt: "expires_at",
  deletedAt: "deleted_at",
  useCount: "use_count",
  lastUsedAt: "last_used_at",
  tsv: "tsv",
  createdAt: "created_at",
  updatedAt: "updated_at",
} as const;

/** The memory columns version 3 added, each optional on an adopted table. */
const ADDED = [
  "subjectType",
  "subjectId",
  "category",
  "confidence",
  "expiresAt",
  "deletedAt",
  "useCount",
  "lastUsedAt",
] as const;

const MESSAGE_EMBEDDINGS = {
  chat: "chat_id",
  message: "message_id",
  user: "user_id",
  tenant: "organization_id",
  embedding: "embedding",
  model: "embedding_model",
  createdAt: "created_at",
} as const;

const NAMES: BlockSqlNames = {
  migrations: tableMoves("memory", 4),
  entities: {
    memory: {
      table: "memories",
      singular: "memory",
      plural: "memories",
      primary: true,
    },
  },
  options: [
    "dimensions",
    "type",
    "textSearch",
    "maxContent",
    "tenant",
    "maxItems",
  ],
  tables: {
    memories: {
      name: "memories",
      columns: MEMORIES,
      optional: ["model", "sourceMessage", "tsv", "createdAt", ...ADDED],
      typed: ["scope", "kind"],
      app: {},
      lifecycle: { user: "owner", tenant: "tenant" },
    },
    messageEmbeddings: {
      name: "memory_message_embeddings",
      columns: MESSAGE_EMBEDDINGS,
      optional: ["model", "createdAt"],
      app: {},
      lifecycle: { user: "user", tenant: "tenant" },
    },
    documents: {
      name: "memory_documents",
      columns: DOCUMENTS,
      optional: ["expiresAt", "createdAt", "updatedAt"],
      app: {},
    },
  },
};

/**
 * A path under `/memories`: segments of letters, digits, dots, dashes,
 * underscores and spaces.
 */
const PATH_PATTERN = "^/memories(/[A-Za-z0-9._ -]+)*$";

/** The namespaces a memory belongs to. */
const SCOPES = "'user', 'agent', 'chat', 'project', 'organization', 'record'";

/** The scopes whose memory has no owner and only admins change. */

/** A category: a lowercase slug. */
const CATEGORY_PATTERN = "^[a-z0-9][a-z0-9_-]*$";

/** A `.` or `..` segment. */
const DOT_SEGMENT = "(^|/)[.]{1,2}(/|$)";

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

/** The memory keys a memory read returns, in order. */
const MEMORY_JSON = [
  "id",
  "tenant",
  "owner",
  "scope",
  "agent",
  "chat",
  "project",
  "kind",
  "path",
  "content",
  "version",
  "model",
  "sourceMessage",
  "subjectType",
  "subjectId",
  "category",
  "confidence",
  "expiresAt",
  "useCount",
  "lastUsedAt",
  "createdAt",
  "updatedAt",
] as const;

function build(ctx: BlockSqlContext, layout: BlockSqlLayout): string {
  const id = ctx.idType;
  const fn = (name: string): string => ctx.fn(name);
  const m = presentColumns(ctx, "memories", MEMORIES);
  const e = presentColumns(ctx, "messageEmbeddings", MESSAGE_EMBEDDINGS);

  const memory = (column: keyof typeof MEMORIES): boolean =>
    ctx.has("memories", column);

  const message = (column: keyof typeof MESSAGE_EMBEDDINGS): boolean =>
    ctx.has("messageEmbeddings", column);

  const line = (present: boolean, definition: string): string =>
    present ? `\n  ${definition},` : "";

  const subject = memory("subjectType") && memory("subjectId");

  const subjectColumns = subject ? `, ${m.subjectType}, ${m.subjectId}` : "";

  // A deleted memory stays until purge_memories removes it; an expired one
  // drops out of reads and searches the same way.
  const column = (row: string, key: keyof typeof MEMORIES): string =>
    row ? `${row}.${m[key]}` : m[key];

  const live = (row: string): string =>
    memory("deletedAt") ? ` and ${column(row, "deletedAt")} is null` : "";

  const fresh = (row: string): string =>
    memory("expiresAt")
      ? ` and (${column(row, "expiresAt")} is null or ${column(row, "expiresAt")} > now())`
      : "";

  const unique = (table: string, what: string, columns: string): string =>
    ctx.owns(table)
      ? ""
      : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName(table).name}_${what}_key`)} on ${ctx.table(table)} (${columns});`;

  const createdAt = (row: string): string =>
    `${row}.${memory("createdAt") ? m.createdAt : m.updatedAt}`;

  const memories = ctx.table("memories");
  const messageEmbeddings = ctx.table("messageEmbeddings");
  const permissions = moduleOperations("memory");
  const read = ctx.permission("read", permissions.read);
  const manage = ctx.permission("manage", permissions.manage);
  const embedding = embeddingColumn(ctx, layout);
  const config = sqlString(textSearchConfig(ctx));

  const tsv = (row: string): string =>
    memory("tsv")
      ? `${row}.${m.tsv}`
      : `to_tsvector(${config}::regconfig, ${row}.${m.content})`;

  const maxContent = ctx.number("maxContent", 100_000);

  if (!Number.isInteger(maxContent) || maxContent < 1) {
    throw new TypeError(
      "blocks.memory.options.maxContent must be a positive whole number of characters",
    );
  }

  const limits = memoryLimits(ctx);

  const chat = ctx.installed("ai-chat") ? ctx.of("ai-chat") : undefined;

  const chatReference = chat
    ? ` references ${chat.table("chats")} (${chat.col("chats", "id")}) on delete cascade`
    : "";

  const projectReference = chat
    ? ` references ${chat.table("projects")} (${chat.col("projects", "id")}) on delete cascade`
    : "";

  const temporaryCheck = chat
    ? `
  if exists (select 1 from ${chat.table("chats")} x where x.${chat.col("chats", "id")} = set_ai_message_embedding.chat_id and x.${chat.col("chats", "temporary")}) then
    return false;
  end if;`
    : "";

  const memoryJson = (row: string): string =>
    `jsonb_build_object(${MEMORY_JSON.map((key) => `'${MEMORIES[key]}', ${memory(key) ? `${row}.${m[key]}` : key === "createdAt" ? `${row}.${m.updatedAt}` : "null"}`).join(", ")})`;

  // Every command names its namespace in ns: {"scope", "agent_id",
  // "chat_id", "project_id", "private"} and, for the service role,
  // "owner_id". Organization and record memory has no owner and only admins
  // change it, unless "private" gives it one. With options.tenant false a
  // namespace with an owner may have no tenant.
  const namespace = (name: string, writes: boolean): string => `
  v_scope := coalesce(${name}.ns ->> 'scope', 'user');
  v_agent := (${name}.ns ->> 'agent_id')::uuid;
  v_chat := (${name}.ns ->> 'chat_id')::uuid;
  v_project := (${name}.ns ->> 'project_id')::uuid;
  v_subject_type := nullif(${name}.ns ->> 'subject_type', '');
  v_subject_id := nullif(${name}.ns ->> 'subject_id', '');
  v_private := coalesce((${name}.ns ->> 'private')::boolean, false);
  v_owner := case when v_scope in (${SHARED}) and not v_private then null when ${SERVICE_CALLER} then (${name}.ns ->> 'owner_id')::uuid else auth.uid() end;
  if not ${SERVICE_CALLER} and (auth.uid() is null or not ${limits.tenantless ? `(${name}.tenant is null or ${ctx.scope.can(`${name}.tenant`, read)})` : ctx.scope.can(`${name}.tenant`, read)}) then
    ${raise("you may not use memory here", "42501", "MEMORY_FORBIDDEN")}
  end if;
  if v_scope not in (${SCOPES})
    or (v_scope = 'agent') <> (v_agent is not null)
    or (v_scope = 'chat') <> (v_chat is not null)
    or (v_scope = 'project') <> (v_project is not null)
    or (v_scope = 'record') <> (v_subject_id is not null)
    or (v_subject_id is not null) <> (v_subject_type is not null)${subject ? "" : "\n    or v_scope = 'record'"}
    or (v_owner is null and (v_scope not in (${SHARED}) or v_private))${limits.tenantless ? `\n    or (${name}.tenant is null and v_owner is null)` : ""} then
    ${raise("ns % is not a memory namespace", "22023", "MEMORY_NAMESPACE", `${name}.ns`)}
  end if;${
    writes
      ? `
  if v_owner is null and not (${SERVICE_CALLER} or ${ctx.scope.can(`${name}.tenant`, manage)}) then
    ${raise("only admins change organization and record memory", "42501", "MEMORY_FORBIDDEN")}
  end if;`
      : ""
  }`;

  const declare = `
  v_scope text;
  v_agent uuid;
  v_chat uuid;
  v_project uuid;
  v_subject_type text;
  v_subject_id text;
  v_private boolean;
  v_owner uuid;`;

  const inNamespace = (row: string, tenant: string): string =>
    `${row}.${m.tenant} ${limits.tenantless ? "is not distinct from" : "="} ${tenant} and ${row}.${m.owner} is not distinct from v_owner and ${asText(ctx, "memories", `${row}.${m.scope}`)} = v_scope and ${row}.${m.agent} is not distinct from v_agent and ${row}.${m.chat} is not distinct from v_chat and ${row}.${m.project} is not distinct from v_project${subject ? ` and ${row}.${m.subjectType} is not distinct from v_subject_type and ${row}.${m.subjectId} is not distinct from v_subject_id` : ""} and ${row}.${m.supersededBy} is null${live(row)}`;

  const checkPath = (path: string): string => `
  if ${path} is null or length(${path}) > 500 or ${path} !~ ${sqlString(PATH_PATTERN)} or ${path} ~ ${sqlString(DOT_SEGMENT)} then
    ${raise("% is not a path under /memories", "22023", "MEMORY_PATH", path)}
  end if;`;

  const checkContent = (content: string): string => `
  if length(${content}) > ${String(maxContent)} then
    ${raise("memory content is limited to % characters", "22023", "MEMORY_TOO_LARGE", String(maxContent))}
  end if;`;

  const subjectInsert = subject ? `, ${m.subjectType}, ${m.subjectId}` : "";

  const subjectValues = subject ? ", v_subject_type, v_subject_id" : "";

  const saved = (
    [
      ["model", "memory_save.model"],
      ["sourceMessage", "memory_save.source_message_id"],
      ["category", "memory_save.category"],
      ["confidence", "memory_save.confidence"],
      ["expiresAt", "memory_save.expires_at"],
    ] as const
  ).filter(([key]) => memory(key));

  const savedColumns = saved.map(([key]) => `, ${m[key]}`).join("");

  const savedValues = saved.map(([, value]) => `, ${value}`).join("");

  const forgetCheck = (row: string): string =>
    `${SERVICE_CALLER} or coalesce(${row}.${m.owner} = auth.uid(), false) or (${row}.${m.owner} is null and ${ctx.scope.can(`${row}.${m.tenant}`, manage)})`;

  const fileNotFound = (path: string): string =>
    raise("% not found", "P0002", "MEMORY_NOT_FOUND", path);

  const signature = (name: string, args: string): string =>
    `${fn(name)}(${args})`;

  const restoreAndPurge = (): string => `
-- Restores a deleted memory, with the same rights as memory_forget. Fails
-- when a live file already has its path.
create or replace function ${fn("memory_restore")}(memory_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${memories}%rowtype;
begin
  select * into v_row from ${memories} x where x.${m.id} = memory_restore.memory_id and x.${m.deletedAt} is not null;
  if not found or not (${forgetCheck("v_row")}) then
    return false;
  end if;
  update ${memories} x set ${m.deletedAt} = null, ${m.updatedAt} = now() where x.${m.id} = v_row.${m.id};
  return true;
exception when unique_violation then
  ${raise("% already exists", "23505", "MEMORY_EXISTS", `v_row.${m.path}`)}
end;
$$;
${userGrant(signature("memory_restore", "uuid"))}

${purgeSql(ctx, m)}`;

  return `${schemaPreamble(ctx)}
-- Memory for AI assistants. Core memory is a small set of files under
-- /memories that the model reads and edits with view, create, str_replace,
-- insert, delete and rename; archival memory is a list of facts found by
-- similarity. Each belongs to a user, an agent, a chat, a project, the
-- organization or a record.
create table if not exists ${memories} (
  ${m.id} uuid primary key default gen_random_uuid(),
  ${m.tenant} ${id}${limits.tenantless ? "" : " not null"},
  ${m.owner} uuid references auth.users (id) on delete cascade,
  ${m.scope} text not null default 'user' check (${m.scope} in (${SCOPES})),
  ${m.agent} uuid,
  ${m.chat} uuid${chatReference},
  ${m.project} uuid${projectReference},
  ${m.kind} text not null check (${m.kind} in ('core', 'archival')),
  ${m.path} text check (${m.path} ~ ${sqlString(PATH_PATTERN)} and ${m.path} !~ ${sqlString(DOT_SEGMENT)}),
  ${m.content} text not null check (length(${m.content}) <= ${String(maxContent)}),
  ${m.version} integer not null default 1,
  ${m.embedding} ${embedding.column},${line(memory("model"), `${m.model} text`)}${line(memory("sourceMessage"), `${m.sourceMessage} text`)}
  ${m.supersededBy} uuid references ${memories} (${m.id}) on delete set null,${line(memory("subjectType"), `${m.subjectType} text`)}${line(memory("subjectId"), `${m.subjectId} text`)}${line(memory("category"), `${m.category} text check (${m.category} ~ ${sqlString(CATEGORY_PATTERN)})`)}${line(memory("confidence"), `${m.confidence} real check (${m.confidence} between 0 and 1)`)}${line(memory("expiresAt"), `${m.expiresAt} timestamptz`)}${line(memory("deletedAt"), `${m.deletedAt} timestamptz`)}${line(memory("useCount"), `${m.useCount} integer not null default 0`)}${line(memory("lastUsedAt"), `${m.lastUsedAt} timestamptz`)}${line(memory("tsv"), `${m.tsv} tsvector generated always as (to_tsvector(${config}::regconfig, ${m.content})) stored`)}${line(memory("createdAt"), `${m.createdAt} timestamptz not null default now()`)}
  ${m.updatedAt} timestamptz not null default now(),
  check ((${m.kind} = 'core') = (${m.path} is not null)),
  constraint ${ctx.naming.rename("memories_owner_check")} check (${m.scope} in (${SHARED}) or ${m.owner} is not null)${subject ? `,\n  constraint ${ctx.naming.rename("memories_subject_check")} check ((${m.scope} = 'record') = (${m.subjectId} is not null) and (${m.subjectId} is null) = (${m.subjectType} is null))` : ""}
);${limits.tenantless && ctx.owns("memories") ? `\nalter table ${memories} alter column ${m.tenant} drop not null;` : ""}
create unique index if not exists ${ctx.naming.rename("memories_path_idx")} on ${memories} (${m.tenant}, ${m.owner}, ${m.scope}, ${m.agent}, ${m.chat}, ${m.project}${subjectColumns}, ${m.path}) nulls not distinct
  where ${m.path} is not null and ${m.supersededBy} is null${live("")};
create index if not exists ${ctx.naming.rename("memories_owner_idx")} on ${memories} (${m.owner}, ${m.tenant}) where ${m.owner} is not null;
create index if not exists ${ctx.naming.rename("memories_tenant_idx")} on ${memories} (${m.tenant}, ${m.scope});
create index if not exists ${ctx.naming.rename("memories_chat_idx")} on ${memories} (${m.chat}) where ${m.chat} is not null;
create index if not exists ${ctx.naming.rename("memories_project_idx")} on ${memories} (${m.project}) where ${m.project} is not null;
${subject ? `create index if not exists ${ctx.naming.rename("memories_subject_idx")} on ${memories} (${m.subjectType}, ${m.subjectId}) where ${m.subjectId} is not null;\n` : ""}${memory("deletedAt") ? `create index if not exists ${ctx.naming.rename("memories_deleted_idx")} on ${memories} (${m.deletedAt}) where ${m.deletedAt} is not null;\n` : ""}${memory("expiresAt") ? `create index if not exists ${ctx.naming.rename("memories_expires_idx")} on ${memories} (${m.expiresAt}) where ${m.expiresAt} is not null;\n` : ""}create index if not exists ${ctx.naming.rename("memories_superseded_idx")} on ${memories} (${m.supersededBy}) where ${m.supersededBy} is not null;
create index if not exists ${ctx.naming.rename("memories_embedding_idx")} on ${memories} using hnsw (${m.embedding} ${embedding.opclass});
${memory("tsv") ? `create index if not exists ${ctx.naming.rename("memories_tsv_idx")} on ${memories} using gin (${m.tsv});\n` : ""}create index if not exists ${ctx.naming.rename("memories_pending_embedding_idx")} on ${memories} (${m.updatedAt})
  where ${m.embedding} is null and ${m.supersededBy} is null${live("")};
alter table ${memories} enable row level security;
${revokeTable(memories)}
grant select on ${memories} to authenticated;
grant all on ${memories} to service_role;
${renderPolicy(makePolicy({ table: memories, name: ctx.naming.rename("memories_read"), command: "select", roles: ["authenticated"], using: `(${m.owner} = (select auth.uid()) or (${m.owner} is null and ${ctx.scope.check(m.tenant, read)}))${live("")}` }), { drop: true, target: memories })}

-- One embedding per message, so an assistant can recall earlier chats.
-- Temporary chats get none.
create table if not exists ${messageEmbeddings} (
  ${e.chat} uuid not null${chatReference},
  ${e.message} text not null,
  ${e.user} uuid not null references auth.users (id) on delete cascade,
  ${e.tenant} ${id} not null,
  ${e.embedding} ${embedding.column} not null,${line(message("model"), `${e.model} text`)}${line(message("createdAt"), `${e.createdAt} timestamptz not null default now()`)}
  primary key (${e.chat}, ${e.message})
);${unique("messageEmbeddings", "message", `${e.chat}, ${e.message}`)}
create index if not exists ${sqlIdent(`${ctx.tableName("messageEmbeddings").name}_user_idx`)} on ${messageEmbeddings} (${e.user}, ${e.tenant});
create index if not exists ${sqlIdent(`${ctx.tableName("messageEmbeddings").name}_embedding_idx`)} on ${messageEmbeddings} using hnsw (${e.embedding} ${embedding.opclass});
alter table ${messageEmbeddings} enable row level security;
${revokeTable(messageEmbeddings)}
grant select on ${messageEmbeddings} to authenticated;
grant all on ${messageEmbeddings} to service_role;
${renderPolicy(makePolicy({ table: messageEmbeddings, name: sqlIdent(`${ctx.tableName("messageEmbeddings").name}_read`), command: "select", roles: ["authenticated"], using: `${e.user} = (select auth.uid())` }), { drop: true, target: messageEmbeddings })}

-- A core memory file, or the files under a directory, or null.
create or replace function ${fn("memory_view")}(tenant ${id}, path text default '/memories', ns jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare${declare}
  v_row ${memories}%rowtype;
  v_entries jsonb;
begin${namespace("memory_view", false)}${checkPath("memory_view.path")}
  select * into v_row from ${memories} x
  where ${inNamespace("x", "memory_view.tenant")} and x.${m.path} = memory_view.path;
  if found then
    return jsonb_build_object('type', 'file', 'path', v_row.${m.path}, 'content', v_row.${m.content}, 'version', v_row.${m.version}, 'updated_at', v_row.${m.updatedAt});
  end if;
  select jsonb_agg(jsonb_build_object('path', x.${m.path}, 'size', length(x.${m.content}), 'updated_at', x.${m.updatedAt}) order by x.${m.path})
  into v_entries
  from ${memories} x
  where ${inNamespace("x", "memory_view.tenant")} and x.${m.path} like replace(replace(memory_view.path, '_', '\\_'), '%', '\\%') || '/%';
  if v_entries is null and memory_view.path <> '/memories' then
    return null;
  end if;
  return jsonb_build_object('type', 'directory', 'path', memory_view.path, 'entries', coalesce(v_entries, '[]'));
end;
$$;
${userGrant(signature("memory_view", `${id}, text, jsonb`))}

-- Creates or overwrites a core memory file. expected_version 0 means the
-- file must not exist yet; another number must match its version.
create or replace function ${fn("memory_create")}(tenant ${id}, path text, content text, ns jsonb default '{}', expected_version integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare${declare}
  v_row ${memories}%rowtype;
begin${namespace("memory_create", true)}${checkPath("memory_create.path")}${checkContent("memory_create.content")}
  select * into v_row from ${memories} x
  where ${inNamespace("x", "memory_create.tenant")} and x.${m.path} = memory_create.path
  for update;
  if found then
    if memory_create.expected_version is not null and memory_create.expected_version <> v_row.${m.version} then
      ${raise("% changed since version %", "40001", "MEMORY_CONFLICT", "memory_create.path", "memory_create.expected_version")}
    end if;
    update ${memories} x set ${m.content} = memory_create.content, ${m.version} = x.${m.version} + 1, ${m.embedding} = null, ${m.updatedAt} = now()
    where x.${m.id} = v_row.${m.id}
    returning * into v_row;
  else
    if coalesce(memory_create.expected_version, 0) <> 0 then
      ${fileNotFound("memory_create.path")}
    end if;
    insert into ${memories} (${m.tenant}, ${m.owner}, ${m.scope}, ${m.agent}, ${m.chat}, ${m.project}${subjectInsert}, ${m.kind}, ${m.path}, ${m.content})
    values (memory_create.tenant, v_owner, ${ctx.cast("memories", "scope", "v_scope")}, v_agent, v_chat, v_project${subjectValues}, 'core', memory_create.path, memory_create.content)
    returning * into v_row;
  end if;
  return ${memoryJson("v_row")};
end;
$$;
${userGrant(signature("memory_create", `${id}, text, text, jsonb, integer`))}

-- Replaces old_text with new_text in a core memory file; old_text has to
-- appear exactly once.
create or replace function ${fn("memory_str_replace")}(tenant ${id}, path text, old_text text, new_text text, ns jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare${declare}
  v_row ${memories}%rowtype;
  v_matches integer;
begin${namespace("memory_str_replace", true)}${checkPath("memory_str_replace.path")}
  select * into v_row from ${memories} x
  where ${inNamespace("x", "memory_str_replace.tenant")} and x.${m.path} = memory_str_replace.path
  for update;
  if not found then
    ${fileNotFound("memory_str_replace.path")}
  end if;
  if coalesce(length(memory_str_replace.old_text), 0) = 0 then
    ${raise("old_text is empty", "22023", "MEMORY_NO_MATCH")}
  end if;
  v_matches := (length(v_row.${m.content}) - length(replace(v_row.${m.content}, memory_str_replace.old_text, ''))) / length(memory_str_replace.old_text);
  if v_matches = 0 then
    ${raise("old_text does not appear in %", "22023", "MEMORY_NO_MATCH", "memory_str_replace.path")}
  elsif v_matches > 1 then
    ${raise("old_text appears % times in %", "22023", "MEMORY_AMBIGUOUS", "v_matches", "memory_str_replace.path")}
  end if;${checkContent(`replace(v_row.${m.content}, memory_str_replace.old_text, coalesce(memory_str_replace.new_text, ''))`)}
  update ${memories} x set
    ${m.content} = replace(x.${m.content}, memory_str_replace.old_text, coalesce(memory_str_replace.new_text, '')),
    ${m.version} = x.${m.version} + 1, ${m.embedding} = null, ${m.updatedAt} = now()
  where x.${m.id} = v_row.${m.id}
  returning * into v_row;
  return ${memoryJson("v_row")};
end;
$$;
${userGrant(signature("memory_str_replace", `${id}, text, text, text, jsonb`))}

-- Inserts text after line insert_line (0 inserts at the top).
create or replace function ${fn("memory_insert")}(tenant ${id}, path text, insert_line integer, insert_text text, ns jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare${declare}
  v_row ${memories}%rowtype;
  v_lines text[];
  v_content text;
begin${namespace("memory_insert", true)}${checkPath("memory_insert.path")}
  select * into v_row from ${memories} x
  where ${inNamespace("x", "memory_insert.tenant")} and x.${m.path} = memory_insert.path
  for update;
  if not found then
    ${fileNotFound("memory_insert.path")}
  end if;
  v_lines := case when v_row.${m.content} = '' then '{}'::text[] else string_to_array(v_row.${m.content}, E'\\n') end;
  if memory_insert.insert_line < 0 or memory_insert.insert_line > coalesce(array_length(v_lines, 1), 0) then
    ${raise("line % is outside the file", "22023", "MEMORY_LINE", "memory_insert.insert_line")}
  end if;
  v_content := array_to_string(v_lines[1:memory_insert.insert_line] || string_to_array(coalesce(memory_insert.insert_text, ''), E'\\n') || v_lines[memory_insert.insert_line + 1:], E'\\n');${checkContent("v_content")}
  update ${memories} x set ${m.content} = v_content, ${m.version} = x.${m.version} + 1, ${m.embedding} = null, ${m.updatedAt} = now()
  where x.${m.id} = v_row.${m.id}
  returning * into v_row;
  return ${memoryJson("v_row")};
end;
$$;
${userGrant(signature("memory_insert", `${id}, text, integer, text, jsonb`))}

-- Deletes a file, or a directory and everything under it, and returns the
-- count. A deleted file stays restorable until purge_memories removes it.
create or replace function ${fn("memory_delete")}(tenant ${id}, path text, ns jsonb default '{}')
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare${declare}
  v_count integer;
begin${namespace("memory_delete", true)}${checkPath("memory_delete.path")}
  ${memory("deletedAt") ? `update ${memories} x set ${m.deletedAt} = now(), ${m.updatedAt} = now()` : `delete from ${memories} x`}
  where ${inNamespace("x", "memory_delete.tenant")}
    and (x.${m.path} = memory_delete.path or x.${m.path} like replace(replace(memory_delete.path, '_', '\\_'), '%', '\\%') || '/%');
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
${userGrant(signature("memory_delete", `${id}, text, jsonb`))}

-- Moves a file or a directory. Fails when the target already exists.
create or replace function ${fn("memory_rename")}(tenant ${id}, old_path text, new_path text, ns jsonb default '{}')
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare${declare}
  v_count integer;
  v_prefix text := replace(replace(memory_rename.old_path, '_', '\\_'), '%', '\\%') || '/%';
begin${namespace("memory_rename", true)}${checkPath("memory_rename.old_path")}${checkPath("memory_rename.new_path")}
  if memory_rename.new_path = memory_rename.old_path or memory_rename.new_path like v_prefix then
    ${raise("cannot move % into itself", "22023", "MEMORY_PATH", "memory_rename.old_path")}
  end if;
  if exists (
    select 1 from ${memories} x
    where ${inNamespace("x", "memory_rename.tenant")}
      and (x.${m.path} = memory_rename.new_path or x.${m.path} like replace(replace(memory_rename.new_path, '_', '\\_'), '%', '\\%') || '/%')
  ) then
    ${raise("% already exists", "23505", "MEMORY_EXISTS", "memory_rename.new_path")}
  end if;
  update ${memories} x set
    ${m.path} = memory_rename.new_path || substr(x.${m.path}, length(memory_rename.old_path) + 1),
    ${m.version} = x.${m.version} + 1, ${m.updatedAt} = now()
  where ${inNamespace("x", "memory_rename.tenant")}
    and (x.${m.path} = memory_rename.old_path or x.${m.path} like v_prefix);
  get diagnostics v_count = row_count;
  if v_count = 0 then
    ${fileNotFound("memory_rename.old_path")}
  end if;
  return v_count;
end;
$$;
${userGrant(signature("memory_rename", `${id}, text, text, jsonb`))}

-- The memories of a namespace, core files by path or archival facts newest first.
create or replace function ${fn("memory_list")}(tenant ${id}, ns jsonb default '{}', kind text default 'core', max_rows integer default 200)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare${declare}
  v_rows jsonb;
begin${namespace("memory_list", false)}
  select coalesce(jsonb_agg(${memoryJson("x")} order by x.${m.path}, ${createdAt("x")} desc), '[]') into v_rows
  from (
    select * from ${memories} y
    where ${inNamespace("y", "memory_list.tenant")}${fresh("y")} and ${asText(ctx, "memories", `y.${m.kind}`)} = memory_list.kind
    order by y.${m.path}, ${createdAt("y")} desc
    limit least(greatest(memory_list.max_rows, 1), 1000)
  ) x;
  return v_rows;
end;
$$;
${userGrant(signature("memory_list", `${id}, jsonb, text, integer`))}

-- Saves an archival fact, with its embedding when the caller has one, a
-- category, a confidence from 0 to 1 that weighs it in searches, and the time
-- it expires.
drop function if exists ${signature("memory_save", `${id}, text, jsonb, ${embedding.type}, text, text`)};
create or replace function ${fn("memory_save")}(
  tenant ${id},
  content text,
  ns jsonb default '{}',
  embedding ${embedding.type} default null,
  model text default null,
  source_message_id text default null,
  category text default null,
  confidence real default null,
  expires_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare${declare}
  v_row ${memories}%rowtype;
begin${namespace("memory_save", true)}
  if coalesce(length(memory_save.content), 0) = 0 then
    ${raise("memory content is empty", "22023", "MEMORY_EMPTY")}
  end if;${checkContent("memory_save.content")}
  if memory_save.confidence is not null and not memory_save.confidence between 0 and 1 then
    ${raise("confidence % is not between 0 and 1", "22023", "MEMORY_CONFIDENCE", "memory_save.confidence")}
  end if;
  if memory_save.category is not null and memory_save.category !~ ${sqlString(CATEGORY_PATTERN)} then
    ${raise("category % is not a lowercase slug", "22023", "MEMORY_CATEGORY", "memory_save.category")}
  end if;
  insert into ${memories} (${m.tenant}, ${m.owner}, ${m.scope}, ${m.agent}, ${m.chat}, ${m.project}${subjectInsert}, ${m.kind}, ${m.content}, ${m.embedding}${savedColumns})
  values (memory_save.tenant, v_owner, ${ctx.cast("memories", "scope", "v_scope")}, v_agent, v_chat, v_project${subjectValues}, 'archival', memory_save.content, memory_save.embedding${savedValues})
  returning * into v_row;${capSql(ctx, limits, m, createdAt("y"))}
  return ${memoryJson("v_row")};
end;
$$;
${userGrant(signature("memory_save", `${id}, text, jsonb, ${embedding.type}, text, text, text, real, timestamptz`))}

-- Archival facts of a namespace ranked by reciprocal rank fusion of vector
-- and full-text search, weighed by confidence, each with its cosine
-- similarity when it has one. Counts each fact it returns as a use.
-- Volatile because it sets hnsw.iterative_scan, which it puts back before
-- returning so the rest of the caller's transaction keeps its own setting.
create or replace function ${fn("memory_search")}(
  tenant ${id},
  query_embedding ${embedding.type} default null,
  query_text text default null,
  ns jsonb default '{}',
  k integer default 8
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare${declare}
  v_rows jsonb;
  v_candidates integer := least(greatest(memory_search.k, 1) * 4, 400);
  v_scan text := current_setting('hnsw.iterative_scan', true);
begin${namespace("memory_search", false)}
  perform set_config('hnsw.iterative_scan', 'relaxed_order', true);
  with scoped as materialized (
    select x.${m.id} as id from ${memories} x
    where ${inNamespace("x", "memory_search.tenant")}${fresh("x")} and x.${m.kind} = 'archival'
  ),
  vector_hits as materialized (
    select t.${m.id} as id, t.${m.embedding} ${embedding.distance} memory_search.query_embedding as distance
    from ${memories} t
    where memory_search.query_embedding is not null and t.${m.embedding} is not null and t.${m.id} in (select scoped.id from scoped)
    order by t.${m.embedding} ${embedding.distance} memory_search.query_embedding
    limit v_candidates
  ),
  vector_ranked as (
    select h.id, h.distance, row_number() over (order by h.distance) as rank from vector_hits h
  ),
  text_ranked as (
    select t.${m.id} as id, row_number() over (order by ts_rank_cd(${tsv("t")}, q) desc) as rank
    from ${memories} t, websearch_to_tsquery(${config}::regconfig, memory_search.query_text) q
    where memory_search.query_text is not null and ${tsv("t")} @@ q and t.${m.id} in (select scoped.id from scoped)
    limit v_candidates
  ),
  fused as materialized (
    select r.id, r.distance, r.score${memory("confidence") ? ` * coalesce(t.${m.confidence}, 1)` : ""} as score
    from (
      select coalesce(v.id, x.id) as id, v.distance,
        coalesce(1.0 / (60 + v.rank), 0) + coalesce(1.0 / (60 + x.rank), 0) as score
      from vector_ranked v full join text_ranked x on x.id = v.id
    ) r join ${memories} t on t.${m.id} = r.id
    order by score desc
    limit least(greatest(memory_search.k, 1), 100)
  )${
    memory("useCount") || memory("lastUsedAt")
      ? `,
  used as (
    update ${memories} t set ${[memory("useCount") ? `${m.useCount} = t.${m.useCount} + 1` : "", memory("lastUsedAt") ? `${m.lastUsedAt} = now()` : ""].filter(Boolean).join(", ")}
    from fused f where t.${m.id} = f.id
  )`
      : ""
  }
  select coalesce(jsonb_agg(${memoryJson("t")} || jsonb_build_object('score', f.score, 'similarity', 1 - f.distance) order by f.score desc), '[]')
  into v_rows
  from fused f join ${memories} t on t.${m.id} = f.id;
  perform set_config('hnsw.iterative_scan', coalesce(nullif(v_scan, ''), 'off'), true);
  return v_rows;
end;
$$;
${userGrant(signature("memory_search", `${id}, ${embedding.type}, text, jsonb, integer`))}

-- Forgets a memory: its owner, an admin for organization or record memory,
-- or the service role. superseded_by points a replaced fact at its
-- successor; otherwise the memory is deleted and stays restorable until
-- purge_memories removes it.
create or replace function ${fn("memory_forget")}(memory_id uuid, superseded_by uuid default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${memories}%rowtype;
begin
  select * into v_row from ${memories} x where x.${m.id} = memory_forget.memory_id;
  if not found or not (${forgetCheck("v_row")}) then
    return false;
  end if;
  if memory_forget.superseded_by is null then
    ${memory("deletedAt") ? `update ${memories} x set ${m.deletedAt} = coalesce(x.${m.deletedAt}, now()), ${m.updatedAt} = now()` : `delete from ${memories} x`} where x.${m.id} = v_row.${m.id};
  else
    update ${memories} x set ${m.supersededBy} = memory_forget.superseded_by, ${m.updatedAt} = now() where x.${m.id} = v_row.${m.id};
  end if;
  return true;
end;
$$;
${userGrant(signature("memory_forget", "uuid, uuid"))}
${memory("deletedAt") ? restoreAndPurge() : ""}
-- content_hash is the md5 of the content that was embedded: a memory edited
-- since then keeps waiting instead of taking a vector of its old text.
drop function if exists ${signature("set_memory_embedding", `uuid, ${embedding.type}, text`)};
create or replace function ${fn("set_memory_embedding")}(memory_id uuid, embedding ${embedding.type}, model text default null, content_hash text default null)
returns boolean
language sql
security definer
set search_path = ''
as $$
  update ${memories} x set ${m.embedding} = set_memory_embedding.embedding${memory("model") ? `, ${m.model} = set_memory_embedding.model` : ""}
  where x.${m.id} = set_memory_embedding.memory_id
    and (set_memory_embedding.content_hash is null or md5(x.${m.content}) = set_memory_embedding.content_hash)
  returning true
$$;
${serviceGrant(signature("set_memory_embedding", `uuid, ${embedding.type}, text, text`))}

-- Stores embeddings for many memories ({"items": [{"id", "hash", "embedding"}]})
-- and returns how many it stored; one whose content no longer matches its
-- hash keeps waiting.
create or replace function ${fn("set_memory_embeddings")}(items jsonb, model text default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_items jsonb := case when jsonb_typeof(set_memory_embeddings.items) = 'object' then set_memory_embeddings.items -> 'items' else set_memory_embeddings.items end;
  v_count integer;
begin
  update ${memories} x set
    ${m.embedding} = (e.value ->> 'embedding')::${embedding.column}${memory("model") ? `,\n    ${m.model} = set_memory_embeddings.model` : ""}
  from jsonb_array_elements(case when jsonb_typeof(v_items) = 'array' then v_items else '[]' end) e
  where x.${m.id} = (e.value ->> 'id')::uuid and md5(x.${m.content}) = e.value ->> 'hash';
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
${serviceGrant(signature("set_memory_embeddings", "jsonb, text"))}

-- Memories edited since they were embedded, for the embed worker, with the
-- md5 of each content it passes back to set_memory_embeddings.
create or replace function ${fn("pending_memory_embeddings")}(batch integer default 64)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x.${m.id}, 'content', x.${m.content}, 'hash', md5(x.${m.content}))), '[]')
  from (
    select * from ${memories} y where y.${m.embedding} is null and y.${m.supersededBy} is null${live("y")}${fresh("y")}
    order by y.${m.updatedAt}
    limit least(greatest(pending_memory_embeddings.batch, 1), 2048)
  ) x
$$;
${serviceGrant(signature("pending_memory_embeddings", "integer"))}

-- Stores a message's embedding. Returns false for temporary chats.
create or replace function ${fn("set_ai_message_embedding")}(
  chat_id uuid,
  message_id text,
  user_id uuid,
  tenant ${id},
  embedding ${embedding.type},
  model text default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin${temporaryCheck}
  insert into ${messageEmbeddings} (${e.chat}, ${e.message}, ${e.user}, ${e.tenant}, ${e.embedding}${message("model") ? `, ${e.model}` : ""})
  values (set_ai_message_embedding.chat_id, set_ai_message_embedding.message_id, set_ai_message_embedding.user_id, set_ai_message_embedding.tenant, set_ai_message_embedding.embedding${message("model") ? ", set_ai_message_embedding.model" : ""})
  on conflict (${e.chat}, ${e.message}) do update set ${e.embedding} = excluded.${e.embedding}${message("model") ? `, ${e.model} = excluded.${e.model}` : ""};
  return true;
end;
$$;
${serviceGrant(signature("set_ai_message_embedding", `uuid, text, uuid, ${id}, ${embedding.type}, text`))}

-- The caller's earlier messages closest to a query, other than in
-- exclude_chat. Volatile and restores hnsw.iterative_scan, as memory_search.
create or replace function ${fn("recall_ai_messages")}(
  tenant ${id},
  query_embedding ${embedding.type},
  k integer default 5,
  exclude_chat uuid default null,
  owner uuid default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user uuid := case when ${SERVICE_CALLER} then recall_ai_messages.owner else auth.uid() end;
  v_rows jsonb;
  v_scan text := current_setting('hnsw.iterative_scan', true);
begin
  if v_user is null then
    return '[]';
  end if;
  perform set_config('hnsw.iterative_scan', 'relaxed_order', true);
  select coalesce(jsonb_agg(jsonb_build_object('chat_id', r.chat_id, 'message_id', r.message_id, 'similarity', 1 - r.distance) order by r.distance), '[]')
  into v_rows
  from (
    select x.${e.chat} as chat_id, x.${e.message} as message_id, x.${e.embedding} ${embedding.distance} recall_ai_messages.query_embedding as distance
    from ${messageEmbeddings} x
    where x.${e.user} = v_user and x.${e.tenant} = recall_ai_messages.tenant
      and x.${e.chat} is distinct from recall_ai_messages.exclude_chat
    order by x.${e.embedding} ${embedding.distance} recall_ai_messages.query_embedding
    limit least(greatest(recall_ai_messages.k, 1), 50)
  ) r;
  perform set_config('hnsw.iterative_scan', coalesce(nullif(v_scan, ''), 'off'), true);
  return v_rows;
end;
$$;
${userGrant(signature("recall_ai_messages", `${id}, ${embedding.type}, integer, uuid, uuid`))}

${memoryDocumentsSql(ctx, maxContent)}`;
}

function upgradeProjectScope(ctx: BlockSqlContext): string {
  if (!ctx.owns("memories")) {
    return "";
  }

  const memories = ctx.table("memories");
  const chat = ctx.installed("ai-chat") ? ctx.of("ai-chat") : undefined;

  const reference = chat
    ? ` references ${chat.table("projects")} (${chat.col("projects", "id")}) on delete cascade`
    : "";

  return `alter table ${memories} add column if not exists ${ctx.col("memories", "project")} uuid${reference};
${replaceColumnCheck({
  table: memories,
  column: ctx.col("memories", "scope"),
  name: "memories_scope_check",
  expression: `${ctx.col("memories", "scope")} in (${SCOPES})`,
})}
-- The module file creates the path index again with the project column.
${dropPathIndex(memories)}`;
}

/** Drops the path index so the module file creates it with its new columns. */
function dropPathIndex(memories: string): string {
  return `do $$
declare
  v_index regclass;
begin
  select i.indexrelid::regclass into v_index
  from pg_catalog.pg_index i
  join pg_catalog.pg_class c on c.oid = i.indexrelid
  where i.indrelid = ${sqlString(memories)}::regclass and c.relname = 'memories_path_idx';
  if v_index is not null then
    execute format('drop index %s', v_index);
  end if;
end;
$$;`;
}

/**
 * Version 3: memories gain a record scope, a category, a confidence, an expiry,
 * soft deletes and use counts. The module file creates the path index again
 * with the subject columns and without deleted rows.
 */
function upgradeRecordScope(ctx: BlockSqlContext): string {
  if (!ctx.owns("memories")) {
    return "";
  }

  const memories = ctx.table("memories");
  const col = (key: keyof typeof MEMORIES): string => ctx.col("memories", key);

  return `alter table ${memories}
  add column if not exists ${col("subjectType")} text,
  add column if not exists ${col("subjectId")} text,
  add column if not exists ${col("category")} text check (${col("category")} ~ ${sqlString(CATEGORY_PATTERN)}),
  add column if not exists ${col("confidence")} real check (${col("confidence")} between 0 and 1),
  add column if not exists ${col("expiresAt")} timestamptz,
  add column if not exists ${col("deletedAt")} timestamptz,
  add column if not exists ${col("useCount")} integer not null default 0,
  add column if not exists ${col("lastUsedAt")} timestamptz;
${replaceColumnCheck({
  table: memories,
  column: col("scope"),
  name: "memories_scope_check",
  expression: `${col("scope")} in (${SCOPES})`,
})}
do $$
declare
  v_name text;
begin
  for v_name in
    select c.conname from pg_catalog.pg_constraint c
    where c.conrelid = ${sqlString(memories)}::regclass and c.contype = 'c'
      and pg_catalog.pg_get_constraintdef(c.oid) like '%''organization''%IS NULL%'
      and pg_catalog.pg_get_constraintdef(c.oid) not like '%ANY%'
  loop
    execute format('alter table ${memories} drop constraint %I', v_name);
  end loop;
end;
$$;
alter table ${memories} drop constraint if exists ${ctx.naming.rename("memories_owner_check")};
alter table ${memories} add constraint ${ctx.naming.rename("memories_owner_check")} check ((${col("scope")} in (${SHARED})) = (${col("owner")} is null));
alter table ${memories} drop constraint if exists ${ctx.naming.rename("memories_subject_check")};
alter table ${memories} add constraint ${ctx.naming.rename("memories_subject_check")} check ((${col("scope")} = 'record') = (${col("subjectId")} is not null) and (${col("subjectId")} is null) = (${col("subjectType")} is null));
${dropPathIndex(memories)}`;
}

export const MEMORY: BlockSqlDefinition = {
  name: "memory",
  scopes: ["tenant"],
  title: "Memory",
  description:
    "Memory for AI assistants: core memory as files under /memories edited with view, create, str_replace, insert, delete and rename with version checks; archival facts with hybrid similarity search; message embeddings to recall earlier chats, skipped for temporary chats; and versioned documents under an opaque scope key for agent runtimes such as eve.",
  requires: ["memberships", "permissions", "vector-search"],
  integrates: ["ai-chat"],
  target: "schema",
  version: 5,
  names: NAMES,
  upgrades: [
    {
      from: 1,
      description:
        "Memories gain a project scope: a project_id column, the scope check allows 'project', and the path index covers the project.",
      sql: upgradeProjectScope,
    },
    {
      from: 2,
      description:
        "Memories gain a record scope, a category, a confidence, an expiry, soft deletes with restore and purge, and use counts. The path index covers the subject and skips deleted rows.",
      sql: upgradeRecordScope,
    },
    {
      from: 3,
      description:
        "Organization and record memory may have an owner (ns.private), options.tenant: false lets personal memory have no tenant, options.maxItems caps archival facts, and purge_memories takes a tenant.",
      sql: upgradeOwners,
    },
  ],
  build,
};
