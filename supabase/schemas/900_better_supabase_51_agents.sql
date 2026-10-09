-- better-supabase module: agents (0.5.1)
-- @bs-module agents@1 managed
-- Custom assistants with instructions, a model, tools, connectors, knowledge scopes and starters; private until published to the organization or the public store, with installs, ratings and provider skills.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Custom assistants: instructions, a model, the tools and connectors they may
-- use and the knowledge they search. An owner keeps an agent private until a
-- member with 'ai_chat.share' publishes it to the organization or the public store.
create table if not exists "better_supabase"."agents" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null,
  "owner_id" uuid references auth.users (id) on delete set null,
  "slug" text not null check ("slug" ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and length("slug") <= 64),
  "name" text not null check (length("name") between 1 and 200),
  "description" text not null default '' check (length("description") <= 2000),
  "instructions" text not null default '' check (length("instructions") <= 100000),
  "model" text,
  "tools" jsonb not null default '[]' check (jsonb_typeof("tools") = 'array'),
  "connector_ids" uuid[] not null default '{}',
  "knowledge_scope" jsonb not null default '[]' check (jsonb_typeof("knowledge_scope") = 'array'),
  "starters" jsonb not null default '[]' check (jsonb_typeof("starters") = 'array'),
  "visibility" text not null default 'private' check ("visibility" in ('private', 'organization', 'public')),
  "published_at" timestamptz,
  "install_count" integer not null default 0,
  "rating_count" integer not null default 0,
  "rating_sum" integer not null default 0,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("organization_id", "slug")
);
create index if not exists agents_owner_idx on "better_supabase"."agents" ("owner_id");
create index if not exists agents_published_idx on "better_supabase"."agents" ("visibility", "published_at") where "published_at" is not null;
alter table "better_supabase"."agents" enable row level security;
revoke all on "better_supabase"."agents" from anon, authenticated;
grant select on "better_supabase"."agents" to authenticated;
grant all on "better_supabase"."agents" to service_role;
drop policy if exists agents_read on "better_supabase"."agents";
create policy agents_read on "better_supabase"."agents" for select to authenticated
  using ("better_supabase"."agents"."owner_id" = (select auth.uid()) or ("better_supabase"."agents"."published_at" is not null and ("better_supabase"."agents"."visibility" = 'public' or ("better_supabase"."agents"."visibility" = 'organization' and "better_supabase"."agents"."organization_id" in (select better_supabase.tenant_ids_with('ai_chat.read'))))) or "better_supabase"."agents"."organization_id" in (select better_supabase.tenant_ids_with('ai_chat.moderate')));

create table if not exists "better_supabase"."agent_installs" (
  "agent_id" uuid not null references "better_supabase"."agents" ("id") on delete cascade,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "organization_id" uuid not null,
  "installed_at" timestamptz not null default now(),
  primary key ("agent_id", "user_id", "organization_id")
);
create index if not exists agent_installs_user_idx on "better_supabase"."agent_installs" ("user_id", "organization_id");
alter table "better_supabase"."agent_installs" enable row level security;
revoke all on "better_supabase"."agent_installs" from anon, authenticated;
grant select on "better_supabase"."agent_installs" to authenticated;
grant all on "better_supabase"."agent_installs" to service_role;
drop policy if exists agent_installs_read on "better_supabase"."agent_installs";
create policy agent_installs_read on "better_supabase"."agent_installs" for select to authenticated
  using ("user_id" = (select auth.uid()));

create table if not exists "better_supabase"."agent_ratings" (
  "agent_id" uuid not null references "better_supabase"."agents" ("id") on delete cascade,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "rating" smallint not null check ("rating" between 1 and 5),
  "comment" text check (length("comment") <= 2000),
  "created_at" timestamptz not null default now(),
  primary key ("agent_id", "user_id")
);
create index if not exists agent_ratings_user_idx on "better_supabase"."agent_ratings" ("user_id");
alter table "better_supabase"."agent_ratings" enable row level security;
revoke all on "better_supabase"."agent_ratings" from anon, authenticated;
grant select on "better_supabase"."agent_ratings" to authenticated;
grant all on "better_supabase"."agent_ratings" to service_role;
drop policy if exists agent_ratings_read on "better_supabase"."agent_ratings";
create policy agent_ratings_read on "better_supabase"."agent_ratings" for select to authenticated
  using (exists (select 1 from "better_supabase"."agents" x where x."id" = "agent_id"));

-- Skills an agent loads from a provider (a reference such as a skill id).
create table if not exists "better_supabase"."agent_skills" (
  "id" uuid primary key default gen_random_uuid(),
  "agent_id" uuid not null references "better_supabase"."agents" ("id") on delete cascade,
  "provider" text not null check (length("provider") between 1 and 100),
  "reference" jsonb not null check (jsonb_typeof("reference") = 'object'),
  "created_at" timestamptz not null default now()
);
create index if not exists agent_skills_agent_idx on "better_supabase"."agent_skills" ("agent_id");
alter table "better_supabase"."agent_skills" enable row level security;
revoke all on "better_supabase"."agent_skills" from anon, authenticated;
grant select on "better_supabase"."agent_skills" to authenticated;
grant all on "better_supabase"."agent_skills" to service_role;
drop policy if exists agent_skills_read on "better_supabase"."agent_skills";
create policy agent_skills_read on "better_supabase"."agent_skills" for select to authenticated
  using (exists (select 1 from "better_supabase"."agents" x where x."id" = "agent_id"));

-- Creates an agent (id null, needs 'ai_chat.create') or changes one its owner or a
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
  if jsonb_typeof(save_agent.fields) is distinct from 'object' then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  if save_agent.id is null then
    if auth.uid() is null or not coalesce(better_supabase.can('tenant', save_agent.tenant, 'ai_chat.create'), false) then
      raise exception 'you may not create agents here' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
    end if;
    if save_agent.fields ->> 'slug' is null or save_agent.fields ->> 'name' is null then
      raise exception 'a new agent needs a slug and a name' using errcode = '22023', hint = 'AGENT_INVALID';
    end if;
    insert into "better_supabase"."agents" ("organization_id", "owner_id", "slug", "name")
    values (save_agent.tenant, auth.uid(), save_agent.fields ->> 'slug', save_agent.fields ->> 'name')
    returning * into v_row;
  else
    select * into v_row from "better_supabase"."agents" x where x."id" = save_agent.id and x."organization_id" = save_agent.tenant for update;
    if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai_chat.moderate'), false)) then
      raise exception 'agent % not found', save_agent.id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
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
  perform better_supabase.audit_event(
    event_type => 'agent.saved',
    category => 'ai',
    target_type => 'agent',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'agentId', v_row."id", 'slug', v_row."slug")
  );
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
exception
  when unique_violation then
    raise exception 'an agent with slug % exists', save_agent.fields ->> 'slug' using errcode = '23505', hint = 'AGENT_SLUG_TAKEN';
end;
$$;
revoke execute on function "better_supabase"."save_agent"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_agent"(uuid, uuid, jsonb) to authenticated, service_role;

-- Publishes an agent to the organization or the public store, or makes it
-- private again. The owner needs 'ai_chat.share'; a moderator may always unpublish.
create or replace function "better_supabase"."publish_agent"(id uuid, visibility text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."agents"%rowtype;
begin
  if publish_agent.visibility is null or publish_agent.visibility not in ('private', 'organization', 'public') then
    raise exception 'visibility is private, organization or public' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = publish_agent.id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai_chat.moderate'), false)) then
    raise exception 'agent % not found', publish_agent.id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if publish_agent.visibility <> 'private' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai_chat.moderate'), false)
    or (v_row."owner_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai_chat.share'), false))) then
    raise exception 'you may not publish agents here' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
  end if;
  update "better_supabase"."agents" x set
    "visibility" = publish_agent.visibility,
    "published_at" = case when publish_agent.visibility = 'private' then null else coalesce(x."published_at", now()) end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform better_supabase.audit_event(
    event_type => 'agent.published',
    category => 'ai',
    target_type => 'agent',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'agentId', v_row."id", 'slug', v_row."slug", 'visibility', publish_agent.visibility)
  );
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."publish_agent"(uuid, text) from public, anon;
grant execute on function "better_supabase"."publish_agent"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."delete_agent"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."agents"%rowtype;
begin
  select * into v_row from "better_supabase"."agents" x where x."id" = delete_agent.id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai_chat.moderate'), false)) then
    return false;
  end if;
  delete from "better_supabase"."agents" x where x."id" = v_row."id";
  perform better_supabase.audit_event(
    event_type => 'agent.deleted',
    category => 'ai',
    target_type => 'agent',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'agentId', v_row."id", 'slug', v_row."slug")
  );
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_agent"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_agent"(uuid) to authenticated, service_role;

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
    or (get_agent.id is null and x."organization_id" = get_agent.tenant and x."slug" = get_agent.slug);
  if not found then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at") || jsonb_build_object(
    'skills', coalesce((select jsonb_agg(jsonb_build_object('id', k."id", 'provider', k."provider", 'reference', k."reference") order by k."created_at") from "better_supabase"."agent_skills" k where k."agent_id" = v_row."id"), '[]'),
    'installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = v_row."id" and n."user_id" = auth.uid()),
    'my_rating', (select g."rating" from "better_supabase"."agent_ratings" g where g."agent_id" = v_row."id" and g."user_id" = auth.uid())
  );
end;
$$;
revoke execute on function "better_supabase"."get_agent"(uuid, uuid, text) from public, anon;
grant execute on function "better_supabase"."get_agent"(uuid, uuid, text) to authenticated, service_role;

-- Agents the caller may read: 'mine', 'installed' in the tenant, or the
-- 'store' (published to the tenant or public), newest first.
create or replace function "better_supabase"."list_agents"(tenant uuid, filter text default 'store', search text default null, max_rows integer default 50)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(y.row order by y.at desc), '[]')
  from (
    select jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."organization_id" = list_agents.tenant)) as row,
      coalesce(x."published_at", x."updated_at") as at
    from "better_supabase"."agents" x
    where case list_agents.filter
        when 'mine' then x."owner_id" = auth.uid() and x."organization_id" = list_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."organization_id" = list_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."organization_id" = list_agents.tenant)
      end
      and (list_agents.search is null or x."name" ilike '%' || replace(replace(list_agents.search, '%', '\%'), '_', '\_') || '%'
        or x."description" ilike '%' || replace(replace(list_agents.search, '%', '\%'), '_', '\_') || '%')
    order by coalesce(x."published_at", x."updated_at") desc
    limit least(greatest(list_agents.max_rows, 1), 200)
  ) y
$$;
revoke execute on function "better_supabase"."list_agents"(uuid, text, text, integer) from public, anon;
grant execute on function "better_supabase"."list_agents"(uuid, text, text, integer) to authenticated, service_role;

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
  if auth.uid() is null or not coalesce(better_supabase.can('tenant', install_agent.tenant, 'ai_chat.read'), false) then
    raise exception 'you may not use agents here' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
  end if;
  if not install_agent.installed then
    delete from "better_supabase"."agent_installs" n where n."agent_id" = install_agent.agent_id and n."user_id" = auth.uid() and n."organization_id" = install_agent.tenant;
    get diagnostics v_count = row_count;
    update "better_supabase"."agents" x set "install_count" = greatest(x."install_count" - v_count, 0) where x."id" = install_agent.agent_id;
    if v_count > 0 then
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
  if not exists (select 1 from "better_supabase"."agents" x where x."id" = install_agent.agent_id and (x."owner_id" = (select auth.uid()) or (x."published_at" is not null and (x."visibility" = 'public' or (x."visibility" = 'organization' and x."organization_id" in (select better_supabase.tenant_ids_with('ai_chat.read'))))) or x."organization_id" in (select better_supabase.tenant_ids_with('ai_chat.moderate')))) then
    raise exception 'agent % not found', install_agent.agent_id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  insert into "better_supabase"."agent_installs" ("agent_id", "user_id", "organization_id") values (install_agent.agent_id, auth.uid(), install_agent.tenant)
  on conflict do nothing;
  get diagnostics v_count = row_count;
  update "better_supabase"."agents" x set "install_count" = x."install_count" + v_count where x."id" = install_agent.agent_id;
  if v_count > 0 then
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
  if auth.uid() is null then
    raise exception 'sign in to rate agents' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = rate_agent.agent_id and (x."owner_id" = (select auth.uid()) or (x."published_at" is not null and (x."visibility" = 'public' or (x."visibility" = 'organization' and x."organization_id" in (select better_supabase.tenant_ids_with('ai_chat.read'))))) or x."organization_id" in (select better_supabase.tenant_ids_with('ai_chat.moderate'))) for update;
  if not found then
    raise exception 'agent % not found', rate_agent.agent_id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
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
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
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
  select * into v_row from "better_supabase"."agents" x where x."id" = set_agent_skills.agent_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai_chat.moderate'), false)) then
    raise exception 'agent % not found', set_agent_skills.agent_id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if jsonb_typeof(v_items) is distinct from 'array' then
    raise exception 'skills must be a list' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  delete from "better_supabase"."agent_skills" k where k."agent_id" = v_row."id";
  insert into "better_supabase"."agent_skills" ("agent_id", "provider", "reference")
  select v_row."id", e ->> 'provider', e -> 'reference' from jsonb_array_elements(v_items) e;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."set_agent_skills"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."set_agent_skills"(uuid, jsonb) to authenticated, service_role;

-- sql.modules.agents.api: entry points for the Data API.
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

create or replace function "api"."delete_agent"(id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_agent"($1) $$;
revoke execute on function "api"."delete_agent"(uuid) from public, anon;
grant execute on function "api"."delete_agent"(uuid) to authenticated, service_role;

create or replace function "api"."get_agent"(id uuid default null, tenant uuid default null, slug text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_agent"($1, $2, $3) $$;
revoke execute on function "api"."get_agent"(uuid, uuid, text) from public, anon;
grant execute on function "api"."get_agent"(uuid, uuid, text) to authenticated, service_role;

create or replace function "api"."list_agents"(tenant uuid, filter text default 'store', search text default null, max_rows integer default 50)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_agents"($1, $2, $3, $4) $$;
revoke execute on function "api"."list_agents"(uuid, text, text, integer) from public, anon;
grant execute on function "api"."list_agents"(uuid, text, text, integer) to authenticated, service_role;

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
