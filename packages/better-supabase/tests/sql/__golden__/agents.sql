-- ==== alone: schema supabase/schemas/900_better_supabase_051_agents.sql
-- better-supabase module: agents
-- @bsb-block agents@2 managed
-- @bsb-hash sha256:c4d6bb70ede4e4385470ee5121e541598e3cc6edec2cb0c6f02db2e89006895f
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
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
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
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = delete_agent.id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)) then
    return false;
  end if;
  delete from "better_supabase"."agents" x where x."id" = v_row."id";
  null;
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
    or (get_agent.id is null and x."tenant_id" = get_agent.tenant and x."slug" = get_agent.slug);
  if not found then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at") || jsonb_build_object(
    'skills', coalesce((select jsonb_agg(jsonb_build_object('id', k."id", 'provider', k."provider", 'reference', k."reference", 'name', k."name", 'files', k."files", 'content_hash', k."content_hash", 'latest_version', k."latest_version", 'provider_refs', k."provider_refs") order by k."created_at") from "better_supabase"."agent_skills" k where k."agent_id" = v_row."id"), '[]'),
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
    select jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = list_agents.tenant)) as row,
      coalesce(x."published_at", x."updated_at") as at
    from "better_supabase"."agents" x
    where case list_agents.filter
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = list_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = list_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = list_agents.tenant)
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
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
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
-- @bsb-hash sha256:c8e583b83d64a3e87b222b245500c88ae74333600351c1f74e6745f4fce0e073
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
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
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
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = delete_agent.id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)) then
    return false;
  end if;
  delete from "better_supabase"."agents" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('agent.deleted', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'agentId', v_row."id", 'slug', v_row."slug"), 'organizations/' || v_row."tenant_id"::text || '/agents/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/agents');
  perform better_supabase.audit_event(
    event_type => 'agent.deleted',
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
    or (get_agent.id is null and x."tenant_id" = get_agent.tenant and x."slug" = get_agent.slug);
  if not found then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at") || jsonb_build_object(
    'skills', coalesce((select jsonb_agg(jsonb_build_object('id', k."id", 'provider', k."provider", 'reference', k."reference", 'name', k."name", 'files', k."files", 'content_hash', k."content_hash", 'latest_version', k."latest_version", 'provider_refs', k."provider_refs") order by k."created_at") from "better_supabase"."agent_skills" k where k."agent_id" = v_row."id"), '[]'),
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
    select jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = list_agents.tenant)) as row,
      coalesce(x."published_at", x."updated_at") as at
    from "better_supabase"."agents" x
    where case list_agents.filter
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = list_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = list_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = list_agents.tenant)
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
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
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
-- @bsb-hash sha256:f9b9c89a1ae2fe279421661db40fed60a9c04aaa0234420bf65ec6e07eafe708
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
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
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
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."publish_agent"(uuid, text) from public, anon;
grant execute on function "app_private"."publish_agent"(uuid, text) to authenticated, service_role;

create or replace function "app_private"."delete_agent"(id uuid)
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
  select * into v_row from "app_private"."agents" x where x."id" = delete_agent.id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)) then
    return false;
  end if;
  delete from "app_private"."agents" x where x."id" = v_row."id";
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."delete_agent"(uuid) from public, anon;
grant execute on function "app_private"."delete_agent"(uuid) to authenticated, service_role;

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
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at") || jsonb_build_object(
    'skills', coalesce((select jsonb_agg(jsonb_build_object('id', k."id", 'provider', k."provider", 'reference', k."reference", 'name', k."name", 'files', k."files", 'content_hash', k."content_hash", 'latest_version', k."latest_version", 'provider_refs', k."provider_refs") order by k."created_at") from "app_private"."agent_skills" k where k."agent_id" = v_row."id"), '[]'),
    'installed', exists (select 1 from "app_private"."agent_installs" n where n."agent_id" = v_row."id" and n."user_id" = auth.uid()),
    'my_rating', (select g."rating" from "app_private"."agent_ratings" g where g."agent_id" = v_row."id" and g."user_id" = auth.uid())
  );
end;
$$;
revoke execute on function "app_private"."get_agent"(uuid, uuid, text) from public, anon;
grant execute on function "app_private"."get_agent"(uuid, uuid, text) to authenticated, service_role;

-- Agents the caller may read: 'mine', 'installed' in the tenant, or the
-- 'store' (published to the tenant or public), newest first.
create or replace function "app_private"."list_agents"(tenant uuid, filter text default 'store', search text default null, max_rows integer default 50)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(y.row order by y.at desc), '[]')
  from (
    select jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at") || jsonb_build_object('installed', exists (select 1 from "app_private"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = list_agents.tenant)) as row,
      coalesce(x."published_at", x."updated_at") as at
    from "app_private"."agents" x
    where case list_agents.filter
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = list_agents.tenant
        when 'installed' then exists (select 1 from "app_private"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = list_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = list_agents.tenant)
      end
      and (list_agents.search is null or x."name" ilike '%' || replace(replace(list_agents.search, '%', '\%'), '_', '\_') || '%'
        or x."description" ilike '%' || replace(replace(list_agents.search, '%', '\%'), '_', '\_') || '%')
    order by coalesce(x."published_at", x."updated_at") desc
    limit least(greatest(list_agents.max_rows, 1), 200)
  ) y
$$;
revoke execute on function "app_private"."list_agents"(uuid, text, text, integer) from public, anon;
grant execute on function "app_private"."list_agents"(uuid, text, text, integer) to authenticated, service_role;

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
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
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
-- @bsb-hash sha256:448f3663cc498129b547db54c969b1591cf581b6c5707b54766ea5f43d6ffe2e
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
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
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
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = delete_agent.id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)) then
    return false;
  end if;
  delete from "better_supabase"."agents" x where x."id" = v_row."id";
  null;
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
    or (get_agent.id is null and x."tenant_id" = get_agent.tenant and x."slug" = get_agent.slug);
  if not found then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at") || jsonb_build_object(
    'skills', coalesce((select jsonb_agg(jsonb_build_object('id', k."id", 'provider', k."provider", 'reference', k."reference", 'name', k."name", 'files', k."files", 'content_hash', k."content_hash", 'latest_version', k."latest_version", 'provider_refs', k."provider_refs") order by k."created_at") from "better_supabase"."agent_skills" k where k."agent_id" = v_row."id"), '[]'),
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
    select jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = list_agents.tenant)) as row,
      coalesce(x."published_at", x."updated_at") as at
    from "better_supabase"."agents" x
    where case list_agents.filter
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = list_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = list_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = list_agents.tenant)
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
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
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
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."get_agent"($1, $2, $3) $$;
revoke execute on function "api"."get_agent"(uuid, uuid, text) from public, anon;
grant execute on function "api"."get_agent"(uuid, uuid, text) to authenticated, service_role;

create or replace function "api"."list_agents"(tenant uuid, filter text default 'store', search text default null, max_rows integer default 50)
returns jsonb
language sql
stable
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
-- @bsb-hash sha256:2e864848edeed447f5bc5da8124abe6a38a1a4e3c34d7c329e4c6b48d9758054
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
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
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
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = delete_agent.id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)) then
    return false;
  end if;
  delete from "better_supabase"."agents" x where x."id" = v_row."id";
  null;
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
    or (get_agent.id is null and x."tenant_id" = get_agent.tenant and x."slug" = get_agent.slug);
  if not found then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at") || jsonb_build_object(
    'skills', coalesce((select jsonb_agg(jsonb_build_object('id', k."id", 'provider', k."provider", 'reference', k."reference", 'name', k."name", 'files', k."files", 'content_hash', k."content_hash", 'latest_version', k."latest_version", 'provider_refs', k."provider_refs") order by k."created_at") from "better_supabase"."agent_skills" k where k."agent_id" = v_row."id"), '[]'),
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
    select jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = list_agents.tenant)) as row,
      coalesce(x."published_at", x."updated_at") as at
    from "better_supabase"."agents" x
    where case list_agents.filter
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = list_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = list_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = list_agents.tenant)
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
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
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
-- @bsb-hash sha256:8012d149f6cdc50b2a5578d717a1407863f3781c56bfe1104cf50cdf7fe91f55
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
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."org_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
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
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."org_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = delete_agent.id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."org_id", 'agents.moderate'), false)) then
    return false;
  end if;
  delete from "better_supabase"."agents" x where x."id" = v_row."id";
  null;
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
    or (get_agent.id is null and x."org_id" = get_agent.tenant and x."slug" = get_agent.slug);
  if not found then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."org_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at") || jsonb_build_object(
    'skills', coalesce((select jsonb_agg(jsonb_build_object('id', k."id", 'provider', k."provider", 'reference', k."reference", 'name', k."name", 'files', k."files", 'content_hash', k."content_hash", 'latest_version', k."latest_version", 'provider_refs', k."provider_refs") order by k."created_at") from "better_supabase"."agent_skills" k where k."agent_id" = v_row."id"), '[]'),
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
    select jsonb_build_object('id', x."id", 'tenant_id', x."org_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."org_id" = list_agents.tenant)) as row,
      coalesce(x."published_at", x."updated_at") as at
    from "better_supabase"."agents" x
    where case list_agents.filter
        when 'mine' then x."owner_id" = auth.uid() and x."org_id" = list_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."org_id" = list_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."org_id" = list_agents.tenant)
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
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."org_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
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
