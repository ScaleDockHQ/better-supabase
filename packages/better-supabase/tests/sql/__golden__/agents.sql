-- ==== alone: schema supabase/schemas/900_better_supabase_051_agents.sql
-- better-supabase module: agents
-- @bsb-block agents@2 managed
-- @bsb-hash sha256:0a038f234ca7706b7ef7452283f81c9f5a06ffc780d68d1b5eb600c4ffec5816
-- Custom assistants with instructions, a model, tools, connectors, knowledge scopes and starters; private until published to the organization or the public store, with installs, ratings and provider skills.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Custom assistants: instructions, a model, the tools and connectors they may
-- use and the knowledge they search. An owner keeps an agent private until a
-- member with 'agents.publish' publishes it to the organization or the public store.
create table "better_supabase"."agents" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "owner_id" uuid references auth.users (id) on delete set null,
  "slug" text not null constraint bsb_agents_slug_check check ("slug" ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and length("slug") <= 64),
  "name" text not null constraint bsb_agents_name_check check (length("name") >= 1 and length("name") <= 200),
  "description" text not null default '' constraint bsb_agents_description_check check (length("description") <= 2000),
  "instructions" text not null default '' constraint bsb_agents_instructions_check check (length("instructions") <= 100000),
  "model" text,
  "tools" jsonb not null default '[]' constraint bsb_agents_tools_check check (jsonb_typeof("tools") = 'array'),
  "connector_ids" uuid[] not null default '{}',
  "knowledge_scope" jsonb not null default '[]' constraint bsb_agents_knowledge_scope_check check (jsonb_typeof("knowledge_scope") = 'array'),
  "starters" jsonb not null default '[]' constraint bsb_agents_starters_check check (jsonb_typeof("starters") = 'array'),
  "visibility" text not null default 'private' constraint bsb_agents_visibility_check check ("visibility" in ('private', 'organization', 'public')),
  "published_at" timestamptz,
  "install_count" integer not null default 0,
  "rating_count" integer not null default 0,
  "rating_sum" integer not null default 0,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  "archived_at" timestamptz,
  unique ("tenant_id", "slug")
);
create index agents_owner_idx on "better_supabase"."agents" ("owner_id");
create index agents_published_idx on "better_supabase"."agents" ("visibility", "published_at") where "published_at" is not null;
alter table "better_supabase"."agents" enable row level security;
revoke all on "better_supabase"."agents" from public, anon, authenticated;
grant select on "better_supabase"."agents" to authenticated;
grant all on "better_supabase"."agents" to service_role;
create policy bsb_agents_read on "better_supabase"."agents"
  for select to authenticated
  using (("better_supabase"."agents"."owner_id" = (select auth.uid()) or ("better_supabase"."agents"."published_at" is not null and ("better_supabase"."agents"."visibility" = 'public' or ("better_supabase"."agents"."visibility" = 'organization' and "better_supabase"."agents"."tenant_id" in (select better_supabase.tenant_ids_with('agents.read'))))) or "better_supabase"."agents"."tenant_id" in (select better_supabase.tenant_ids_with('agents.moderate'))));

create table "better_supabase"."agent_installs" (
  "agent_id" uuid not null references "better_supabase"."agents" ("id") on delete cascade,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "tenant_id" uuid not null,
  "installed_at" timestamptz not null default now(),
  primary key ("agent_id", "user_id", "tenant_id")
);
create index agent_installs_user_idx on "better_supabase"."agent_installs" ("user_id", "tenant_id");
alter table "better_supabase"."agent_installs" enable row level security;
revoke all on "better_supabase"."agent_installs" from public, anon, authenticated;
grant select on "better_supabase"."agent_installs" to authenticated;
grant all on "better_supabase"."agent_installs" to service_role;
create policy bsb_agent_installs_read on "better_supabase"."agent_installs"
  for select to authenticated
  using ("user_id" = (select auth.uid()));

create table "better_supabase"."agent_ratings" (
  "agent_id" uuid not null references "better_supabase"."agents" ("id") on delete cascade,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "rating" smallint not null constraint bsb_agent_ratings_rating_check check ("rating" >= 1 and "rating" <= 5),
  "comment" text constraint bsb_agent_ratings_comment_check check (length("comment") <= 2000),
  "created_at" timestamptz not null default now(),
  primary key ("agent_id", "user_id")
);
create index agent_ratings_user_idx on "better_supabase"."agent_ratings" ("user_id");
alter table "better_supabase"."agent_ratings" enable row level security;
revoke all on "better_supabase"."agent_ratings" from public, anon, authenticated;
grant select on "better_supabase"."agent_ratings" to authenticated;
grant all on "better_supabase"."agent_ratings" to service_role;
create policy bsb_agent_ratings_read on "better_supabase"."agent_ratings"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."agents" x where x."id" = "agent_id"));

-- Skills an agent loads from a provider (a reference such as a skill id).
create table "better_supabase"."agent_skills" (
  "id" uuid primary key default gen_random_uuid(),
  "agent_id" uuid not null references "better_supabase"."agents" ("id") on delete cascade,
  "provider" text not null constraint bsb_agent_skills_provider_check check (length("provider") >= 1 and length("provider") <= 100),
  "reference" jsonb not null constraint bsb_agent_skills_reference_check check (jsonb_typeof("reference") = 'object'),
  -- Skill files kept in Storage (a list of {path, object}), the hash of their
  -- bytes, and the reference each provider returned for that hash.
  "name" text,
  "files" jsonb not null default '[]' constraint bsb_agent_skills_files_check check (jsonb_typeof("files") = 'array'),
  "content_hash" text,
  "latest_version" text,
  "provider_refs" jsonb not null default '{}' constraint bsb_agent_skills_provider_refs_check check (jsonb_typeof("provider_refs") = 'object'),
  "created_at" timestamptz not null default now()
);
create index agent_skills_agent_idx on "better_supabase"."agent_skills" ("agent_id");
alter table "better_supabase"."agent_skills" enable row level security;
revoke all on "better_supabase"."agent_skills" from public, anon, authenticated;
grant select on "better_supabase"."agent_skills" to authenticated;
grant all on "better_supabase"."agent_skills" to service_role;
create policy bsb_agent_skills_read on "better_supabase"."agent_skills"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."agents" x where x."id" = "agent_id"));

-- Creates an agent (id null, needs 'agents.write') or changes one its owner or a
-- moderator may change. fields holds the columns to set; visibility and
-- published_at change through publish_agent only.
create or replace function "better_supabase"."save_agent"(tenant uuid, id uuid default null, fields jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."agents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(save_agent.fields) is distinct from 'object' then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  if save_agent.id is null then
    if auth.uid() is null or not coalesce(better_supabase.can('tenant', save_agent.tenant, 'agents.write'), false) then
      raise exception 'you may not create agents here' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
    end if;
    if save_agent.fields ->> 'slug' is null or save_agent.fields ->> 'name' is null then
      raise exception 'a new agent needs a slug and a name' using errcode = '22023', hint = 'AGENT_INVALID';
    end if;
    insert into "better_supabase"."agents" ("tenant_id", "owner_id", "slug", "name")
    values (save_agent.tenant, auth.uid(), save_agent.fields ->> 'slug', save_agent.fields ->> 'name')
    returning * into v_row;
  else
    select * into v_row from "better_supabase"."agents" x where x."id" = save_agent.id and x."tenant_id" = save_agent.tenant for update;
    if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)) then
      raise exception 'agent % not found', save_agent.id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
    end if;
    if v_row."archived_at" is not null then
    raise exception 'agent is archived; restore it first' using errcode = '55000', hint = 'AGENT_ARCHIVED';
  end if;
  
  end if;
  update "better_supabase"."agents" x set
    "slug" = coalesce(save_agent.fields ->> 'slug', x."slug"),
    "name" = coalesce(save_agent.fields ->> 'name', x."name"),
    "description" = coalesce(save_agent.fields ->> 'description', x."description"),
    "instructions" = coalesce(save_agent.fields ->> 'instructions', x."instructions"),
    "model" = case when save_agent.fields ? 'model' then save_agent.fields ->> 'model' else x."model" end,
    "tools" = coalesce(save_agent.fields -> 'tools', x."tools"),
    "connector_ids" = case when save_agent.fields ? 'connector_ids'
      then array(select jsonb_array_elements_text(save_agent.fields -> 'connector_ids')::uuid)
      else x."connector_ids" end,
    "knowledge_scope" = coalesce(save_agent.fields -> 'knowledge_scope', x."knowledge_scope"),
    "starters" = coalesce(save_agent.fields -> 'starters', x."starters"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if save_agent.id is null then
    null;
  else
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
exception
  when unique_violation then
    raise exception 'an agent with slug % exists', save_agent.fields ->> 'slug' using errcode = '23505', hint = 'AGENT_SLUG_TAKEN';
end;
$$;
revoke execute on function "better_supabase"."save_agent"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_agent"(uuid, uuid, jsonb) to authenticated, service_role;

-- Publishes an agent to the organization or the public store, or makes it
-- private again. The owner needs 'agents.publish'; a moderator may always unpublish.
create or replace function "better_supabase"."publish_agent"(id uuid, visibility text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."agents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if publish_agent.visibility is null or publish_agent.visibility not in ('private', 'organization', 'public') then
    raise exception 'visibility is private, organization or public' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = publish_agent.id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)) then
    raise exception 'agent % not found', publish_agent.id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if v_row."archived_at" is not null then
    raise exception 'agent is archived; restore it first' using errcode = '55000', hint = 'AGENT_ARCHIVED';
  end if;
    if publish_agent.visibility <> 'private' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)
    or (coalesce(v_row."owner_id" = auth.uid(), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.publish'), false))) then
    raise exception 'you may not publish agents here' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
  end if;
  update "better_supabase"."agents" x set
    "visibility" = publish_agent.visibility,
    "published_at" = case when publish_agent.visibility = 'private' then null else coalesce(x."published_at", now()) end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
end;
$$;
revoke execute on function "better_supabase"."publish_agent"(uuid, text) from public, anon;
grant execute on function "better_supabase"."publish_agent"(uuid, text) to authenticated, service_role;

-- Archives an agent: it leaves the store, the lists and new installs, and it can't be changed, published or rated until it is restored. Installs, ratings and skills stay. The owner or a moderator may; archiving an archived agent returns it unchanged.
create or replace function "better_supabase"."archive_agent"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."agents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = archive_agent.id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)) then
    raise exception 'agent % not found', archive_agent.id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if (v_row."archived_at" is not null) = true then
    return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
  end if;
  update "better_supabase"."agents" x set "archived_at" = now(), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
end;
$$;
revoke execute on function "better_supabase"."archive_agent"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_agent"(uuid) to authenticated, service_role;

-- Restores an archived agent with the visibility it had. The owner or a moderator may; restoring one that is not archived returns it unchanged.
create or replace function "better_supabase"."restore_agent"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."agents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = restore_agent.id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)) then
    raise exception 'agent % not found', restore_agent.id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if (v_row."archived_at" is not null) = false then
    return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
  end if;
  update "better_supabase"."agents" x set "archived_at" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
end;
$$;
revoke execute on function "better_supabase"."restore_agent"(uuid) from public, anon;
grant execute on function "better_supabase"."restore_agent"(uuid) to authenticated, service_role;

-- Deletes an agent for good with its installs, ratings and skills; archive
-- keeps them. Needs 'agents.moderate', which falls back to the moderate key, and the
-- owner needs it too. False when the caller can't see the agent.

create or replace function "better_supabase"."purge_agent"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."agents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = purge_agent.id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)) then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)) then
    raise exception 'you may not purge agents here' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
  end if;
  delete from "better_supabase"."agents" x where x."id" = v_row."id";
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."purge_agent"(uuid) from public, anon;
grant execute on function "better_supabase"."purge_agent"(uuid) to authenticated, service_role;

-- An agent by id or by slug in a tenant, with its skills, when the caller may read it.
create or replace function "better_supabase"."get_agent"(id uuid default null, tenant uuid default null, slug text default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_row "better_supabase"."agents"%rowtype;
begin
  select * into v_row from "better_supabase"."agents" x
  where (get_agent.id is not null and x."id" = get_agent.id)
    or (get_agent.id is null and x."tenant_id" = get_agent.tenant and x."slug" = get_agent.slug);
  if not found then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at") || jsonb_build_object(
    'skills', coalesce((select jsonb_agg(jsonb_build_object('id', k."id", 'provider', k."provider", 'reference', k."reference", 'name', k."name", 'files', k."files", 'content_hash', k."content_hash", 'latest_version', k."latest_version", 'provider_refs', k."provider_refs") order by k."created_at") from "better_supabase"."agent_skills" k where k."agent_id" = v_row."id"), '[]'),
    'installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = v_row."id" and n."user_id" = auth.uid()),
    'my_rating', (select g."rating" from "better_supabase"."agent_ratings" g where g."agent_id" = v_row."id" and g."user_id" = auth.uid())
  );
end;
$$;
revoke execute on function "better_supabase"."get_agent"(uuid, uuid, text) from public, anon;
grant execute on function "better_supabase"."get_agent"(uuid, uuid, text) to authenticated, service_role;

-- Agents the caller may read: 'mine', 'installed' in the tenant, or the
-- 'store' (published to the tenant or public), newest first. Archived agents
-- stay out unless include_archived is true.

create or replace function "better_supabase"."list_agents"(tenant uuid, filter text default 'store', search text default null, max_rows integer default 50, include_archived boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(y.row order by y.at desc), '[]')
  from (
    select jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = list_agents.tenant)) as row,
      coalesce(x."published_at", x."updated_at") as at
    from "better_supabase"."agents" x
    where case list_agents.filter
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = list_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = list_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = list_agents.tenant)
      end
      and (coalesce(list_agents.include_archived, false) or x."archived_at" is null)
      and (list_agents.search is null or x."name" ilike '%' || replace(replace(list_agents.search, '%', '\%'), '_', '\_') || '%'
        or x."description" ilike '%' || replace(replace(list_agents.search, '%', '\%'), '_', '\_') || '%')
    order by coalesce(x."published_at", x."updated_at") desc
    limit least(greatest(list_agents.max_rows, 1), 200)
  ) y
$$;
revoke execute on function "better_supabase"."list_agents"(uuid, text, text, integer, boolean) from public, anon;
grant execute on function "better_supabase"."list_agents"(uuid, text, text, integer, boolean) to authenticated, service_role;

-- Agents as a keyset page (ADR 1077): the same three modes as list_agents.
-- filters is { mode ('store' by default, 'mine' or 'installed'), visibility (a
-- value or a list), includeArchived, search (name, description), sort (name,
-- updatedAt, createdAt, installCount), direction, facet, count, limit, after,
-- offset, paged, total, totalCap }. The default order is the newest published
-- or updated agent first.
create or replace function "better_supabase"."page_agents"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_agents.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_mode text := coalesce(nullif(coalesce(v_filters #>> '{mode,0}', v_filters ->> 'mode'), ''), 'store');
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if v_mode not in ('store', 'mine', 'installed') then
    raise exception 'mode is store, mine or installed' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'visibility') = 'array' then v_filters -> 'visibility' when jsonb_typeof(v_filters -> 'visibility') in ('string', 'number') then jsonb_build_array(v_filters -> 'visibility') else '[]'::jsonb end) s where s not in ('private', 'organization', 'public')) then
    raise exception 'visibility is private, organization or public' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('visibility') then
      raise exception 'facet is one of visibility' using errcode = '22023', hint = 'AGENT_INVALID';
    end if;
    with s as (
      select (case v_facet when 'visibility' then (x."visibility")::text end) as v
      from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'updatedAt', 'createdAt', 'installCount') then
    raise exception 'sort is one of name, updatedAt, createdAt, installCount' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((coalesce(x."published_at", x."updated_at"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (coalesce(x."published_at", x."updated_at"), x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."published_at", x."updated_at") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((coalesce(x."published_at", x."updated_at"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (coalesce(x."published_at", x."updated_at") <= (v_after ->> 0)::timestamptz and ((coalesce(x."published_at", x."updated_at") < (v_after ->> 0)::timestamptz) or (coalesce(x."published_at", x."updated_at") = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."published_at", x."updated_at") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."updated_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."updated_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."updated_at" <= (v_after ->> 0)::timestamptz and ((x."updated_at" < (v_after ->> 0)::timestamptz) or (x."updated_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."updated_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'installCount' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((coalesce(x."install_count", 0))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (coalesce(x."install_count", 0), x."id") > ((v_after ->> 0)::integer, (v_after ->> 1)::uuid))
      order by coalesce(x."install_count", 0) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'installCount' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((coalesce(x."install_count", 0))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (coalesce(x."install_count", 0) <= (v_after ->> 0)::integer and ((coalesce(x."install_count", 0) < (v_after ->> 0)::integer) or (coalesce(x."install_count", 0) = (v_after ->> 0)::integer and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."install_count", 0) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_agents"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."page_agents"(uuid, jsonb) to authenticated, service_role;

-- Adds a readable agent to the caller's list in a tenant they belong to, or removes it.
create or replace function "better_supabase"."install_agent"(tenant uuid, agent_id uuid, installed boolean default true)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null or not coalesce(better_supabase.can('tenant', install_agent.tenant, 'agents.read'), false) then
    raise exception 'you may not use agents here' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
  end if;
  if not install_agent.installed then
    delete from "better_supabase"."agent_installs" n where n."agent_id" = install_agent.agent_id and n."user_id" = auth.uid() and n."tenant_id" = install_agent.tenant;
    get diagnostics v_count = row_count;
    update "better_supabase"."agents" x set "install_count" = greatest(x."install_count" - v_count, 0) where x."id" = install_agent.agent_id;
    if v_count > 0 then
      null;
    end if;
    return v_count > 0;
  end if;
  if not exists (select 1 from "better_supabase"."agents" x where x."id" = install_agent.agent_id and (x."owner_id" = (select auth.uid()) or (x."published_at" is not null and (x."visibility" = 'public' or (x."visibility" = 'organization' and x."tenant_id" in (select better_supabase.tenant_ids_with('agents.read'))))) or x."tenant_id" in (select better_supabase.tenant_ids_with('agents.moderate')))) then
    raise exception 'agent % not found', install_agent.agent_id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if exists (select 1 from "better_supabase"."agents" x where x."id" = install_agent.agent_id and x."archived_at" is not null) then
    raise exception 'agent is archived; restore it first' using errcode = '55000', hint = 'AGENT_ARCHIVED';
  end if;
  insert into "better_supabase"."agent_installs" ("agent_id", "user_id", "tenant_id") values (install_agent.agent_id, auth.uid(), install_agent.tenant)
  on conflict do nothing;
  get diagnostics v_count = row_count;
  update "better_supabase"."agents" x set "install_count" = x."install_count" + v_count where x."id" = install_agent.agent_id;
  if v_count > 0 then
    null;
  end if;
  return v_count > 0;
end;
$$;
revoke execute on function "better_supabase"."install_agent"(uuid, uuid, boolean) from public, anon;
grant execute on function "better_supabase"."install_agent"(uuid, uuid, boolean) to authenticated, service_role;

-- Rates a readable agent 1 to 5, replacing the caller's rating; null removes it.
create or replace function "better_supabase"."rate_agent"(agent_id uuid, rating integer, comment text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old integer;
  v_row "better_supabase"."agents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    raise exception 'sign in to rate agents' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = rate_agent.agent_id and (x."owner_id" = (select auth.uid()) or (x."published_at" is not null and (x."visibility" = 'public' or (x."visibility" = 'organization' and x."tenant_id" in (select better_supabase.tenant_ids_with('agents.read'))))) or x."tenant_id" in (select better_supabase.tenant_ids_with('agents.moderate'))) for update;
  if not found then
    raise exception 'agent % not found', rate_agent.agent_id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if v_row."archived_at" is not null then
    raise exception 'agent is archived; restore it first' using errcode = '55000', hint = 'AGENT_ARCHIVED';
  end if;
    if rate_agent.rating is not null and rate_agent.rating not between 1 and 5 then
    raise exception 'a rating is 1 to 5' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  delete from "better_supabase"."agent_ratings" g where g."agent_id" = v_row."id" and g."user_id" = auth.uid()
  returning g."rating" into v_old;
  if rate_agent.rating is not null then
    insert into "better_supabase"."agent_ratings" ("agent_id", "user_id", "rating", "comment")
    values (v_row."id", auth.uid(), rate_agent.rating, rate_agent.comment);
  end if;
  update "better_supabase"."agents" x set
    "rating_count" = x."rating_count" - (case when v_old is null then 0 else 1 end) + (case when rate_agent.rating is null then 0 else 1 end),
    "rating_sum" = x."rating_sum" - coalesce(v_old, 0) + coalesce(rate_agent.rating, 0)
  where x."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
end;
$$;
revoke execute on function "better_supabase"."rate_agent"(uuid, integer, text) from public, anon;
grant execute on function "better_supabase"."rate_agent"(uuid, integer, text) to authenticated, service_role;

-- Replaces an agent's skills with a list of {provider, reference}.
create or replace function "better_supabase"."set_agent_skills"(agent_id uuid, skills jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."agents"%rowtype;
  v_items jsonb := case when jsonb_typeof(set_agent_skills.skills) = 'object' then set_agent_skills.skills -> 'items' else set_agent_skills.skills end;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = set_agent_skills.agent_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)) then
    raise exception 'agent % not found', set_agent_skills.agent_id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if v_row."archived_at" is not null then
    raise exception 'agent is archived; restore it first' using errcode = '55000', hint = 'AGENT_ARCHIVED';
  end if;
    if jsonb_typeof(v_items) is distinct from 'array' then
    raise exception 'skills must be a list' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  delete from "better_supabase"."agent_skills" k where k."agent_id" = v_row."id";
  insert into "better_supabase"."agent_skills" ("agent_id", "provider", "reference", "name", "files", "content_hash", "latest_version", "provider_refs")
  select v_row."id", e ->> 'provider', coalesce(e -> 'reference', '{}'), e ->> 'name', coalesce(e -> 'files', '[]'), e ->> 'content_hash', e ->> 'latest_version', coalesce(e -> 'provider_refs', '{}')
  from jsonb_array_elements(v_items) e;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."set_agent_skills"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."set_agent_skills"(uuid, jsonb) to authenticated, service_role;

-- Records what a provider returned for a skill's current content: its
-- reference and the hash it was uploaded from. syncSkill calls it as the
-- service role after uploadSkill, and skips the upload while the hash matches.
create or replace function "better_supabase"."record_skill_sync"(skill_id uuid, provider text, reference jsonb, content_hash text)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_row "better_supabase"."agent_skills"%rowtype;
begin
  update "better_supabase"."agent_skills" k
  set "provider_refs" = k."provider_refs" || jsonb_build_object(record_skill_sync.provider, jsonb_build_object('reference', record_skill_sync.reference, 'content_hash', record_skill_sync.content_hash)),
      "content_hash" = record_skill_sync.content_hash
  where k."id" = record_skill_sync.skill_id
  returning * into v_row;
  if not found then
    raise exception 'agent % not found', record_skill_sync.skill_id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  return v_row."provider_refs";
end;
$$;
revoke execute on function "better_supabase"."record_skill_sync"(uuid, text, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."record_skill_sync"(uuid, text, jsonb, text) to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."agents" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (("better_supabase"."agents"."owner_id" = (select auth.uid()) or ("better_supabase"."agents"."published_at" is not null and ("better_supabase"."agents"."visibility" = 'public' or ("better_supabase"."agents"."visibility" = 'organization' and "better_supabase"."agents"."tenant_id" in (select better_supabase.tenant_ids_with('agents.read'))))) or "better_supabase"."agents"."tenant_id" in (select better_supabase.tenant_ids_with('agents.moderate'))))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."agents" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."agents" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."agents" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."agent_installs" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."agent_installs" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."agent_installs" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."agent_installs" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_051_agents.sql
-- better-supabase module: agents
-- @bsb-block-data agents
-- @bsb-hash sha256:89cbc764a7f121e0277343276dfc4456394a839780009117dc1dd6f25a6fbf28
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('agents', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_051_agents.sql
-- better-supabase module: agents
-- @bsb-block agents@2 managed
-- @bsb-hash sha256:1fbb997ee0df2474798f2090df1ab7bcff891c7ed0adad2d871e81847dd36ae7
-- Custom assistants with instructions, a model, tools, connectors, knowledge scopes and starters; private until published to the organization or the public store, with installs, ratings and provider skills.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Custom assistants: instructions, a model, the tools and connectors they may
-- use and the knowledge they search. An owner keeps an agent private until a
-- member with 'agents.publish' publishes it to the organization or the public store.
create table "better_supabase"."agents" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "owner_id" uuid references auth.users (id) on delete set null,
  "slug" text not null constraint bsb_agents_slug_check check ("slug" ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and length("slug") <= 64),
  "name" text not null constraint bsb_agents_name_check check (length("name") >= 1 and length("name") <= 200),
  "description" text not null default '' constraint bsb_agents_description_check check (length("description") <= 2000),
  "instructions" text not null default '' constraint bsb_agents_instructions_check check (length("instructions") <= 100000),
  "model" text,
  "tools" jsonb not null default '[]' constraint bsb_agents_tools_check check (jsonb_typeof("tools") = 'array'),
  "connector_ids" uuid[] not null default '{}',
  "knowledge_scope" jsonb not null default '[]' constraint bsb_agents_knowledge_scope_check check (jsonb_typeof("knowledge_scope") = 'array'),
  "starters" jsonb not null default '[]' constraint bsb_agents_starters_check check (jsonb_typeof("starters") = 'array'),
  "visibility" text not null default 'private' constraint bsb_agents_visibility_check check ("visibility" in ('private', 'organization', 'public')),
  "published_at" timestamptz,
  "install_count" integer not null default 0,
  "rating_count" integer not null default 0,
  "rating_sum" integer not null default 0,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  "archived_at" timestamptz,
  unique ("tenant_id", "slug")
);
create index agents_owner_idx on "better_supabase"."agents" ("owner_id");
create index agents_published_idx on "better_supabase"."agents" ("visibility", "published_at") where "published_at" is not null;
alter table "better_supabase"."agents" enable row level security;
revoke all on "better_supabase"."agents" from public, anon, authenticated;
grant select on "better_supabase"."agents" to authenticated;
grant all on "better_supabase"."agents" to service_role;
create policy bsb_agents_read on "better_supabase"."agents"
  for select to authenticated
  using (("better_supabase"."agents"."owner_id" = (select auth.uid()) or ("better_supabase"."agents"."published_at" is not null and ("better_supabase"."agents"."visibility" = 'public' or ("better_supabase"."agents"."visibility" = 'organization' and "better_supabase"."agents"."tenant_id" in (select better_supabase.tenant_ids_with('agents.read'))))) or "better_supabase"."agents"."tenant_id" in (select better_supabase.tenant_ids_with('agents.moderate'))));

create table "better_supabase"."agent_installs" (
  "agent_id" uuid not null references "better_supabase"."agents" ("id") on delete cascade,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "tenant_id" uuid not null,
  "installed_at" timestamptz not null default now(),
  primary key ("agent_id", "user_id", "tenant_id")
);
create index agent_installs_user_idx on "better_supabase"."agent_installs" ("user_id", "tenant_id");
alter table "better_supabase"."agent_installs" enable row level security;
revoke all on "better_supabase"."agent_installs" from public, anon, authenticated;
grant select on "better_supabase"."agent_installs" to authenticated;
grant all on "better_supabase"."agent_installs" to service_role;
create policy bsb_agent_installs_read on "better_supabase"."agent_installs"
  for select to authenticated
  using ("user_id" = (select auth.uid()));

create table "better_supabase"."agent_ratings" (
  "agent_id" uuid not null references "better_supabase"."agents" ("id") on delete cascade,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "rating" smallint not null constraint bsb_agent_ratings_rating_check check ("rating" >= 1 and "rating" <= 5),
  "comment" text constraint bsb_agent_ratings_comment_check check (length("comment") <= 2000),
  "created_at" timestamptz not null default now(),
  primary key ("agent_id", "user_id")
);
create index agent_ratings_user_idx on "better_supabase"."agent_ratings" ("user_id");
alter table "better_supabase"."agent_ratings" enable row level security;
revoke all on "better_supabase"."agent_ratings" from public, anon, authenticated;
grant select on "better_supabase"."agent_ratings" to authenticated;
grant all on "better_supabase"."agent_ratings" to service_role;
create policy bsb_agent_ratings_read on "better_supabase"."agent_ratings"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."agents" x where x."id" = "agent_id"));

-- Skills an agent loads from a provider (a reference such as a skill id).
create table "better_supabase"."agent_skills" (
  "id" uuid primary key default gen_random_uuid(),
  "agent_id" uuid not null references "better_supabase"."agents" ("id") on delete cascade,
  "provider" text not null constraint bsb_agent_skills_provider_check check (length("provider") >= 1 and length("provider") <= 100),
  "reference" jsonb not null constraint bsb_agent_skills_reference_check check (jsonb_typeof("reference") = 'object'),
  -- Skill files kept in Storage (a list of {path, object}), the hash of their
  -- bytes, and the reference each provider returned for that hash.
  "name" text,
  "files" jsonb not null default '[]' constraint bsb_agent_skills_files_check check (jsonb_typeof("files") = 'array'),
  "content_hash" text,
  "latest_version" text,
  "provider_refs" jsonb not null default '{}' constraint bsb_agent_skills_provider_refs_check check (jsonb_typeof("provider_refs") = 'object'),
  "created_at" timestamptz not null default now()
);
create index agent_skills_agent_idx on "better_supabase"."agent_skills" ("agent_id");
alter table "better_supabase"."agent_skills" enable row level security;
revoke all on "better_supabase"."agent_skills" from public, anon, authenticated;
grant select on "better_supabase"."agent_skills" to authenticated;
grant all on "better_supabase"."agent_skills" to service_role;
create policy bsb_agent_skills_read on "better_supabase"."agent_skills"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."agents" x where x."id" = "agent_id"));

-- Creates an agent (id null, needs 'agents.write') or changes one its owner or a
-- moderator may change. fields holds the columns to set; visibility and
-- published_at change through publish_agent only.
create or replace function "better_supabase"."save_agent"(tenant uuid, id uuid default null, fields jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."agents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(save_agent.fields) is distinct from 'object' then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  if save_agent.id is null then
    if auth.uid() is null or not coalesce(better_supabase.can('tenant', save_agent.tenant, 'agents.write'), false) then
      raise exception 'you may not create agents here' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
    end if;
    if save_agent.fields ->> 'slug' is null or save_agent.fields ->> 'name' is null then
      raise exception 'a new agent needs a slug and a name' using errcode = '22023', hint = 'AGENT_INVALID';
    end if;
    insert into "better_supabase"."agents" ("tenant_id", "owner_id", "slug", "name")
    values (save_agent.tenant, auth.uid(), save_agent.fields ->> 'slug', save_agent.fields ->> 'name')
    returning * into v_row;
  else
    select * into v_row from "better_supabase"."agents" x where x."id" = save_agent.id and x."tenant_id" = save_agent.tenant for update;
    if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)) then
      raise exception 'agent % not found', save_agent.id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
    end if;
    if v_row."archived_at" is not null then
    raise exception 'agent is archived; restore it first' using errcode = '55000', hint = 'AGENT_ARCHIVED';
  end if;
  
  end if;
  update "better_supabase"."agents" x set
    "slug" = coalesce(save_agent.fields ->> 'slug', x."slug"),
    "name" = coalesce(save_agent.fields ->> 'name', x."name"),
    "description" = coalesce(save_agent.fields ->> 'description', x."description"),
    "instructions" = coalesce(save_agent.fields ->> 'instructions', x."instructions"),
    "model" = case when save_agent.fields ? 'model' then save_agent.fields ->> 'model' else x."model" end,
    "tools" = coalesce(save_agent.fields -> 'tools', x."tools"),
    "connector_ids" = case when save_agent.fields ? 'connector_ids'
      then array(select jsonb_array_elements_text(save_agent.fields -> 'connector_ids')::uuid)
      else x."connector_ids" end,
    "knowledge_scope" = coalesce(save_agent.fields -> 'knowledge_scope', x."knowledge_scope"),
    "starters" = coalesce(save_agent.fields -> 'starters', x."starters"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if save_agent.id is null then
    perform "better_supabase".emit_event('agent.created', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'agentId', v_row."id", 'slug', v_row."slug"), 'organizations/' || v_row."tenant_id"::text || '/agents/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/agents');
  perform better_supabase.audit_event(
    event_type => 'agent.created',
    category => 'ai',
    target_type => 'agent',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'agentId', v_row."id", 'slug', v_row."slug")
  );
  else
    perform "better_supabase".emit_event('agent.updated', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'agentId', v_row."id", 'slug', v_row."slug"), 'organizations/' || v_row."tenant_id"::text || '/agents/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/agents');
  perform better_supabase.audit_event(
    event_type => 'agent.updated',
    category => 'ai',
    target_type => 'agent',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'agentId', v_row."id", 'slug', v_row."slug")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
exception
  when unique_violation then
    raise exception 'an agent with slug % exists', save_agent.fields ->> 'slug' using errcode = '23505', hint = 'AGENT_SLUG_TAKEN';
end;
$$;
revoke execute on function "better_supabase"."save_agent"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_agent"(uuid, uuid, jsonb) to authenticated, service_role;

-- Publishes an agent to the organization or the public store, or makes it
-- private again. The owner needs 'agents.publish'; a moderator may always unpublish.
create or replace function "better_supabase"."publish_agent"(id uuid, visibility text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."agents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if publish_agent.visibility is null or publish_agent.visibility not in ('private', 'organization', 'public') then
    raise exception 'visibility is private, organization or public' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = publish_agent.id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)) then
    raise exception 'agent % not found', publish_agent.id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if v_row."archived_at" is not null then
    raise exception 'agent is archived; restore it first' using errcode = '55000', hint = 'AGENT_ARCHIVED';
  end if;
    if publish_agent.visibility <> 'private' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)
    or (coalesce(v_row."owner_id" = auth.uid(), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.publish'), false))) then
    raise exception 'you may not publish agents here' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
  end if;
  update "better_supabase"."agents" x set
    "visibility" = publish_agent.visibility,
    "published_at" = case when publish_agent.visibility = 'private' then null else coalesce(x."published_at", now()) end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('agent.published', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'agentId', v_row."id", 'slug', v_row."slug", 'visibility', publish_agent.visibility), 'organizations/' || v_row."tenant_id"::text || '/agents/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/agents');
  perform better_supabase.audit_event(
    event_type => 'agent.published',
    category => 'ai',
    target_type => 'agent',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'agentId', v_row."id", 'slug', v_row."slug", 'visibility', publish_agent.visibility)
  );
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
end;
$$;
revoke execute on function "better_supabase"."publish_agent"(uuid, text) from public, anon;
grant execute on function "better_supabase"."publish_agent"(uuid, text) to authenticated, service_role;

-- Archives an agent: it leaves the store, the lists and new installs, and it can't be changed, published or rated until it is restored. Installs, ratings and skills stay. The owner or a moderator may; archiving an archived agent returns it unchanged.
create or replace function "better_supabase"."archive_agent"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."agents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = archive_agent.id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)) then
    raise exception 'agent % not found', archive_agent.id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if (v_row."archived_at" is not null) = true then
    return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
  end if;
  update "better_supabase"."agents" x set "archived_at" = now(), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('agent.archived', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'agentId', v_row."id", 'slug', v_row."slug"), 'organizations/' || v_row."tenant_id"::text || '/agents/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/agents');
  perform better_supabase.audit_event(
    event_type => 'agent.archived',
    category => 'ai',
    target_type => 'agent',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'agentId', v_row."id", 'slug', v_row."slug")
  );
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
end;
$$;
revoke execute on function "better_supabase"."archive_agent"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_agent"(uuid) to authenticated, service_role;

-- Restores an archived agent with the visibility it had. The owner or a moderator may; restoring one that is not archived returns it unchanged.
create or replace function "better_supabase"."restore_agent"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."agents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = restore_agent.id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)) then
    raise exception 'agent % not found', restore_agent.id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if (v_row."archived_at" is not null) = false then
    return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
  end if;
  update "better_supabase"."agents" x set "archived_at" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('agent.restored', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'agentId', v_row."id", 'slug', v_row."slug"), 'organizations/' || v_row."tenant_id"::text || '/agents/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/agents');
  perform better_supabase.audit_event(
    event_type => 'agent.restored',
    category => 'ai',
    target_type => 'agent',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'agentId', v_row."id", 'slug', v_row."slug")
  );
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
end;
$$;
revoke execute on function "better_supabase"."restore_agent"(uuid) from public, anon;
grant execute on function "better_supabase"."restore_agent"(uuid) to authenticated, service_role;

-- Deletes an agent for good with its installs, ratings and skills; archive
-- keeps them. Needs 'agents.moderate', which falls back to the moderate key, and the
-- owner needs it too. False when the caller can't see the agent.

create or replace function "better_supabase"."purge_agent"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."agents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = purge_agent.id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)) then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)) then
    raise exception 'you may not purge agents here' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
  end if;
  delete from "better_supabase"."agents" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('agent.purged', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'agentId', v_row."id", 'slug', v_row."slug"), 'organizations/' || v_row."tenant_id"::text || '/agents/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/agents');
  perform better_supabase.audit_event(
    event_type => 'agent.purged',
    category => 'ai',
    target_type => 'agent',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'agentId', v_row."id", 'slug', v_row."slug")
  );
  return true;
end;
$$;
revoke execute on function "better_supabase"."purge_agent"(uuid) from public, anon;
grant execute on function "better_supabase"."purge_agent"(uuid) to authenticated, service_role;

-- An agent by id or by slug in a tenant, with its skills, when the caller may read it.
create or replace function "better_supabase"."get_agent"(id uuid default null, tenant uuid default null, slug text default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_row "better_supabase"."agents"%rowtype;
begin
  select * into v_row from "better_supabase"."agents" x
  where (get_agent.id is not null and x."id" = get_agent.id)
    or (get_agent.id is null and x."tenant_id" = get_agent.tenant and x."slug" = get_agent.slug);
  if not found then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at") || jsonb_build_object(
    'skills', coalesce((select jsonb_agg(jsonb_build_object('id', k."id", 'provider', k."provider", 'reference', k."reference", 'name', k."name", 'files', k."files", 'content_hash', k."content_hash", 'latest_version', k."latest_version", 'provider_refs', k."provider_refs") order by k."created_at") from "better_supabase"."agent_skills" k where k."agent_id" = v_row."id"), '[]'),
    'installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = v_row."id" and n."user_id" = auth.uid()),
    'my_rating', (select g."rating" from "better_supabase"."agent_ratings" g where g."agent_id" = v_row."id" and g."user_id" = auth.uid())
  );
end;
$$;
revoke execute on function "better_supabase"."get_agent"(uuid, uuid, text) from public, anon;
grant execute on function "better_supabase"."get_agent"(uuid, uuid, text) to authenticated, service_role;

-- Agents the caller may read: 'mine', 'installed' in the tenant, or the
-- 'store' (published to the tenant or public), newest first. Archived agents
-- stay out unless include_archived is true.

create or replace function "better_supabase"."list_agents"(tenant uuid, filter text default 'store', search text default null, max_rows integer default 50, include_archived boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(y.row order by y.at desc), '[]')
  from (
    select jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = list_agents.tenant)) as row,
      coalesce(x."published_at", x."updated_at") as at
    from "better_supabase"."agents" x
    where case list_agents.filter
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = list_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = list_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = list_agents.tenant)
      end
      and (coalesce(list_agents.include_archived, false) or x."archived_at" is null)
      and (list_agents.search is null or x."name" ilike '%' || replace(replace(list_agents.search, '%', '\%'), '_', '\_') || '%'
        or x."description" ilike '%' || replace(replace(list_agents.search, '%', '\%'), '_', '\_') || '%')
    order by coalesce(x."published_at", x."updated_at") desc
    limit least(greatest(list_agents.max_rows, 1), 200)
  ) y
$$;
revoke execute on function "better_supabase"."list_agents"(uuid, text, text, integer, boolean) from public, anon;
grant execute on function "better_supabase"."list_agents"(uuid, text, text, integer, boolean) to authenticated, service_role;

-- Agents as a keyset page (ADR 1077): the same three modes as list_agents.
-- filters is { mode ('store' by default, 'mine' or 'installed'), visibility (a
-- value or a list), includeArchived, search (name, description), sort (name,
-- updatedAt, createdAt, installCount), direction, facet, count, limit, after,
-- offset, paged, total, totalCap }. The default order is the newest published
-- or updated agent first.
create or replace function "better_supabase"."page_agents"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_agents.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_mode text := coalesce(nullif(coalesce(v_filters #>> '{mode,0}', v_filters ->> 'mode'), ''), 'store');
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if v_mode not in ('store', 'mine', 'installed') then
    raise exception 'mode is store, mine or installed' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'visibility') = 'array' then v_filters -> 'visibility' when jsonb_typeof(v_filters -> 'visibility') in ('string', 'number') then jsonb_build_array(v_filters -> 'visibility') else '[]'::jsonb end) s where s not in ('private', 'organization', 'public')) then
    raise exception 'visibility is private, organization or public' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('visibility') then
      raise exception 'facet is one of visibility' using errcode = '22023', hint = 'AGENT_INVALID';
    end if;
    with s as (
      select (case v_facet when 'visibility' then (x."visibility")::text end) as v
      from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'updatedAt', 'createdAt', 'installCount') then
    raise exception 'sort is one of name, updatedAt, createdAt, installCount' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((coalesce(x."published_at", x."updated_at"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (coalesce(x."published_at", x."updated_at"), x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."published_at", x."updated_at") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((coalesce(x."published_at", x."updated_at"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (coalesce(x."published_at", x."updated_at") <= (v_after ->> 0)::timestamptz and ((coalesce(x."published_at", x."updated_at") < (v_after ->> 0)::timestamptz) or (coalesce(x."published_at", x."updated_at") = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."published_at", x."updated_at") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."updated_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."updated_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."updated_at" <= (v_after ->> 0)::timestamptz and ((x."updated_at" < (v_after ->> 0)::timestamptz) or (x."updated_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."updated_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'installCount' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((coalesce(x."install_count", 0))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (coalesce(x."install_count", 0), x."id") > ((v_after ->> 0)::integer, (v_after ->> 1)::uuid))
      order by coalesce(x."install_count", 0) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'installCount' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((coalesce(x."install_count", 0))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (coalesce(x."install_count", 0) <= (v_after ->> 0)::integer and ((coalesce(x."install_count", 0) < (v_after ->> 0)::integer) or (coalesce(x."install_count", 0) = (v_after ->> 0)::integer and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."install_count", 0) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_agents"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."page_agents"(uuid, jsonb) to authenticated, service_role;

-- Adds a readable agent to the caller's list in a tenant they belong to, or removes it.
create or replace function "better_supabase"."install_agent"(tenant uuid, agent_id uuid, installed boolean default true)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null or not coalesce(better_supabase.can('tenant', install_agent.tenant, 'agents.read'), false) then
    raise exception 'you may not use agents here' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
  end if;
  if not install_agent.installed then
    delete from "better_supabase"."agent_installs" n where n."agent_id" = install_agent.agent_id and n."user_id" = auth.uid() and n."tenant_id" = install_agent.tenant;
    get diagnostics v_count = row_count;
    update "better_supabase"."agents" x set "install_count" = greatest(x."install_count" - v_count, 0) where x."id" = install_agent.agent_id;
    if v_count > 0 then
      perform "better_supabase".emit_event('agent.uninstalled', jsonb_build_object('organizationId', install_agent.tenant::text, 'agentId', install_agent.agent_id, 'userId', auth.uid()), 'organizations/' || install_agent.tenant::text || '/agents/' || install_agent.agent_id::text, (install_agent.tenant)::text, null, 'better-supabase/agents');
  perform better_supabase.audit_event(
    event_type => 'agent.uninstalled',
    category => 'ai',
    target_type => 'agent',
    record_id => install_agent.agent_id::text,
    tenant => (install_agent.tenant)::uuid,
    metadata => jsonb_build_object('organizationId', install_agent.tenant::text, 'agentId', install_agent.agent_id, 'userId', auth.uid())
  );
    end if;
    return v_count > 0;
  end if;
  if not exists (select 1 from "better_supabase"."agents" x where x."id" = install_agent.agent_id and (x."owner_id" = (select auth.uid()) or (x."published_at" is not null and (x."visibility" = 'public' or (x."visibility" = 'organization' and x."tenant_id" in (select better_supabase.tenant_ids_with('agents.read'))))) or x."tenant_id" in (select better_supabase.tenant_ids_with('agents.moderate')))) then
    raise exception 'agent % not found', install_agent.agent_id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if exists (select 1 from "better_supabase"."agents" x where x."id" = install_agent.agent_id and x."archived_at" is not null) then
    raise exception 'agent is archived; restore it first' using errcode = '55000', hint = 'AGENT_ARCHIVED';
  end if;
  insert into "better_supabase"."agent_installs" ("agent_id", "user_id", "tenant_id") values (install_agent.agent_id, auth.uid(), install_agent.tenant)
  on conflict do nothing;
  get diagnostics v_count = row_count;
  update "better_supabase"."agents" x set "install_count" = x."install_count" + v_count where x."id" = install_agent.agent_id;
  if v_count > 0 then
    perform "better_supabase".emit_event('agent.installed', jsonb_build_object('organizationId', install_agent.tenant::text, 'agentId', install_agent.agent_id, 'userId', auth.uid()), 'organizations/' || install_agent.tenant::text || '/agents/' || install_agent.agent_id::text, (install_agent.tenant)::text, null, 'better-supabase/agents');
  perform better_supabase.audit_event(
    event_type => 'agent.installed',
    category => 'ai',
    target_type => 'agent',
    record_id => install_agent.agent_id::text,
    tenant => (install_agent.tenant)::uuid,
    metadata => jsonb_build_object('organizationId', install_agent.tenant::text, 'agentId', install_agent.agent_id, 'userId', auth.uid())
  );
  end if;
  return v_count > 0;
end;
$$;
revoke execute on function "better_supabase"."install_agent"(uuid, uuid, boolean) from public, anon;
grant execute on function "better_supabase"."install_agent"(uuid, uuid, boolean) to authenticated, service_role;

-- Rates a readable agent 1 to 5, replacing the caller's rating; null removes it.
create or replace function "better_supabase"."rate_agent"(agent_id uuid, rating integer, comment text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old integer;
  v_row "better_supabase"."agents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    raise exception 'sign in to rate agents' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = rate_agent.agent_id and (x."owner_id" = (select auth.uid()) or (x."published_at" is not null and (x."visibility" = 'public' or (x."visibility" = 'organization' and x."tenant_id" in (select better_supabase.tenant_ids_with('agents.read'))))) or x."tenant_id" in (select better_supabase.tenant_ids_with('agents.moderate'))) for update;
  if not found then
    raise exception 'agent % not found', rate_agent.agent_id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if v_row."archived_at" is not null then
    raise exception 'agent is archived; restore it first' using errcode = '55000', hint = 'AGENT_ARCHIVED';
  end if;
    if rate_agent.rating is not null and rate_agent.rating not between 1 and 5 then
    raise exception 'a rating is 1 to 5' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  delete from "better_supabase"."agent_ratings" g where g."agent_id" = v_row."id" and g."user_id" = auth.uid()
  returning g."rating" into v_old;
  if rate_agent.rating is not null then
    insert into "better_supabase"."agent_ratings" ("agent_id", "user_id", "rating", "comment")
    values (v_row."id", auth.uid(), rate_agent.rating, rate_agent.comment);
  end if;
  update "better_supabase"."agents" x set
    "rating_count" = x."rating_count" - (case when v_old is null then 0 else 1 end) + (case when rate_agent.rating is null then 0 else 1 end),
    "rating_sum" = x."rating_sum" - coalesce(v_old, 0) + coalesce(rate_agent.rating, 0)
  where x."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
end;
$$;
revoke execute on function "better_supabase"."rate_agent"(uuid, integer, text) from public, anon;
grant execute on function "better_supabase"."rate_agent"(uuid, integer, text) to authenticated, service_role;

-- Replaces an agent's skills with a list of {provider, reference}.
create or replace function "better_supabase"."set_agent_skills"(agent_id uuid, skills jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."agents"%rowtype;
  v_items jsonb := case when jsonb_typeof(set_agent_skills.skills) = 'object' then set_agent_skills.skills -> 'items' else set_agent_skills.skills end;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = set_agent_skills.agent_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)) then
    raise exception 'agent % not found', set_agent_skills.agent_id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if v_row."archived_at" is not null then
    raise exception 'agent is archived; restore it first' using errcode = '55000', hint = 'AGENT_ARCHIVED';
  end if;
    if jsonb_typeof(v_items) is distinct from 'array' then
    raise exception 'skills must be a list' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  delete from "better_supabase"."agent_skills" k where k."agent_id" = v_row."id";
  insert into "better_supabase"."agent_skills" ("agent_id", "provider", "reference", "name", "files", "content_hash", "latest_version", "provider_refs")
  select v_row."id", e ->> 'provider', coalesce(e -> 'reference', '{}'), e ->> 'name', coalesce(e -> 'files', '[]'), e ->> 'content_hash', e ->> 'latest_version', coalesce(e -> 'provider_refs', '{}')
  from jsonb_array_elements(v_items) e;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."set_agent_skills"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."set_agent_skills"(uuid, jsonb) to authenticated, service_role;

-- Records what a provider returned for a skill's current content: its
-- reference and the hash it was uploaded from. syncSkill calls it as the
-- service role after uploadSkill, and skips the upload while the hash matches.
create or replace function "better_supabase"."record_skill_sync"(skill_id uuid, provider text, reference jsonb, content_hash text)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_row "better_supabase"."agent_skills"%rowtype;
begin
  update "better_supabase"."agent_skills" k
  set "provider_refs" = k."provider_refs" || jsonb_build_object(record_skill_sync.provider, jsonb_build_object('reference', record_skill_sync.reference, 'content_hash', record_skill_sync.content_hash)),
      "content_hash" = record_skill_sync.content_hash
  where k."id" = record_skill_sync.skill_id
  returning * into v_row;
  if not found then
    raise exception 'agent % not found', record_skill_sync.skill_id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  return v_row."provider_refs";
end;
$$;
revoke execute on function "better_supabase"."record_skill_sync"(uuid, text, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."record_skill_sync"(uuid, text, jsonb, text) to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."agents" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (("better_supabase"."agents"."owner_id" = (select auth.uid()) or ("better_supabase"."agents"."published_at" is not null and ("better_supabase"."agents"."visibility" = 'public' or ("better_supabase"."agents"."visibility" = 'organization' and "better_supabase"."agents"."tenant_id" in (select better_supabase.tenant_ids_with('agents.read'))))) or "better_supabase"."agents"."tenant_id" in (select better_supabase.tenant_ids_with('agents.moderate'))))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."agents" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."agents" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."agents" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."agent_installs" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."agent_installs" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."agent_installs" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."agent_installs" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- Row audit for the module's tables (blocks.audit.options.blockTables)
create constraint trigger bsb_audit after insert or update or delete on better_supabase.agents deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"agent","event_prefix":"agent"}');

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_051_agents.sql
-- better-supabase module: agents
-- @bsb-block-data agents
-- @bsb-hash sha256:89cbc764a7f121e0277343276dfc4456394a839780009117dc1dd6f25a6fbf28
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('agents', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_051_agents.sql
-- better-supabase module: agents
-- @bsb-block agents@2 managed
-- @bsb-hash sha256:6162c133390d66324a8dd98108110659b108d5ebf339cfa6a3b3aeade08a52e1
-- Custom assistants with instructions, a model, tools, connectors, knowledge scopes and starters; private until published to the organization or the public store, with installs, ratings and provider skills.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on functions from public, anon, authenticated;
-- Custom assistants: instructions, a model, the tools and connectors they may
-- use and the knowledge they search. An owner keeps an agent private until a
-- member with 'agents.publish' publishes it to the organization or the public store.
create table "app_private"."agents" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "owner_id" uuid references auth.users (id) on delete set null,
  "slug" text not null constraint bsb_agents_slug_check check ("slug" ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and length("slug") <= 64),
  "name" text not null constraint bsb_agents_name_check check (length("name") >= 1 and length("name") <= 200),
  "description" text not null default '' constraint bsb_agents_description_check check (length("description") <= 2000),
  "instructions" text not null default '' constraint bsb_agents_instructions_check check (length("instructions") <= 100000),
  "model" text,
  "tools" jsonb not null default '[]' constraint bsb_agents_tools_check check (jsonb_typeof("tools") = 'array'),
  "connector_ids" uuid[] not null default '{}',
  "knowledge_scope" jsonb not null default '[]' constraint bsb_agents_knowledge_scope_check check (jsonb_typeof("knowledge_scope") = 'array'),
  "starters" jsonb not null default '[]' constraint bsb_agents_starters_check check (jsonb_typeof("starters") = 'array'),
  "visibility" text not null default 'private' constraint bsb_agents_visibility_check check ("visibility" in ('private', 'organization', 'public')),
  "published_at" timestamptz,
  "install_count" integer not null default 0,
  "rating_count" integer not null default 0,
  "rating_sum" integer not null default 0,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  "archived_at" timestamptz,
  unique ("tenant_id", "slug")
);
create index agents_owner_idx on "app_private"."agents" ("owner_id");
create index agents_published_idx on "app_private"."agents" ("visibility", "published_at") where "published_at" is not null;
alter table "app_private"."agents" enable row level security;
revoke all on "app_private"."agents" from public, anon, authenticated;
grant select on "app_private"."agents" to authenticated;
grant all on "app_private"."agents" to service_role;
create policy bsb_agents_read on "app_private"."agents"
  for select to authenticated
  using (("app_private"."agents"."owner_id" = (select auth.uid()) or ("app_private"."agents"."published_at" is not null and ("app_private"."agents"."visibility" = 'public' or ("app_private"."agents"."visibility" = 'organization' and "app_private"."agents"."tenant_id" in (select better_supabase.tenant_ids_with('agents.read'))))) or "app_private"."agents"."tenant_id" in (select better_supabase.tenant_ids_with('agents.moderate'))));

create table "app_private"."agent_installs" (
  "agent_id" uuid not null references "app_private"."agents" ("id") on delete cascade,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "tenant_id" uuid not null,
  "installed_at" timestamptz not null default now(),
  primary key ("agent_id", "user_id", "tenant_id")
);
create index agent_installs_user_idx on "app_private"."agent_installs" ("user_id", "tenant_id");
alter table "app_private"."agent_installs" enable row level security;
revoke all on "app_private"."agent_installs" from public, anon, authenticated;
grant select on "app_private"."agent_installs" to authenticated;
grant all on "app_private"."agent_installs" to service_role;
create policy bsb_agent_installs_read on "app_private"."agent_installs"
  for select to authenticated
  using ("user_id" = (select auth.uid()));

create table "app_private"."agent_ratings" (
  "agent_id" uuid not null references "app_private"."agents" ("id") on delete cascade,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "rating" smallint not null constraint bsb_agent_ratings_rating_check check ("rating" >= 1 and "rating" <= 5),
  "comment" text constraint bsb_agent_ratings_comment_check check (length("comment") <= 2000),
  "created_at" timestamptz not null default now(),
  primary key ("agent_id", "user_id")
);
create index agent_ratings_user_idx on "app_private"."agent_ratings" ("user_id");
alter table "app_private"."agent_ratings" enable row level security;
revoke all on "app_private"."agent_ratings" from public, anon, authenticated;
grant select on "app_private"."agent_ratings" to authenticated;
grant all on "app_private"."agent_ratings" to service_role;
create policy bsb_agent_ratings_read on "app_private"."agent_ratings"
  for select to authenticated
  using (exists (select 1 from "app_private"."agents" x where x."id" = "agent_id"));

-- Skills an agent loads from a provider (a reference such as a skill id).
create table "app_private"."agent_skills" (
  "id" uuid primary key default gen_random_uuid(),
  "agent_id" uuid not null references "app_private"."agents" ("id") on delete cascade,
  "provider" text not null constraint bsb_agent_skills_provider_check check (length("provider") >= 1 and length("provider") <= 100),
  "reference" jsonb not null constraint bsb_agent_skills_reference_check check (jsonb_typeof("reference") = 'object'),
  -- Skill files kept in Storage (a list of {path, object}), the hash of their
  -- bytes, and the reference each provider returned for that hash.
  "name" text,
  "files" jsonb not null default '[]' constraint bsb_agent_skills_files_check check (jsonb_typeof("files") = 'array'),
  "content_hash" text,
  "latest_version" text,
  "provider_refs" jsonb not null default '{}' constraint bsb_agent_skills_provider_refs_check check (jsonb_typeof("provider_refs") = 'object'),
  "created_at" timestamptz not null default now()
);
create index agent_skills_agent_idx on "app_private"."agent_skills" ("agent_id");
alter table "app_private"."agent_skills" enable row level security;
revoke all on "app_private"."agent_skills" from public, anon, authenticated;
grant select on "app_private"."agent_skills" to authenticated;
grant all on "app_private"."agent_skills" to service_role;
create policy bsb_agent_skills_read on "app_private"."agent_skills"
  for select to authenticated
  using (exists (select 1 from "app_private"."agents" x where x."id" = "agent_id"));

-- Creates an agent (id null, needs 'agents.write') or changes one its owner or a
-- moderator may change. fields holds the columns to set; visibility and
-- published_at change through publish_agent only.
create or replace function "app_private"."save_agent"(tenant uuid, id uuid default null, fields jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."agents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(save_agent.fields) is distinct from 'object' then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  if save_agent.id is null then
    if auth.uid() is null or not coalesce(better_supabase.can('tenant', save_agent.tenant, 'agents.write'), false) then
      raise exception 'you may not create agents here' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
    end if;
    if save_agent.fields ->> 'slug' is null or save_agent.fields ->> 'name' is null then
      raise exception 'a new agent needs a slug and a name' using errcode = '22023', hint = 'AGENT_INVALID';
    end if;
    insert into "app_private"."agents" ("tenant_id", "owner_id", "slug", "name")
    values (save_agent.tenant, auth.uid(), save_agent.fields ->> 'slug', save_agent.fields ->> 'name')
    returning * into v_row;
  else
    select * into v_row from "app_private"."agents" x where x."id" = save_agent.id and x."tenant_id" = save_agent.tenant for update;
    if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)) then
      raise exception 'agent % not found', save_agent.id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
    end if;
    if v_row."archived_at" is not null then
    raise exception 'agent is archived; restore it first' using errcode = '55000', hint = 'AGENT_ARCHIVED';
  end if;
  
  end if;
  update "app_private"."agents" x set
    "slug" = coalesce(save_agent.fields ->> 'slug', x."slug"),
    "name" = coalesce(save_agent.fields ->> 'name', x."name"),
    "description" = coalesce(save_agent.fields ->> 'description', x."description"),
    "instructions" = coalesce(save_agent.fields ->> 'instructions', x."instructions"),
    "model" = case when save_agent.fields ? 'model' then save_agent.fields ->> 'model' else x."model" end,
    "tools" = coalesce(save_agent.fields -> 'tools', x."tools"),
    "connector_ids" = case when save_agent.fields ? 'connector_ids'
      then array(select jsonb_array_elements_text(save_agent.fields -> 'connector_ids')::uuid)
      else x."connector_ids" end,
    "knowledge_scope" = coalesce(save_agent.fields -> 'knowledge_scope', x."knowledge_scope"),
    "starters" = coalesce(save_agent.fields -> 'starters', x."starters"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if save_agent.id is null then
    null;
  else
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
exception
  when unique_violation then
    raise exception 'an agent with slug % exists', save_agent.fields ->> 'slug' using errcode = '23505', hint = 'AGENT_SLUG_TAKEN';
end;
$$;
revoke execute on function "app_private"."save_agent"(uuid, uuid, jsonb) from public, anon;
grant execute on function "app_private"."save_agent"(uuid, uuid, jsonb) to authenticated, service_role;

-- Publishes an agent to the organization or the public store, or makes it
-- private again. The owner needs 'agents.publish'; a moderator may always unpublish.
create or replace function "app_private"."publish_agent"(id uuid, visibility text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."agents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if publish_agent.visibility is null or publish_agent.visibility not in ('private', 'organization', 'public') then
    raise exception 'visibility is private, organization or public' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select * into v_row from "app_private"."agents" x where x."id" = publish_agent.id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)) then
    raise exception 'agent % not found', publish_agent.id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if v_row."archived_at" is not null then
    raise exception 'agent is archived; restore it first' using errcode = '55000', hint = 'AGENT_ARCHIVED';
  end if;
    if publish_agent.visibility <> 'private' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)
    or (coalesce(v_row."owner_id" = auth.uid(), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.publish'), false))) then
    raise exception 'you may not publish agents here' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
  end if;
  update "app_private"."agents" x set
    "visibility" = publish_agent.visibility,
    "published_at" = case when publish_agent.visibility = 'private' then null else coalesce(x."published_at", now()) end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
end;
$$;
revoke execute on function "app_private"."publish_agent"(uuid, text) from public, anon;
grant execute on function "app_private"."publish_agent"(uuid, text) to authenticated, service_role;

-- Archives an agent: it leaves the store, the lists and new installs, and it can't be changed, published or rated until it is restored. Installs, ratings and skills stay. The owner or a moderator may; archiving an archived agent returns it unchanged.
create or replace function "app_private"."archive_agent"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."agents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."agents" x where x."id" = archive_agent.id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)) then
    raise exception 'agent % not found', archive_agent.id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if (v_row."archived_at" is not null) = true then
    return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
  end if;
  update "app_private"."agents" x set "archived_at" = now(), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
end;
$$;
revoke execute on function "app_private"."archive_agent"(uuid) from public, anon;
grant execute on function "app_private"."archive_agent"(uuid) to authenticated, service_role;

-- Restores an archived agent with the visibility it had. The owner or a moderator may; restoring one that is not archived returns it unchanged.
create or replace function "app_private"."restore_agent"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."agents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."agents" x where x."id" = restore_agent.id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)) then
    raise exception 'agent % not found', restore_agent.id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if (v_row."archived_at" is not null) = false then
    return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
  end if;
  update "app_private"."agents" x set "archived_at" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
end;
$$;
revoke execute on function "app_private"."restore_agent"(uuid) from public, anon;
grant execute on function "app_private"."restore_agent"(uuid) to authenticated, service_role;

-- Deletes an agent for good with its installs, ratings and skills; archive
-- keeps them. Needs 'agents.moderate', which falls back to the moderate key, and the
-- owner needs it too. False when the caller can't see the agent.

create or replace function "app_private"."purge_agent"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."agents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."agents" x where x."id" = purge_agent.id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)) then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)) then
    raise exception 'you may not purge agents here' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
  end if;
  delete from "app_private"."agents" x where x."id" = v_row."id";
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."purge_agent"(uuid) from public, anon;
grant execute on function "app_private"."purge_agent"(uuid) to authenticated, service_role;

-- An agent by id or by slug in a tenant, with its skills, when the caller may read it.
create or replace function "app_private"."get_agent"(id uuid default null, tenant uuid default null, slug text default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_row "app_private"."agents"%rowtype;
begin
  select * into v_row from "app_private"."agents" x
  where (get_agent.id is not null and x."id" = get_agent.id)
    or (get_agent.id is null and x."tenant_id" = get_agent.tenant and x."slug" = get_agent.slug);
  if not found then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at") || jsonb_build_object(
    'skills', coalesce((select jsonb_agg(jsonb_build_object('id', k."id", 'provider', k."provider", 'reference', k."reference", 'name', k."name", 'files', k."files", 'content_hash', k."content_hash", 'latest_version', k."latest_version", 'provider_refs', k."provider_refs") order by k."created_at") from "app_private"."agent_skills" k where k."agent_id" = v_row."id"), '[]'),
    'installed', exists (select 1 from "app_private"."agent_installs" n where n."agent_id" = v_row."id" and n."user_id" = auth.uid()),
    'my_rating', (select g."rating" from "app_private"."agent_ratings" g where g."agent_id" = v_row."id" and g."user_id" = auth.uid())
  );
end;
$$;
revoke execute on function "app_private"."get_agent"(uuid, uuid, text) from public, anon;
grant execute on function "app_private"."get_agent"(uuid, uuid, text) to authenticated, service_role;

-- Agents the caller may read: 'mine', 'installed' in the tenant, or the
-- 'store' (published to the tenant or public), newest first. Archived agents
-- stay out unless include_archived is true.

create or replace function "app_private"."list_agents"(tenant uuid, filter text default 'store', search text default null, max_rows integer default 50, include_archived boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(y.row order by y.at desc), '[]')
  from (
    select jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "app_private"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = list_agents.tenant)) as row,
      coalesce(x."published_at", x."updated_at") as at
    from "app_private"."agents" x
    where case list_agents.filter
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = list_agents.tenant
        when 'installed' then exists (select 1 from "app_private"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = list_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = list_agents.tenant)
      end
      and (coalesce(list_agents.include_archived, false) or x."archived_at" is null)
      and (list_agents.search is null or x."name" ilike '%' || replace(replace(list_agents.search, '%', '\%'), '_', '\_') || '%'
        or x."description" ilike '%' || replace(replace(list_agents.search, '%', '\%'), '_', '\_') || '%')
    order by coalesce(x."published_at", x."updated_at") desc
    limit least(greatest(list_agents.max_rows, 1), 200)
  ) y
$$;
revoke execute on function "app_private"."list_agents"(uuid, text, text, integer, boolean) from public, anon;
grant execute on function "app_private"."list_agents"(uuid, text, text, integer, boolean) to authenticated, service_role;

-- Agents as a keyset page (ADR 1077): the same three modes as list_agents.
-- filters is { mode ('store' by default, 'mine' or 'installed'), visibility (a
-- value or a list), includeArchived, search (name, description), sort (name,
-- updatedAt, createdAt, installCount), direction, facet, count, limit, after,
-- offset, paged, total, totalCap }. The default order is the newest published
-- or updated agent first.
create or replace function "app_private"."page_agents"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_agents.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_mode text := coalesce(nullif(coalesce(v_filters #>> '{mode,0}', v_filters ->> 'mode'), ''), 'store');
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if v_mode not in ('store', 'mine', 'installed') then
    raise exception 'mode is store, mine or installed' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'visibility') = 'array' then v_filters -> 'visibility' when jsonb_typeof(v_filters -> 'visibility') in ('string', 'number') then jsonb_build_array(v_filters -> 'visibility') else '[]'::jsonb end) s where s not in ('private', 'organization', 'public')) then
    raise exception 'visibility is private, organization or public' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('visibility') then
      raise exception 'facet is one of visibility' using errcode = '22023', hint = 'AGENT_INVALID';
    end if;
    with s as (
      select (case v_facet when 'visibility' then (x."visibility")::text end) as v
      from "app_private"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "app_private"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "app_private"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "app_private"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'updatedAt', 'createdAt', 'installCount') then
    raise exception 'sort is one of name, updatedAt, createdAt, installCount' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "app_private"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((coalesce(x."published_at", x."updated_at"))::text, (x."id")::text) as k
    from (
      select * from "app_private"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "app_private"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (coalesce(x."published_at", x."updated_at"), x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."published_at", x."updated_at") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "app_private"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((coalesce(x."published_at", x."updated_at"))::text, (x."id")::text) as k
    from (
      select * from "app_private"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "app_private"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (coalesce(x."published_at", x."updated_at") <= (v_after ->> 0)::timestamptz and ((coalesce(x."published_at", x."updated_at") < (v_after ->> 0)::timestamptz) or (coalesce(x."published_at", x."updated_at") = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."published_at", x."updated_at") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "app_private"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "app_private"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "app_private"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "app_private"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "app_private"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "app_private"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "app_private"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "app_private"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "app_private"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."updated_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."updated_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "app_private"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "app_private"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "app_private"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."updated_at" <= (v_after ->> 0)::timestamptz and ((x."updated_at" < (v_after ->> 0)::timestamptz) or (x."updated_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."updated_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "app_private"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "app_private"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "app_private"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "app_private"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "app_private"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "app_private"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'installCount' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "app_private"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((coalesce(x."install_count", 0))::text, (x."id")::text) as k
    from (
      select * from "app_private"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "app_private"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (coalesce(x."install_count", 0), x."id") > ((v_after ->> 0)::integer, (v_after ->> 1)::uuid))
      order by coalesce(x."install_count", 0) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'installCount' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "app_private"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((coalesce(x."install_count", 0))::text, (x."id")::text) as k
    from (
      select * from "app_private"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "app_private"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (coalesce(x."install_count", 0) <= (v_after ->> 0)::integer and ((coalesce(x."install_count", 0) < (v_after ->> 0)::integer) or (coalesce(x."install_count", 0) = (v_after ->> 0)::integer and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."install_count", 0) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "app_private"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "app_private"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "app_private"."page_agents"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."page_agents"(uuid, jsonb) to authenticated, service_role;

-- Adds a readable agent to the caller's list in a tenant they belong to, or removes it.
create or replace function "app_private"."install_agent"(tenant uuid, agent_id uuid, installed boolean default true)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null or not coalesce(better_supabase.can('tenant', install_agent.tenant, 'agents.read'), false) then
    raise exception 'you may not use agents here' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
  end if;
  if not install_agent.installed then
    delete from "app_private"."agent_installs" n where n."agent_id" = install_agent.agent_id and n."user_id" = auth.uid() and n."tenant_id" = install_agent.tenant;
    get diagnostics v_count = row_count;
    update "app_private"."agents" x set "install_count" = greatest(x."install_count" - v_count, 0) where x."id" = install_agent.agent_id;
    if v_count > 0 then
      null;
    end if;
    return v_count > 0;
  end if;
  if not exists (select 1 from "app_private"."agents" x where x."id" = install_agent.agent_id and (x."owner_id" = (select auth.uid()) or (x."published_at" is not null and (x."visibility" = 'public' or (x."visibility" = 'organization' and x."tenant_id" in (select better_supabase.tenant_ids_with('agents.read'))))) or x."tenant_id" in (select better_supabase.tenant_ids_with('agents.moderate')))) then
    raise exception 'agent % not found', install_agent.agent_id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if exists (select 1 from "app_private"."agents" x where x."id" = install_agent.agent_id and x."archived_at" is not null) then
    raise exception 'agent is archived; restore it first' using errcode = '55000', hint = 'AGENT_ARCHIVED';
  end if;
  insert into "app_private"."agent_installs" ("agent_id", "user_id", "tenant_id") values (install_agent.agent_id, auth.uid(), install_agent.tenant)
  on conflict do nothing;
  get diagnostics v_count = row_count;
  update "app_private"."agents" x set "install_count" = x."install_count" + v_count where x."id" = install_agent.agent_id;
  if v_count > 0 then
    null;
  end if;
  return v_count > 0;
end;
$$;
revoke execute on function "app_private"."install_agent"(uuid, uuid, boolean) from public, anon;
grant execute on function "app_private"."install_agent"(uuid, uuid, boolean) to authenticated, service_role;

-- Rates a readable agent 1 to 5, replacing the caller's rating; null removes it.
create or replace function "app_private"."rate_agent"(agent_id uuid, rating integer, comment text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old integer;
  v_row "app_private"."agents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    raise exception 'sign in to rate agents' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
  end if;
  select * into v_row from "app_private"."agents" x where x."id" = rate_agent.agent_id and (x."owner_id" = (select auth.uid()) or (x."published_at" is not null and (x."visibility" = 'public' or (x."visibility" = 'organization' and x."tenant_id" in (select better_supabase.tenant_ids_with('agents.read'))))) or x."tenant_id" in (select better_supabase.tenant_ids_with('agents.moderate'))) for update;
  if not found then
    raise exception 'agent % not found', rate_agent.agent_id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if v_row."archived_at" is not null then
    raise exception 'agent is archived; restore it first' using errcode = '55000', hint = 'AGENT_ARCHIVED';
  end if;
    if rate_agent.rating is not null and rate_agent.rating not between 1 and 5 then
    raise exception 'a rating is 1 to 5' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  delete from "app_private"."agent_ratings" g where g."agent_id" = v_row."id" and g."user_id" = auth.uid()
  returning g."rating" into v_old;
  if rate_agent.rating is not null then
    insert into "app_private"."agent_ratings" ("agent_id", "user_id", "rating", "comment")
    values (v_row."id", auth.uid(), rate_agent.rating, rate_agent.comment);
  end if;
  update "app_private"."agents" x set
    "rating_count" = x."rating_count" - (case when v_old is null then 0 else 1 end) + (case when rate_agent.rating is null then 0 else 1 end),
    "rating_sum" = x."rating_sum" - coalesce(v_old, 0) + coalesce(rate_agent.rating, 0)
  where x."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
end;
$$;
revoke execute on function "app_private"."rate_agent"(uuid, integer, text) from public, anon;
grant execute on function "app_private"."rate_agent"(uuid, integer, text) to authenticated, service_role;

-- Replaces an agent's skills with a list of {provider, reference}.
create or replace function "app_private"."set_agent_skills"(agent_id uuid, skills jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."agents"%rowtype;
  v_items jsonb := case when jsonb_typeof(set_agent_skills.skills) = 'object' then set_agent_skills.skills -> 'items' else set_agent_skills.skills end;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."agents" x where x."id" = set_agent_skills.agent_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)) then
    raise exception 'agent % not found', set_agent_skills.agent_id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if v_row."archived_at" is not null then
    raise exception 'agent is archived; restore it first' using errcode = '55000', hint = 'AGENT_ARCHIVED';
  end if;
    if jsonb_typeof(v_items) is distinct from 'array' then
    raise exception 'skills must be a list' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  delete from "app_private"."agent_skills" k where k."agent_id" = v_row."id";
  insert into "app_private"."agent_skills" ("agent_id", "provider", "reference", "name", "files", "content_hash", "latest_version", "provider_refs")
  select v_row."id", e ->> 'provider', coalesce(e -> 'reference', '{}'), e ->> 'name', coalesce(e -> 'files', '[]'), e ->> 'content_hash', e ->> 'latest_version', coalesce(e -> 'provider_refs', '{}')
  from jsonb_array_elements(v_items) e;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "app_private"."set_agent_skills"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."set_agent_skills"(uuid, jsonb) to authenticated, service_role;

-- Records what a provider returned for a skill's current content: its
-- reference and the hash it was uploaded from. syncSkill calls it as the
-- service role after uploadSkill, and skips the upload while the hash matches.
create or replace function "app_private"."record_skill_sync"(skill_id uuid, provider text, reference jsonb, content_hash text)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_row "app_private"."agent_skills"%rowtype;
begin
  update "app_private"."agent_skills" k
  set "provider_refs" = k."provider_refs" || jsonb_build_object(record_skill_sync.provider, jsonb_build_object('reference', record_skill_sync.reference, 'content_hash', record_skill_sync.content_hash)),
      "content_hash" = record_skill_sync.content_hash
  where k."id" = record_skill_sync.skill_id
  returning * into v_row;
  if not found then
    raise exception 'agent % not found', record_skill_sync.skill_id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  return v_row."provider_refs";
end;
$$;
revoke execute on function "app_private"."record_skill_sync"(uuid, text, jsonb, text) from public, anon, authenticated;
grant execute on function "app_private"."record_skill_sync"(uuid, text, jsonb, text) to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "app_private"."agents" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (("app_private"."agents"."owner_id" = (select auth.uid()) or ("app_private"."agents"."published_at" is not null and ("app_private"."agents"."visibility" = 'public' or ("app_private"."agents"."visibility" = 'organization' and "app_private"."agents"."tenant_id" in (select better_supabase.tenant_ids_with('agents.read'))))) or "app_private"."agents"."tenant_id" in (select better_supabase.tenant_ids_with('agents.moderate'))))
  );
create policy bsb_tenant_scope_insert on "app_private"."agents" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "app_private"."agents" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "app_private"."agents" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "app_private"."agent_installs" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()))
  );
create policy bsb_tenant_scope_insert on "app_private"."agent_installs" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "app_private"."agent_installs" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "app_private"."agent_installs" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_051_agents.sql
-- better-supabase module: agents
-- @bsb-block-data agents
-- @bsb-hash sha256:89cbc764a7f121e0277343276dfc4456394a839780009117dc1dd6f25a6fbf28
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('agents', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_051_agents.sql
-- better-supabase module: agents
-- @bsb-block agents@2 managed
-- @bsb-hash sha256:7c5f9d2850229cd3a939e7ae40889d00179f51ea4af58e33186d42c4bf39e6c3
-- Custom assistants with instructions, a model, tools, connectors, knowledge scopes and starters; private until published to the organization or the public store, with installs, ratings and provider skills.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Custom assistants: instructions, a model, the tools and connectors they may
-- use and the knowledge they search. An owner keeps an agent private until a
-- member with 'agents.publish' publishes it to the organization or the public store.
create table "better_supabase"."agents" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "owner_id" uuid references auth.users (id) on delete set null,
  "slug" text not null constraint bsb_agents_slug_check check ("slug" ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and length("slug") <= 64),
  "name" text not null constraint bsb_agents_name_check check (length("name") >= 1 and length("name") <= 200),
  "description" text not null default '' constraint bsb_agents_description_check check (length("description") <= 2000),
  "instructions" text not null default '' constraint bsb_agents_instructions_check check (length("instructions") <= 100000),
  "model" text,
  "tools" jsonb not null default '[]' constraint bsb_agents_tools_check check (jsonb_typeof("tools") = 'array'),
  "connector_ids" uuid[] not null default '{}',
  "knowledge_scope" jsonb not null default '[]' constraint bsb_agents_knowledge_scope_check check (jsonb_typeof("knowledge_scope") = 'array'),
  "starters" jsonb not null default '[]' constraint bsb_agents_starters_check check (jsonb_typeof("starters") = 'array'),
  "visibility" text not null default 'private' constraint bsb_agents_visibility_check check ("visibility" in ('private', 'organization', 'public')),
  "published_at" timestamptz,
  "install_count" integer not null default 0,
  "rating_count" integer not null default 0,
  "rating_sum" integer not null default 0,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  "archived_at" timestamptz,
  unique ("tenant_id", "slug")
);
create index agents_owner_idx on "better_supabase"."agents" ("owner_id");
create index agents_published_idx on "better_supabase"."agents" ("visibility", "published_at") where "published_at" is not null;
alter table "better_supabase"."agents" enable row level security;
revoke all on "better_supabase"."agents" from public, anon, authenticated;
grant select on "better_supabase"."agents" to authenticated;
grant all on "better_supabase"."agents" to service_role;
create policy bsb_agents_read on "better_supabase"."agents"
  for select to authenticated
  using (("better_supabase"."agents"."owner_id" = (select auth.uid()) or ("better_supabase"."agents"."published_at" is not null and ("better_supabase"."agents"."visibility" = 'public' or ("better_supabase"."agents"."visibility" = 'organization' and "better_supabase"."agents"."tenant_id" in (select better_supabase.tenant_ids_with('agents.read'))))) or "better_supabase"."agents"."tenant_id" in (select better_supabase.tenant_ids_with('agents.moderate'))));

create table "better_supabase"."agent_installs" (
  "agent_id" uuid not null references "better_supabase"."agents" ("id") on delete cascade,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "tenant_id" uuid not null,
  "installed_at" timestamptz not null default now(),
  primary key ("agent_id", "user_id", "tenant_id")
);
create index agent_installs_user_idx on "better_supabase"."agent_installs" ("user_id", "tenant_id");
alter table "better_supabase"."agent_installs" enable row level security;
revoke all on "better_supabase"."agent_installs" from public, anon, authenticated;
grant select on "better_supabase"."agent_installs" to authenticated;
grant all on "better_supabase"."agent_installs" to service_role;
create policy bsb_agent_installs_read on "better_supabase"."agent_installs"
  for select to authenticated
  using ("user_id" = (select auth.uid()));

create table "better_supabase"."agent_ratings" (
  "agent_id" uuid not null references "better_supabase"."agents" ("id") on delete cascade,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "rating" smallint not null constraint bsb_agent_ratings_rating_check check ("rating" >= 1 and "rating" <= 5),
  "comment" text constraint bsb_agent_ratings_comment_check check (length("comment") <= 2000),
  "created_at" timestamptz not null default now(),
  primary key ("agent_id", "user_id")
);
create index agent_ratings_user_idx on "better_supabase"."agent_ratings" ("user_id");
alter table "better_supabase"."agent_ratings" enable row level security;
revoke all on "better_supabase"."agent_ratings" from public, anon, authenticated;
grant select on "better_supabase"."agent_ratings" to authenticated;
grant all on "better_supabase"."agent_ratings" to service_role;
create policy bsb_agent_ratings_read on "better_supabase"."agent_ratings"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."agents" x where x."id" = "agent_id"));

-- Skills an agent loads from a provider (a reference such as a skill id).
create table "better_supabase"."agent_skills" (
  "id" uuid primary key default gen_random_uuid(),
  "agent_id" uuid not null references "better_supabase"."agents" ("id") on delete cascade,
  "provider" text not null constraint bsb_agent_skills_provider_check check (length("provider") >= 1 and length("provider") <= 100),
  "reference" jsonb not null constraint bsb_agent_skills_reference_check check (jsonb_typeof("reference") = 'object'),
  -- Skill files kept in Storage (a list of {path, object}), the hash of their
  -- bytes, and the reference each provider returned for that hash.
  "name" text,
  "files" jsonb not null default '[]' constraint bsb_agent_skills_files_check check (jsonb_typeof("files") = 'array'),
  "content_hash" text,
  "latest_version" text,
  "provider_refs" jsonb not null default '{}' constraint bsb_agent_skills_provider_refs_check check (jsonb_typeof("provider_refs") = 'object'),
  "created_at" timestamptz not null default now()
);
create index agent_skills_agent_idx on "better_supabase"."agent_skills" ("agent_id");
alter table "better_supabase"."agent_skills" enable row level security;
revoke all on "better_supabase"."agent_skills" from public, anon, authenticated;
grant select on "better_supabase"."agent_skills" to authenticated;
grant all on "better_supabase"."agent_skills" to service_role;
create policy bsb_agent_skills_read on "better_supabase"."agent_skills"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."agents" x where x."id" = "agent_id"));

-- Creates an agent (id null, needs 'agents.write') or changes one its owner or a
-- moderator may change. fields holds the columns to set; visibility and
-- published_at change through publish_agent only.
create or replace function "better_supabase"."save_agent"(tenant uuid, id uuid default null, fields jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."agents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(save_agent.fields) is distinct from 'object' then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  if save_agent.id is null then
    if auth.uid() is null or not coalesce(better_supabase.can('tenant', save_agent.tenant, 'agents.write'), false) then
      raise exception 'you may not create agents here' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
    end if;
    if save_agent.fields ->> 'slug' is null or save_agent.fields ->> 'name' is null then
      raise exception 'a new agent needs a slug and a name' using errcode = '22023', hint = 'AGENT_INVALID';
    end if;
    insert into "better_supabase"."agents" ("tenant_id", "owner_id", "slug", "name")
    values (save_agent.tenant, auth.uid(), save_agent.fields ->> 'slug', save_agent.fields ->> 'name')
    returning * into v_row;
  else
    select * into v_row from "better_supabase"."agents" x where x."id" = save_agent.id and x."tenant_id" = save_agent.tenant for update;
    if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)) then
      raise exception 'agent % not found', save_agent.id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
    end if;
    if v_row."archived_at" is not null then
    raise exception 'agent is archived; restore it first' using errcode = '55000', hint = 'AGENT_ARCHIVED';
  end if;
  
  end if;
  update "better_supabase"."agents" x set
    "slug" = coalesce(save_agent.fields ->> 'slug', x."slug"),
    "name" = coalesce(save_agent.fields ->> 'name', x."name"),
    "description" = coalesce(save_agent.fields ->> 'description', x."description"),
    "instructions" = coalesce(save_agent.fields ->> 'instructions', x."instructions"),
    "model" = case when save_agent.fields ? 'model' then save_agent.fields ->> 'model' else x."model" end,
    "tools" = coalesce(save_agent.fields -> 'tools', x."tools"),
    "connector_ids" = case when save_agent.fields ? 'connector_ids'
      then array(select jsonb_array_elements_text(save_agent.fields -> 'connector_ids')::uuid)
      else x."connector_ids" end,
    "knowledge_scope" = coalesce(save_agent.fields -> 'knowledge_scope', x."knowledge_scope"),
    "starters" = coalesce(save_agent.fields -> 'starters', x."starters"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if save_agent.id is null then
    null;
  else
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
exception
  when unique_violation then
    raise exception 'an agent with slug % exists', save_agent.fields ->> 'slug' using errcode = '23505', hint = 'AGENT_SLUG_TAKEN';
end;
$$;
revoke execute on function "better_supabase"."save_agent"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_agent"(uuid, uuid, jsonb) to authenticated, service_role;

-- Publishes an agent to the organization or the public store, or makes it
-- private again. The owner needs 'agents.publish'; a moderator may always unpublish.
create or replace function "better_supabase"."publish_agent"(id uuid, visibility text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."agents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if publish_agent.visibility is null or publish_agent.visibility not in ('private', 'organization', 'public') then
    raise exception 'visibility is private, organization or public' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = publish_agent.id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)) then
    raise exception 'agent % not found', publish_agent.id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if v_row."archived_at" is not null then
    raise exception 'agent is archived; restore it first' using errcode = '55000', hint = 'AGENT_ARCHIVED';
  end if;
    if publish_agent.visibility <> 'private' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)
    or (coalesce(v_row."owner_id" = auth.uid(), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.publish'), false))) then
    raise exception 'you may not publish agents here' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
  end if;
  update "better_supabase"."agents" x set
    "visibility" = publish_agent.visibility,
    "published_at" = case when publish_agent.visibility = 'private' then null else coalesce(x."published_at", now()) end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
end;
$$;
revoke execute on function "better_supabase"."publish_agent"(uuid, text) from public, anon;
grant execute on function "better_supabase"."publish_agent"(uuid, text) to authenticated, service_role;

-- Archives an agent: it leaves the store, the lists and new installs, and it can't be changed, published or rated until it is restored. Installs, ratings and skills stay. The owner or a moderator may; archiving an archived agent returns it unchanged.
create or replace function "better_supabase"."archive_agent"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."agents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = archive_agent.id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)) then
    raise exception 'agent % not found', archive_agent.id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if (v_row."archived_at" is not null) = true then
    return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
  end if;
  update "better_supabase"."agents" x set "archived_at" = now(), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
end;
$$;
revoke execute on function "better_supabase"."archive_agent"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_agent"(uuid) to authenticated, service_role;

-- Restores an archived agent with the visibility it had. The owner or a moderator may; restoring one that is not archived returns it unchanged.
create or replace function "better_supabase"."restore_agent"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."agents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = restore_agent.id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)) then
    raise exception 'agent % not found', restore_agent.id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if (v_row."archived_at" is not null) = false then
    return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
  end if;
  update "better_supabase"."agents" x set "archived_at" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
end;
$$;
revoke execute on function "better_supabase"."restore_agent"(uuid) from public, anon;
grant execute on function "better_supabase"."restore_agent"(uuid) to authenticated, service_role;

-- Deletes an agent for good with its installs, ratings and skills; archive
-- keeps them. Needs 'agents.moderate', which falls back to the moderate key, and the
-- owner needs it too. False when the caller can't see the agent.

create or replace function "better_supabase"."purge_agent"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."agents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = purge_agent.id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)) then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)) then
    raise exception 'you may not purge agents here' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
  end if;
  delete from "better_supabase"."agents" x where x."id" = v_row."id";
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."purge_agent"(uuid) from public, anon;
grant execute on function "better_supabase"."purge_agent"(uuid) to authenticated, service_role;

-- An agent by id or by slug in a tenant, with its skills, when the caller may read it.
create or replace function "better_supabase"."get_agent"(id uuid default null, tenant uuid default null, slug text default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_row "better_supabase"."agents"%rowtype;
begin
  select * into v_row from "better_supabase"."agents" x
  where (get_agent.id is not null and x."id" = get_agent.id)
    or (get_agent.id is null and x."tenant_id" = get_agent.tenant and x."slug" = get_agent.slug);
  if not found then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at") || jsonb_build_object(
    'skills', coalesce((select jsonb_agg(jsonb_build_object('id', k."id", 'provider', k."provider", 'reference', k."reference", 'name', k."name", 'files', k."files", 'content_hash', k."content_hash", 'latest_version', k."latest_version", 'provider_refs', k."provider_refs") order by k."created_at") from "better_supabase"."agent_skills" k where k."agent_id" = v_row."id"), '[]'),
    'installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = v_row."id" and n."user_id" = auth.uid()),
    'my_rating', (select g."rating" from "better_supabase"."agent_ratings" g where g."agent_id" = v_row."id" and g."user_id" = auth.uid())
  );
end;
$$;
revoke execute on function "better_supabase"."get_agent"(uuid, uuid, text) from public, anon;
grant execute on function "better_supabase"."get_agent"(uuid, uuid, text) to authenticated, service_role;

-- Agents the caller may read: 'mine', 'installed' in the tenant, or the
-- 'store' (published to the tenant or public), newest first. Archived agents
-- stay out unless include_archived is true.

create or replace function "better_supabase"."list_agents"(tenant uuid, filter text default 'store', search text default null, max_rows integer default 50, include_archived boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(y.row order by y.at desc), '[]')
  from (
    select jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = list_agents.tenant)) as row,
      coalesce(x."published_at", x."updated_at") as at
    from "better_supabase"."agents" x
    where case list_agents.filter
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = list_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = list_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = list_agents.tenant)
      end
      and (coalesce(list_agents.include_archived, false) or x."archived_at" is null)
      and (list_agents.search is null or x."name" ilike '%' || replace(replace(list_agents.search, '%', '\%'), '_', '\_') || '%'
        or x."description" ilike '%' || replace(replace(list_agents.search, '%', '\%'), '_', '\_') || '%')
    order by coalesce(x."published_at", x."updated_at") desc
    limit least(greatest(list_agents.max_rows, 1), 200)
  ) y
$$;
revoke execute on function "better_supabase"."list_agents"(uuid, text, text, integer, boolean) from public, anon;
grant execute on function "better_supabase"."list_agents"(uuid, text, text, integer, boolean) to authenticated, service_role;

-- Agents as a keyset page (ADR 1077): the same three modes as list_agents.
-- filters is { mode ('store' by default, 'mine' or 'installed'), visibility (a
-- value or a list), includeArchived, search (name, description), sort (name,
-- updatedAt, createdAt, installCount), direction, facet, count, limit, after,
-- offset, paged, total, totalCap }. The default order is the newest published
-- or updated agent first.
create or replace function "better_supabase"."page_agents"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_agents.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_mode text := coalesce(nullif(coalesce(v_filters #>> '{mode,0}', v_filters ->> 'mode'), ''), 'store');
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if v_mode not in ('store', 'mine', 'installed') then
    raise exception 'mode is store, mine or installed' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'visibility') = 'array' then v_filters -> 'visibility' when jsonb_typeof(v_filters -> 'visibility') in ('string', 'number') then jsonb_build_array(v_filters -> 'visibility') else '[]'::jsonb end) s where s not in ('private', 'organization', 'public')) then
    raise exception 'visibility is private, organization or public' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('visibility') then
      raise exception 'facet is one of visibility' using errcode = '22023', hint = 'AGENT_INVALID';
    end if;
    with s as (
      select (case v_facet when 'visibility' then (x."visibility")::text end) as v
      from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'updatedAt', 'createdAt', 'installCount') then
    raise exception 'sort is one of name, updatedAt, createdAt, installCount' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((coalesce(x."published_at", x."updated_at"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (coalesce(x."published_at", x."updated_at"), x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."published_at", x."updated_at") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((coalesce(x."published_at", x."updated_at"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (coalesce(x."published_at", x."updated_at") <= (v_after ->> 0)::timestamptz and ((coalesce(x."published_at", x."updated_at") < (v_after ->> 0)::timestamptz) or (coalesce(x."published_at", x."updated_at") = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."published_at", x."updated_at") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."updated_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."updated_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."updated_at" <= (v_after ->> 0)::timestamptz and ((x."updated_at" < (v_after ->> 0)::timestamptz) or (x."updated_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."updated_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'installCount' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((coalesce(x."install_count", 0))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (coalesce(x."install_count", 0), x."id") > ((v_after ->> 0)::integer, (v_after ->> 1)::uuid))
      order by coalesce(x."install_count", 0) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'installCount' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((coalesce(x."install_count", 0))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (coalesce(x."install_count", 0) <= (v_after ->> 0)::integer and ((coalesce(x."install_count", 0) < (v_after ->> 0)::integer) or (coalesce(x."install_count", 0) = (v_after ->> 0)::integer and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."install_count", 0) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_agents"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."page_agents"(uuid, jsonb) to authenticated, service_role;

-- Adds a readable agent to the caller's list in a tenant they belong to, or removes it.
create or replace function "better_supabase"."install_agent"(tenant uuid, agent_id uuid, installed boolean default true)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null or not coalesce(better_supabase.can('tenant', install_agent.tenant, 'agents.read'), false) then
    raise exception 'you may not use agents here' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
  end if;
  if not install_agent.installed then
    delete from "better_supabase"."agent_installs" n where n."agent_id" = install_agent.agent_id and n."user_id" = auth.uid() and n."tenant_id" = install_agent.tenant;
    get diagnostics v_count = row_count;
    update "better_supabase"."agents" x set "install_count" = greatest(x."install_count" - v_count, 0) where x."id" = install_agent.agent_id;
    if v_count > 0 then
      null;
    end if;
    return v_count > 0;
  end if;
  if not exists (select 1 from "better_supabase"."agents" x where x."id" = install_agent.agent_id and (x."owner_id" = (select auth.uid()) or (x."published_at" is not null and (x."visibility" = 'public' or (x."visibility" = 'organization' and x."tenant_id" in (select better_supabase.tenant_ids_with('agents.read'))))) or x."tenant_id" in (select better_supabase.tenant_ids_with('agents.moderate')))) then
    raise exception 'agent % not found', install_agent.agent_id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if exists (select 1 from "better_supabase"."agents" x where x."id" = install_agent.agent_id and x."archived_at" is not null) then
    raise exception 'agent is archived; restore it first' using errcode = '55000', hint = 'AGENT_ARCHIVED';
  end if;
  insert into "better_supabase"."agent_installs" ("agent_id", "user_id", "tenant_id") values (install_agent.agent_id, auth.uid(), install_agent.tenant)
  on conflict do nothing;
  get diagnostics v_count = row_count;
  update "better_supabase"."agents" x set "install_count" = x."install_count" + v_count where x."id" = install_agent.agent_id;
  if v_count > 0 then
    null;
  end if;
  return v_count > 0;
end;
$$;
revoke execute on function "better_supabase"."install_agent"(uuid, uuid, boolean) from public, anon;
grant execute on function "better_supabase"."install_agent"(uuid, uuid, boolean) to authenticated, service_role;

-- Rates a readable agent 1 to 5, replacing the caller's rating; null removes it.
create or replace function "better_supabase"."rate_agent"(agent_id uuid, rating integer, comment text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old integer;
  v_row "better_supabase"."agents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    raise exception 'sign in to rate agents' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = rate_agent.agent_id and (x."owner_id" = (select auth.uid()) or (x."published_at" is not null and (x."visibility" = 'public' or (x."visibility" = 'organization' and x."tenant_id" in (select better_supabase.tenant_ids_with('agents.read'))))) or x."tenant_id" in (select better_supabase.tenant_ids_with('agents.moderate'))) for update;
  if not found then
    raise exception 'agent % not found', rate_agent.agent_id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if v_row."archived_at" is not null then
    raise exception 'agent is archived; restore it first' using errcode = '55000', hint = 'AGENT_ARCHIVED';
  end if;
    if rate_agent.rating is not null and rate_agent.rating not between 1 and 5 then
    raise exception 'a rating is 1 to 5' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  delete from "better_supabase"."agent_ratings" g where g."agent_id" = v_row."id" and g."user_id" = auth.uid()
  returning g."rating" into v_old;
  if rate_agent.rating is not null then
    insert into "better_supabase"."agent_ratings" ("agent_id", "user_id", "rating", "comment")
    values (v_row."id", auth.uid(), rate_agent.rating, rate_agent.comment);
  end if;
  update "better_supabase"."agents" x set
    "rating_count" = x."rating_count" - (case when v_old is null then 0 else 1 end) + (case when rate_agent.rating is null then 0 else 1 end),
    "rating_sum" = x."rating_sum" - coalesce(v_old, 0) + coalesce(rate_agent.rating, 0)
  where x."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
end;
$$;
revoke execute on function "better_supabase"."rate_agent"(uuid, integer, text) from public, anon;
grant execute on function "better_supabase"."rate_agent"(uuid, integer, text) to authenticated, service_role;

-- Replaces an agent's skills with a list of {provider, reference}.
create or replace function "better_supabase"."set_agent_skills"(agent_id uuid, skills jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."agents"%rowtype;
  v_items jsonb := case when jsonb_typeof(set_agent_skills.skills) = 'object' then set_agent_skills.skills -> 'items' else set_agent_skills.skills end;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = set_agent_skills.agent_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)) then
    raise exception 'agent % not found', set_agent_skills.agent_id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if v_row."archived_at" is not null then
    raise exception 'agent is archived; restore it first' using errcode = '55000', hint = 'AGENT_ARCHIVED';
  end if;
    if jsonb_typeof(v_items) is distinct from 'array' then
    raise exception 'skills must be a list' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  delete from "better_supabase"."agent_skills" k where k."agent_id" = v_row."id";
  insert into "better_supabase"."agent_skills" ("agent_id", "provider", "reference", "name", "files", "content_hash", "latest_version", "provider_refs")
  select v_row."id", e ->> 'provider', coalesce(e -> 'reference', '{}'), e ->> 'name', coalesce(e -> 'files', '[]'), e ->> 'content_hash', e ->> 'latest_version', coalesce(e -> 'provider_refs', '{}')
  from jsonb_array_elements(v_items) e;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."set_agent_skills"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."set_agent_skills"(uuid, jsonb) to authenticated, service_role;

-- Records what a provider returned for a skill's current content: its
-- reference and the hash it was uploaded from. syncSkill calls it as the
-- service role after uploadSkill, and skips the upload while the hash matches.
create or replace function "better_supabase"."record_skill_sync"(skill_id uuid, provider text, reference jsonb, content_hash text)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_row "better_supabase"."agent_skills"%rowtype;
begin
  update "better_supabase"."agent_skills" k
  set "provider_refs" = k."provider_refs" || jsonb_build_object(record_skill_sync.provider, jsonb_build_object('reference', record_skill_sync.reference, 'content_hash', record_skill_sync.content_hash)),
      "content_hash" = record_skill_sync.content_hash
  where k."id" = record_skill_sync.skill_id
  returning * into v_row;
  if not found then
    raise exception 'agent % not found', record_skill_sync.skill_id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  return v_row."provider_refs";
end;
$$;
revoke execute on function "better_supabase"."record_skill_sync"(uuid, text, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."record_skill_sync"(uuid, text, jsonb, text) to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."agents" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (("better_supabase"."agents"."owner_id" = (select auth.uid()) or ("better_supabase"."agents"."published_at" is not null and ("better_supabase"."agents"."visibility" = 'public' or ("better_supabase"."agents"."visibility" = 'organization' and "better_supabase"."agents"."tenant_id" in (select better_supabase.tenant_ids_with('agents.read'))))) or "better_supabase"."agents"."tenant_id" in (select better_supabase.tenant_ids_with('agents.moderate'))))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."agents" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."agents" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."agents" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."agent_installs" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."agent_installs" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."agent_installs" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."agent_installs" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.agents.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."save_agent"(tenant uuid, id uuid default null, fields jsonb default '{}')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_agent"($1, $2, $3) $$;
revoke execute on function "api"."save_agent"(uuid, uuid, jsonb) from public, anon;
grant execute on function "api"."save_agent"(uuid, uuid, jsonb) to authenticated, service_role;

create or replace function "api"."publish_agent"(id uuid, visibility text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."publish_agent"($1, $2) $$;
revoke execute on function "api"."publish_agent"(uuid, text) from public, anon;
grant execute on function "api"."publish_agent"(uuid, text) to authenticated, service_role;

create or replace function "api"."archive_agent"(id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."archive_agent"($1) $$;
revoke execute on function "api"."archive_agent"(uuid) from public, anon;
grant execute on function "api"."archive_agent"(uuid) to authenticated, service_role;

create or replace function "api"."restore_agent"(id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."restore_agent"($1) $$;
revoke execute on function "api"."restore_agent"(uuid) from public, anon;
grant execute on function "api"."restore_agent"(uuid) to authenticated, service_role;

create or replace function "api"."purge_agent"(id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."purge_agent"($1) $$;
revoke execute on function "api"."purge_agent"(uuid) from public, anon;
grant execute on function "api"."purge_agent"(uuid) to authenticated, service_role;

create or replace function "api"."get_agent"(id uuid default null, tenant uuid default null, slug text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."get_agent"($1, $2, $3) $$;
revoke execute on function "api"."get_agent"(uuid, uuid, text) from public, anon;
grant execute on function "api"."get_agent"(uuid, uuid, text) to authenticated, service_role;

create or replace function "api"."list_agents"(tenant uuid, filter text default 'store', search text default null, max_rows integer default 50, include_archived boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_agents"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."list_agents"(uuid, text, text, integer, boolean) from public, anon;
grant execute on function "api"."list_agents"(uuid, text, text, integer, boolean) to authenticated, service_role;

create or replace function "api"."page_agents"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."page_agents"($1, $2) $$;
revoke execute on function "api"."page_agents"(uuid, jsonb) from public, anon;
grant execute on function "api"."page_agents"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."install_agent"(tenant uuid, agent_id uuid, installed boolean default true)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."install_agent"($1, $2, $3) $$;
revoke execute on function "api"."install_agent"(uuid, uuid, boolean) from public, anon;
grant execute on function "api"."install_agent"(uuid, uuid, boolean) to authenticated, service_role;

create or replace function "api"."rate_agent"(agent_id uuid, rating integer, comment text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."rate_agent"($1, $2, $3) $$;
revoke execute on function "api"."rate_agent"(uuid, integer, text) from public, anon;
grant execute on function "api"."rate_agent"(uuid, integer, text) to authenticated, service_role;

create or replace function "api"."set_agent_skills"(agent_id uuid, skills jsonb)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_agent_skills"($1, $2) $$;
revoke execute on function "api"."set_agent_skills"(uuid, jsonb) from public, anon;
grant execute on function "api"."set_agent_skills"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."record_skill_sync"(skill_id uuid, provider text, reference jsonb, content_hash text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_skill_sync"($1, $2, $3, $4) $$;
revoke execute on function "api"."record_skill_sync"(uuid, text, jsonb, text) from public, anon, authenticated;
grant execute on function "api"."record_skill_sync"(uuid, text, jsonb, text) to service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_051_agents.sql
-- better-supabase module: agents
-- @bsb-block-data agents
-- @bsb-hash sha256:89cbc764a7f121e0277343276dfc4456394a839780009117dc1dd6f25a6fbf28
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('agents', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_051_agents.sql
-- better-supabase module: agents
-- @bsb-block agents@2 managed
-- @bsb-hash sha256:7aeed09e89b391fe7b6547e712f2055029f5383f8d973aa83ef24cd6ed8bef42
-- Custom assistants with instructions, a model, tools, connectors, knowledge scopes and starters; private until published to the organization or the public store, with installs, ratings and provider skills.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Custom assistants: instructions, a model, the tools and connectors they may
-- use and the knowledge they search. An owner keeps an agent private until a
-- member with 'agents.publish' publishes it to the organization or the public store.
-- better_supabase.agents is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."agents" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."agents" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."agents" add column if not exists "owner_id" uuid references auth.users (id) on delete set null;
alter table "better_supabase"."agents" add column if not exists "slug" text constraint bsb_agents_slug_check check ("slug" ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and length("slug") <= 64);
alter table "better_supabase"."agents" add column if not exists "name" text constraint bsb_agents_name_check check (length("name") >= 1 and length("name") <= 200);
alter table "better_supabase"."agents" add column if not exists "description" text not null default '' constraint bsb_agents_description_check check (length("description") <= 2000);
alter table "better_supabase"."agents" add column if not exists "instructions" text not null default '' constraint bsb_agents_instructions_check check (length("instructions") <= 100000);
alter table "better_supabase"."agents" add column if not exists "model" text;
alter table "better_supabase"."agents" add column if not exists "tools" jsonb not null default '[]' constraint bsb_agents_tools_check check (jsonb_typeof("tools") = 'array');
alter table "better_supabase"."agents" add column if not exists "connector_ids" uuid[] not null default '{}';
alter table "better_supabase"."agents" add column if not exists "knowledge_scope" jsonb not null default '[]' constraint bsb_agents_knowledge_scope_check check (jsonb_typeof("knowledge_scope") = 'array');
alter table "better_supabase"."agents" add column if not exists "starters" jsonb not null default '[]' constraint bsb_agents_starters_check check (jsonb_typeof("starters") = 'array');
alter table "better_supabase"."agents" add column if not exists "visibility" text not null default 'private' constraint bsb_agents_visibility_check check ("visibility" in ('private', 'organization', 'public'));
alter table "better_supabase"."agents" add column if not exists "published_at" timestamptz;
alter table "better_supabase"."agents" add column if not exists "install_count" integer not null default 0;
alter table "better_supabase"."agents" add column if not exists "rating_count" integer not null default 0;
alter table "better_supabase"."agents" add column if not exists "rating_sum" integer not null default 0;
alter table "better_supabase"."agents" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."agents" add column if not exists "updated_at" timestamptz not null default now();
alter table "better_supabase"."agents" add column if not exists "archived_at" timestamptz;
alter table "better_supabase"."agents" add column if not exists "archived_at" timestamptz;
create index if not exists agents_owner_idx on "better_supabase"."agents" ("owner_id");
create index if not exists agents_published_idx on "better_supabase"."agents" ("visibility", "published_at") where "published_at" is not null;
alter table "better_supabase"."agents" enable row level security;
grant select on "better_supabase"."agents" to authenticated;
grant all on "better_supabase"."agents" to service_role;
create policy bsb_agents_select on "better_supabase"."agents"
  for select to authenticated
  using (("better_supabase"."agents"."owner_id" = (select auth.uid()) or ("better_supabase"."agents"."published_at" is not null and ("better_supabase"."agents"."visibility" = 'public' or ("better_supabase"."agents"."visibility" = 'organization' and "better_supabase"."agents"."tenant_id" in (select better_supabase.tenant_ids_with('agents.read'))))) or "better_supabase"."agents"."tenant_id" in (select better_supabase.tenant_ids_with('agents.moderate'))));

-- better_supabase.agent_installs is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."agent_installs" add column if not exists "agent_id" uuid references "better_supabase"."agents" ("id") on delete cascade;
alter table "better_supabase"."agent_installs" add column if not exists "user_id" uuid references auth.users (id) on delete cascade;
alter table "better_supabase"."agent_installs" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."agent_installs" add column if not exists "installed_at" timestamptz not null default now();
create unique index if not exists "bsb_agent_installs_install_key" on "better_supabase"."agent_installs" ("agent_id", "user_id", "tenant_id");
create index if not exists agent_installs_user_idx on "better_supabase"."agent_installs" ("user_id", "tenant_id");
alter table "better_supabase"."agent_installs" enable row level security;
grant select on "better_supabase"."agent_installs" to authenticated;
grant all on "better_supabase"."agent_installs" to service_role;
create policy bsb_agent_installs_select on "better_supabase"."agent_installs"
  for select to authenticated
  using ("user_id" = (select auth.uid()));

-- better_supabase.agent_ratings is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."agent_ratings" add column if not exists "agent_id" uuid references "better_supabase"."agents" ("id") on delete cascade;
alter table "better_supabase"."agent_ratings" add column if not exists "user_id" uuid references auth.users (id) on delete cascade;
alter table "better_supabase"."agent_ratings" add column if not exists "rating" smallint constraint bsb_agent_ratings_rating_check check ("rating" >= 1 and "rating" <= 5);
alter table "better_supabase"."agent_ratings" add column if not exists "comment" text constraint bsb_agent_ratings_comment_check check (length("comment") <= 2000);
alter table "better_supabase"."agent_ratings" add column if not exists "created_at" timestamptz not null default now();
create index if not exists agent_ratings_user_idx on "better_supabase"."agent_ratings" ("user_id");
alter table "better_supabase"."agent_ratings" enable row level security;
grant select on "better_supabase"."agent_ratings" to authenticated;
grant all on "better_supabase"."agent_ratings" to service_role;
create policy bsb_agent_ratings_select on "better_supabase"."agent_ratings"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."agents" x where x."id" = "agent_id"));

-- Skills an agent loads from a provider (a reference such as a skill id).
-- better_supabase.agent_skills is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."agent_skills" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."agent_skills" add column if not exists "agent_id" uuid references "better_supabase"."agents" ("id") on delete cascade;
alter table "better_supabase"."agent_skills" add column if not exists "provider" text constraint bsb_agent_skills_provider_check check (length("provider") >= 1 and length("provider") <= 100);
alter table "better_supabase"."agent_skills" add column if not exists "reference" jsonb constraint bsb_agent_skills_reference_check check (jsonb_typeof("reference") = 'object');
alter table "better_supabase"."agent_skills" add column if not exists "name" text;
alter table "better_supabase"."agent_skills" add column if not exists "files" jsonb not null default '[]' constraint bsb_agent_skills_files_check check (jsonb_typeof("files") = 'array');
alter table "better_supabase"."agent_skills" add column if not exists "content_hash" text;
alter table "better_supabase"."agent_skills" add column if not exists "latest_version" text;
alter table "better_supabase"."agent_skills" add column if not exists "provider_refs" jsonb not null default '{}' constraint bsb_agent_skills_provider_refs_check check (jsonb_typeof("provider_refs") = 'object');
alter table "better_supabase"."agent_skills" add column if not exists "created_at" timestamptz not null default now();
create index if not exists agent_skills_agent_idx on "better_supabase"."agent_skills" ("agent_id");
alter table "better_supabase"."agent_skills" enable row level security;
grant select on "better_supabase"."agent_skills" to authenticated;
grant all on "better_supabase"."agent_skills" to service_role;
create policy bsb_agent_skills_select on "better_supabase"."agent_skills"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."agents" x where x."id" = "agent_id"));

-- Creates an agent (id null, needs 'agents.write') or changes one its owner or a
-- moderator may change. fields holds the columns to set; visibility and
-- published_at change through publish_agent only.
create or replace function "better_supabase"."save_agent"(tenant uuid, id uuid default null, fields jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."agents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(save_agent.fields) is distinct from 'object' then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  if save_agent.id is null then
    if auth.uid() is null or not coalesce(better_supabase.can('tenant', save_agent.tenant, 'agents.write'), false) then
      raise exception 'you may not create agents here' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
    end if;
    if save_agent.fields ->> 'slug' is null or save_agent.fields ->> 'name' is null then
      raise exception 'a new agent needs a slug and a name' using errcode = '22023', hint = 'AGENT_INVALID';
    end if;
    insert into "better_supabase"."agents" ("tenant_id", "owner_id", "slug", "name")
    values (save_agent.tenant, auth.uid(), save_agent.fields ->> 'slug', save_agent.fields ->> 'name')
    returning * into v_row;
  else
    select * into v_row from "better_supabase"."agents" x where x."id" = save_agent.id and x."tenant_id" = save_agent.tenant for update;
    if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)) then
      raise exception 'agent % not found', save_agent.id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
    end if;
    if v_row."archived_at" is not null then
    raise exception 'agent is archived; restore it first' using errcode = '55000', hint = 'AGENT_ARCHIVED';
  end if;
  
  end if;
  update "better_supabase"."agents" x set
    "slug" = coalesce(save_agent.fields ->> 'slug', x."slug"),
    "name" = coalesce(save_agent.fields ->> 'name', x."name"),
    "description" = coalesce(save_agent.fields ->> 'description', x."description"),
    "instructions" = coalesce(save_agent.fields ->> 'instructions', x."instructions"),
    "model" = case when save_agent.fields ? 'model' then save_agent.fields ->> 'model' else x."model" end,
    "tools" = coalesce(save_agent.fields -> 'tools', x."tools"),
    "connector_ids" = case when save_agent.fields ? 'connector_ids'
      then array(select jsonb_array_elements_text(save_agent.fields -> 'connector_ids')::uuid)
      else x."connector_ids" end,
    "knowledge_scope" = coalesce(save_agent.fields -> 'knowledge_scope', x."knowledge_scope"),
    "starters" = coalesce(save_agent.fields -> 'starters', x."starters"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if save_agent.id is null then
    null;
  else
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
exception
  when unique_violation then
    raise exception 'an agent with slug % exists', save_agent.fields ->> 'slug' using errcode = '23505', hint = 'AGENT_SLUG_TAKEN';
end;
$$;
revoke execute on function "better_supabase"."save_agent"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_agent"(uuid, uuid, jsonb) to authenticated, service_role;

-- Publishes an agent to the organization or the public store, or makes it
-- private again. The owner needs 'agents.publish'; a moderator may always unpublish.
create or replace function "better_supabase"."publish_agent"(id uuid, visibility text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."agents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if publish_agent.visibility is null or publish_agent.visibility not in ('private', 'organization', 'public') then
    raise exception 'visibility is private, organization or public' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = publish_agent.id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)) then
    raise exception 'agent % not found', publish_agent.id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if v_row."archived_at" is not null then
    raise exception 'agent is archived; restore it first' using errcode = '55000', hint = 'AGENT_ARCHIVED';
  end if;
    if publish_agent.visibility <> 'private' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)
    or (coalesce(v_row."owner_id" = auth.uid(), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.publish'), false))) then
    raise exception 'you may not publish agents here' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
  end if;
  update "better_supabase"."agents" x set
    "visibility" = better_supabase.as_column_type(publish_agent.visibility, (null::"better_supabase"."agents")."visibility"),
    "published_at" = case when publish_agent.visibility = 'private' then null else coalesce(x."published_at", now()) end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
end;
$$;
revoke execute on function "better_supabase"."publish_agent"(uuid, text) from public, anon;
grant execute on function "better_supabase"."publish_agent"(uuid, text) to authenticated, service_role;

-- Archives an agent: it leaves the store, the lists and new installs, and it can't be changed, published or rated until it is restored. Installs, ratings and skills stay. The owner or a moderator may; archiving an archived agent returns it unchanged.
create or replace function "better_supabase"."archive_agent"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."agents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = archive_agent.id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)) then
    raise exception 'agent % not found', archive_agent.id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if (v_row."archived_at" is not null) = true then
    return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
  end if;
  update "better_supabase"."agents" x set "archived_at" = now(), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
end;
$$;
revoke execute on function "better_supabase"."archive_agent"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_agent"(uuid) to authenticated, service_role;

-- Restores an archived agent with the visibility it had. The owner or a moderator may; restoring one that is not archived returns it unchanged.
create or replace function "better_supabase"."restore_agent"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."agents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = restore_agent.id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)) then
    raise exception 'agent % not found', restore_agent.id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if (v_row."archived_at" is not null) = false then
    return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
  end if;
  update "better_supabase"."agents" x set "archived_at" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
end;
$$;
revoke execute on function "better_supabase"."restore_agent"(uuid) from public, anon;
grant execute on function "better_supabase"."restore_agent"(uuid) to authenticated, service_role;

-- Deletes an agent for good with its installs, ratings and skills; archive
-- keeps them. Needs 'agents.moderate', which falls back to the moderate key, and the
-- owner needs it too. False when the caller can't see the agent.

create or replace function "better_supabase"."purge_agent"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."agents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = purge_agent.id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)) then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)) then
    raise exception 'you may not purge agents here' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
  end if;
  delete from "better_supabase"."agents" x where x."id" = v_row."id";
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."purge_agent"(uuid) from public, anon;
grant execute on function "better_supabase"."purge_agent"(uuid) to authenticated, service_role;

-- An agent by id or by slug in a tenant, with its skills, when the caller may read it.
create or replace function "better_supabase"."get_agent"(id uuid default null, tenant uuid default null, slug text default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_row "better_supabase"."agents"%rowtype;
begin
  select * into v_row from "better_supabase"."agents" x
  where (get_agent.id is not null and x."id" = get_agent.id)
    or (get_agent.id is null and x."tenant_id" = get_agent.tenant and x."slug" = get_agent.slug);
  if not found then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at") || jsonb_build_object(
    'skills', coalesce((select jsonb_agg(jsonb_build_object('id', k."id", 'provider', k."provider", 'reference', k."reference", 'name', k."name", 'files', k."files", 'content_hash', k."content_hash", 'latest_version', k."latest_version", 'provider_refs', k."provider_refs") order by k."created_at") from "better_supabase"."agent_skills" k where k."agent_id" = v_row."id"), '[]'),
    'installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = v_row."id" and n."user_id" = auth.uid()),
    'my_rating', (select g."rating" from "better_supabase"."agent_ratings" g where g."agent_id" = v_row."id" and g."user_id" = auth.uid())
  );
end;
$$;
revoke execute on function "better_supabase"."get_agent"(uuid, uuid, text) from public, anon;
grant execute on function "better_supabase"."get_agent"(uuid, uuid, text) to authenticated, service_role;

-- Agents the caller may read: 'mine', 'installed' in the tenant, or the
-- 'store' (published to the tenant or public), newest first. Archived agents
-- stay out unless include_archived is true.

create or replace function "better_supabase"."list_agents"(tenant uuid, filter text default 'store', search text default null, max_rows integer default 50, include_archived boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(y.row order by y.at desc), '[]')
  from (
    select jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = list_agents.tenant)) as row,
      coalesce(x."published_at", x."updated_at") as at
    from "better_supabase"."agents" x
    where case list_agents.filter
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = list_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = list_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = list_agents.tenant)
      end
      and (coalesce(list_agents.include_archived, false) or x."archived_at" is null)
      and (list_agents.search is null or x."name" ilike '%' || replace(replace(list_agents.search, '%', '\%'), '_', '\_') || '%'
        or x."description" ilike '%' || replace(replace(list_agents.search, '%', '\%'), '_', '\_') || '%')
    order by coalesce(x."published_at", x."updated_at") desc
    limit least(greatest(list_agents.max_rows, 1), 200)
  ) y
$$;
revoke execute on function "better_supabase"."list_agents"(uuid, text, text, integer, boolean) from public, anon;
grant execute on function "better_supabase"."list_agents"(uuid, text, text, integer, boolean) to authenticated, service_role;

-- Agents as a keyset page (ADR 1077): the same three modes as list_agents.
-- filters is { mode ('store' by default, 'mine' or 'installed'), visibility (a
-- value or a list), includeArchived, search (name, description), sort (name,
-- updatedAt, createdAt, installCount), direction, facet, count, limit, after,
-- offset, paged, total, totalCap }. The default order is the newest published
-- or updated agent first.
create or replace function "better_supabase"."page_agents"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_agents.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_mode text := coalesce(nullif(coalesce(v_filters #>> '{mode,0}', v_filters ->> 'mode'), ''), 'store');
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if v_mode not in ('store', 'mine', 'installed') then
    raise exception 'mode is store, mine or installed' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'visibility') = 'array' then v_filters -> 'visibility' when jsonb_typeof(v_filters -> 'visibility') in ('string', 'number') then jsonb_build_array(v_filters -> 'visibility') else '[]'::jsonb end) s where s not in ('private', 'organization', 'public')) then
    raise exception 'visibility is private, organization or public' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('visibility') then
      raise exception 'facet is one of visibility' using errcode = '22023', hint = 'AGENT_INVALID';
    end if;
    with s as (
      select (case v_facet when 'visibility' then (x."visibility")::text end) as v
      from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'updatedAt', 'createdAt', 'installCount') then
    raise exception 'sort is one of name, updatedAt, createdAt, installCount' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((coalesce(x."published_at", x."updated_at"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (coalesce(x."published_at", x."updated_at"), x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."published_at", x."updated_at") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((coalesce(x."published_at", x."updated_at"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (coalesce(x."published_at", x."updated_at") <= (v_after ->> 0)::timestamptz and ((coalesce(x."published_at", x."updated_at") < (v_after ->> 0)::timestamptz) or (coalesce(x."published_at", x."updated_at") = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."published_at", x."updated_at") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."updated_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."updated_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."updated_at" <= (v_after ->> 0)::timestamptz and ((x."updated_at" < (v_after ->> 0)::timestamptz) or (x."updated_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."updated_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'installCount' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((coalesce(x."install_count", 0))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (coalesce(x."install_count", 0), x."id") > ((v_after ->> 0)::integer, (v_after ->> 1)::uuid))
      order by coalesce(x."install_count", 0) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'installCount' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((coalesce(x."install_count", 0))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (coalesce(x."install_count", 0) <= (v_after ->> 0)::integer and ((coalesce(x."install_count", 0) < (v_after ->> 0)::integer) or (coalesce(x."install_count", 0) = (v_after ->> 0)::integer and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."install_count", 0) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_agents"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."page_agents"(uuid, jsonb) to authenticated, service_role;

-- Adds a readable agent to the caller's list in a tenant they belong to, or removes it.
create or replace function "better_supabase"."install_agent"(tenant uuid, agent_id uuid, installed boolean default true)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null or not coalesce(better_supabase.can('tenant', install_agent.tenant, 'agents.read'), false) then
    raise exception 'you may not use agents here' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
  end if;
  if not install_agent.installed then
    delete from "better_supabase"."agent_installs" n where n."agent_id" = install_agent.agent_id and n."user_id" = auth.uid() and n."tenant_id" = install_agent.tenant;
    get diagnostics v_count = row_count;
    update "better_supabase"."agents" x set "install_count" = greatest(x."install_count" - v_count, 0) where x."id" = install_agent.agent_id;
    if v_count > 0 then
      null;
    end if;
    return v_count > 0;
  end if;
  if not exists (select 1 from "better_supabase"."agents" x where x."id" = install_agent.agent_id and (x."owner_id" = (select auth.uid()) or (x."published_at" is not null and (x."visibility" = 'public' or (x."visibility" = 'organization' and x."tenant_id" in (select better_supabase.tenant_ids_with('agents.read'))))) or x."tenant_id" in (select better_supabase.tenant_ids_with('agents.moderate')))) then
    raise exception 'agent % not found', install_agent.agent_id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if exists (select 1 from "better_supabase"."agents" x where x."id" = install_agent.agent_id and x."archived_at" is not null) then
    raise exception 'agent is archived; restore it first' using errcode = '55000', hint = 'AGENT_ARCHIVED';
  end if;
  insert into "better_supabase"."agent_installs" ("agent_id", "user_id", "tenant_id") values (install_agent.agent_id, auth.uid(), install_agent.tenant)
  on conflict do nothing;
  get diagnostics v_count = row_count;
  update "better_supabase"."agents" x set "install_count" = x."install_count" + v_count where x."id" = install_agent.agent_id;
  if v_count > 0 then
    null;
  end if;
  return v_count > 0;
end;
$$;
revoke execute on function "better_supabase"."install_agent"(uuid, uuid, boolean) from public, anon;
grant execute on function "better_supabase"."install_agent"(uuid, uuid, boolean) to authenticated, service_role;

-- Rates a readable agent 1 to 5, replacing the caller's rating; null removes it.
create or replace function "better_supabase"."rate_agent"(agent_id uuid, rating integer, comment text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old integer;
  v_row "better_supabase"."agents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    raise exception 'sign in to rate agents' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = rate_agent.agent_id and (x."owner_id" = (select auth.uid()) or (x."published_at" is not null and (x."visibility" = 'public' or (x."visibility" = 'organization' and x."tenant_id" in (select better_supabase.tenant_ids_with('agents.read'))))) or x."tenant_id" in (select better_supabase.tenant_ids_with('agents.moderate'))) for update;
  if not found then
    raise exception 'agent % not found', rate_agent.agent_id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if v_row."archived_at" is not null then
    raise exception 'agent is archived; restore it first' using errcode = '55000', hint = 'AGENT_ARCHIVED';
  end if;
    if rate_agent.rating is not null and rate_agent.rating not between 1 and 5 then
    raise exception 'a rating is 1 to 5' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  delete from "better_supabase"."agent_ratings" g where g."agent_id" = v_row."id" and g."user_id" = auth.uid()
  returning g."rating" into v_old;
  if rate_agent.rating is not null then
    insert into "better_supabase"."agent_ratings" ("agent_id", "user_id", "rating", "comment")
    values (v_row."id", auth.uid(), rate_agent.rating, rate_agent.comment);
  end if;
  update "better_supabase"."agents" x set
    "rating_count" = x."rating_count" - (case when v_old is null then 0 else 1 end) + (case when rate_agent.rating is null then 0 else 1 end),
    "rating_sum" = x."rating_sum" - coalesce(v_old, 0) + coalesce(rate_agent.rating, 0)
  where x."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
end;
$$;
revoke execute on function "better_supabase"."rate_agent"(uuid, integer, text) from public, anon;
grant execute on function "better_supabase"."rate_agent"(uuid, integer, text) to authenticated, service_role;

-- Replaces an agent's skills with a list of {provider, reference}.
create or replace function "better_supabase"."set_agent_skills"(agent_id uuid, skills jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."agents"%rowtype;
  v_items jsonb := case when jsonb_typeof(set_agent_skills.skills) = 'object' then set_agent_skills.skills -> 'items' else set_agent_skills.skills end;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = set_agent_skills.agent_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)) then
    raise exception 'agent % not found', set_agent_skills.agent_id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if v_row."archived_at" is not null then
    raise exception 'agent is archived; restore it first' using errcode = '55000', hint = 'AGENT_ARCHIVED';
  end if;
    if jsonb_typeof(v_items) is distinct from 'array' then
    raise exception 'skills must be a list' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  delete from "better_supabase"."agent_skills" k where k."agent_id" = v_row."id";
  insert into "better_supabase"."agent_skills" ("agent_id", "provider", "reference", "name", "files", "content_hash", "latest_version", "provider_refs")
  select v_row."id", e ->> 'provider', coalesce(e -> 'reference', '{}'), e ->> 'name', coalesce(e -> 'files', '[]'), e ->> 'content_hash', e ->> 'latest_version', coalesce(e -> 'provider_refs', '{}')
  from jsonb_array_elements(v_items) e;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."set_agent_skills"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."set_agent_skills"(uuid, jsonb) to authenticated, service_role;

-- Records what a provider returned for a skill's current content: its
-- reference and the hash it was uploaded from. syncSkill calls it as the
-- service role after uploadSkill, and skips the upload while the hash matches.
create or replace function "better_supabase"."record_skill_sync"(skill_id uuid, provider text, reference jsonb, content_hash text)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_row "better_supabase"."agent_skills"%rowtype;
begin
  update "better_supabase"."agent_skills" k
  set "provider_refs" = k."provider_refs" || jsonb_build_object(record_skill_sync.provider, jsonb_build_object('reference', record_skill_sync.reference, 'content_hash', record_skill_sync.content_hash)),
      "content_hash" = record_skill_sync.content_hash
  where k."id" = record_skill_sync.skill_id
  returning * into v_row;
  if not found then
    raise exception 'agent % not found', record_skill_sync.skill_id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  return v_row."provider_refs";
end;
$$;
revoke execute on function "better_supabase"."record_skill_sync"(uuid, text, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."record_skill_sync"(uuid, text, jsonb, text) to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."agents" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (("better_supabase"."agents"."owner_id" = (select auth.uid()) or ("better_supabase"."agents"."published_at" is not null and ("better_supabase"."agents"."visibility" = 'public' or ("better_supabase"."agents"."visibility" = 'organization' and "better_supabase"."agents"."tenant_id" in (select better_supabase.tenant_ids_with('agents.read'))))) or "better_supabase"."agents"."tenant_id" in (select better_supabase.tenant_ids_with('agents.moderate'))))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."agents" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."agents" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."agents" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."agent_installs" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."agent_installs" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."agent_installs" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."agent_installs" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_051_agents.sql
-- better-supabase module: agents
-- @bsb-block-data agents
-- @bsb-hash sha256:89cbc764a7f121e0277343276dfc4456394a839780009117dc1dd6f25a6fbf28
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('agents', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_051_agents.sql
-- better-supabase module: agents
-- @bsb-block agents@2 managed
-- @bsb-hash sha256:de2d25241f53c4e1715424a7c2e236d2bda7aec29de1fbf7afead04c37c3743d
-- Custom assistants with instructions, a model, tools, connectors, knowledge scopes and starters; private until published to the organization or the public store, with installs, ratings and provider skills.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Custom assistants: instructions, a model, the tools and connectors they may
-- use and the knowledge they search. An owner keeps an agent private until a
-- member with 'agents.publish' publishes it to the organization or the public store.
create table "better_supabase"."agents" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "owner_id" uuid references auth.users (id) on delete set null,
  "slug" text not null constraint bsb_agents_slug_check check ("slug" ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and length("slug") <= 64),
  "name" text not null constraint bsb_agents_name_check check (length("name") >= 1 and length("name") <= 200),
  "description" text not null default '' constraint bsb_agents_description_check check (length("description") <= 2000),
  "instructions" text not null default '' constraint bsb_agents_instructions_check check (length("instructions") <= 100000),
  "model" text,
  "tools" jsonb not null default '[]' constraint bsb_agents_tools_check check (jsonb_typeof("tools") = 'array'),
  "connector_ids" uuid[] not null default '{}',
  "knowledge_scope" jsonb not null default '[]' constraint bsb_agents_knowledge_scope_check check (jsonb_typeof("knowledge_scope") = 'array'),
  "starters" jsonb not null default '[]' constraint bsb_agents_starters_check check (jsonb_typeof("starters") = 'array'),
  "visibility" text not null default 'private' constraint bsb_agents_visibility_check check ("visibility" in ('private', 'organization', 'public')),
  "published_at" timestamptz,
  "install_count" integer not null default 0,
  "rating_count" integer not null default 0,
  "rating_sum" integer not null default 0,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  "archived_at" timestamptz,
  unique ("org_id", "slug")
);
create index agents_owner_idx on "better_supabase"."agents" ("owner_id");
create index agents_published_idx on "better_supabase"."agents" ("visibility", "published_at") where "published_at" is not null;
alter table "better_supabase"."agents" enable row level security;
revoke all on "better_supabase"."agents" from public, anon, authenticated;
grant select on "better_supabase"."agents" to authenticated;
grant all on "better_supabase"."agents" to service_role;
create policy bsb_agents_read on "better_supabase"."agents"
  for select to authenticated
  using (("better_supabase"."agents"."owner_id" = (select auth.uid()) or ("better_supabase"."agents"."published_at" is not null and ("better_supabase"."agents"."visibility" = 'public' or ("better_supabase"."agents"."visibility" = 'organization' and "better_supabase"."agents"."org_id" in (select better_supabase.tenant_ids_with('agents.read'))))) or "better_supabase"."agents"."org_id" in (select better_supabase.tenant_ids_with('agents.moderate'))));

create table "better_supabase"."agent_installs" (
  "agent_id" uuid not null references "better_supabase"."agents" ("id") on delete cascade,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "org_id" uuid not null,
  "installed_at" timestamptz not null default now(),
  primary key ("agent_id", "user_id", "org_id")
);
create index agent_installs_user_idx on "better_supabase"."agent_installs" ("user_id", "org_id");
alter table "better_supabase"."agent_installs" enable row level security;
revoke all on "better_supabase"."agent_installs" from public, anon, authenticated;
grant select on "better_supabase"."agent_installs" to authenticated;
grant all on "better_supabase"."agent_installs" to service_role;
create policy bsb_agent_installs_read on "better_supabase"."agent_installs"
  for select to authenticated
  using ("user_id" = (select auth.uid()));

create table "better_supabase"."agent_ratings" (
  "agent_id" uuid not null references "better_supabase"."agents" ("id") on delete cascade,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "rating" smallint not null constraint bsb_agent_ratings_rating_check check ("rating" >= 1 and "rating" <= 5),
  "comment" text constraint bsb_agent_ratings_comment_check check (length("comment") <= 2000),
  "created_at" timestamptz not null default now(),
  primary key ("agent_id", "user_id")
);
create index agent_ratings_user_idx on "better_supabase"."agent_ratings" ("user_id");
alter table "better_supabase"."agent_ratings" enable row level security;
revoke all on "better_supabase"."agent_ratings" from public, anon, authenticated;
grant select on "better_supabase"."agent_ratings" to authenticated;
grant all on "better_supabase"."agent_ratings" to service_role;
create policy bsb_agent_ratings_read on "better_supabase"."agent_ratings"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."agents" x where x."id" = "agent_id"));

-- Skills an agent loads from a provider (a reference such as a skill id).
create table "better_supabase"."agent_skills" (
  "id" uuid primary key default gen_random_uuid(),
  "agent_id" uuid not null references "better_supabase"."agents" ("id") on delete cascade,
  "provider" text not null constraint bsb_agent_skills_provider_check check (length("provider") >= 1 and length("provider") <= 100),
  "reference" jsonb not null constraint bsb_agent_skills_reference_check check (jsonb_typeof("reference") = 'object'),
  -- Skill files kept in Storage (a list of {path, object}), the hash of their
  -- bytes, and the reference each provider returned for that hash.
  "name" text,
  "files" jsonb not null default '[]' constraint bsb_agent_skills_files_check check (jsonb_typeof("files") = 'array'),
  "content_hash" text,
  "latest_version" text,
  "provider_refs" jsonb not null default '{}' constraint bsb_agent_skills_provider_refs_check check (jsonb_typeof("provider_refs") = 'object'),
  "created_at" timestamptz not null default now()
);
create index agent_skills_agent_idx on "better_supabase"."agent_skills" ("agent_id");
alter table "better_supabase"."agent_skills" enable row level security;
revoke all on "better_supabase"."agent_skills" from public, anon, authenticated;
grant select on "better_supabase"."agent_skills" to authenticated;
grant all on "better_supabase"."agent_skills" to service_role;
create policy bsb_agent_skills_read on "better_supabase"."agent_skills"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."agents" x where x."id" = "agent_id"));

-- Creates an agent (id null, needs 'agents.write') or changes one its owner or a
-- moderator may change. fields holds the columns to set; visibility and
-- published_at change through publish_agent only.
create or replace function "better_supabase"."save_agent"(tenant uuid, id uuid default null, fields jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."agents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(save_agent.fields) is distinct from 'object' then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  if save_agent.id is null then
    if auth.uid() is null or not coalesce(better_supabase.can('tenant', save_agent.tenant, 'agents.write'), false) then
      raise exception 'you may not create agents here' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
    end if;
    if save_agent.fields ->> 'slug' is null or save_agent.fields ->> 'name' is null then
      raise exception 'a new agent needs a slug and a name' using errcode = '22023', hint = 'AGENT_INVALID';
    end if;
    insert into "better_supabase"."agents" ("org_id", "owner_id", "slug", "name")
    values (save_agent.tenant, auth.uid(), save_agent.fields ->> 'slug', save_agent.fields ->> 'name')
    returning * into v_row;
  else
    select * into v_row from "better_supabase"."agents" x where x."id" = save_agent.id and x."org_id" = save_agent.tenant for update;
    if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."org_id", 'agents.moderate'), false)) then
      raise exception 'agent % not found', save_agent.id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
    end if;
    if v_row."archived_at" is not null then
    raise exception 'agent is archived; restore it first' using errcode = '55000', hint = 'AGENT_ARCHIVED';
  end if;
  
  end if;
  update "better_supabase"."agents" x set
    "slug" = coalesce(save_agent.fields ->> 'slug', x."slug"),
    "name" = coalesce(save_agent.fields ->> 'name', x."name"),
    "description" = coalesce(save_agent.fields ->> 'description', x."description"),
    "instructions" = coalesce(save_agent.fields ->> 'instructions', x."instructions"),
    "model" = case when save_agent.fields ? 'model' then save_agent.fields ->> 'model' else x."model" end,
    "tools" = coalesce(save_agent.fields -> 'tools', x."tools"),
    "connector_ids" = case when save_agent.fields ? 'connector_ids'
      then array(select jsonb_array_elements_text(save_agent.fields -> 'connector_ids')::uuid)
      else x."connector_ids" end,
    "knowledge_scope" = coalesce(save_agent.fields -> 'knowledge_scope', x."knowledge_scope"),
    "starters" = coalesce(save_agent.fields -> 'starters', x."starters"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if save_agent.id is null then
    null;
  else
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."org_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
exception
  when unique_violation then
    raise exception 'an agent with slug % exists', save_agent.fields ->> 'slug' using errcode = '23505', hint = 'AGENT_SLUG_TAKEN';
end;
$$;
revoke execute on function "better_supabase"."save_agent"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_agent"(uuid, uuid, jsonb) to authenticated, service_role;

-- Publishes an agent to the organization or the public store, or makes it
-- private again. The owner needs 'agents.publish'; a moderator may always unpublish.
create or replace function "better_supabase"."publish_agent"(id uuid, visibility text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."agents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if publish_agent.visibility is null or publish_agent.visibility not in ('private', 'organization', 'public') then
    raise exception 'visibility is private, organization or public' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = publish_agent.id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."org_id", 'agents.moderate'), false)) then
    raise exception 'agent % not found', publish_agent.id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if v_row."archived_at" is not null then
    raise exception 'agent is archived; restore it first' using errcode = '55000', hint = 'AGENT_ARCHIVED';
  end if;
    if publish_agent.visibility <> 'private' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'agents.moderate'), false)
    or (coalesce(v_row."owner_id" = auth.uid(), false) and coalesce(better_supabase.can('tenant', v_row."org_id", 'agents.publish'), false))) then
    raise exception 'you may not publish agents here' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
  end if;
  update "better_supabase"."agents" x set
    "visibility" = publish_agent.visibility,
    "published_at" = case when publish_agent.visibility = 'private' then null else coalesce(x."published_at", now()) end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."org_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
end;
$$;
revoke execute on function "better_supabase"."publish_agent"(uuid, text) from public, anon;
grant execute on function "better_supabase"."publish_agent"(uuid, text) to authenticated, service_role;

-- Archives an agent: it leaves the store, the lists and new installs, and it can't be changed, published or rated until it is restored. Installs, ratings and skills stay. The owner or a moderator may; archiving an archived agent returns it unchanged.
create or replace function "better_supabase"."archive_agent"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."agents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = archive_agent.id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."org_id", 'agents.moderate'), false)) then
    raise exception 'agent % not found', archive_agent.id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if (v_row."archived_at" is not null) = true then
    return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."org_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
  end if;
  update "better_supabase"."agents" x set "archived_at" = now(), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."org_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
end;
$$;
revoke execute on function "better_supabase"."archive_agent"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_agent"(uuid) to authenticated, service_role;

-- Restores an archived agent with the visibility it had. The owner or a moderator may; restoring one that is not archived returns it unchanged.
create or replace function "better_supabase"."restore_agent"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."agents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = restore_agent.id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."org_id", 'agents.moderate'), false)) then
    raise exception 'agent % not found', restore_agent.id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if (v_row."archived_at" is not null) = false then
    return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."org_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
  end if;
  update "better_supabase"."agents" x set "archived_at" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."org_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
end;
$$;
revoke execute on function "better_supabase"."restore_agent"(uuid) from public, anon;
grant execute on function "better_supabase"."restore_agent"(uuid) to authenticated, service_role;

-- Deletes an agent for good with its installs, ratings and skills; archive
-- keeps them. Needs 'agents.moderate', which falls back to the moderate key, and the
-- owner needs it too. False when the caller can't see the agent.

create or replace function "better_supabase"."purge_agent"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."agents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = purge_agent.id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."org_id", 'agents.moderate'), false)) then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'agents.moderate'), false)) then
    raise exception 'you may not purge agents here' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
  end if;
  delete from "better_supabase"."agents" x where x."id" = v_row."id";
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."purge_agent"(uuid) from public, anon;
grant execute on function "better_supabase"."purge_agent"(uuid) to authenticated, service_role;

-- An agent by id or by slug in a tenant, with its skills, when the caller may read it.
create or replace function "better_supabase"."get_agent"(id uuid default null, tenant uuid default null, slug text default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_row "better_supabase"."agents"%rowtype;
begin
  select * into v_row from "better_supabase"."agents" x
  where (get_agent.id is not null and x."id" = get_agent.id)
    or (get_agent.id is null and x."org_id" = get_agent.tenant and x."slug" = get_agent.slug);
  if not found then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."org_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at") || jsonb_build_object(
    'skills', coalesce((select jsonb_agg(jsonb_build_object('id', k."id", 'provider', k."provider", 'reference', k."reference", 'name', k."name", 'files', k."files", 'content_hash', k."content_hash", 'latest_version', k."latest_version", 'provider_refs', k."provider_refs") order by k."created_at") from "better_supabase"."agent_skills" k where k."agent_id" = v_row."id"), '[]'),
    'installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = v_row."id" and n."user_id" = auth.uid()),
    'my_rating', (select g."rating" from "better_supabase"."agent_ratings" g where g."agent_id" = v_row."id" and g."user_id" = auth.uid())
  );
end;
$$;
revoke execute on function "better_supabase"."get_agent"(uuid, uuid, text) from public, anon;
grant execute on function "better_supabase"."get_agent"(uuid, uuid, text) to authenticated, service_role;

-- Agents the caller may read: 'mine', 'installed' in the tenant, or the
-- 'store' (published to the tenant or public), newest first. Archived agents
-- stay out unless include_archived is true.

create or replace function "better_supabase"."list_agents"(tenant uuid, filter text default 'store', search text default null, max_rows integer default 50, include_archived boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(y.row order by y.at desc), '[]')
  from (
    select jsonb_build_object('id', x."id", 'tenant_id', x."org_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."org_id" = list_agents.tenant)) as row,
      coalesce(x."published_at", x."updated_at") as at
    from "better_supabase"."agents" x
    where case list_agents.filter
        when 'mine' then x."owner_id" = auth.uid() and x."org_id" = list_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."org_id" = list_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."org_id" = list_agents.tenant)
      end
      and (coalesce(list_agents.include_archived, false) or x."archived_at" is null)
      and (list_agents.search is null or x."name" ilike '%' || replace(replace(list_agents.search, '%', '\%'), '_', '\_') || '%'
        or x."description" ilike '%' || replace(replace(list_agents.search, '%', '\%'), '_', '\_') || '%')
    order by coalesce(x."published_at", x."updated_at") desc
    limit least(greatest(list_agents.max_rows, 1), 200)
  ) y
$$;
revoke execute on function "better_supabase"."list_agents"(uuid, text, text, integer, boolean) from public, anon;
grant execute on function "better_supabase"."list_agents"(uuid, text, text, integer, boolean) to authenticated, service_role;

-- Agents as a keyset page (ADR 1077): the same three modes as list_agents.
-- filters is { mode ('store' by default, 'mine' or 'installed'), visibility (a
-- value or a list), includeArchived, search (name, description), sort (name,
-- updatedAt, createdAt, installCount), direction, facet, count, limit, after,
-- offset, paged, total, totalCap }. The default order is the newest published
-- or updated agent first.
create or replace function "better_supabase"."page_agents"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_agents.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_mode text := coalesce(nullif(coalesce(v_filters #>> '{mode,0}', v_filters ->> 'mode'), ''), 'store');
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if v_mode not in ('store', 'mine', 'installed') then
    raise exception 'mode is store, mine or installed' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'visibility') = 'array' then v_filters -> 'visibility' when jsonb_typeof(v_filters -> 'visibility') in ('string', 'number') then jsonb_build_array(v_filters -> 'visibility') else '[]'::jsonb end) s where s not in ('private', 'organization', 'public')) then
    raise exception 'visibility is private, organization or public' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('visibility') then
      raise exception 'facet is one of visibility' using errcode = '22023', hint = 'AGENT_INVALID';
    end if;
    with s as (
      select (case v_facet when 'visibility' then (x."visibility")::text end) as v
      from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."org_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."org_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."org_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."org_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."org_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."org_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'updatedAt', 'createdAt', 'installCount') then
    raise exception 'sort is one of name, updatedAt, createdAt, installCount' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."org_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."org_id" = page_agents.tenant)) as j, jsonb_build_array((coalesce(x."published_at", x."updated_at"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."org_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."org_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."org_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (coalesce(x."published_at", x."updated_at"), x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."published_at", x."updated_at") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."org_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."org_id" = page_agents.tenant)) as j, jsonb_build_array((coalesce(x."published_at", x."updated_at"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."org_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."org_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."org_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (coalesce(x."published_at", x."updated_at") <= (v_after ->> 0)::timestamptz and ((coalesce(x."published_at", x."updated_at") < (v_after ->> 0)::timestamptz) or (coalesce(x."published_at", x."updated_at") = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."published_at", x."updated_at") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."org_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."org_id" = page_agents.tenant)) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."org_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."org_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."org_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."org_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."org_id" = page_agents.tenant)) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."org_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."org_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."org_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."org_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."org_id" = page_agents.tenant)) as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."org_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."org_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."org_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."updated_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."updated_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."org_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."org_id" = page_agents.tenant)) as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."org_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."org_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."org_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."updated_at" <= (v_after ->> 0)::timestamptz and ((x."updated_at" < (v_after ->> 0)::timestamptz) or (x."updated_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."updated_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."org_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."org_id" = page_agents.tenant)) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."org_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."org_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."org_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."org_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."org_id" = page_agents.tenant)) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."org_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."org_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."org_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'installCount' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."org_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."org_id" = page_agents.tenant)) as j, jsonb_build_array((coalesce(x."install_count", 0))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."org_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."org_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."org_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (coalesce(x."install_count", 0), x."id") > ((v_after ->> 0)::integer, (v_after ->> 1)::uuid))
      order by coalesce(x."install_count", 0) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'installCount' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."org_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."org_id" = page_agents.tenant)) as j, jsonb_build_array((coalesce(x."install_count", 0))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."org_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."org_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."org_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (coalesce(x."install_count", 0) <= (v_after ->> 0)::integer and ((coalesce(x."install_count", 0) < (v_after ->> 0)::integer) or (coalesce(x."install_count", 0) = (v_after ->> 0)::integer and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."install_count", 0) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."org_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."org_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."org_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_agents"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."page_agents"(uuid, jsonb) to authenticated, service_role;

-- Adds a readable agent to the caller's list in a tenant they belong to, or removes it.
create or replace function "better_supabase"."install_agent"(tenant uuid, agent_id uuid, installed boolean default true)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null or not coalesce(better_supabase.can('tenant', install_agent.tenant, 'agents.read'), false) then
    raise exception 'you may not use agents here' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
  end if;
  if not install_agent.installed then
    delete from "better_supabase"."agent_installs" n where n."agent_id" = install_agent.agent_id and n."user_id" = auth.uid() and n."org_id" = install_agent.tenant;
    get diagnostics v_count = row_count;
    update "better_supabase"."agents" x set "install_count" = greatest(x."install_count" - v_count, 0) where x."id" = install_agent.agent_id;
    if v_count > 0 then
      null;
    end if;
    return v_count > 0;
  end if;
  if not exists (select 1 from "better_supabase"."agents" x where x."id" = install_agent.agent_id and (x."owner_id" = (select auth.uid()) or (x."published_at" is not null and (x."visibility" = 'public' or (x."visibility" = 'organization' and x."org_id" in (select better_supabase.tenant_ids_with('agents.read'))))) or x."org_id" in (select better_supabase.tenant_ids_with('agents.moderate')))) then
    raise exception 'agent % not found', install_agent.agent_id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if exists (select 1 from "better_supabase"."agents" x where x."id" = install_agent.agent_id and x."archived_at" is not null) then
    raise exception 'agent is archived; restore it first' using errcode = '55000', hint = 'AGENT_ARCHIVED';
  end if;
  insert into "better_supabase"."agent_installs" ("agent_id", "user_id", "org_id") values (install_agent.agent_id, auth.uid(), install_agent.tenant)
  on conflict do nothing;
  get diagnostics v_count = row_count;
  update "better_supabase"."agents" x set "install_count" = x."install_count" + v_count where x."id" = install_agent.agent_id;
  if v_count > 0 then
    null;
  end if;
  return v_count > 0;
end;
$$;
revoke execute on function "better_supabase"."install_agent"(uuid, uuid, boolean) from public, anon;
grant execute on function "better_supabase"."install_agent"(uuid, uuid, boolean) to authenticated, service_role;

-- Rates a readable agent 1 to 5, replacing the caller's rating; null removes it.
create or replace function "better_supabase"."rate_agent"(agent_id uuid, rating integer, comment text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old integer;
  v_row "better_supabase"."agents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    raise exception 'sign in to rate agents' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = rate_agent.agent_id and (x."owner_id" = (select auth.uid()) or (x."published_at" is not null and (x."visibility" = 'public' or (x."visibility" = 'organization' and x."org_id" in (select better_supabase.tenant_ids_with('agents.read'))))) or x."org_id" in (select better_supabase.tenant_ids_with('agents.moderate'))) for update;
  if not found then
    raise exception 'agent % not found', rate_agent.agent_id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if v_row."archived_at" is not null then
    raise exception 'agent is archived; restore it first' using errcode = '55000', hint = 'AGENT_ARCHIVED';
  end if;
    if rate_agent.rating is not null and rate_agent.rating not between 1 and 5 then
    raise exception 'a rating is 1 to 5' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  delete from "better_supabase"."agent_ratings" g where g."agent_id" = v_row."id" and g."user_id" = auth.uid()
  returning g."rating" into v_old;
  if rate_agent.rating is not null then
    insert into "better_supabase"."agent_ratings" ("agent_id", "user_id", "rating", "comment")
    values (v_row."id", auth.uid(), rate_agent.rating, rate_agent.comment);
  end if;
  update "better_supabase"."agents" x set
    "rating_count" = x."rating_count" - (case when v_old is null then 0 else 1 end) + (case when rate_agent.rating is null then 0 else 1 end),
    "rating_sum" = x."rating_sum" - coalesce(v_old, 0) + coalesce(rate_agent.rating, 0)
  where x."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."org_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
end;
$$;
revoke execute on function "better_supabase"."rate_agent"(uuid, integer, text) from public, anon;
grant execute on function "better_supabase"."rate_agent"(uuid, integer, text) to authenticated, service_role;

-- Replaces an agent's skills with a list of {provider, reference}.
create or replace function "better_supabase"."set_agent_skills"(agent_id uuid, skills jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."agents"%rowtype;
  v_items jsonb := case when jsonb_typeof(set_agent_skills.skills) = 'object' then set_agent_skills.skills -> 'items' else set_agent_skills.skills end;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = set_agent_skills.agent_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."org_id", 'agents.moderate'), false)) then
    raise exception 'agent % not found', set_agent_skills.agent_id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if v_row."archived_at" is not null then
    raise exception 'agent is archived; restore it first' using errcode = '55000', hint = 'AGENT_ARCHIVED';
  end if;
    if jsonb_typeof(v_items) is distinct from 'array' then
    raise exception 'skills must be a list' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  delete from "better_supabase"."agent_skills" k where k."agent_id" = v_row."id";
  insert into "better_supabase"."agent_skills" ("agent_id", "provider", "reference", "name", "files", "content_hash", "latest_version", "provider_refs")
  select v_row."id", e ->> 'provider', coalesce(e -> 'reference', '{}'), e ->> 'name', coalesce(e -> 'files', '[]'), e ->> 'content_hash', e ->> 'latest_version', coalesce(e -> 'provider_refs', '{}')
  from jsonb_array_elements(v_items) e;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."set_agent_skills"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."set_agent_skills"(uuid, jsonb) to authenticated, service_role;

-- Records what a provider returned for a skill's current content: its
-- reference and the hash it was uploaded from. syncSkill calls it as the
-- service role after uploadSkill, and skips the upload while the hash matches.
create or replace function "better_supabase"."record_skill_sync"(skill_id uuid, provider text, reference jsonb, content_hash text)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_row "better_supabase"."agent_skills"%rowtype;
begin
  update "better_supabase"."agent_skills" k
  set "provider_refs" = k."provider_refs" || jsonb_build_object(record_skill_sync.provider, jsonb_build_object('reference', record_skill_sync.reference, 'content_hash', record_skill_sync.content_hash)),
      "content_hash" = record_skill_sync.content_hash
  where k."id" = record_skill_sync.skill_id
  returning * into v_row;
  if not found then
    raise exception 'agent % not found', record_skill_sync.skill_id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  return v_row."provider_refs";
end;
$$;
revoke execute on function "better_supabase"."record_skill_sync"(uuid, text, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."record_skill_sync"(uuid, text, jsonb, text) to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."agents" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or (("better_supabase"."agents"."owner_id" = (select auth.uid()) or ("better_supabase"."agents"."published_at" is not null and ("better_supabase"."agents"."visibility" = 'public' or ("better_supabase"."agents"."visibility" = 'organization' and "better_supabase"."agents"."org_id" in (select better_supabase.tenant_ids_with('agents.read'))))) or "better_supabase"."agents"."org_id" in (select better_supabase.tenant_ids_with('agents.moderate'))))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."agents" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."agents" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."agents" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."agent_installs" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."agent_installs" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."agent_installs" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."agent_installs" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_051_agents.sql
-- better-supabase module: agents
-- @bsb-block-data agents
-- @bsb-hash sha256:89cbc764a7f121e0277343276dfc4456394a839780009117dc1dd6f25a6fbf28
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('agents', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
