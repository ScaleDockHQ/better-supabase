-- better-supabase module: memory (0.5.1)
-- @bs-module memory@1 managed
-- Memory for AI assistants: core memory as files under /memories edited with view, create, str_replace, insert, delete and rename with version checks; archival facts with hybrid similarity search; and message embeddings to recall earlier chats, skipped for temporary chats.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Memory for AI assistants. Core memory is a small set of files under
-- /memories that the model reads and edits with view, create, str_replace,
-- insert, delete and rename; archival memory is a list of facts found by
-- similarity. Each belongs to a user, an agent, a chat or the organization.
create table if not exists "better_supabase"."memories" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null,
  "owner_id" uuid references auth.users (id) on delete cascade,
  "scope" text not null default 'user' check ("scope" in ('user', 'agent', 'chat', 'organization')),
  "agent_id" uuid,
  "chat_id" uuid references "better_supabase"."ai_chats" ("id") on delete cascade,
  "kind" text not null check ("kind" in ('core', 'archival')),
  "path" text check ("path" ~ '^/memories(/[A-Za-z0-9._ -]+)*$' and "path" !~ '(^|/)[.]{1,2}(/|$)'),
  "content" text not null check (length("content") <= 100000),
  "version" integer not null default 1,
  "embedding" extensions.vector(1536),
  "embedding_model" text,
  "source_message_id" text,
  "superseded_by" uuid references "better_supabase"."memories" ("id") on delete set null,
  "tsv" tsvector generated always as (to_tsvector('simple'::regconfig, "content")) stored,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check (("kind" = 'core') = ("path" is not null)),
  check (("scope" = 'organization') = ("owner_id" is null))
);
create unique index if not exists memories_path_idx on "better_supabase"."memories" ("organization_id", "owner_id", "scope", "agent_id", "chat_id", "path") nulls not distinct
  where "path" is not null and "superseded_by" is null;
create index if not exists memories_owner_idx on "better_supabase"."memories" ("owner_id", "organization_id") where "owner_id" is not null;
create index if not exists memories_tenant_idx on "better_supabase"."memories" ("organization_id", "scope");
create index if not exists memories_chat_idx on "better_supabase"."memories" ("chat_id") where "chat_id" is not null;
create index if not exists memories_superseded_idx on "better_supabase"."memories" ("superseded_by") where "superseded_by" is not null;
create index if not exists memories_embedding_idx on "better_supabase"."memories" using hnsw ("embedding" extensions.vector_cosine_ops);
create index if not exists memories_tsv_idx on "better_supabase"."memories" using gin ("tsv");
alter table "better_supabase"."memories" enable row level security;
revoke all on "better_supabase"."memories" from anon, authenticated;
grant select on "better_supabase"."memories" to authenticated;
grant all on "better_supabase"."memories" to service_role;
drop policy if exists memories_read on "better_supabase"."memories";
create policy memories_read on "better_supabase"."memories" for select to authenticated
  using ("owner_id" = (select auth.uid()) or ("scope" = 'organization' and "organization_id" in (select better_supabase.tenant_ids_with('ai_chat.read'))));

-- One embedding per message, so an assistant can recall earlier chats.
-- Temporary chats get none.
create table if not exists "better_supabase"."ai_message_embeddings" (
  "chat_id" uuid not null references "better_supabase"."ai_chats" ("id") on delete cascade,
  "message_id" text not null,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "organization_id" uuid not null,
  "embedding" extensions.vector(1536) not null,
  "embedding_model" text,
  "created_at" timestamptz not null default now(),
  primary key ("chat_id", "message_id")
);
create index if not exists ai_message_embeddings_user_idx on "better_supabase"."ai_message_embeddings" ("user_id", "organization_id");
create index if not exists ai_message_embeddings_embedding_idx on "better_supabase"."ai_message_embeddings" using hnsw ("embedding" extensions.vector_cosine_ops);
alter table "better_supabase"."ai_message_embeddings" enable row level security;
revoke all on "better_supabase"."ai_message_embeddings" from anon, authenticated;
grant select on "better_supabase"."ai_message_embeddings" to authenticated;
grant all on "better_supabase"."ai_message_embeddings" to service_role;
drop policy if exists ai_message_embeddings_read on "better_supabase"."ai_message_embeddings";
create policy ai_message_embeddings_read on "better_supabase"."ai_message_embeddings" for select to authenticated
  using ("user_id" = (select auth.uid()));

-- A core memory file, or the files under a directory, or null.
create or replace function "better_supabase"."memory_view"(tenant uuid, path text default '/memories', ns jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
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
$$;
revoke execute on function "better_supabase"."memory_view"(uuid, text, jsonb) from public, anon;
grant execute on function "better_supabase"."memory_view"(uuid, text, jsonb) to authenticated, service_role;

-- Creates or overwrites a core memory file. expected_version 0 means the
-- file must not exist yet; another number must match its version.
create or replace function "better_supabase"."memory_create"(tenant uuid, path text, content text, ns jsonb default '{}', expected_version integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
$$;
revoke execute on function "better_supabase"."memory_create"(uuid, text, text, jsonb, integer) from public, anon;
grant execute on function "better_supabase"."memory_create"(uuid, text, text, jsonb, integer) to authenticated, service_role;

-- Replaces old_text with new_text in a core memory file; old_text has to
-- appear exactly once.
create or replace function "better_supabase"."memory_str_replace"(tenant uuid, path text, old_text text, new_text text, ns jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
$$;
revoke execute on function "better_supabase"."memory_str_replace"(uuid, text, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."memory_str_replace"(uuid, text, text, text, jsonb) to authenticated, service_role;

-- Inserts text after line insert_line (0 inserts at the top).
create or replace function "better_supabase"."memory_insert"(tenant uuid, path text, insert_line integer, insert_text text, ns jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
$$;
revoke execute on function "better_supabase"."memory_insert"(uuid, text, integer, text, jsonb) from public, anon;
grant execute on function "better_supabase"."memory_insert"(uuid, text, integer, text, jsonb) to authenticated, service_role;

-- Deletes a file, or a directory and everything under it. Returns the count.
create or replace function "better_supabase"."memory_delete"(tenant uuid, path text, ns jsonb default '{}')
returns integer
language plpgsql
security definer
set search_path = ''
as $$
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
$$;
revoke execute on function "better_supabase"."memory_delete"(uuid, text, jsonb) from public, anon;
grant execute on function "better_supabase"."memory_delete"(uuid, text, jsonb) to authenticated, service_role;

-- Moves a file or a directory. Fails when the target already exists.
create or replace function "better_supabase"."memory_rename"(tenant uuid, old_path text, new_path text, ns jsonb default '{}')
returns integer
language plpgsql
security definer
set search_path = ''
as $$
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
$$;
revoke execute on function "better_supabase"."memory_rename"(uuid, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."memory_rename"(uuid, text, text, jsonb) to authenticated, service_role;

-- The memories of a namespace, core files by path or archival facts newest first.
create or replace function "better_supabase"."memory_list"(tenant uuid, ns jsonb default '{}', kind text default 'core', max_rows integer default 200)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
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
$$;
revoke execute on function "better_supabase"."memory_list"(uuid, jsonb, text, integer) from public, anon;
grant execute on function "better_supabase"."memory_list"(uuid, jsonb, text, integer) to authenticated, service_role;

-- Saves an archival fact, with its embedding when the caller has one.
create or replace function "better_supabase"."memory_save"(
  tenant uuid,
  content text,
  ns jsonb default '{}',
  embedding extensions.vector default null,
  model text default null,
  source_message_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
$$;
revoke execute on function "better_supabase"."memory_save"(uuid, text, jsonb, extensions.vector, text, text) from public, anon;
grant execute on function "better_supabase"."memory_save"(uuid, text, jsonb, extensions.vector, text, text) to authenticated, service_role;

-- Archival facts of a namespace ranked by reciprocal rank fusion of vector
-- and full-text search, each with its cosine similarity when it has one.
create or replace function "better_supabase"."memory_search"(
  tenant uuid,
  query_embedding extensions.vector default null,
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
$$;
revoke execute on function "better_supabase"."memory_search"(uuid, extensions.vector, text, jsonb, integer) from public, anon;
grant execute on function "better_supabase"."memory_search"(uuid, extensions.vector, text, jsonb, integer) to authenticated, service_role;

-- Forgets a memory: its owner, an admin for organization memory, or the
-- service role. superseded_by points a replaced fact at its successor.
create or replace function "better_supabase"."memory_forget"(memory_id uuid, superseded_by uuid default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
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
$$;
revoke execute on function "better_supabase"."memory_forget"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."memory_forget"(uuid, uuid) to authenticated, service_role;

create or replace function "better_supabase"."set_memory_embedding"(memory_id uuid, embedding extensions.vector, model text default null)
returns boolean
language sql
security definer
set search_path = ''
as $$
  update "better_supabase"."memories" x set "embedding" = set_memory_embedding.embedding, "embedding_model" = set_memory_embedding.model
  where x."id" = set_memory_embedding.memory_id
  returning true
$$;
revoke execute on function "better_supabase"."set_memory_embedding"(uuid, extensions.vector, text) from public, anon, authenticated;
grant execute on function "better_supabase"."set_memory_embedding"(uuid, extensions.vector, text) to service_role;

-- Memories edited since they were embedded, for the embed worker.
create or replace function "better_supabase"."pending_memory_embeddings"(batch integer default 64)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'content', x."content")), '[]')
  from (
    select * from "better_supabase"."memories" y where y."embedding" is null and y."superseded_by" is null
    order by y."updated_at"
    limit least(greatest(pending_memory_embeddings.batch, 1), 2048)
  ) x
$$;
revoke execute on function "better_supabase"."pending_memory_embeddings"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."pending_memory_embeddings"(integer) to service_role;

-- Stores a message's embedding. Returns false for temporary chats.
create or replace function "better_supabase"."set_ai_message_embedding"(
  chat_id uuid,
  message_id text,
  user_id uuid,
  tenant uuid,
  embedding extensions.vector,
  model text default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
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
$$;
revoke execute on function "better_supabase"."set_ai_message_embedding"(uuid, text, uuid, uuid, extensions.vector, text) from public, anon, authenticated;
grant execute on function "better_supabase"."set_ai_message_embedding"(uuid, text, uuid, uuid, extensions.vector, text) to service_role;

-- The caller's earlier messages closest to a query, other than in exclude_chat.
create or replace function "better_supabase"."recall_ai_messages"(
  tenant uuid,
  query_embedding extensions.vector,
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
$$;
revoke execute on function "better_supabase"."recall_ai_messages"(uuid, extensions.vector, integer, uuid, uuid) from public, anon;
grant execute on function "better_supabase"."recall_ai_messages"(uuid, extensions.vector, integer, uuid, uuid) to authenticated, service_role;

-- sql.modules.memory.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."memory_view"(tenant uuid, path text default '/memories', ns jsonb default '{}')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."memory_view"($1, $2, $3) $$;
revoke execute on function "api"."memory_view"(uuid, text, jsonb) from public, anon;
grant execute on function "api"."memory_view"(uuid, text, jsonb) to authenticated, service_role;

create or replace function "api"."memory_create"(tenant uuid, path text, content text, ns jsonb default '{}', expected_version integer default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."memory_create"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."memory_create"(uuid, text, text, jsonb, integer) from public, anon;
grant execute on function "api"."memory_create"(uuid, text, text, jsonb, integer) to authenticated, service_role;

create or replace function "api"."memory_str_replace"(tenant uuid, path text, old_text text, new_text text, ns jsonb default '{}')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."memory_str_replace"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."memory_str_replace"(uuid, text, text, text, jsonb) from public, anon;
grant execute on function "api"."memory_str_replace"(uuid, text, text, text, jsonb) to authenticated, service_role;

create or replace function "api"."memory_insert"(tenant uuid, path text, insert_line integer, insert_text text, ns jsonb default '{}')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."memory_insert"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."memory_insert"(uuid, text, integer, text, jsonb) from public, anon;
grant execute on function "api"."memory_insert"(uuid, text, integer, text, jsonb) to authenticated, service_role;

create or replace function "api"."memory_delete"(tenant uuid, path text, ns jsonb default '{}')
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."memory_delete"($1, $2, $3) $$;
revoke execute on function "api"."memory_delete"(uuid, text, jsonb) from public, anon;
grant execute on function "api"."memory_delete"(uuid, text, jsonb) to authenticated, service_role;

create or replace function "api"."memory_rename"(tenant uuid, old_path text, new_path text, ns jsonb default '{}')
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."memory_rename"($1, $2, $3, $4) $$;
revoke execute on function "api"."memory_rename"(uuid, text, text, jsonb) from public, anon;
grant execute on function "api"."memory_rename"(uuid, text, text, jsonb) to authenticated, service_role;

create or replace function "api"."memory_list"(tenant uuid, ns jsonb default '{}', kind text default 'core', max_rows integer default 200)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."memory_list"($1, $2, $3, $4) $$;
revoke execute on function "api"."memory_list"(uuid, jsonb, text, integer) from public, anon;
grant execute on function "api"."memory_list"(uuid, jsonb, text, integer) to authenticated, service_role;

create or replace function "api"."memory_save"(tenant uuid, content text, ns jsonb default '{}', embedding extensions.vector default null, model text default null, source_message_id text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."memory_save"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."memory_save"(uuid, text, jsonb, extensions.vector, text, text) from public, anon;
grant execute on function "api"."memory_save"(uuid, text, jsonb, extensions.vector, text, text) to authenticated, service_role;

create or replace function "api"."memory_search"(tenant uuid, query_embedding extensions.vector default null, query_text text default null, ns jsonb default '{}', k integer default 8)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."memory_search"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."memory_search"(uuid, extensions.vector, text, jsonb, integer) from public, anon;
grant execute on function "api"."memory_search"(uuid, extensions.vector, text, jsonb, integer) to authenticated, service_role;

create or replace function "api"."memory_forget"(memory_id uuid, superseded_by uuid default null)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."memory_forget"($1, $2) $$;
revoke execute on function "api"."memory_forget"(uuid, uuid) from public, anon;
grant execute on function "api"."memory_forget"(uuid, uuid) to authenticated, service_role;

create or replace function "api"."set_memory_embedding"(memory_id uuid, embedding extensions.vector, model text default null)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_memory_embedding"($1, $2, $3) $$;
revoke execute on function "api"."set_memory_embedding"(uuid, extensions.vector, text) from public, anon, authenticated;
grant execute on function "api"."set_memory_embedding"(uuid, extensions.vector, text) to service_role;

create or replace function "api"."pending_memory_embeddings"(batch integer default 64)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."pending_memory_embeddings"($1) $$;
revoke execute on function "api"."pending_memory_embeddings"(integer) from public, anon, authenticated;
grant execute on function "api"."pending_memory_embeddings"(integer) to service_role;

create or replace function "api"."set_ai_message_embedding"(chat_id uuid, message_id text, user_id uuid, tenant uuid, embedding extensions.vector, model text default null)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_ai_message_embedding"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."set_ai_message_embedding"(uuid, text, uuid, uuid, extensions.vector, text) from public, anon, authenticated;
grant execute on function "api"."set_ai_message_embedding"(uuid, text, uuid, uuid, extensions.vector, text) to service_role;

create or replace function "api"."recall_ai_messages"(tenant uuid, query_embedding extensions.vector, k integer default 5, exclude_chat uuid default null, owner uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."recall_ai_messages"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."recall_ai_messages"(uuid, extensions.vector, integer, uuid, uuid) from public, anon;
grant execute on function "api"."recall_ai_messages"(uuid, extensions.vector, integer, uuid, uuid) to authenticated, service_role;

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
