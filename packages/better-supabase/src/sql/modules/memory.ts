import type { ModuleContext, ModuleNames } from "../context.ts";
import type { ModuleDefinition, ModuleLayout } from "../registry.ts";

import { sqlString } from "../../core/template.ts";
import { schemaPreamble, SERVICE_CALLER, tenantIn } from "../shared.ts";
import { MODULE_PERMISSIONS } from "./access-model.ts";
import { canIn, raise, serviceGrant, userGrant } from "./ai-chat-sql.ts";
import { embeddingColumn, textSearchConfig } from "./knowledge.ts";

const MEMORIES = {
  id: "id",
  tenant: "organization_id",
  owner: "owner_id",
  scope: "scope",
  agent: "agent_id",
  chat: "chat_id",
  kind: "kind",
  path: "path",
  content: "content",
  version: "version",
  embedding: "embedding",
  model: "embedding_model",
  sourceMessage: "source_message_id",
  supersededBy: "superseded_by",
  tsv: "tsv",
  createdAt: "created_at",
  updatedAt: "updated_at",
} as const;

const MESSAGE_EMBEDDINGS = {
  chat: "chat_id",
  message: "message_id",
  user: "user_id",
  tenant: "organization_id",
  embedding: "embedding",
  model: "embedding_model",
  createdAt: "created_at",
} as const;

const NAMES: ModuleNames = {
  options: ["dimensions", "type", "textSearch", "maxContent"],
  tables: {
    memories: {
      name: "memories",
      columns: MEMORIES,
      lifecycle: { user: "owner", tenant: "tenant" },
    },
    messageEmbeddings: {
      name: "ai_message_embeddings",
      columns: MESSAGE_EMBEDDINGS,
      lifecycle: { user: "user", tenant: "tenant" },
    },
  },
};

/** A path under `/memories`: segments of letters, digits, dots, dashes, underscores and spaces. */
const PATH_PATTERN = "^/memories(/[A-Za-z0-9._ -]+)*$";
/** A `.` or `..` segment. */
const DOT_SEGMENT = "(^|/)[.]{1,2}(/|$)";

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
  const m = columnsOf(ctx, "memories", MEMORIES);
  const e = columnsOf(ctx, "messageEmbeddings", MESSAGE_EMBEDDINGS);
  const memories = ctx.table("memories");
  const messageEmbeddings = ctx.table("messageEmbeddings");
  const permissions = MODULE_PERMISSIONS.memory;
  const read = ctx.permission("read", permissions.read);
  const manage = ctx.permission("manage", permissions.manage);
  const embedding = embeddingColumn(ctx, layout);
  const config = sqlString(textSearchConfig(ctx));
  const maxContent = ctx.number("maxContent", 100_000);
  if (!Number.isInteger(maxContent) || maxContent < 1) {
    throw new TypeError(
      "sql.modules.memory.options.maxContent must be a positive whole number of characters",
    );
  }
  const chat = ctx.installed("ai-chat") ? ctx.of("ai-chat") : undefined;
  const chatReference = chat
    ? ` references ${chat.table("chats")} (${chat.col("chats", "id")}) on delete cascade`
    : "";
  const temporaryCheck = chat
    ? `
  if exists (select 1 from ${chat.table("chats")} x where x.${chat.col("chats", "id")} = set_ai_message_embedding.chat_id and x.${chat.col("chats", "temporary")}) then
    return false;
  end if;`
    : "";
  const memoryJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${m.id}, 'organization_id', ${row}.${m.tenant}, 'owner_id', ${row}.${m.owner}, 'scope', ${row}.${m.scope}, 'agent_id', ${row}.${m.agent}, 'chat_id', ${row}.${m.chat}, 'kind', ${row}.${m.kind}, 'path', ${row}.${m.path}, 'content', ${row}.${m.content}, 'version', ${row}.${m.version}, 'embedding_model', ${row}.${m.model}, 'source_message_id', ${row}.${m.sourceMessage}, 'created_at', ${row}.${m.createdAt}, 'updated_at', ${row}.${m.updatedAt})`;
  // Every command names its namespace in ns: {"scope", "agent_id",
  // "chat_id"} and, for the service role, "owner_id". Organization memory
  // has no owner and only admins change it.
  const namespace = (name: string, writes: boolean): string => `
  v_scope := coalesce(${name}.ns ->> 'scope', 'user');
  v_agent := (${name}.ns ->> 'agent_id')::uuid;
  v_chat := (${name}.ns ->> 'chat_id')::uuid;
  v_owner := case when v_scope = 'organization' then null when ${SERVICE_CALLER} then (${name}.ns ->> 'owner_id')::uuid else auth.uid() end;
  if not ${SERVICE_CALLER} and (auth.uid() is null or not ${canIn(`${name}.tenant`, read)}) then
    ${raise("you may not use memory here", "42501", "MEMORY_FORBIDDEN")}
  end if;
  if v_scope not in ('user', 'agent', 'chat', 'organization')
    or (v_scope = 'agent') <> (v_agent is not null)
    or (v_scope = 'chat') <> (v_chat is not null)
    or (v_scope <> 'organization' and v_owner is null) then
    ${raise("ns % is not a memory namespace", "22023", "MEMORY_NAMESPACE", `${name}.ns`)}
  end if;${
    writes
      ? `
  if v_scope = 'organization' and not (${SERVICE_CALLER} or ${canIn(`${name}.tenant`, manage)}) then
    ${raise("only admins change organization memory", "42501", "MEMORY_FORBIDDEN")}
  end if;`
      : ""
  }`;
  const declare = `
  v_scope text;
  v_agent uuid;
  v_chat uuid;
  v_owner uuid;`;
  const inNamespace = (row: string, tenant: string): string =>
    `${row}.${m.tenant} = ${tenant} and ${row}.${m.owner} is not distinct from v_owner and ${row}.${m.scope} = v_scope and ${row}.${m.agent} is not distinct from v_agent and ${row}.${m.chat} is not distinct from v_chat and ${row}.${m.supersededBy} is null`;
  const checkPath = (path: string): string => `
  if ${path} is null or length(${path}) > 500 or ${path} !~ ${sqlString(PATH_PATTERN)} or ${path} ~ ${sqlString(DOT_SEGMENT)} then
    ${raise("% is not a path under /memories", "22023", "MEMORY_PATH", path)}
  end if;`;
  const checkContent = (content: string): string => `
  if length(${content}) > ${String(maxContent)} then
    ${raise("memory content is limited to % characters", "22023", "MEMORY_TOO_LARGE", String(maxContent))}
  end if;`;
  const fileNotFound = (path: string): string =>
    raise("% not found", "P0002", "MEMORY_NOT_FOUND", path);
  const signature = (name: string, args: string): string =>
    `${fn(name)}(${args})`;

  return `${schemaPreamble(ctx)}
-- Memory for AI assistants. Core memory is a small set of files under
-- /memories that the model reads and edits with view, create, str_replace,
-- insert, delete and rename; archival memory is a list of facts found by
-- similarity. Each belongs to a user, an agent, a chat or the organization.
create table if not exists ${memories} (
  ${m.id} uuid primary key default gen_random_uuid(),
  ${m.tenant} ${id} not null,
  ${m.owner} uuid references auth.users (id) on delete cascade,
  ${m.scope} text not null default 'user' check (${m.scope} in ('user', 'agent', 'chat', 'organization')),
  ${m.agent} uuid,
  ${m.chat} uuid${chatReference},
  ${m.kind} text not null check (${m.kind} in ('core', 'archival')),
  ${m.path} text check (${m.path} ~ ${sqlString(PATH_PATTERN)} and ${m.path} !~ ${sqlString(DOT_SEGMENT)}),
  ${m.content} text not null check (length(${m.content}) <= ${String(maxContent)}),
  ${m.version} integer not null default 1,
  ${m.embedding} ${embedding.column},
  ${m.model} text,
  ${m.sourceMessage} text,
  ${m.supersededBy} uuid references ${memories} (${m.id}) on delete set null,
  ${m.tsv} tsvector generated always as (to_tsvector(${config}::regconfig, ${m.content})) stored,
  ${m.createdAt} timestamptz not null default now(),
  ${m.updatedAt} timestamptz not null default now(),
  check ((${m.kind} = 'core') = (${m.path} is not null)),
  check ((${m.scope} = 'organization') = (${m.owner} is null))
);
create unique index if not exists memories_path_idx on ${memories} (${m.tenant}, ${m.owner}, ${m.scope}, ${m.agent}, ${m.chat}, ${m.path}) nulls not distinct
  where ${m.path} is not null and ${m.supersededBy} is null;
create index if not exists memories_owner_idx on ${memories} (${m.owner}, ${m.tenant}) where ${m.owner} is not null;
create index if not exists memories_tenant_idx on ${memories} (${m.tenant}, ${m.scope});
create index if not exists memories_chat_idx on ${memories} (${m.chat}) where ${m.chat} is not null;
create index if not exists memories_superseded_idx on ${memories} (${m.supersededBy}) where ${m.supersededBy} is not null;
create index if not exists memories_embedding_idx on ${memories} using hnsw (${m.embedding} ${embedding.opclass});
create index if not exists memories_tsv_idx on ${memories} using gin (${m.tsv});
alter table ${memories} enable row level security;
revoke all on ${memories} from anon, authenticated;
grant select on ${memories} to authenticated;
grant all on ${memories} to service_role;
drop policy if exists memories_read on ${memories};
create policy memories_read on ${memories} for select to authenticated
  using (${m.owner} = (select auth.uid()) or (${m.scope} = 'organization' and ${tenantIn(m.tenant, read)}));

-- One embedding per message, so an assistant can recall earlier chats.
-- Temporary chats get none.
create table if not exists ${messageEmbeddings} (
  ${e.chat} uuid not null${chatReference},
  ${e.message} text not null,
  ${e.user} uuid not null references auth.users (id) on delete cascade,
  ${e.tenant} ${id} not null,
  ${e.embedding} ${embedding.column} not null,
  ${e.model} text,
  ${e.createdAt} timestamptz not null default now(),
  primary key (${e.chat}, ${e.message})
);
create index if not exists ai_message_embeddings_user_idx on ${messageEmbeddings} (${e.user}, ${e.tenant});
create index if not exists ai_message_embeddings_embedding_idx on ${messageEmbeddings} using hnsw (${e.embedding} ${embedding.opclass});
alter table ${messageEmbeddings} enable row level security;
revoke all on ${messageEmbeddings} from anon, authenticated;
grant select on ${messageEmbeddings} to authenticated;
grant all on ${messageEmbeddings} to service_role;
drop policy if exists ai_message_embeddings_read on ${messageEmbeddings};
create policy ai_message_embeddings_read on ${messageEmbeddings} for select to authenticated
  using (${e.user} = (select auth.uid()));

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
    insert into ${memories} (${m.tenant}, ${m.owner}, ${m.scope}, ${m.agent}, ${m.chat}, ${m.kind}, ${m.path}, ${m.content})
    values (memory_create.tenant, v_owner, v_scope, v_agent, v_chat, 'core', memory_create.path, memory_create.content)
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

-- Deletes a file, or a directory and everything under it. Returns the count.
create or replace function ${fn("memory_delete")}(tenant ${id}, path text, ns jsonb default '{}')
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare${declare}
  v_count integer;
begin${namespace("memory_delete", true)}${checkPath("memory_delete.path")}
  delete from ${memories} x
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
  select coalesce(jsonb_agg(${memoryJson("x")} order by x.${m.path}, x.${m.createdAt} desc), '[]') into v_rows
  from (
    select * from ${memories} y
    where ${inNamespace("y", "memory_list.tenant")} and y.${m.kind} = memory_list.kind
    order by y.${m.path}, y.${m.createdAt} desc
    limit least(greatest(memory_list.max_rows, 1), 1000)
  ) x;
  return v_rows;
end;
$$;
${userGrant(signature("memory_list", `${id}, jsonb, text, integer`))}

-- Saves an archival fact, with its embedding when the caller has one.
create or replace function ${fn("memory_save")}(
  tenant ${id},
  content text,
  ns jsonb default '{}',
  embedding ${embedding.type} default null,
  model text default null,
  source_message_id text default null
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
  insert into ${memories} (${m.tenant}, ${m.owner}, ${m.scope}, ${m.agent}, ${m.chat}, ${m.kind}, ${m.content}, ${m.embedding}, ${m.model}, ${m.sourceMessage})
  values (memory_save.tenant, v_owner, v_scope, v_agent, v_chat, 'archival', memory_save.content, memory_save.embedding, memory_save.model, memory_save.source_message_id)
  returning * into v_row;
  return ${memoryJson("v_row")};
end;
$$;
${userGrant(signature("memory_save", `${id}, text, jsonb, ${embedding.type}, text, text`))}

-- Archival facts of a namespace ranked by reciprocal rank fusion of vector
-- and full-text search, each with its cosine similarity when it has one.
create or replace function ${fn("memory_search")}(
  tenant ${id},
  query_embedding ${embedding.type} default null,
  query_text text default null,
  ns jsonb default '{}',
  k integer default 8
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare${declare}
  v_rows jsonb;
  v_candidates integer := least(greatest(memory_search.k, 1) * 4, 400);
begin${namespace("memory_search", false)}
  perform set_config('hnsw.iterative_scan', 'relaxed_order', true);
  with scoped as materialized (
    select x.${m.id} as id from ${memories} x
    where ${inNamespace("x", "memory_search.tenant")} and x.${m.kind} = 'archival'
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
    select t.${m.id} as id, row_number() over (order by ts_rank_cd(t.${m.tsv}, q) desc) as rank
    from ${memories} t, websearch_to_tsquery(${config}::regconfig, memory_search.query_text) q
    where memory_search.query_text is not null and t.${m.tsv} @@ q and t.${m.id} in (select scoped.id from scoped)
    limit v_candidates
  ),
  fused as (
    select coalesce(v.id, x.id) as id, v.distance,
      coalesce(1.0 / (60 + v.rank), 0) + coalesce(1.0 / (60 + x.rank), 0) as score
    from vector_ranked v full join text_ranked x on x.id = v.id
    order by score desc
    limit least(greatest(memory_search.k, 1), 100)
  )
  select coalesce(jsonb_agg(${memoryJson("t")} || jsonb_build_object('score', f.score, 'similarity', 1 - f.distance) order by f.score desc), '[]')
  into v_rows
  from fused f join ${memories} t on t.${m.id} = f.id;
  return v_rows;
end;
$$;
${userGrant(signature("memory_search", `${id}, ${embedding.type}, text, jsonb, integer`))}

-- Forgets a memory: its owner, an admin for organization memory, or the
-- service role. superseded_by points a replaced fact at its successor.
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
  if not found or not (${SERVICE_CALLER} or v_row.${m.owner} = auth.uid() or (v_row.${m.scope} = 'organization' and ${canIn(`v_row.${m.tenant}`, manage)})) then
    return false;
  end if;
  if memory_forget.superseded_by is null then
    delete from ${memories} x where x.${m.id} = v_row.${m.id};
  else
    update ${memories} x set ${m.supersededBy} = memory_forget.superseded_by, ${m.updatedAt} = now() where x.${m.id} = v_row.${m.id};
  end if;
  return true;
end;
$$;
${userGrant(signature("memory_forget", "uuid, uuid"))}

create or replace function ${fn("set_memory_embedding")}(memory_id uuid, embedding ${embedding.type}, model text default null)
returns boolean
language sql
security definer
set search_path = ''
as $$
  update ${memories} x set ${m.embedding} = set_memory_embedding.embedding, ${m.model} = set_memory_embedding.model
  where x.${m.id} = set_memory_embedding.memory_id
  returning true
$$;
${serviceGrant(signature("set_memory_embedding", `uuid, ${embedding.type}, text`))}

-- Memories edited since they were embedded, for the embed worker.
create or replace function ${fn("pending_memory_embeddings")}(batch integer default 64)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x.${m.id}, 'content', x.${m.content})), '[]')
  from (
    select * from ${memories} y where y.${m.embedding} is null and y.${m.supersededBy} is null
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
  insert into ${messageEmbeddings} (${e.chat}, ${e.message}, ${e.user}, ${e.tenant}, ${e.embedding}, ${e.model})
  values (set_ai_message_embedding.chat_id, set_ai_message_embedding.message_id, set_ai_message_embedding.user_id, set_ai_message_embedding.tenant, set_ai_message_embedding.embedding, set_ai_message_embedding.model)
  on conflict (${e.chat}, ${e.message}) do update set ${e.embedding} = excluded.${e.embedding}, ${e.model} = excluded.${e.model};
  return true;
end;
$$;
${serviceGrant(signature("set_ai_message_embedding", `uuid, text, uuid, ${id}, ${embedding.type}, text`))}

-- The caller's earlier messages closest to a query, other than in exclude_chat.
create or replace function ${fn("recall_ai_messages")}(
  tenant ${id},
  query_embedding ${embedding.type},
  k integer default 5,
  exclude_chat uuid default null,
  owner uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := case when ${SERVICE_CALLER} then recall_ai_messages.owner else auth.uid() end;
  v_rows jsonb;
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
  return v_rows;
end;
$$;
${userGrant(signature("recall_ai_messages", `${id}, ${embedding.type}, integer, uuid, uuid`))}`;
}

export const MEMORY: ModuleDefinition = {
  name: "memory",
  title: "Memory",
  description:
    "Memory for AI assistants: core memory as files under /memories edited with view, create, str_replace, insert, delete and rename with version checks; archival facts with hybrid similarity search; and message embeddings to recall earlier chats, skipped for temporary chats.",
  requires: ["tenant", "access", "vector-search"],
  target: "schema",
  version: 1,
  names: NAMES,
  build,
};
