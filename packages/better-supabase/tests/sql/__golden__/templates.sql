-- ==== alone: schema supabase/schemas/900_better_supabase_091_templates.sql
-- better-supabase module: templates
-- @bsb-block templates@1 managed
-- @bsb-hash sha256:1a16b70e1bb12879353b1ad95fa6ae2d58595932a9823f9a1b4ceb2bbd56e772
-- Typed, versioned templates (system starters and tenant forks) that create records, with merge fields and workflows started on each record they create.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."templates";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."templates";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."templates";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."templates";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."templates";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."template_applications";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."template_applications";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."template_applications";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."template_applications";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."template_applications";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create extension if not exists pgcrypto with schema extensions;

-- Templates of a type (an invoice, a project, an email): a tenant's own, or
-- a system starter (no tenant) that sync_templates keeps by key and tenants
-- fork, or with options.brand a starter of one brand. forked_from: the template and version a fork copied.
create table if not exists "better_supabase"."templates" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid,
  "scope" text not null default 'tenant' check ("scope" in ('tenant', 'system')),
  "key" text check ("key" ~ '^[a-z0-9][a-z0-9_.-]{0,99}$'),
  "type" text not null check ("type" ~ '^[a-z][a-z0-9_.-]{0,63}$'),
  "name" text not null check (length("name") between 1 and 200),
  "language" text not null default 'en' check ("language" ~ '^[a-z]{2,3}(-[A-Za-z0-9]{1,8})*$'),
  "is_default" boolean not null default false,
  "settings" jsonb not null default '{}'::jsonb
    check (jsonb_typeof("settings") = 'object' and pg_column_size("settings") <= 65536),
  "forked_from" uuid references "better_supabase"."templates" ("id") on delete set null,
  "forked_from_version" integer check ("forked_from_version" > 0),
  "created_by" uuid references auth.users (id) on delete set null,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  constraint templates_system_check check (("scope" = 'system') = ("tenant_id" is null))
);
create unique index if not exists templates_key_idx on "better_supabase"."templates" ("tenant_id", "key") nulls not distinct where "key" is not null;
create unique index if not exists templates_default_idx on "better_supabase"."templates" ("tenant_id", "type", "language") nulls not distinct where "is_default";
create index if not exists templates_type_idx on "better_supabase"."templates" ("tenant_id", "type");
create index if not exists templates_forked_from_idx on "better_supabase"."templates" ("forked_from") where "forked_from" is not null;
create index if not exists templates_created_by_idx on "better_supabase"."templates" ("created_by");
alter table "better_supabase"."templates" enable row level security;
revoke all on "better_supabase"."templates" from public, anon, authenticated;
grant select on "better_supabase"."templates" to authenticated;
grant all on "better_supabase"."templates" to service_role;
drop policy if exists templates_read on "better_supabase"."templates";
create policy templates_read on "better_supabase"."templates"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('templates.read'))
    or ("scope" = 'system' and exists (select better_supabase.tenant_ids_with('templates.read'))));

-- Numbered snapshots of a template's body: at most one draft, and published
-- versions that never change. hash: the SHA-256 of the body as text.
create table if not exists "better_supabase"."template_versions" (
  "id" uuid primary key default gen_random_uuid(),
  "template_id" uuid not null references "better_supabase"."templates" ("id") on delete cascade,
  "version" integer not null check ("version" > 0),
  "body" jsonb not null check (pg_column_size("body") <= 1048576),
  "hash" text not null,
  "published_at" timestamptz,
  "created_by" uuid references auth.users (id) on delete set null,
  "created_at" timestamptz not null default now(),
  constraint template_versions_template_version_key unique ("template_id", "version")
);
create unique index if not exists template_versions_one_draft_idx on "better_supabase"."template_versions" ("template_id") where "published_at" is null;
create index if not exists template_versions_created_by_idx on "better_supabase"."template_versions" ("created_by");
alter table "better_supabase"."template_versions" enable row level security;
revoke all on "better_supabase"."template_versions" from public, anon, authenticated;
grant select on "better_supabase"."template_versions" to authenticated;
grant all on "better_supabase"."template_versions" to service_role;
drop policy if exists template_versions_read on "better_supabase"."template_versions";
create policy template_versions_read on "better_supabase"."template_versions"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."templates" x where x."id" = "template_id"));

-- Each time a published version created a record, and which one.
create table if not exists "better_supabase"."template_applications" (
  "id" uuid primary key default gen_random_uuid(),
  "template_id" uuid not null references "better_supabase"."templates" ("id") on delete cascade,
  "version_id" uuid not null references "better_supabase"."template_versions" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "subject_type" text not null check (length("subject_type") between 1 and 100),
  "subject_id" text not null check (length("subject_id") between 1 and 200),
  "applied_by" uuid references auth.users (id) on delete set null,
  "applied_at" timestamptz not null default now()
);
create index if not exists template_applications_tenant_idx on "better_supabase"."template_applications" ("tenant_id", "applied_at" desc);
create index if not exists template_applications_template_idx on "better_supabase"."template_applications" ("template_id");
create index if not exists template_applications_version_idx on "better_supabase"."template_applications" ("version_id");
create index if not exists template_applications_subject_idx on "better_supabase"."template_applications" ("subject_type", "subject_id");
create index if not exists template_applications_applied_by_idx on "better_supabase"."template_applications" ("applied_by");
alter table "better_supabase"."template_applications" enable row level security;
revoke all on "better_supabase"."template_applications" from public, anon, authenticated;
grant select on "better_supabase"."template_applications" to authenticated;
grant all on "better_supabase"."template_applications" to service_role;
drop policy if exists template_applications_read on "better_supabase"."template_applications";
create policy template_applications_read on "better_supabase"."template_applications"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('templates.read')));

-- Creates a template (template_id null) or renames it and replaces its
-- settings. tenant null saves a system template, which only the service
-- role may; a tenant's needs templates.manage there.
-- fields: the extra columns (blocks.templates.options.extraColumns) to set.
drop function if exists "better_supabase"."save_template"(uuid, uuid, text, text, text, jsonb, jsonb);
create or replace function "better_supabase"."save_template"(template_id uuid, tenant uuid, type text, name text, language text, settings jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."templates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if save_template.settings is not null and jsonb_typeof(save_template.settings) <> 'object' then
    raise exception 'settings must be an object' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  if save_template.template_id is not null then
    select * into v_row from "better_supabase"."templates" x where x."id" = save_template.template_id for update;
    if not found or v_row."tenant_id" is distinct from save_template.tenant then
      raise exception 'No such template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_FOUND';
    end if;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_template.tenant is not null and coalesce(better_supabase.can('tenant', save_template.tenant, 'templates.manage'), false))) then
    raise exception 'You may not change templates here' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  if save_template.template_id is null and (save_template.type is null or save_template.type !~ '^[a-z][a-z0-9_.-]{0,63}$') then
    raise exception 'type must be lower-case letters, digits, dots, dashes or underscores' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  if save_template.template_id is null and save_template.name is null then
    raise exception 'A template needs a name' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_template_save"(uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::jsonb)', v_hook::oid::regproc)
        using save_template.tenant, coalesce(save_template.type, v_row."type"), save_template.settings;
    end if;
  end;
  if save_template.template_id is null then
    insert into "better_supabase"."templates" ("tenant_id", "scope", "type", "name", "language", "settings", "created_by")
    values (
      save_template.tenant,
      case when save_template.tenant is null then 'system' else 'tenant' end,
      save_template.type,
      save_template.name,
      coalesce(save_template.language, 'en'),
      coalesce(save_template.settings, '{}'::jsonb),
      (select auth.uid())
    )
    returning * into v_row;
  else
    update "better_supabase"."templates" x set
      "name" = coalesce(save_template.name, x."name"),
      "language" = coalesce(save_template.language, x."language"),
      "settings" = coalesce(save_template.settings, x."settings"),
      "is_default" = x."is_default" and coalesce(save_template.language, x."language") = x."language",
      "updated_at" = now()
    where x."id" = save_template.template_id
    returning * into v_row;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_template_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object(
    'id', v_row."id",
    'tenant', v_row."tenant_id",
    'scope', v_row."scope",
    'key', v_row."key",
    'type', v_row."type",
    'name', v_row."name",
    'language', v_row."language",
    'isDefault', v_row."is_default",
    'settings', v_row."settings",
    'forkedFrom', v_row."forked_from",
    'forkedFromVersion', v_row."forked_from_version",
    'publishedVersion', (select y."version" from "better_supabase"."template_versions" y where y."template_id" = v_row."id" and y."published_at" is not null order by y."version" desc limit 1),
    'upstreamVersion', case when v_row."forked_from" is not null then (select y."version" from "better_supabase"."template_versions" y where y."template_id" = v_row."forked_from" and y."published_at" is not null order by y."version" desc limit 1) end,
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'updatedAt', v_row."updated_at"
  );
end;
$$;
revoke execute on function "better_supabase"."save_template"(uuid, uuid, text, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."save_template"(uuid, uuid, text, text, text, jsonb) to authenticated, service_role;

-- The tenant's templates and the system ones (only the system ones without
-- a tenant), filtered by type and language, defaults first.
create or replace function "better_supabase"."templates_list"(tenant uuid, type text, language text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x."id",
    'tenant', x."tenant_id",
    'scope', x."scope",
    'key', x."key",
    'type', x."type",
    'name', x."name",
    'language', x."language",
    'isDefault', x."is_default",
    'settings', x."settings",
    'forkedFrom', x."forked_from",
    'forkedFromVersion', x."forked_from_version",
    'publishedVersion', (select y."version" from "better_supabase"."template_versions" y where y."template_id" = x."id" and y."published_at" is not null order by y."version" desc limit 1),
    'upstreamVersion', case when x."forked_from" is not null then (select y."version" from "better_supabase"."template_versions" y where y."template_id" = x."forked_from" and y."published_at" is not null order by y."version" desc limit 1) end,
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at"
  )
    order by x."is_default" desc, x."scope" desc, x."name", x."id"), '[]'::jsonb)
  from "better_supabase"."templates" x
  where (x."scope" = 'system' or x."tenant_id" = templates_list.tenant)
    and (templates_list.type is null or x."type" = templates_list.type)
    and (templates_list.language is null or x."language" = templates_list.language)
$$;
revoke execute on function "better_supabase"."templates_list"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."templates_list"(uuid, text, text) to authenticated, service_role;

-- One template with its newest published version and its draft, bodies
-- included; null when the caller can't read it.
create or replace function "better_supabase"."template_get"(template_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'id', x."id",
    'tenant', x."tenant_id",
    'scope', x."scope",
    'key', x."key",
    'type', x."type",
    'name', x."name",
    'language', x."language",
    'isDefault', x."is_default",
    'settings', x."settings",
    'forkedFrom', x."forked_from",
    'forkedFromVersion', x."forked_from_version",
    'publishedVersion', (select y."version" from "better_supabase"."template_versions" y where y."template_id" = x."id" and y."published_at" is not null order by y."version" desc limit 1),
    'upstreamVersion', case when x."forked_from" is not null then (select y."version" from "better_supabase"."template_versions" y where y."template_id" = x."forked_from" and y."published_at" is not null order by y."version" desc limit 1) end,
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at"
  ) || jsonb_build_object(
    'published', (select jsonb_build_object(
    'id', y."id",
    'template', y."template_id",
    'version', y."version",
    'hash', y."hash",
    'publishedAt', y."published_at",
    'createdBy', y."created_by",
    'createdAt', y."created_at",
    'body', y."body"
  ) from "better_supabase"."template_versions" y
      where y."template_id" = x."id" and y."published_at" is not null
      order by y."version" desc limit 1),
    'draft', (select jsonb_build_object(
    'id', y."id",
    'template', y."template_id",
    'version', y."version",
    'hash', y."hash",
    'publishedAt', y."published_at",
    'createdBy', y."created_by",
    'createdAt', y."created_at",
    'body', y."body"
  ) from "better_supabase"."template_versions" y
      where y."template_id" = x."id" and y."published_at" is null))
  from "better_supabase"."templates" x
  where x."id" = template_get.template_id
$$;
revoke execute on function "better_supabase"."template_get"(uuid) from public, anon;
grant execute on function "better_supabase"."template_get"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."remove_template"(template_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."templates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."templates" x where x."id" = remove_template.template_id;
  if not found then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'templates.manage'), false))) then
    raise exception 'You may not remove this template' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  delete from "better_supabase"."templates" x where x."id" = remove_template.template_id;
  return true;
end;
$$;
revoke execute on function "better_supabase"."remove_template"(uuid) from public, anon;
grant execute on function "better_supabase"."remove_template"(uuid) to authenticated, service_role;

-- Saves body as the template's draft: updates the open one, or opens one
-- numbered after the last version.
create or replace function "better_supabase"."save_template_draft"(template_id uuid, body jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tpl "better_supabase"."templates"%rowtype;
  v_row "better_supabase"."template_versions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_tpl from "better_supabase"."templates" x where x."id" = save_template_draft.template_id for update;
  if not found then
    raise exception 'No such template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tpl."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_tpl."tenant_id", 'templates.manage'), false))) then
    raise exception 'You may not edit this template' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  if save_template_draft.body is null then
    raise exception 'A template version needs a body' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  update "better_supabase"."template_versions" x set
    "body" = save_template_draft.body,
    "hash" = encode(extensions.digest(save_template_draft.body::text, 'sha256'), 'hex')
  where x."template_id" = save_template_draft.template_id and x."published_at" is null
  returning * into v_row;
  if not found then
    insert into "better_supabase"."template_versions" ("template_id", "version", "body", "hash", "created_by")
    values (
      save_template_draft.template_id,
      coalesce((select max(y."version") from "better_supabase"."template_versions" y where y."template_id" = save_template_draft.template_id), 0) + 1,
      save_template_draft.body,
      encode(extensions.digest(save_template_draft.body::text, 'sha256'), 'hex'),
      (select auth.uid())
    )
    returning * into v_row;
  end if;
  update "better_supabase"."templates" x set "updated_at" = now() where x."id" = save_template_draft.template_id;
  return jsonb_build_object(
    'id', v_row."id",
    'template', v_row."template_id",
    'version', v_row."version",
    'hash', v_row."hash",
    'publishedAt', v_row."published_at",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'body', v_row."body"
  );
end;
$$;
revoke execute on function "better_supabase"."save_template_draft"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_template_draft"(uuid, jsonb) to authenticated, service_role;

-- Publishes the template's draft. Applications use the newest published
-- version; published versions never change.
create or replace function "better_supabase"."publish_template_version"(template_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tpl "better_supabase"."templates"%rowtype;
  v_row "better_supabase"."template_versions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_tpl from "better_supabase"."templates" x where x."id" = publish_template_version.template_id for update;
  if not found then
    raise exception 'No such template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tpl."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_tpl."tenant_id", 'templates.manage'), false))) then
    raise exception 'You may not publish this template' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  update "better_supabase"."template_versions" x set "published_at" = now()
  where x."template_id" = publish_template_version.template_id and x."published_at" is null
  returning * into v_row;
  if not found then
    raise exception 'This template has no draft to publish' using errcode = 'P0002', hint = 'TEMPLATE_NO_DRAFT';
  end if;
  update "better_supabase"."templates" x set "updated_at" = now() where x."id" = publish_template_version.template_id;
  null;
  return jsonb_build_object(
    'id', v_row."id",
    'template', v_row."template_id",
    'version', v_row."version",
    'hash', v_row."hash",
    'publishedAt', v_row."published_at",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'body', v_row."body"
  );
end;
$$;
revoke execute on function "better_supabase"."publish_template_version"(uuid) from public, anon;
grant execute on function "better_supabase"."publish_template_version"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."template_versions_list"(template_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', y."id",
    'template', y."template_id",
    'version', y."version",
    'hash', y."hash",
    'publishedAt', y."published_at",
    'createdBy', y."created_by",
    'createdAt', y."created_at"
  ) order by y."version" desc), '[]'::jsonb)
  from "better_supabase"."template_versions" y where y."template_id" = template_versions_list.template_id
$$;
revoke execute on function "better_supabase"."template_versions_list"(uuid) from public, anon;
grant execute on function "better_supabase"."template_versions_list"(uuid) to authenticated, service_role;

-- One default per tenant, type and language.
create or replace function "better_supabase"."set_default_template"(template_id uuid, on_default boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."templates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."templates" x where x."id" = set_default_template.template_id for update;
  if not found then
    raise exception 'No such template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'templates.manage'), false))) then
    raise exception 'You may not change this template' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  if set_default_template.on_default then
    update "better_supabase"."templates" x set "is_default" = false, "updated_at" = now()
    where x."tenant_id" is not distinct from v_row."tenant_id"
      and x."type" = v_row."type" and x."language" = v_row."language"
      and x."is_default" and x."id" <> v_row."id";
  end if;
  update "better_supabase"."templates" x set "is_default" = coalesce(set_default_template.on_default, false), "updated_at" = now()
  where x."id" = set_default_template.template_id;
  return true;
end;
$$;
revoke execute on function "better_supabase"."set_default_template"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."set_default_template"(uuid, boolean) to authenticated, service_role;

-- Copies the newest published version of source (a system template, or one
-- in tenant) into a new template in tenant, published as its version 1, and
-- records the version it copied. templates.manage in tenant.
create or replace function "better_supabase"."fork_template"(source uuid, tenant uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_src "better_supabase"."templates"%rowtype;
  v_version "better_supabase"."template_versions"%rowtype;
  v_row "better_supabase"."templates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_src from "better_supabase"."templates" x where x."id" = fork_template.source;
  if not found or not (v_src."scope" = 'system' or v_src."tenant_id" = fork_template.tenant) then
    raise exception 'No such template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_FOUND';
  end if;
  if fork_template.tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (fork_template.tenant is not null and coalesce(better_supabase.can('tenant', fork_template.tenant, 'templates.manage'), false))) then
    raise exception 'You may not create templates here' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  select * into v_version from "better_supabase"."template_versions" y
  where y."template_id" = fork_template.source and y."published_at" is not null
  order by y."version" desc limit 1;
  if not found then
    raise exception 'This template has no published version' using errcode = 'P0002', hint = 'TEMPLATE_NOT_PUBLISHED';
  end if;
  insert into "better_supabase"."templates" ("tenant_id", "scope", "type", "name", "language", "settings", "forked_from", "forked_from_version", "created_by")
  values (fork_template.tenant, 'tenant', v_src."type", v_src."name", v_src."language", v_src."settings", v_src."id", v_version."version", (select auth.uid()))
  returning * into v_row;
  insert into "better_supabase"."template_versions" ("template_id", "version", "body", "hash", "published_at", "created_by")
  values (v_row."id", 1, v_version."body", v_version."hash", now(), (select auth.uid()));

  return jsonb_build_object(
    'id', v_row."id",
    'tenant', v_row."tenant_id",
    'scope', v_row."scope",
    'key', v_row."key",
    'type', v_row."type",
    'name', v_row."name",
    'language', v_row."language",
    'isDefault', v_row."is_default",
    'settings', v_row."settings",
    'forkedFrom', v_row."forked_from",
    'forkedFromVersion', v_row."forked_from_version",
    'publishedVersion', (select y."version" from "better_supabase"."template_versions" y where y."template_id" = v_row."id" and y."published_at" is not null order by y."version" desc limit 1),
    'upstreamVersion', case when v_row."forked_from" is not null then (select y."version" from "better_supabase"."template_versions" y where y."template_id" = v_row."forked_from" and y."published_at" is not null order by y."version" desc limit 1) end,
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'updatedAt', v_row."updated_at"
  );
end;
$$;
revoke execute on function "better_supabase"."fork_template"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."fork_template"(uuid, uuid) to authenticated, service_role;

-- Upserts the system templates by key from starters, a JSON array of
-- { key, type, name, language?, settings?, body }, and publishes a new
-- version of each whose body changed. Returns how many it published.
create or replace function "better_supabase"."sync_templates"(starters jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_starter jsonb;
  v_row "better_supabase"."templates"%rowtype;
  v_hash text;
  v_version "better_supabase"."template_versions"%rowtype;
  v_count integer := 0;
begin
  if jsonb_typeof(sync_templates.starters) <> 'array' then
    raise exception 'starters must be an array' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  for v_starter in select value from jsonb_array_elements(sync_templates.starters) loop
    if coalesce(v_starter ->> 'key', '') !~ '^[a-z0-9][a-z0-9_.-]{0,99}$' or not (v_starter ? 'body') then
      raise exception 'Each starter needs a key and a body' using errcode = '22023', hint = 'TEMPLATE_INVALID';
    end if;
    if v_starter ? 'brand' then
      raise exception 'this templates table has no brand column' using errcode = '22023', hint = 'TEMPLATE_BRAND_UNSUPPORTED';
    end if;
    select * into v_row from "better_supabase"."templates" x where x."tenant_id" is null and x."key" = v_starter ->> 'key' for update;
    if not found then
      insert into "better_supabase"."templates" ("tenant_id", "scope", "key", "type", "name", "language", "settings")
      values (null, 'system', v_starter ->> 'key', v_starter ->> 'type', v_starter ->> 'name',
        coalesce(v_starter ->> 'language', 'en'), coalesce(v_starter -> 'settings', '{}'::jsonb))
      returning * into v_row;
    else
      update "better_supabase"."templates" x set
        "type" = coalesce(v_starter ->> 'type', x."type"),
        "name" = coalesce(v_starter ->> 'name', x."name"),
        "language" = coalesce(v_starter ->> 'language', x."language"),
        "settings" = coalesce(v_starter -> 'settings', x."settings"),
        "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    end if;
    v_hash := encode(extensions.digest((v_starter -> 'body')::text, 'sha256'), 'hex');
    if v_hash is distinct from (select y."hash" from "better_supabase"."template_versions" y
        where y."template_id" = v_row."id" and y."published_at" is not null
        order by y."version" desc limit 1) then
      delete from "better_supabase"."template_versions" y where y."template_id" = v_row."id" and y."published_at" is null;
      insert into "better_supabase"."template_versions" ("template_id", "version", "body", "hash", "published_at")
      values (
        v_row."id",
        coalesce((select max(y."version") from "better_supabase"."template_versions" y where y."template_id" = v_row."id"), 0) + 1,
        v_starter -> 'body',
        v_hash,
        now()
      )
      returning * into v_version;
      v_count := v_count + 1;
      null;
    end if;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."sync_templates"(jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."sync_templates"(jsonb) to service_role;

-- What applying template in tenant needs: the template, its newest
-- published version with the body, and the enabled workflow attachments,
-- each input checked against the published version's input_schema
-- (TEMPLATE_WORKFLOW_INPUT_INVALID). templates.apply in tenant.
create or replace function "better_supabase"."template_apply_target"(template_id uuid, tenant uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tpl "better_supabase"."templates"%rowtype;
  v_version "better_supabase"."template_versions"%rowtype;
  v_workflows jsonb := '[]'::jsonb;
begin
  if template_apply_target.tenant is null then
    raise exception 'Applying a template needs a tenant' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', template_apply_target.tenant, 'templates.apply'), false)) then
    raise exception 'You may not apply templates here' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  select * into v_tpl from "better_supabase"."templates" x where x."id" = template_apply_target.template_id;
  if not found or not (v_tpl."scope" = 'system' or v_tpl."tenant_id" = template_apply_target.tenant) then
    raise exception 'No such template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_FOUND';
  end if;
  select * into v_version from "better_supabase"."template_versions" y
  where y."template_id" = v_tpl."id" and y."published_at" is not null
  order by y."version" desc limit 1;
  if not found then
    raise exception 'This template has no published version' using errcode = 'P0002', hint = 'TEMPLATE_NOT_PUBLISHED';
  end if;

  return jsonb_build_object(
    'template', jsonb_build_object(
    'id', v_tpl."id",
    'tenant', v_tpl."tenant_id",
    'scope', v_tpl."scope",
    'key', v_tpl."key",
    'type', v_tpl."type",
    'name', v_tpl."name",
    'language', v_tpl."language",
    'isDefault', v_tpl."is_default",
    'settings', v_tpl."settings",
    'forkedFrom', v_tpl."forked_from",
    'forkedFromVersion', v_tpl."forked_from_version",
    'publishedVersion', (select y."version" from "better_supabase"."template_versions" y where y."template_id" = v_tpl."id" and y."published_at" is not null order by y."version" desc limit 1),
    'upstreamVersion', case when v_tpl."forked_from" is not null then (select y."version" from "better_supabase"."template_versions" y where y."template_id" = v_tpl."forked_from" and y."published_at" is not null order by y."version" desc limit 1) end,
    'createdBy', v_tpl."created_by",
    'createdAt', v_tpl."created_at",
    'updatedAt', v_tpl."updated_at"
  ),
    'version', jsonb_build_object(
    'id', v_version."id",
    'template', v_version."template_id",
    'version', v_version."version",
    'hash', v_version."hash",
    'publishedAt', v_version."published_at",
    'createdBy', v_version."created_by",
    'createdAt', v_version."created_at",
    'body', v_version."body"
  ),
    'workflows', v_workflows
  );
end;
$$;
revoke execute on function "better_supabase"."template_apply_target"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."template_apply_target"(uuid, uuid) to authenticated, service_role;

-- Records that version of template created subject_type/subject_id in
-- tenant. templates.apply in tenant.
create or replace function "better_supabase"."record_template_application"(template_id uuid, version_id uuid, tenant uuid, subject_type text, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tpl "better_supabase"."templates"%rowtype;
  v_row "better_supabase"."template_applications"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if record_template_application.tenant is null then
    raise exception 'Applying a template needs a tenant' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', record_template_application.tenant, 'templates.apply'), false)) then
    raise exception 'You may not apply templates here' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  select * into v_tpl from "better_supabase"."templates" x where x."id" = record_template_application.template_id;
  if not found or not (v_tpl."scope" = 'system' or v_tpl."tenant_id" = record_template_application.tenant) then
    raise exception 'No such template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_FOUND';
  end if;
  if not exists (select 1 from "better_supabase"."template_versions" y where y."id" = record_template_application.version_id
      and y."template_id" = v_tpl."id" and y."published_at" is not null) then
    raise exception 'Not a published version of this template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_PUBLISHED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_template_apply"(uuid, uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text, $4::text)', v_hook::oid::regproc)
        using record_template_application.tenant, v_tpl."id", record_template_application.subject_type, record_template_application.subject_id;
    end if;
  end;
  insert into "better_supabase"."template_applications" ("template_id", "version_id", "tenant_id", "subject_type", "subject_id", "applied_by")
  values (v_tpl."id", record_template_application.version_id, record_template_application.tenant,
    record_template_application.subject_type, record_template_application.subject_id, (select auth.uid()))
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_template_apply"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object(
    'id', v_row."id",
    'template', v_row."template_id",
    'version', v_row."version_id",
    'tenant', v_row."tenant_id",
    'subjectType', v_row."subject_type",
    'subjectId', v_row."subject_id",
    'appliedBy', v_row."applied_by",
    'appliedAt', v_row."applied_at"
  );
end;
$$;
revoke execute on function "better_supabase"."record_template_application"(uuid, uuid, uuid, text, text) from public, anon;
grant execute on function "better_supabase"."record_template_application"(uuid, uuid, uuid, text, text) to authenticated, service_role;

-- The tenant's applications, newest first, of one template or onto one
-- subject when those are given.
create or replace function "better_supabase"."template_applications_list"(tenant uuid, template_id uuid, subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(r.value order by r.at desc, r.id), '[]'::jsonb)
  from (
    select jsonb_build_object(
    'id', a."id",
    'template', a."template_id",
    'version', a."version_id",
    'tenant', a."tenant_id",
    'subjectType', a."subject_type",
    'subjectId', a."subject_id",
    'appliedBy', a."applied_by",
    'appliedAt', a."applied_at"
  ) as value, a."applied_at" as at, a."id" as id
    from "better_supabase"."template_applications" a
    where a."tenant_id" = template_applications_list.tenant
      and (template_applications_list.template_id is null or a."template_id" = template_applications_list.template_id)
      and (template_applications_list.subject_type is null or a."subject_type" = template_applications_list.subject_type)
      and (template_applications_list.subject_id is null or a."subject_id" = template_applications_list.subject_id)
    order by a."applied_at" desc, a."id"
    limit 200
  ) r
$$;
revoke execute on function "better_supabase"."template_applications_list"(uuid, uuid, text, text) from public, anon;
grant execute on function "better_supabase"."template_applications_list"(uuid, uuid, text, text) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."templates";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."templates";
create policy bsb_tenant_scope_select on "better_supabase"."templates" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('templates.read'))
    or ("scope" = 'system' and exists (select better_supabase.tenant_ids_with('templates.read'))))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."templates";
create policy bsb_tenant_scope_insert on "better_supabase"."templates" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."templates";
create policy bsb_tenant_scope_update on "better_supabase"."templates" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."templates";
create policy bsb_tenant_scope_delete on "better_supabase"."templates" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."template_applications";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."template_applications";
create policy bsb_tenant_scope_select on "better_supabase"."template_applications" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('templates.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."template_applications";
create policy bsb_tenant_scope_insert on "better_supabase"."template_applications" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."template_applications";
create policy bsb_tenant_scope_update on "better_supabase"."template_applications" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."template_applications";
create policy bsb_tenant_scope_delete on "better_supabase"."template_applications" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_091_templates.sql
-- better-supabase module: templates
-- @bsb-block-data templates
-- @bsb-hash sha256:b8f109c9be802b16766dc2421c68f34cacf2322c02b9c507938fd08f01f94689
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "pgcrypto" with schema "extensions";

insert into better_supabase.blocks (name, version, mode)
values ('templates', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_091_templates.sql
-- better-supabase module: templates
-- @bsb-block templates@1 managed
-- @bsb-hash sha256:54dab34aab480d6015365f2bd8c4572d0d6ffedc9168130212e603271c1b0dcc
-- Typed, versioned templates (system starters and tenant forks) that create records, with merge fields and workflows started on each record they create.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."templates";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."templates";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."templates";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."templates";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."templates";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."template_applications";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."template_applications";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."template_applications";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."template_applications";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."template_applications";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."template_schedules";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."template_schedules";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."template_schedules";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."template_schedules";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."template_schedules";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."template_schedule_runs";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."template_schedule_runs";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."template_schedule_runs";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."template_schedule_runs";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."template_schedule_runs";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create extension if not exists pgcrypto with schema extensions;

-- Templates of a type (an invoice, a project, an email): a tenant's own, or
-- a system starter (no tenant) that sync_templates keeps by key and tenants
-- fork, or with options.brand a starter of one brand. forked_from: the template and version a fork copied.
create table if not exists "better_supabase"."templates" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid,
  "scope" text not null default 'tenant' check ("scope" in ('tenant', 'system')),
  "key" text check ("key" ~ '^[a-z0-9][a-z0-9_.-]{0,99}$'),
  "type" text not null check ("type" ~ '^[a-z][a-z0-9_.-]{0,63}$'),
  "name" text not null check (length("name") between 1 and 200),
  "language" text not null default 'en' check ("language" ~ '^[a-z]{2,3}(-[A-Za-z0-9]{1,8})*$'),
  "is_default" boolean not null default false,
  "settings" jsonb not null default '{}'::jsonb
    check (jsonb_typeof("settings") = 'object' and pg_column_size("settings") <= 65536),
  "forked_from" uuid references "better_supabase"."templates" ("id") on delete set null,
  "forked_from_version" integer check ("forked_from_version" > 0),
  "created_by" uuid references auth.users (id) on delete set null,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  constraint templates_system_check check (("scope" = 'system') = ("tenant_id" is null))
);
create unique index if not exists templates_key_idx on "better_supabase"."templates" ("tenant_id", "key") nulls not distinct where "key" is not null;
create unique index if not exists templates_default_idx on "better_supabase"."templates" ("tenant_id", "type", "language") nulls not distinct where "is_default";
create index if not exists templates_type_idx on "better_supabase"."templates" ("tenant_id", "type");
create index if not exists templates_forked_from_idx on "better_supabase"."templates" ("forked_from") where "forked_from" is not null;
create index if not exists templates_created_by_idx on "better_supabase"."templates" ("created_by");
alter table "better_supabase"."templates" enable row level security;
revoke all on "better_supabase"."templates" from public, anon, authenticated;
grant select on "better_supabase"."templates" to authenticated;
grant all on "better_supabase"."templates" to service_role;
drop policy if exists templates_read on "better_supabase"."templates";
create policy templates_read on "better_supabase"."templates"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('templates.read'))
    or ("scope" = 'system' and exists (select better_supabase.tenant_ids_with('templates.read'))));

-- Numbered snapshots of a template's body: at most one draft, and published
-- versions that never change. hash: the SHA-256 of the body as text.
create table if not exists "better_supabase"."template_versions" (
  "id" uuid primary key default gen_random_uuid(),
  "template_id" uuid not null references "better_supabase"."templates" ("id") on delete cascade,
  "version" integer not null check ("version" > 0),
  "body" jsonb not null check (pg_column_size("body") <= 1048576),
  "hash" text not null,
  "published_at" timestamptz,
  "created_by" uuid references auth.users (id) on delete set null,
  "created_at" timestamptz not null default now(),
  constraint template_versions_template_version_key unique ("template_id", "version")
);
create unique index if not exists template_versions_one_draft_idx on "better_supabase"."template_versions" ("template_id") where "published_at" is null;
create index if not exists template_versions_created_by_idx on "better_supabase"."template_versions" ("created_by");
alter table "better_supabase"."template_versions" enable row level security;
revoke all on "better_supabase"."template_versions" from public, anon, authenticated;
grant select on "better_supabase"."template_versions" to authenticated;
grant all on "better_supabase"."template_versions" to service_role;
drop policy if exists template_versions_read on "better_supabase"."template_versions";
create policy template_versions_read on "better_supabase"."template_versions"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."templates" x where x."id" = "template_id"));

-- Each time a published version created a record, and which one.
create table if not exists "better_supabase"."template_applications" (
  "id" uuid primary key default gen_random_uuid(),
  "template_id" uuid not null references "better_supabase"."templates" ("id") on delete cascade,
  "version_id" uuid not null references "better_supabase"."template_versions" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "subject_type" text not null check (length("subject_type") between 1 and 100),
  "subject_id" text not null check (length("subject_id") between 1 and 200),
  "applied_by" uuid references auth.users (id) on delete set null,
  "applied_at" timestamptz not null default now()
);
create index if not exists template_applications_tenant_idx on "better_supabase"."template_applications" ("tenant_id", "applied_at" desc);
create index if not exists template_applications_template_idx on "better_supabase"."template_applications" ("template_id");
create index if not exists template_applications_version_idx on "better_supabase"."template_applications" ("version_id");
create index if not exists template_applications_subject_idx on "better_supabase"."template_applications" ("subject_type", "subject_id");
create index if not exists template_applications_applied_by_idx on "better_supabase"."template_applications" ("applied_by");
alter table "better_supabase"."template_applications" enable row level security;
revoke all on "better_supabase"."template_applications" from public, anon, authenticated;
grant select on "better_supabase"."template_applications" to authenticated;
grant all on "better_supabase"."template_applications" to service_role;
drop policy if exists template_applications_read on "better_supabase"."template_applications";
create policy template_applications_read on "better_supabase"."template_applications"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('templates.read')));

-- The workflow definitions a template starts on each record it creates, with
-- the input each run takes.
create table if not exists "better_supabase"."template_workflows" (
  "id" uuid primary key default gen_random_uuid(),
  "template_id" uuid not null references "better_supabase"."templates" ("id") on delete cascade,
  "definition_id" uuid not null references "better_supabase"."workflow_definitions" ("id") on delete cascade,
  "inputs" jsonb not null default '{}'::jsonb check (jsonb_typeof("inputs") = 'object'),
  "enabled" boolean not null default true,
  "created_by" uuid references auth.users (id) on delete set null,
  "created_at" timestamptz not null default now(),
  constraint template_workflows_template_definition_key unique ("template_id", "definition_id")
);
create index if not exists template_workflows_definition_idx on "better_supabase"."template_workflows" ("definition_id");
create index if not exists template_workflows_created_by_idx on "better_supabase"."template_workflows" ("created_by");
alter table "better_supabase"."template_workflows" enable row level security;
revoke all on "better_supabase"."template_workflows" from public, anon, authenticated;
grant select on "better_supabase"."template_workflows" to authenticated;
grant all on "better_supabase"."template_workflows" to service_role;
drop policy if exists template_workflows_read on "better_supabase"."template_workflows";
create policy template_workflows_read on "better_supabase"."template_workflows"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."templates" x where x."id" = "template_id"));

-- Why inputs don't match the input_schema of definition's published version:
-- empty when it matches, has no published version or no schema. The
-- required keys are always checked, then the whole schema.
create or replace function "better_supabase"."template_workflow_input_errors"(definition uuid, inputs jsonb)
returns text[]
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_schema jsonb;
  v_errors text[];
begin
  select y."input_schema" into v_schema from "better_supabase"."workflow_versions" y
  where y."definition_id" = template_workflow_input_errors.definition and y."status" = 'published';
  if v_schema is null then
    return '{}';
  end if;
  if jsonb_typeof(inputs) <> 'object' then
    return array['inputs must be an object'];
  end if;
  select coalesce(array_agg('missing required input ' || k order by k), '{}') into v_errors
  from jsonb_array_elements_text(case when jsonb_typeof(v_schema -> 'required') = 'array' then v_schema -> 'required' else '[]'::jsonb end) k
  where not (inputs ? k);
  if cardinality(v_errors) = 0 then
    v_errors := extensions.jsonschema_validation_errors(v_schema::json, inputs::json);
  end if;
  return v_errors;
end;
$$;
revoke execute on function "better_supabase"."template_workflow_input_errors"(uuid, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."template_workflow_input_errors"(uuid, jsonb) to service_role;

-- Creates a template (template_id null) or renames it and replaces its
-- settings. tenant null saves a system template, which only the service
-- role may; a tenant's needs templates.manage there.
-- fields: the extra columns (blocks.templates.options.extraColumns) to set.
drop function if exists "better_supabase"."save_template"(uuid, uuid, text, text, text, jsonb, jsonb);
create or replace function "better_supabase"."save_template"(template_id uuid, tenant uuid, type text, name text, language text, settings jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."templates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if save_template.settings is not null and jsonb_typeof(save_template.settings) <> 'object' then
    raise exception 'settings must be an object' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  if save_template.template_id is not null then
    select * into v_row from "better_supabase"."templates" x where x."id" = save_template.template_id for update;
    if not found or v_row."tenant_id" is distinct from save_template.tenant then
      raise exception 'No such template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_FOUND';
    end if;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_template.tenant is not null and coalesce(better_supabase.can('tenant', save_template.tenant, 'templates.manage'), false))) then
    raise exception 'You may not change templates here' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  if save_template.template_id is null and (save_template.type is null or save_template.type !~ '^[a-z][a-z0-9_.-]{0,63}$') then
    raise exception 'type must be lower-case letters, digits, dots, dashes or underscores' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  if save_template.template_id is null and save_template.name is null then
    raise exception 'A template needs a name' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_template_save"(uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::jsonb)', v_hook::oid::regproc)
        using save_template.tenant, coalesce(save_template.type, v_row."type"), save_template.settings;
    end if;
  end;
  if save_template.template_id is null then
    insert into "better_supabase"."templates" ("tenant_id", "scope", "type", "name", "language", "settings", "created_by")
    values (
      save_template.tenant,
      case when save_template.tenant is null then 'system' else 'tenant' end,
      save_template.type,
      save_template.name,
      coalesce(save_template.language, 'en'),
      coalesce(save_template.settings, '{}'::jsonb),
      (select auth.uid())
    )
    returning * into v_row;
  else
    update "better_supabase"."templates" x set
      "name" = coalesce(save_template.name, x."name"),
      "language" = coalesce(save_template.language, x."language"),
      "settings" = coalesce(save_template.settings, x."settings"),
      "is_default" = x."is_default" and coalesce(save_template.language, x."language") = x."language",
      "updated_at" = now()
    where x."id" = save_template.template_id
    returning * into v_row;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_template_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object(
    'id', v_row."id",
    'tenant', v_row."tenant_id",
    'scope', v_row."scope",
    'key', v_row."key",
    'type', v_row."type",
    'name', v_row."name",
    'language', v_row."language",
    'isDefault', v_row."is_default",
    'settings', v_row."settings",
    'forkedFrom', v_row."forked_from",
    'forkedFromVersion', v_row."forked_from_version",
    'publishedVersion', (select y."version" from "better_supabase"."template_versions" y where y."template_id" = v_row."id" and y."published_at" is not null order by y."version" desc limit 1),
    'upstreamVersion', case when v_row."forked_from" is not null then (select y."version" from "better_supabase"."template_versions" y where y."template_id" = v_row."forked_from" and y."published_at" is not null order by y."version" desc limit 1) end,
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'updatedAt', v_row."updated_at"
  );
end;
$$;
revoke execute on function "better_supabase"."save_template"(uuid, uuid, text, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."save_template"(uuid, uuid, text, text, text, jsonb) to authenticated, service_role;

-- The tenant's templates and the system ones (only the system ones without
-- a tenant), filtered by type and language, defaults first.
create or replace function "better_supabase"."templates_list"(tenant uuid, type text, language text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x."id",
    'tenant', x."tenant_id",
    'scope', x."scope",
    'key', x."key",
    'type', x."type",
    'name', x."name",
    'language', x."language",
    'isDefault', x."is_default",
    'settings', x."settings",
    'forkedFrom', x."forked_from",
    'forkedFromVersion', x."forked_from_version",
    'publishedVersion', (select y."version" from "better_supabase"."template_versions" y where y."template_id" = x."id" and y."published_at" is not null order by y."version" desc limit 1),
    'upstreamVersion', case when x."forked_from" is not null then (select y."version" from "better_supabase"."template_versions" y where y."template_id" = x."forked_from" and y."published_at" is not null order by y."version" desc limit 1) end,
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at"
  )
    order by x."is_default" desc, x."scope" desc, x."name", x."id"), '[]'::jsonb)
  from "better_supabase"."templates" x
  where (x."scope" = 'system' or x."tenant_id" = templates_list.tenant)
    and (templates_list.type is null or x."type" = templates_list.type)
    and (templates_list.language is null or x."language" = templates_list.language)
$$;
revoke execute on function "better_supabase"."templates_list"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."templates_list"(uuid, text, text) to authenticated, service_role;

-- One template with its newest published version and its draft, bodies
-- included; null when the caller can't read it.
create or replace function "better_supabase"."template_get"(template_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'id', x."id",
    'tenant', x."tenant_id",
    'scope', x."scope",
    'key', x."key",
    'type', x."type",
    'name', x."name",
    'language', x."language",
    'isDefault', x."is_default",
    'settings', x."settings",
    'forkedFrom', x."forked_from",
    'forkedFromVersion', x."forked_from_version",
    'publishedVersion', (select y."version" from "better_supabase"."template_versions" y where y."template_id" = x."id" and y."published_at" is not null order by y."version" desc limit 1),
    'upstreamVersion', case when x."forked_from" is not null then (select y."version" from "better_supabase"."template_versions" y where y."template_id" = x."forked_from" and y."published_at" is not null order by y."version" desc limit 1) end,
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at"
  ) || jsonb_build_object(
    'published', (select jsonb_build_object(
    'id', y."id",
    'template', y."template_id",
    'version', y."version",
    'hash', y."hash",
    'publishedAt', y."published_at",
    'createdBy', y."created_by",
    'createdAt', y."created_at",
    'body', y."body"
  ) from "better_supabase"."template_versions" y
      where y."template_id" = x."id" and y."published_at" is not null
      order by y."version" desc limit 1),
    'draft', (select jsonb_build_object(
    'id', y."id",
    'template', y."template_id",
    'version', y."version",
    'hash', y."hash",
    'publishedAt', y."published_at",
    'createdBy', y."created_by",
    'createdAt', y."created_at",
    'body', y."body"
  ) from "better_supabase"."template_versions" y
      where y."template_id" = x."id" and y."published_at" is null))
  from "better_supabase"."templates" x
  where x."id" = template_get.template_id
$$;
revoke execute on function "better_supabase"."template_get"(uuid) from public, anon;
grant execute on function "better_supabase"."template_get"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."remove_template"(template_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."templates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."templates" x where x."id" = remove_template.template_id;
  if not found then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'templates.manage'), false))) then
    raise exception 'You may not remove this template' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  delete from "better_supabase"."templates" x where x."id" = remove_template.template_id;
  return true;
end;
$$;
revoke execute on function "better_supabase"."remove_template"(uuid) from public, anon;
grant execute on function "better_supabase"."remove_template"(uuid) to authenticated, service_role;

-- Saves body as the template's draft: updates the open one, or opens one
-- numbered after the last version.
create or replace function "better_supabase"."save_template_draft"(template_id uuid, body jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tpl "better_supabase"."templates"%rowtype;
  v_row "better_supabase"."template_versions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_tpl from "better_supabase"."templates" x where x."id" = save_template_draft.template_id for update;
  if not found then
    raise exception 'No such template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tpl."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_tpl."tenant_id", 'templates.manage'), false))) then
    raise exception 'You may not edit this template' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  if save_template_draft.body is null then
    raise exception 'A template version needs a body' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  update "better_supabase"."template_versions" x set
    "body" = save_template_draft.body,
    "hash" = encode(extensions.digest(save_template_draft.body::text, 'sha256'), 'hex')
  where x."template_id" = save_template_draft.template_id and x."published_at" is null
  returning * into v_row;
  if not found then
    insert into "better_supabase"."template_versions" ("template_id", "version", "body", "hash", "created_by")
    values (
      save_template_draft.template_id,
      coalesce((select max(y."version") from "better_supabase"."template_versions" y where y."template_id" = save_template_draft.template_id), 0) + 1,
      save_template_draft.body,
      encode(extensions.digest(save_template_draft.body::text, 'sha256'), 'hex'),
      (select auth.uid())
    )
    returning * into v_row;
  end if;
  update "better_supabase"."templates" x set "updated_at" = now() where x."id" = save_template_draft.template_id;
  return jsonb_build_object(
    'id', v_row."id",
    'template', v_row."template_id",
    'version', v_row."version",
    'hash', v_row."hash",
    'publishedAt', v_row."published_at",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'body', v_row."body"
  );
end;
$$;
revoke execute on function "better_supabase"."save_template_draft"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_template_draft"(uuid, jsonb) to authenticated, service_role;

-- Publishes the template's draft. Applications use the newest published
-- version; published versions never change.
create or replace function "better_supabase"."publish_template_version"(template_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tpl "better_supabase"."templates"%rowtype;
  v_row "better_supabase"."template_versions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_tpl from "better_supabase"."templates" x where x."id" = publish_template_version.template_id for update;
  if not found then
    raise exception 'No such template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tpl."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_tpl."tenant_id", 'templates.manage'), false))) then
    raise exception 'You may not publish this template' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  update "better_supabase"."template_versions" x set "published_at" = now()
  where x."template_id" = publish_template_version.template_id and x."published_at" is null
  returning * into v_row;
  if not found then
    raise exception 'This template has no draft to publish' using errcode = 'P0002', hint = 'TEMPLATE_NO_DRAFT';
  end if;
  update "better_supabase"."templates" x set "updated_at" = now() where x."id" = publish_template_version.template_id;
  perform "better_supabase".emit_event('template.published', jsonb_build_object('organizationId', v_tpl."tenant_id", 'id', v_tpl."id", 'versionId', v_row."id", 'version', v_row."version", 'type', v_tpl."type"), 'templates/' || v_tpl."id"::text, (v_tpl."tenant_id")::text, null, 'better-supabase/templates');
  perform better_supabase.audit_event(
    event_type => 'template.published',
    category => 'configuration',
    target_type => 'template',
    record_id => v_tpl."id"::text,
    target_label => v_tpl."name",
    tenant => (v_tpl."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_tpl."tenant_id", 'id', v_tpl."id", 'versionId', v_row."id", 'version', v_row."version", 'type', v_tpl."type")
  );
  return jsonb_build_object(
    'id', v_row."id",
    'template', v_row."template_id",
    'version', v_row."version",
    'hash', v_row."hash",
    'publishedAt', v_row."published_at",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'body', v_row."body"
  );
end;
$$;
revoke execute on function "better_supabase"."publish_template_version"(uuid) from public, anon;
grant execute on function "better_supabase"."publish_template_version"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."template_versions_list"(template_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', y."id",
    'template', y."template_id",
    'version', y."version",
    'hash', y."hash",
    'publishedAt', y."published_at",
    'createdBy', y."created_by",
    'createdAt', y."created_at"
  ) order by y."version" desc), '[]'::jsonb)
  from "better_supabase"."template_versions" y where y."template_id" = template_versions_list.template_id
$$;
revoke execute on function "better_supabase"."template_versions_list"(uuid) from public, anon;
grant execute on function "better_supabase"."template_versions_list"(uuid) to authenticated, service_role;

-- One default per tenant, type and language.
create or replace function "better_supabase"."set_default_template"(template_id uuid, on_default boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."templates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."templates" x where x."id" = set_default_template.template_id for update;
  if not found then
    raise exception 'No such template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'templates.manage'), false))) then
    raise exception 'You may not change this template' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  if set_default_template.on_default then
    update "better_supabase"."templates" x set "is_default" = false, "updated_at" = now()
    where x."tenant_id" is not distinct from v_row."tenant_id"
      and x."type" = v_row."type" and x."language" = v_row."language"
      and x."is_default" and x."id" <> v_row."id";
  end if;
  update "better_supabase"."templates" x set "is_default" = coalesce(set_default_template.on_default, false), "updated_at" = now()
  where x."id" = set_default_template.template_id;
  return true;
end;
$$;
revoke execute on function "better_supabase"."set_default_template"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."set_default_template"(uuid, boolean) to authenticated, service_role;

-- Copies the newest published version of source (a system template, or one
-- in tenant) into a new template in tenant, published as its version 1, and
-- records the version it copied. templates.manage in tenant.
create or replace function "better_supabase"."fork_template"(source uuid, tenant uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_src "better_supabase"."templates"%rowtype;
  v_version "better_supabase"."template_versions"%rowtype;
  v_row "better_supabase"."templates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_src from "better_supabase"."templates" x where x."id" = fork_template.source;
  if not found or not (v_src."scope" = 'system' or v_src."tenant_id" = fork_template.tenant) then
    raise exception 'No such template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_FOUND';
  end if;
  if fork_template.tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (fork_template.tenant is not null and coalesce(better_supabase.can('tenant', fork_template.tenant, 'templates.manage'), false))) then
    raise exception 'You may not create templates here' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  select * into v_version from "better_supabase"."template_versions" y
  where y."template_id" = fork_template.source and y."published_at" is not null
  order by y."version" desc limit 1;
  if not found then
    raise exception 'This template has no published version' using errcode = 'P0002', hint = 'TEMPLATE_NOT_PUBLISHED';
  end if;
  insert into "better_supabase"."templates" ("tenant_id", "scope", "type", "name", "language", "settings", "forked_from", "forked_from_version", "created_by")
  values (fork_template.tenant, 'tenant', v_src."type", v_src."name", v_src."language", v_src."settings", v_src."id", v_version."version", (select auth.uid()))
  returning * into v_row;
  insert into "better_supabase"."template_versions" ("template_id", "version", "body", "hash", "published_at", "created_by")
  values (v_row."id", 1, v_version."body", v_version."hash", now(), (select auth.uid()));
  insert into "better_supabase"."template_workflows" ("template_id", "definition_id", "inputs", "enabled", "created_by")
  select v_row."id", w."definition_id", w."inputs", w."enabled", (select auth.uid())
  from "better_supabase"."template_workflows" w where w."template_id" = v_src."id";

  return jsonb_build_object(
    'id', v_row."id",
    'tenant', v_row."tenant_id",
    'scope', v_row."scope",
    'key', v_row."key",
    'type', v_row."type",
    'name', v_row."name",
    'language', v_row."language",
    'isDefault', v_row."is_default",
    'settings', v_row."settings",
    'forkedFrom', v_row."forked_from",
    'forkedFromVersion', v_row."forked_from_version",
    'publishedVersion', (select y."version" from "better_supabase"."template_versions" y where y."template_id" = v_row."id" and y."published_at" is not null order by y."version" desc limit 1),
    'upstreamVersion', case when v_row."forked_from" is not null then (select y."version" from "better_supabase"."template_versions" y where y."template_id" = v_row."forked_from" and y."published_at" is not null order by y."version" desc limit 1) end,
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'updatedAt', v_row."updated_at"
  );
end;
$$;
revoke execute on function "better_supabase"."fork_template"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."fork_template"(uuid, uuid) to authenticated, service_role;

-- Upserts the system templates by key from starters, a JSON array of
-- { key, type, name, language?, settings?, body }, and publishes a new
-- version of each whose body changed. Returns how many it published.
create or replace function "better_supabase"."sync_templates"(starters jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_starter jsonb;
  v_row "better_supabase"."templates"%rowtype;
  v_hash text;
  v_version "better_supabase"."template_versions"%rowtype;
  v_count integer := 0;
begin
  if jsonb_typeof(sync_templates.starters) <> 'array' then
    raise exception 'starters must be an array' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  for v_starter in select value from jsonb_array_elements(sync_templates.starters) loop
    if coalesce(v_starter ->> 'key', '') !~ '^[a-z0-9][a-z0-9_.-]{0,99}$' or not (v_starter ? 'body') then
      raise exception 'Each starter needs a key and a body' using errcode = '22023', hint = 'TEMPLATE_INVALID';
    end if;
    if v_starter ? 'brand' then
      raise exception 'this templates table has no brand column' using errcode = '22023', hint = 'TEMPLATE_BRAND_UNSUPPORTED';
    end if;
    select * into v_row from "better_supabase"."templates" x where x."tenant_id" is null and x."key" = v_starter ->> 'key' for update;
    if not found then
      insert into "better_supabase"."templates" ("tenant_id", "scope", "key", "type", "name", "language", "settings")
      values (null, 'system', v_starter ->> 'key', v_starter ->> 'type', v_starter ->> 'name',
        coalesce(v_starter ->> 'language', 'en'), coalesce(v_starter -> 'settings', '{}'::jsonb))
      returning * into v_row;
    else
      update "better_supabase"."templates" x set
        "type" = coalesce(v_starter ->> 'type', x."type"),
        "name" = coalesce(v_starter ->> 'name', x."name"),
        "language" = coalesce(v_starter ->> 'language', x."language"),
        "settings" = coalesce(v_starter -> 'settings', x."settings"),
        "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    end if;
    v_hash := encode(extensions.digest((v_starter -> 'body')::text, 'sha256'), 'hex');
    if v_hash is distinct from (select y."hash" from "better_supabase"."template_versions" y
        where y."template_id" = v_row."id" and y."published_at" is not null
        order by y."version" desc limit 1) then
      delete from "better_supabase"."template_versions" y where y."template_id" = v_row."id" and y."published_at" is null;
      insert into "better_supabase"."template_versions" ("template_id", "version", "body", "hash", "published_at")
      values (
        v_row."id",
        coalesce((select max(y."version") from "better_supabase"."template_versions" y where y."template_id" = v_row."id"), 0) + 1,
        v_starter -> 'body',
        v_hash,
        now()
      )
      returning * into v_version;
      v_count := v_count + 1;
      perform "better_supabase".emit_event('template.published', jsonb_build_object('organizationId', null, 'id', v_row."id", 'versionId', v_version."id", 'version', v_version."version", 'type', v_row."type"), 'templates/' || v_row."id"::text, null, null, 'better-supabase/templates');
    end if;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."sync_templates"(jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."sync_templates"(jsonb) to service_role;

-- What applying template in tenant needs: the template, its newest
-- published version with the body, and the enabled workflow attachments,
-- each input checked against the published version's input_schema
-- (TEMPLATE_WORKFLOW_INPUT_INVALID). templates.apply in tenant.
create or replace function "better_supabase"."template_apply_target"(template_id uuid, tenant uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tpl "better_supabase"."templates"%rowtype;
  v_version "better_supabase"."template_versions"%rowtype;
  v_workflows jsonb := '[]'::jsonb;
begin
  if template_apply_target.tenant is null then
    raise exception 'Applying a template needs a tenant' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', template_apply_target.tenant, 'templates.apply'), false)) then
    raise exception 'You may not apply templates here' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  select * into v_tpl from "better_supabase"."templates" x where x."id" = template_apply_target.template_id;
  if not found or not (v_tpl."scope" = 'system' or v_tpl."tenant_id" = template_apply_target.tenant) then
    raise exception 'No such template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_FOUND';
  end if;
  select * into v_version from "better_supabase"."template_versions" y
  where y."template_id" = v_tpl."id" and y."published_at" is not null
  order by y."version" desc limit 1;
  if not found then
    raise exception 'This template has no published version' using errcode = 'P0002', hint = 'TEMPLATE_NOT_PUBLISHED';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
      'definition', w."definition_id",
      'inputs', w."inputs",
      'errors', to_jsonb("better_supabase"."template_workflow_input_errors"(w."definition_id", w."inputs")))
    order by w."created_at", w."id"), '[]'::jsonb)
  into v_workflows
  from "better_supabase"."template_workflows" w where w."template_id" = v_tpl."id" and w."enabled";
  if exists (select 1 from jsonb_array_elements(v_workflows) e where jsonb_array_length(e.value -> 'errors') > 0) then
    raise exception 'A workflow input does not match its input schema: %',
      (select string_agg(e.value ->> 'definition' || ': ' || (e.value -> 'errors' ->> 0), '; ')
        from jsonb_array_elements(v_workflows) e where jsonb_array_length(e.value -> 'errors') > 0)
      using errcode = '22023', hint = 'TEMPLATE_WORKFLOW_INPUT_INVALID';
  end if;
  select coalesce(jsonb_agg(e.value - 'errors'), '[]'::jsonb) into v_workflows from jsonb_array_elements(v_workflows) e;

  return jsonb_build_object(
    'template', jsonb_build_object(
    'id', v_tpl."id",
    'tenant', v_tpl."tenant_id",
    'scope', v_tpl."scope",
    'key', v_tpl."key",
    'type', v_tpl."type",
    'name', v_tpl."name",
    'language', v_tpl."language",
    'isDefault', v_tpl."is_default",
    'settings', v_tpl."settings",
    'forkedFrom', v_tpl."forked_from",
    'forkedFromVersion', v_tpl."forked_from_version",
    'publishedVersion', (select y."version" from "better_supabase"."template_versions" y where y."template_id" = v_tpl."id" and y."published_at" is not null order by y."version" desc limit 1),
    'upstreamVersion', case when v_tpl."forked_from" is not null then (select y."version" from "better_supabase"."template_versions" y where y."template_id" = v_tpl."forked_from" and y."published_at" is not null order by y."version" desc limit 1) end,
    'createdBy', v_tpl."created_by",
    'createdAt', v_tpl."created_at",
    'updatedAt', v_tpl."updated_at"
  ),
    'version', jsonb_build_object(
    'id', v_version."id",
    'template', v_version."template_id",
    'version', v_version."version",
    'hash', v_version."hash",
    'publishedAt', v_version."published_at",
    'createdBy', v_version."created_by",
    'createdAt', v_version."created_at",
    'body', v_version."body"
  ),
    'workflows', v_workflows
  );
end;
$$;
revoke execute on function "better_supabase"."template_apply_target"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."template_apply_target"(uuid, uuid) to authenticated, service_role;

-- Records that version of template created subject_type/subject_id in
-- tenant. templates.apply in tenant.
create or replace function "better_supabase"."record_template_application"(template_id uuid, version_id uuid, tenant uuid, subject_type text, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tpl "better_supabase"."templates"%rowtype;
  v_row "better_supabase"."template_applications"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if record_template_application.tenant is null then
    raise exception 'Applying a template needs a tenant' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', record_template_application.tenant, 'templates.apply'), false)) then
    raise exception 'You may not apply templates here' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  select * into v_tpl from "better_supabase"."templates" x where x."id" = record_template_application.template_id;
  if not found or not (v_tpl."scope" = 'system' or v_tpl."tenant_id" = record_template_application.tenant) then
    raise exception 'No such template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_FOUND';
  end if;
  if not exists (select 1 from "better_supabase"."template_versions" y where y."id" = record_template_application.version_id
      and y."template_id" = v_tpl."id" and y."published_at" is not null) then
    raise exception 'Not a published version of this template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_PUBLISHED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_template_apply"(uuid, uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text, $4::text)', v_hook::oid::regproc)
        using record_template_application.tenant, v_tpl."id", record_template_application.subject_type, record_template_application.subject_id;
    end if;
  end;
  insert into "better_supabase"."template_applications" ("template_id", "version_id", "tenant_id", "subject_type", "subject_id", "applied_by")
  values (v_tpl."id", record_template_application.version_id, record_template_application.tenant,
    record_template_application.subject_type, record_template_application.subject_id, (select auth.uid()))
  returning * into v_row;
  perform "better_supabase".emit_event('template.applied', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'id', v_row."id", 'templateId', v_row."template_id", 'versionId', v_row."version_id"), 'template-applications/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/templates');
  perform better_supabase.audit_event(
    event_type => 'template.applied',
    category => 'data',
    target_type => 'template_application',
    record_id => v_row."id"::text,
    target_label => v_tpl."name",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'id', v_row."id", 'templateId', v_row."template_id", 'versionId', v_row."version_id")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_template_apply"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object(
    'id', v_row."id",
    'template', v_row."template_id",
    'version', v_row."version_id",
    'tenant', v_row."tenant_id",
    'subjectType', v_row."subject_type",
    'subjectId', v_row."subject_id",
    'appliedBy', v_row."applied_by",
    'appliedAt', v_row."applied_at"
  );
end;
$$;
revoke execute on function "better_supabase"."record_template_application"(uuid, uuid, uuid, text, text) from public, anon;
grant execute on function "better_supabase"."record_template_application"(uuid, uuid, uuid, text, text) to authenticated, service_role;

-- The tenant's applications, newest first, of one template or onto one
-- subject when those are given.
create or replace function "better_supabase"."template_applications_list"(tenant uuid, template_id uuid, subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(r.value order by r.at desc, r.id), '[]'::jsonb)
  from (
    select jsonb_build_object(
    'id', a."id",
    'template', a."template_id",
    'version', a."version_id",
    'tenant', a."tenant_id",
    'subjectType', a."subject_type",
    'subjectId', a."subject_id",
    'appliedBy', a."applied_by",
    'appliedAt', a."applied_at"
  ) as value, a."applied_at" as at, a."id" as id
    from "better_supabase"."template_applications" a
    where a."tenant_id" = template_applications_list.tenant
      and (template_applications_list.template_id is null or a."template_id" = template_applications_list.template_id)
      and (template_applications_list.subject_type is null or a."subject_type" = template_applications_list.subject_type)
      and (template_applications_list.subject_id is null or a."subject_id" = template_applications_list.subject_id)
    order by a."applied_at" desc, a."id"
    limit 200
  ) r
$$;
revoke execute on function "better_supabase"."template_applications_list"(uuid, uuid, text, text) from public, anon;
grant execute on function "better_supabase"."template_applications_list"(uuid, uuid, text, text) to authenticated, service_role;

-- Starts definition on every record template creates, with inputs as the
-- run's input. The definition must be in the template's tenant or a system
-- one; inputs are checked against its published input_schema.
create or replace function "better_supabase"."attach_template_workflow"(template_id uuid, definition uuid, inputs jsonb, enabled boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tpl "better_supabase"."templates"%rowtype;
  v_def "better_supabase"."workflow_definitions"%rowtype;
  v_errors text[];
  v_row "better_supabase"."template_workflows"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_tpl from "better_supabase"."templates" x where x."id" = attach_template_workflow.template_id;
  if not found then
    raise exception 'No such template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tpl."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_tpl."tenant_id", 'templates.manage'), false))) then
    raise exception 'You may not change this template' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  select * into v_def from "better_supabase"."workflow_definitions" x where x."id" = attach_template_workflow.definition;
  if not found or not (v_def."scope" = 'system' or v_def."tenant_id" is not distinct from v_tpl."tenant_id") then
    raise exception 'No such workflow' using errcode = 'P0002', hint = 'TEMPLATE_WORKFLOW_NOT_FOUND';
  end if;
  v_errors := "better_supabase"."template_workflow_input_errors"(attach_template_workflow.definition, coalesce(attach_template_workflow.inputs, '{}'::jsonb));
  if cardinality(v_errors) > 0 then
    raise exception 'The workflow input does not match its input schema: %', v_errors[1]
      using errcode = '22023', hint = 'TEMPLATE_WORKFLOW_INPUT_INVALID';
  end if;
  insert into "better_supabase"."template_workflows" as w ("template_id", "definition_id", "inputs", "enabled", "created_by")
  values (v_tpl."id", attach_template_workflow.definition,
    coalesce(attach_template_workflow.inputs, '{}'::jsonb), coalesce(attach_template_workflow.enabled, true), (select auth.uid()))
  on conflict on constraint template_workflows_template_definition_key do update set
    "inputs" = excluded."inputs",
    "enabled" = excluded."enabled"
  returning * into v_row;
  return jsonb_build_object(
    'id', v_row."id",
    'template', v_row."template_id",
    'definition', v_row."definition_id",
    'inputs', v_row."inputs",
    'enabled', v_row."enabled",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at"
  );
end;
$$;
revoke execute on function "better_supabase"."attach_template_workflow"(uuid, uuid, jsonb, boolean) from public, anon;
grant execute on function "better_supabase"."attach_template_workflow"(uuid, uuid, jsonb, boolean) to authenticated, service_role;

create or replace function "better_supabase"."detach_template_workflow"(template_id uuid, definition uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tpl "better_supabase"."templates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_tpl from "better_supabase"."templates" x where x."id" = detach_template_workflow.template_id;
  if not found then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tpl."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_tpl."tenant_id", 'templates.manage'), false))) then
    raise exception 'You may not change this template' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  delete from "better_supabase"."template_workflows" w where w."template_id" = detach_template_workflow.template_id
    and w."definition_id" = detach_template_workflow.definition;
  return found;
end;
$$;
revoke execute on function "better_supabase"."detach_template_workflow"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."detach_template_workflow"(uuid, uuid) to authenticated, service_role;

create or replace function "better_supabase"."template_workflows_list"(template_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', w."id",
    'template', w."template_id",
    'definition', w."definition_id",
    'inputs', w."inputs",
    'enabled', w."enabled",
    'createdBy', w."created_by",
    'createdAt', w."created_at"
  ) order by w."created_at", w."id"), '[]'::jsonb)
  from "better_supabase"."template_workflows" w where w."template_id" = template_workflows_list.template_id
$$;
revoke execute on function "better_supabase"."template_workflows_list"(uuid) from public, anon;
grant execute on function "better_supabase"."template_workflows_list"(uuid) to authenticated, service_role;

-- Recurring records: each schedule applies template_id in tenant_id with
-- input at every occurrence of its rule in "better_supabase"."recurrence_rules"
-- (subject_type 'template_schedule'). The client expands the rules and enqueues
-- one job per occurrence.
create table if not exists "better_supabase"."template_schedules" (
  "id" uuid primary key default gen_random_uuid(),
  "template_id" uuid not null references "better_supabase"."templates" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "input" jsonb not null default '{}'::jsonb
    check (jsonb_typeof("input") = 'object' and pg_column_size("input") <= 65536),
  "enabled" boolean not null default true,
  "created_by" uuid references auth.users (id) on delete set null,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index if not exists template_schedules_tenant_idx on "better_supabase"."template_schedules" ("tenant_id", "template_id");
create index if not exists template_schedules_template_idx on "better_supabase"."template_schedules" ("template_id");
create index if not exists template_schedules_created_by_idx on "better_supabase"."template_schedules" ("created_by");
alter table "better_supabase"."template_schedules" enable row level security;
revoke all on "better_supabase"."template_schedules" from public, anon, authenticated;
grant select on "better_supabase"."template_schedules" to authenticated;
grant all on "better_supabase"."template_schedules" to service_role;
drop policy if exists template_schedules_read on "better_supabase"."template_schedules";
create policy template_schedules_read on "better_supabase"."template_schedules"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('templates.read')));

-- One row per occurrence a schedule claimed, and the application it made.
create table if not exists "better_supabase"."template_schedule_runs" (
  "schedule_id" uuid not null references "better_supabase"."template_schedules" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "occurrence_at" timestamptz not null,
  "application_id" uuid references "better_supabase"."template_applications" ("id") on delete set null,
  "created_at" timestamptz not null default now(),
  primary key ("schedule_id", "occurrence_at")
);
create index if not exists template_schedule_runs_tenant_idx on "better_supabase"."template_schedule_runs" ("tenant_id", "occurrence_at" desc);
create index if not exists template_schedule_runs_application_idx on "better_supabase"."template_schedule_runs" ("application_id");
alter table "better_supabase"."template_schedule_runs" enable row level security;
revoke all on "better_supabase"."template_schedule_runs" from public, anon, authenticated;
grant select on "better_supabase"."template_schedule_runs" to authenticated;
grant all on "better_supabase"."template_schedule_runs" to service_role;
drop policy if exists template_schedule_runs_read on "better_supabase"."template_schedule_runs";
create policy template_schedule_runs_read on "better_supabase"."template_schedule_runs"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('templates.read')));

-- A removed schedule (or one its template took with it) drops its rule.
create or replace function "better_supabase"."template_schedule_removed"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from "better_supabase"."recurrence_rules" u where u."tenant_id" = old."tenant_id"
      and u."subject_type" = 'template_schedule'
      and u."subject_id" = old."id"::text;
  return old;
end;
$$;
revoke execute on function "better_supabase"."template_schedule_removed"() from public, anon, authenticated;
drop trigger if exists "bsb_template_schedule_removed" on "better_supabase"."template_schedules";
create trigger "bsb_template_schedule_removed" after delete on "better_supabase"."template_schedules"
for each row execute function "better_supabase"."template_schedule_removed"();

-- Creates a schedule (schedule_id null) or changes one: template_id applies
-- in tenant with input at each occurrence of rrule from dtstart in tzid.
-- templates.manage in tenant; the template must be visible there.
create or replace function "better_supabase"."save_template_schedule"(schedule_id uuid, template_id uuid, tenant uuid, dtstart timestamptz, tzid text, rrule text, input jsonb, enabled boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tpl "better_supabase"."templates"%rowtype;
  v_row "better_supabase"."template_schedules"%rowtype;
  v_rule "better_supabase"."recurrence_rules"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if save_template_schedule.tenant is null then
    raise exception 'A schedule needs a tenant' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_template_schedule.tenant is not null and coalesce(better_supabase.can('tenant', save_template_schedule.tenant, 'templates.manage'), false))) then
    raise exception 'You may not schedule templates here' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  if save_template_schedule.dtstart is null or coalesce(length(save_template_schedule.rrule), 0) not between 1 and 1000 then
    raise exception 'A schedule needs a start and a rule' using errcode = '22023', hint = 'TEMPLATE_SCHEDULE_INVALID';
  end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names z where z.name = coalesce(save_template_schedule.tzid, 'UTC')) then
    raise exception 'tzid must be an IANA time zone' using errcode = '22023', hint = 'TEMPLATE_SCHEDULE_INVALID';
  end if;
  if save_template_schedule.input is not null and jsonb_typeof(save_template_schedule.input) <> 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  select * into v_tpl from "better_supabase"."templates" x where x."id" = save_template_schedule.template_id;
  if not found or not (v_tpl."scope" = 'system' or v_tpl."tenant_id" = save_template_schedule.tenant) then
    raise exception 'No such template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_FOUND';
  end if;
  if save_template_schedule.schedule_id is null then
    insert into "better_supabase"."template_schedules" ("template_id", "tenant_id", "input", "enabled", "created_by")
    values (v_tpl."id", save_template_schedule.tenant, coalesce(save_template_schedule.input, '{}'::jsonb),
      coalesce(save_template_schedule.enabled, true), (select auth.uid()))
    returning * into v_row;
  else
    update "better_supabase"."template_schedules" x set
      "template_id" = v_tpl."id",
      "input" = coalesce(save_template_schedule.input, x."input"),
      "enabled" = coalesce(save_template_schedule.enabled, x."enabled"),
      "updated_at" = now()
    where x."id" = save_template_schedule.schedule_id and x."tenant_id" = save_template_schedule.tenant
    returning * into v_row;
    if not found then
      raise exception 'No such schedule' using errcode = 'P0002', hint = 'TEMPLATE_SCHEDULE_NOT_FOUND';
    end if;
  end if;
  update "better_supabase"."recurrence_rules" u set
    "dtstart" = save_template_schedule.dtstart,
    "tzid" = coalesce(save_template_schedule.tzid, 'UTC'),
    "rrule" = save_template_schedule.rrule
  where u."tenant_id" = v_row."tenant_id"
      and u."subject_type" = 'template_schedule'
      and u."subject_id" = v_row."id"::text
  returning * into v_rule;
  if not found then
    insert into "better_supabase"."recurrence_rules" ("tenant_id", "subject_type", "subject_id", "dtstart", "tzid", "rrule")
    values (v_row."tenant_id", 'template_schedule', v_row."id"::text, save_template_schedule.dtstart,
      coalesce(save_template_schedule.tzid, 'UTC'), save_template_schedule.rrule)
    returning * into v_rule;
  end if;
  return jsonb_build_object(
    'id', v_row."id",
    'template', v_row."template_id",
    'tenant', v_row."tenant_id",
    'input', v_row."input",
    'enabled', v_row."enabled",
    'dtstart', v_rule."dtstart",
    'tzid', v_rule."tzid",
    'rrule', v_rule."rrule",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'updatedAt', v_row."updated_at"
  );
end;
$$;
revoke execute on function "better_supabase"."save_template_schedule"(uuid, uuid, uuid, timestamptz, text, text, jsonb, boolean) from public, anon;
grant execute on function "better_supabase"."save_template_schedule"(uuid, uuid, uuid, timestamptz, text, text, jsonb, boolean) to authenticated, service_role;

-- Removes a schedule and its rule. templates.manage in its tenant.
create or replace function "better_supabase"."remove_template_schedule"(schedule_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."template_schedules"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."template_schedules" x where x."id" = remove_template_schedule.schedule_id;
  if not found then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'templates.manage'), false))) then
    raise exception 'You may not remove this schedule' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  delete from "better_supabase"."template_schedules" x where x."id" = v_row."id";
  return true;
end;
$$;
revoke execute on function "better_supabase"."remove_template_schedule"(uuid) from public, anon;
grant execute on function "better_supabase"."remove_template_schedule"(uuid) to authenticated, service_role;

-- The tenant's schedules with their rules, of one template when given.
-- templates.read in tenant.
create or replace function "better_supabase"."template_schedules_list"(tenant uuid, template_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', template_schedules_list.tenant, 'templates.read'), false)) then
    raise exception 'You may not read schedules here' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
    'id', x."id",
    'template', x."template_id",
    'tenant', x."tenant_id",
    'input', x."input",
    'enabled', x."enabled",
    'dtstart', u."dtstart",
    'tzid', u."tzid",
    'rrule', u."rrule",
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at"
  ) order by x."created_at", x."id"), '[]'::jsonb)
    from "better_supabase"."template_schedules" x
    left join "better_supabase"."recurrence_rules" u on u."tenant_id" = x."tenant_id"
      and u."subject_type" = 'template_schedule'
      and u."subject_id" = x."id"::text
    where x."tenant_id" = template_schedules_list.tenant
      and (template_schedules_list.template_id is null or x."template_id" = template_schedules_list.template_id)
  );
end;
$$;
revoke execute on function "better_supabase"."template_schedules_list"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."template_schedules_list"(uuid, uuid) to authenticated, service_role;

-- Every enabled schedule with its rule, for the client to expand.
create or replace function "better_supabase"."list_template_schedule"()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x."id",
    'template', x."template_id",
    'tenant', x."tenant_id",
    'input', x."input",
    'enabled', x."enabled",
    'dtstart', u."dtstart",
    'tzid', u."tzid",
    'rrule', u."rrule",
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at"
  ) order by x."id"), '[]'::jsonb)
  from "better_supabase"."template_schedules" x
  join "better_supabase"."recurrence_rules" u on u."tenant_id" = x."tenant_id"
      and u."subject_type" = 'template_schedule'
      and u."subject_id" = x."id"::text
  where x."enabled" and u."rrule" is not null
$$;
revoke execute on function "better_supabase"."list_template_schedule"() from public, anon, authenticated;
grant execute on function "better_supabase"."list_template_schedule"() to service_role;

-- Claims one occurrence of an enabled schedule: the schedule when the
-- occurrence is new or hasn't recorded an application yet, else null.
create or replace function "better_supabase"."claim_template_occurrence"(schedule_id uuid, occurrence_at timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."template_schedules"%rowtype;
  v_rule "better_supabase"."recurrence_rules"%rowtype;
begin
  select * into v_row from "better_supabase"."template_schedules" x where x."id" = claim_template_occurrence.schedule_id and x."enabled";
  if not found then
    return null;
  end if;
  insert into "better_supabase"."template_schedule_runs" ("schedule_id", "tenant_id", "occurrence_at")
  values (v_row."id", v_row."tenant_id", claim_template_occurrence.occurrence_at)
  on conflict ("schedule_id", "occurrence_at") do nothing;
  if not found and exists (select 1 from "better_supabase"."template_schedule_runs" y
      where y."schedule_id" = v_row."id" and y."occurrence_at" = claim_template_occurrence.occurrence_at
        and y."application_id" is not null) then
    return null;
  end if;
  select * into v_rule from "better_supabase"."recurrence_rules" u where u."tenant_id" = v_row."tenant_id"
      and u."subject_type" = 'template_schedule'
      and u."subject_id" = v_row."id"::text;
  return jsonb_build_object(
    'id', v_row."id",
    'template', v_row."template_id",
    'tenant', v_row."tenant_id",
    'input', v_row."input",
    'enabled', v_row."enabled",
    'dtstart', v_rule."dtstart",
    'tzid', v_rule."tzid",
    'rrule', v_rule."rrule",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'updatedAt', v_row."updated_at"
  );
end;
$$;
revoke execute on function "better_supabase"."claim_template_occurrence"(uuid, timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."claim_template_occurrence"(uuid, timestamptz) to service_role;

-- Records the application an occurrence made. False when it already had one.
create or replace function "better_supabase"."finish_template_occurrence"(schedule_id uuid, occurrence_at timestamptz, application_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  update "better_supabase"."template_schedule_runs" y set "application_id" = finish_template_occurrence.application_id
  where y."schedule_id" = finish_template_occurrence.schedule_id
    and y."occurrence_at" = finish_template_occurrence.occurrence_at
    and y."application_id" is null;
  return found;
end;
$$;
revoke execute on function "better_supabase"."finish_template_occurrence"(uuid, timestamptz, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."finish_template_occurrence"(uuid, timestamptz, uuid) to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."templates";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."templates";
create policy bsb_tenant_scope_select on "better_supabase"."templates" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('templates.read'))
    or ("scope" = 'system' and exists (select better_supabase.tenant_ids_with('templates.read'))))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."templates";
create policy bsb_tenant_scope_insert on "better_supabase"."templates" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."templates";
create policy bsb_tenant_scope_update on "better_supabase"."templates" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."templates";
create policy bsb_tenant_scope_delete on "better_supabase"."templates" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."template_applications";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."template_applications";
create policy bsb_tenant_scope_select on "better_supabase"."template_applications" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('templates.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."template_applications";
create policy bsb_tenant_scope_insert on "better_supabase"."template_applications" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."template_applications";
create policy bsb_tenant_scope_update on "better_supabase"."template_applications" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."template_applications";
create policy bsb_tenant_scope_delete on "better_supabase"."template_applications" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."template_schedules";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."template_schedules";
create policy bsb_tenant_scope_select on "better_supabase"."template_schedules" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('templates.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."template_schedules";
create policy bsb_tenant_scope_insert on "better_supabase"."template_schedules" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."template_schedules";
create policy bsb_tenant_scope_update on "better_supabase"."template_schedules" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."template_schedules";
create policy bsb_tenant_scope_delete on "better_supabase"."template_schedules" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."template_schedule_runs";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."template_schedule_runs";
create policy bsb_tenant_scope_select on "better_supabase"."template_schedule_runs" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('templates.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."template_schedule_runs";
create policy bsb_tenant_scope_insert on "better_supabase"."template_schedule_runs" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."template_schedule_runs";
create policy bsb_tenant_scope_update on "better_supabase"."template_schedule_runs" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."template_schedule_runs";
create policy bsb_tenant_scope_delete on "better_supabase"."template_schedule_runs" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_091_templates.sql
-- better-supabase module: templates
-- @bsb-block-data templates
-- @bsb-hash sha256:b8f109c9be802b16766dc2421c68f34cacf2322c02b9c507938fd08f01f94689
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "pgcrypto" with schema "extensions";

insert into better_supabase.blocks (name, version, mode)
values ('templates', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_091_templates.sql
-- better-supabase module: templates
-- @bsb-block templates@1 managed
-- @bsb-hash sha256:cbbab7bba9e9d8ef06773287ed2e60e9861a0bbcf8adcdfe0d3296921cbcddda
-- Typed, versioned templates (system starters and tenant forks) that create records, with merge fields and workflows started on each record they create.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."templates";
    drop policy if exists bsb_tenant_scope_select on "app_private"."templates";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."templates";
    drop policy if exists bsb_tenant_scope_update on "app_private"."templates";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."templates";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."template_applications";
    drop policy if exists bsb_tenant_scope_select on "app_private"."template_applications";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."template_applications";
    drop policy if exists bsb_tenant_scope_update on "app_private"."template_applications";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."template_applications";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on functions from public, anon, authenticated;
create extension if not exists pgcrypto with schema extensions;

-- Templates of a type (an invoice, a project, an email): a tenant's own, or
-- a system starter (no tenant) that sync_templates keeps by key and tenants
-- fork, or with options.brand a starter of one brand. forked_from: the template and version a fork copied.
create table if not exists "app_private"."templates" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid,
  "scope" text not null default 'tenant' check ("scope" in ('tenant', 'system')),
  "key" text check ("key" ~ '^[a-z0-9][a-z0-9_.-]{0,99}$'),
  "type" text not null check ("type" ~ '^[a-z][a-z0-9_.-]{0,63}$'),
  "name" text not null check (length("name") between 1 and 200),
  "language" text not null default 'en' check ("language" ~ '^[a-z]{2,3}(-[A-Za-z0-9]{1,8})*$'),
  "is_default" boolean not null default false,
  "settings" jsonb not null default '{}'::jsonb
    check (jsonb_typeof("settings") = 'object' and pg_column_size("settings") <= 65536),
  "forked_from" uuid references "app_private"."templates" ("id") on delete set null,
  "forked_from_version" integer check ("forked_from_version" > 0),
  "created_by" uuid references auth.users (id) on delete set null,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  constraint templates_system_check check (("scope" = 'system') = ("tenant_id" is null))
);
create unique index if not exists templates_key_idx on "app_private"."templates" ("tenant_id", "key") nulls not distinct where "key" is not null;
create unique index if not exists templates_default_idx on "app_private"."templates" ("tenant_id", "type", "language") nulls not distinct where "is_default";
create index if not exists templates_type_idx on "app_private"."templates" ("tenant_id", "type");
create index if not exists templates_forked_from_idx on "app_private"."templates" ("forked_from") where "forked_from" is not null;
create index if not exists templates_created_by_idx on "app_private"."templates" ("created_by");
alter table "app_private"."templates" enable row level security;
revoke all on "app_private"."templates" from public, anon, authenticated;
grant select on "app_private"."templates" to authenticated;
grant all on "app_private"."templates" to service_role;
drop policy if exists templates_read on "app_private"."templates";
create policy templates_read on "app_private"."templates"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('templates.read'))
    or ("scope" = 'system' and exists (select better_supabase.tenant_ids_with('templates.read'))));

-- Numbered snapshots of a template's body: at most one draft, and published
-- versions that never change. hash: the SHA-256 of the body as text.
create table if not exists "app_private"."template_versions" (
  "id" uuid primary key default gen_random_uuid(),
  "template_id" uuid not null references "app_private"."templates" ("id") on delete cascade,
  "version" integer not null check ("version" > 0),
  "body" jsonb not null check (pg_column_size("body") <= 1048576),
  "hash" text not null,
  "published_at" timestamptz,
  "created_by" uuid references auth.users (id) on delete set null,
  "created_at" timestamptz not null default now(),
  constraint template_versions_template_version_key unique ("template_id", "version")
);
create unique index if not exists template_versions_one_draft_idx on "app_private"."template_versions" ("template_id") where "published_at" is null;
create index if not exists template_versions_created_by_idx on "app_private"."template_versions" ("created_by");
alter table "app_private"."template_versions" enable row level security;
revoke all on "app_private"."template_versions" from public, anon, authenticated;
grant select on "app_private"."template_versions" to authenticated;
grant all on "app_private"."template_versions" to service_role;
drop policy if exists template_versions_read on "app_private"."template_versions";
create policy template_versions_read on "app_private"."template_versions"
  for select to authenticated
  using (exists (select 1 from "app_private"."templates" x where x."id" = "template_id"));

-- Each time a published version created a record, and which one.
create table if not exists "app_private"."template_applications" (
  "id" uuid primary key default gen_random_uuid(),
  "template_id" uuid not null references "app_private"."templates" ("id") on delete cascade,
  "version_id" uuid not null references "app_private"."template_versions" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "subject_type" text not null check (length("subject_type") between 1 and 100),
  "subject_id" text not null check (length("subject_id") between 1 and 200),
  "applied_by" uuid references auth.users (id) on delete set null,
  "applied_at" timestamptz not null default now()
);
create index if not exists template_applications_tenant_idx on "app_private"."template_applications" ("tenant_id", "applied_at" desc);
create index if not exists template_applications_template_idx on "app_private"."template_applications" ("template_id");
create index if not exists template_applications_version_idx on "app_private"."template_applications" ("version_id");
create index if not exists template_applications_subject_idx on "app_private"."template_applications" ("subject_type", "subject_id");
create index if not exists template_applications_applied_by_idx on "app_private"."template_applications" ("applied_by");
alter table "app_private"."template_applications" enable row level security;
revoke all on "app_private"."template_applications" from public, anon, authenticated;
grant select on "app_private"."template_applications" to authenticated;
grant all on "app_private"."template_applications" to service_role;
drop policy if exists template_applications_read on "app_private"."template_applications";
create policy template_applications_read on "app_private"."template_applications"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('templates.read')));

-- Creates a template (template_id null) or renames it and replaces its
-- settings. tenant null saves a system template, which only the service
-- role may; a tenant's needs templates.manage there.
-- fields: the extra columns (blocks.templates.options.extraColumns) to set.
drop function if exists "app_private"."save_template"(uuid, uuid, text, text, text, jsonb, jsonb);
create or replace function "app_private"."save_template"(template_id uuid, tenant uuid, type text, name text, language text, settings jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."templates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if save_template.settings is not null and jsonb_typeof(save_template.settings) <> 'object' then
    raise exception 'settings must be an object' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  if save_template.template_id is not null then
    select * into v_row from "app_private"."templates" x where x."id" = save_template.template_id for update;
    if not found or v_row."tenant_id" is distinct from save_template.tenant then
      raise exception 'No such template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_FOUND';
    end if;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_template.tenant is not null and coalesce(better_supabase.can('tenant', save_template.tenant, 'templates.manage'), false))) then
    raise exception 'You may not change templates here' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  if save_template.template_id is null and (save_template.type is null or save_template.type !~ '^[a-z][a-z0-9_.-]{0,63}$') then
    raise exception 'type must be lower-case letters, digits, dots, dashes or underscores' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  if save_template.template_id is null and save_template.name is null then
    raise exception 'A template needs a name' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_template_save"(uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::jsonb)', v_hook::oid::regproc)
        using save_template.tenant, coalesce(save_template.type, v_row."type"), save_template.settings;
    end if;
  end;
  if save_template.template_id is null then
    insert into "app_private"."templates" ("tenant_id", "scope", "type", "name", "language", "settings", "created_by")
    values (
      save_template.tenant,
      case when save_template.tenant is null then 'system' else 'tenant' end,
      save_template.type,
      save_template.name,
      coalesce(save_template.language, 'en'),
      coalesce(save_template.settings, '{}'::jsonb),
      (select auth.uid())
    )
    returning * into v_row;
  else
    update "app_private"."templates" x set
      "name" = coalesce(save_template.name, x."name"),
      "language" = coalesce(save_template.language, x."language"),
      "settings" = coalesce(save_template.settings, x."settings"),
      "is_default" = x."is_default" and coalesce(save_template.language, x."language") = x."language",
      "updated_at" = now()
    where x."id" = save_template.template_id
    returning * into v_row;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_template_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object(
    'id', v_row."id",
    'tenant', v_row."tenant_id",
    'scope', v_row."scope",
    'key', v_row."key",
    'type', v_row."type",
    'name', v_row."name",
    'language', v_row."language",
    'isDefault', v_row."is_default",
    'settings', v_row."settings",
    'forkedFrom', v_row."forked_from",
    'forkedFromVersion', v_row."forked_from_version",
    'publishedVersion', (select y."version" from "app_private"."template_versions" y where y."template_id" = v_row."id" and y."published_at" is not null order by y."version" desc limit 1),
    'upstreamVersion', case when v_row."forked_from" is not null then (select y."version" from "app_private"."template_versions" y where y."template_id" = v_row."forked_from" and y."published_at" is not null order by y."version" desc limit 1) end,
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'updatedAt', v_row."updated_at"
  );
end;
$$;
revoke execute on function "app_private"."save_template"(uuid, uuid, text, text, text, jsonb) from public, anon;
grant execute on function "app_private"."save_template"(uuid, uuid, text, text, text, jsonb) to authenticated, service_role;

-- The tenant's templates and the system ones (only the system ones without
-- a tenant), filtered by type and language, defaults first.
create or replace function "app_private"."templates_list"(tenant uuid, type text, language text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x."id",
    'tenant', x."tenant_id",
    'scope', x."scope",
    'key', x."key",
    'type', x."type",
    'name', x."name",
    'language', x."language",
    'isDefault', x."is_default",
    'settings', x."settings",
    'forkedFrom', x."forked_from",
    'forkedFromVersion', x."forked_from_version",
    'publishedVersion', (select y."version" from "app_private"."template_versions" y where y."template_id" = x."id" and y."published_at" is not null order by y."version" desc limit 1),
    'upstreamVersion', case when x."forked_from" is not null then (select y."version" from "app_private"."template_versions" y where y."template_id" = x."forked_from" and y."published_at" is not null order by y."version" desc limit 1) end,
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at"
  )
    order by x."is_default" desc, x."scope" desc, x."name", x."id"), '[]'::jsonb)
  from "app_private"."templates" x
  where (x."scope" = 'system' or x."tenant_id" = templates_list.tenant)
    and (templates_list.type is null or x."type" = templates_list.type)
    and (templates_list.language is null or x."language" = templates_list.language)
$$;
revoke execute on function "app_private"."templates_list"(uuid, text, text) from public, anon;
grant execute on function "app_private"."templates_list"(uuid, text, text) to authenticated, service_role;

-- One template with its newest published version and its draft, bodies
-- included; null when the caller can't read it.
create or replace function "app_private"."template_get"(template_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'id', x."id",
    'tenant', x."tenant_id",
    'scope', x."scope",
    'key', x."key",
    'type', x."type",
    'name', x."name",
    'language', x."language",
    'isDefault', x."is_default",
    'settings', x."settings",
    'forkedFrom', x."forked_from",
    'forkedFromVersion', x."forked_from_version",
    'publishedVersion', (select y."version" from "app_private"."template_versions" y where y."template_id" = x."id" and y."published_at" is not null order by y."version" desc limit 1),
    'upstreamVersion', case when x."forked_from" is not null then (select y."version" from "app_private"."template_versions" y where y."template_id" = x."forked_from" and y."published_at" is not null order by y."version" desc limit 1) end,
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at"
  ) || jsonb_build_object(
    'published', (select jsonb_build_object(
    'id', y."id",
    'template', y."template_id",
    'version', y."version",
    'hash', y."hash",
    'publishedAt', y."published_at",
    'createdBy', y."created_by",
    'createdAt', y."created_at",
    'body', y."body"
  ) from "app_private"."template_versions" y
      where y."template_id" = x."id" and y."published_at" is not null
      order by y."version" desc limit 1),
    'draft', (select jsonb_build_object(
    'id', y."id",
    'template', y."template_id",
    'version', y."version",
    'hash', y."hash",
    'publishedAt', y."published_at",
    'createdBy', y."created_by",
    'createdAt', y."created_at",
    'body', y."body"
  ) from "app_private"."template_versions" y
      where y."template_id" = x."id" and y."published_at" is null))
  from "app_private"."templates" x
  where x."id" = template_get.template_id
$$;
revoke execute on function "app_private"."template_get"(uuid) from public, anon;
grant execute on function "app_private"."template_get"(uuid) to authenticated, service_role;

create or replace function "app_private"."remove_template"(template_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."templates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."templates" x where x."id" = remove_template.template_id;
  if not found then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'templates.manage'), false))) then
    raise exception 'You may not remove this template' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  delete from "app_private"."templates" x where x."id" = remove_template.template_id;
  return true;
end;
$$;
revoke execute on function "app_private"."remove_template"(uuid) from public, anon;
grant execute on function "app_private"."remove_template"(uuid) to authenticated, service_role;

-- Saves body as the template's draft: updates the open one, or opens one
-- numbered after the last version.
create or replace function "app_private"."save_template_draft"(template_id uuid, body jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tpl "app_private"."templates"%rowtype;
  v_row "app_private"."template_versions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_tpl from "app_private"."templates" x where x."id" = save_template_draft.template_id for update;
  if not found then
    raise exception 'No such template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tpl."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_tpl."tenant_id", 'templates.manage'), false))) then
    raise exception 'You may not edit this template' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  if save_template_draft.body is null then
    raise exception 'A template version needs a body' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  update "app_private"."template_versions" x set
    "body" = save_template_draft.body,
    "hash" = encode(extensions.digest(save_template_draft.body::text, 'sha256'), 'hex')
  where x."template_id" = save_template_draft.template_id and x."published_at" is null
  returning * into v_row;
  if not found then
    insert into "app_private"."template_versions" ("template_id", "version", "body", "hash", "created_by")
    values (
      save_template_draft.template_id,
      coalesce((select max(y."version") from "app_private"."template_versions" y where y."template_id" = save_template_draft.template_id), 0) + 1,
      save_template_draft.body,
      encode(extensions.digest(save_template_draft.body::text, 'sha256'), 'hex'),
      (select auth.uid())
    )
    returning * into v_row;
  end if;
  update "app_private"."templates" x set "updated_at" = now() where x."id" = save_template_draft.template_id;
  return jsonb_build_object(
    'id', v_row."id",
    'template', v_row."template_id",
    'version', v_row."version",
    'hash', v_row."hash",
    'publishedAt', v_row."published_at",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'body', v_row."body"
  );
end;
$$;
revoke execute on function "app_private"."save_template_draft"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."save_template_draft"(uuid, jsonb) to authenticated, service_role;

-- Publishes the template's draft. Applications use the newest published
-- version; published versions never change.
create or replace function "app_private"."publish_template_version"(template_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tpl "app_private"."templates"%rowtype;
  v_row "app_private"."template_versions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_tpl from "app_private"."templates" x where x."id" = publish_template_version.template_id for update;
  if not found then
    raise exception 'No such template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tpl."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_tpl."tenant_id", 'templates.manage'), false))) then
    raise exception 'You may not publish this template' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  update "app_private"."template_versions" x set "published_at" = now()
  where x."template_id" = publish_template_version.template_id and x."published_at" is null
  returning * into v_row;
  if not found then
    raise exception 'This template has no draft to publish' using errcode = 'P0002', hint = 'TEMPLATE_NO_DRAFT';
  end if;
  update "app_private"."templates" x set "updated_at" = now() where x."id" = publish_template_version.template_id;
  null;
  return jsonb_build_object(
    'id', v_row."id",
    'template', v_row."template_id",
    'version', v_row."version",
    'hash', v_row."hash",
    'publishedAt', v_row."published_at",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'body', v_row."body"
  );
end;
$$;
revoke execute on function "app_private"."publish_template_version"(uuid) from public, anon;
grant execute on function "app_private"."publish_template_version"(uuid) to authenticated, service_role;

create or replace function "app_private"."template_versions_list"(template_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', y."id",
    'template', y."template_id",
    'version', y."version",
    'hash', y."hash",
    'publishedAt', y."published_at",
    'createdBy', y."created_by",
    'createdAt', y."created_at"
  ) order by y."version" desc), '[]'::jsonb)
  from "app_private"."template_versions" y where y."template_id" = template_versions_list.template_id
$$;
revoke execute on function "app_private"."template_versions_list"(uuid) from public, anon;
grant execute on function "app_private"."template_versions_list"(uuid) to authenticated, service_role;

-- One default per tenant, type and language.
create or replace function "app_private"."set_default_template"(template_id uuid, on_default boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."templates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."templates" x where x."id" = set_default_template.template_id for update;
  if not found then
    raise exception 'No such template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'templates.manage'), false))) then
    raise exception 'You may not change this template' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  if set_default_template.on_default then
    update "app_private"."templates" x set "is_default" = false, "updated_at" = now()
    where x."tenant_id" is not distinct from v_row."tenant_id"
      and x."type" = v_row."type" and x."language" = v_row."language"
      and x."is_default" and x."id" <> v_row."id";
  end if;
  update "app_private"."templates" x set "is_default" = coalesce(set_default_template.on_default, false), "updated_at" = now()
  where x."id" = set_default_template.template_id;
  return true;
end;
$$;
revoke execute on function "app_private"."set_default_template"(uuid, boolean) from public, anon;
grant execute on function "app_private"."set_default_template"(uuid, boolean) to authenticated, service_role;

-- Copies the newest published version of source (a system template, or one
-- in tenant) into a new template in tenant, published as its version 1, and
-- records the version it copied. templates.manage in tenant.
create or replace function "app_private"."fork_template"(source uuid, tenant uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_src "app_private"."templates"%rowtype;
  v_version "app_private"."template_versions"%rowtype;
  v_row "app_private"."templates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_src from "app_private"."templates" x where x."id" = fork_template.source;
  if not found or not (v_src."scope" = 'system' or v_src."tenant_id" = fork_template.tenant) then
    raise exception 'No such template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_FOUND';
  end if;
  if fork_template.tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (fork_template.tenant is not null and coalesce(better_supabase.can('tenant', fork_template.tenant, 'templates.manage'), false))) then
    raise exception 'You may not create templates here' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  select * into v_version from "app_private"."template_versions" y
  where y."template_id" = fork_template.source and y."published_at" is not null
  order by y."version" desc limit 1;
  if not found then
    raise exception 'This template has no published version' using errcode = 'P0002', hint = 'TEMPLATE_NOT_PUBLISHED';
  end if;
  insert into "app_private"."templates" ("tenant_id", "scope", "type", "name", "language", "settings", "forked_from", "forked_from_version", "created_by")
  values (fork_template.tenant, 'tenant', v_src."type", v_src."name", v_src."language", v_src."settings", v_src."id", v_version."version", (select auth.uid()))
  returning * into v_row;
  insert into "app_private"."template_versions" ("template_id", "version", "body", "hash", "published_at", "created_by")
  values (v_row."id", 1, v_version."body", v_version."hash", now(), (select auth.uid()));

  return jsonb_build_object(
    'id', v_row."id",
    'tenant', v_row."tenant_id",
    'scope', v_row."scope",
    'key', v_row."key",
    'type', v_row."type",
    'name', v_row."name",
    'language', v_row."language",
    'isDefault', v_row."is_default",
    'settings', v_row."settings",
    'forkedFrom', v_row."forked_from",
    'forkedFromVersion', v_row."forked_from_version",
    'publishedVersion', (select y."version" from "app_private"."template_versions" y where y."template_id" = v_row."id" and y."published_at" is not null order by y."version" desc limit 1),
    'upstreamVersion', case when v_row."forked_from" is not null then (select y."version" from "app_private"."template_versions" y where y."template_id" = v_row."forked_from" and y."published_at" is not null order by y."version" desc limit 1) end,
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'updatedAt', v_row."updated_at"
  );
end;
$$;
revoke execute on function "app_private"."fork_template"(uuid, uuid) from public, anon;
grant execute on function "app_private"."fork_template"(uuid, uuid) to authenticated, service_role;

-- Upserts the system templates by key from starters, a JSON array of
-- { key, type, name, language?, settings?, body }, and publishes a new
-- version of each whose body changed. Returns how many it published.
create or replace function "app_private"."sync_templates"(starters jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_starter jsonb;
  v_row "app_private"."templates"%rowtype;
  v_hash text;
  v_version "app_private"."template_versions"%rowtype;
  v_count integer := 0;
begin
  if jsonb_typeof(sync_templates.starters) <> 'array' then
    raise exception 'starters must be an array' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  for v_starter in select value from jsonb_array_elements(sync_templates.starters) loop
    if coalesce(v_starter ->> 'key', '') !~ '^[a-z0-9][a-z0-9_.-]{0,99}$' or not (v_starter ? 'body') then
      raise exception 'Each starter needs a key and a body' using errcode = '22023', hint = 'TEMPLATE_INVALID';
    end if;
    if v_starter ? 'brand' then
      raise exception 'this templates table has no brand column' using errcode = '22023', hint = 'TEMPLATE_BRAND_UNSUPPORTED';
    end if;
    select * into v_row from "app_private"."templates" x where x."tenant_id" is null and x."key" = v_starter ->> 'key' for update;
    if not found then
      insert into "app_private"."templates" ("tenant_id", "scope", "key", "type", "name", "language", "settings")
      values (null, 'system', v_starter ->> 'key', v_starter ->> 'type', v_starter ->> 'name',
        coalesce(v_starter ->> 'language', 'en'), coalesce(v_starter -> 'settings', '{}'::jsonb))
      returning * into v_row;
    else
      update "app_private"."templates" x set
        "type" = coalesce(v_starter ->> 'type', x."type"),
        "name" = coalesce(v_starter ->> 'name', x."name"),
        "language" = coalesce(v_starter ->> 'language', x."language"),
        "settings" = coalesce(v_starter -> 'settings', x."settings"),
        "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    end if;
    v_hash := encode(extensions.digest((v_starter -> 'body')::text, 'sha256'), 'hex');
    if v_hash is distinct from (select y."hash" from "app_private"."template_versions" y
        where y."template_id" = v_row."id" and y."published_at" is not null
        order by y."version" desc limit 1) then
      delete from "app_private"."template_versions" y where y."template_id" = v_row."id" and y."published_at" is null;
      insert into "app_private"."template_versions" ("template_id", "version", "body", "hash", "published_at")
      values (
        v_row."id",
        coalesce((select max(y."version") from "app_private"."template_versions" y where y."template_id" = v_row."id"), 0) + 1,
        v_starter -> 'body',
        v_hash,
        now()
      )
      returning * into v_version;
      v_count := v_count + 1;
      null;
    end if;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "app_private"."sync_templates"(jsonb) from public, anon, authenticated;
grant execute on function "app_private"."sync_templates"(jsonb) to service_role;

-- What applying template in tenant needs: the template, its newest
-- published version with the body, and the enabled workflow attachments,
-- each input checked against the published version's input_schema
-- (TEMPLATE_WORKFLOW_INPUT_INVALID). templates.apply in tenant.
create or replace function "app_private"."template_apply_target"(template_id uuid, tenant uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tpl "app_private"."templates"%rowtype;
  v_version "app_private"."template_versions"%rowtype;
  v_workflows jsonb := '[]'::jsonb;
begin
  if template_apply_target.tenant is null then
    raise exception 'Applying a template needs a tenant' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', template_apply_target.tenant, 'templates.apply'), false)) then
    raise exception 'You may not apply templates here' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  select * into v_tpl from "app_private"."templates" x where x."id" = template_apply_target.template_id;
  if not found or not (v_tpl."scope" = 'system' or v_tpl."tenant_id" = template_apply_target.tenant) then
    raise exception 'No such template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_FOUND';
  end if;
  select * into v_version from "app_private"."template_versions" y
  where y."template_id" = v_tpl."id" and y."published_at" is not null
  order by y."version" desc limit 1;
  if not found then
    raise exception 'This template has no published version' using errcode = 'P0002', hint = 'TEMPLATE_NOT_PUBLISHED';
  end if;

  return jsonb_build_object(
    'template', jsonb_build_object(
    'id', v_tpl."id",
    'tenant', v_tpl."tenant_id",
    'scope', v_tpl."scope",
    'key', v_tpl."key",
    'type', v_tpl."type",
    'name', v_tpl."name",
    'language', v_tpl."language",
    'isDefault', v_tpl."is_default",
    'settings', v_tpl."settings",
    'forkedFrom', v_tpl."forked_from",
    'forkedFromVersion', v_tpl."forked_from_version",
    'publishedVersion', (select y."version" from "app_private"."template_versions" y where y."template_id" = v_tpl."id" and y."published_at" is not null order by y."version" desc limit 1),
    'upstreamVersion', case when v_tpl."forked_from" is not null then (select y."version" from "app_private"."template_versions" y where y."template_id" = v_tpl."forked_from" and y."published_at" is not null order by y."version" desc limit 1) end,
    'createdBy', v_tpl."created_by",
    'createdAt', v_tpl."created_at",
    'updatedAt', v_tpl."updated_at"
  ),
    'version', jsonb_build_object(
    'id', v_version."id",
    'template', v_version."template_id",
    'version', v_version."version",
    'hash', v_version."hash",
    'publishedAt', v_version."published_at",
    'createdBy', v_version."created_by",
    'createdAt', v_version."created_at",
    'body', v_version."body"
  ),
    'workflows', v_workflows
  );
end;
$$;
revoke execute on function "app_private"."template_apply_target"(uuid, uuid) from public, anon;
grant execute on function "app_private"."template_apply_target"(uuid, uuid) to authenticated, service_role;

-- Records that version of template created subject_type/subject_id in
-- tenant. templates.apply in tenant.
create or replace function "app_private"."record_template_application"(template_id uuid, version_id uuid, tenant uuid, subject_type text, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tpl "app_private"."templates"%rowtype;
  v_row "app_private"."template_applications"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if record_template_application.tenant is null then
    raise exception 'Applying a template needs a tenant' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', record_template_application.tenant, 'templates.apply'), false)) then
    raise exception 'You may not apply templates here' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  select * into v_tpl from "app_private"."templates" x where x."id" = record_template_application.template_id;
  if not found or not (v_tpl."scope" = 'system' or v_tpl."tenant_id" = record_template_application.tenant) then
    raise exception 'No such template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_FOUND';
  end if;
  if not exists (select 1 from "app_private"."template_versions" y where y."id" = record_template_application.version_id
      and y."template_id" = v_tpl."id" and y."published_at" is not null) then
    raise exception 'Not a published version of this template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_PUBLISHED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_template_apply"(uuid, uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text, $4::text)', v_hook::oid::regproc)
        using record_template_application.tenant, v_tpl."id", record_template_application.subject_type, record_template_application.subject_id;
    end if;
  end;
  insert into "app_private"."template_applications" ("template_id", "version_id", "tenant_id", "subject_type", "subject_id", "applied_by")
  values (v_tpl."id", record_template_application.version_id, record_template_application.tenant,
    record_template_application.subject_type, record_template_application.subject_id, (select auth.uid()))
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_template_apply"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object(
    'id', v_row."id",
    'template', v_row."template_id",
    'version', v_row."version_id",
    'tenant', v_row."tenant_id",
    'subjectType', v_row."subject_type",
    'subjectId', v_row."subject_id",
    'appliedBy', v_row."applied_by",
    'appliedAt', v_row."applied_at"
  );
end;
$$;
revoke execute on function "app_private"."record_template_application"(uuid, uuid, uuid, text, text) from public, anon;
grant execute on function "app_private"."record_template_application"(uuid, uuid, uuid, text, text) to authenticated, service_role;

-- The tenant's applications, newest first, of one template or onto one
-- subject when those are given.
create or replace function "app_private"."template_applications_list"(tenant uuid, template_id uuid, subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(r.value order by r.at desc, r.id), '[]'::jsonb)
  from (
    select jsonb_build_object(
    'id', a."id",
    'template', a."template_id",
    'version', a."version_id",
    'tenant', a."tenant_id",
    'subjectType', a."subject_type",
    'subjectId', a."subject_id",
    'appliedBy', a."applied_by",
    'appliedAt', a."applied_at"
  ) as value, a."applied_at" as at, a."id" as id
    from "app_private"."template_applications" a
    where a."tenant_id" = template_applications_list.tenant
      and (template_applications_list.template_id is null or a."template_id" = template_applications_list.template_id)
      and (template_applications_list.subject_type is null or a."subject_type" = template_applications_list.subject_type)
      and (template_applications_list.subject_id is null or a."subject_id" = template_applications_list.subject_id)
    order by a."applied_at" desc, a."id"
    limit 200
  ) r
$$;
revoke execute on function "app_private"."template_applications_list"(uuid, uuid, text, text) from public, anon;
grant execute on function "app_private"."template_applications_list"(uuid, uuid, text, text) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "app_private"."templates";
drop policy if exists bsb_tenant_scope_select on "app_private"."templates";
create policy bsb_tenant_scope_select on "app_private"."templates" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('templates.read'))
    or ("scope" = 'system' and exists (select better_supabase.tenant_ids_with('templates.read'))))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."templates";
create policy bsb_tenant_scope_insert on "app_private"."templates" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."templates";
create policy bsb_tenant_scope_update on "app_private"."templates" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."templates";
create policy bsb_tenant_scope_delete on "app_private"."templates" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."template_applications";
drop policy if exists bsb_tenant_scope_select on "app_private"."template_applications";
create policy bsb_tenant_scope_select on "app_private"."template_applications" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('templates.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."template_applications";
create policy bsb_tenant_scope_insert on "app_private"."template_applications" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."template_applications";
create policy bsb_tenant_scope_update on "app_private"."template_applications" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."template_applications";
create policy bsb_tenant_scope_delete on "app_private"."template_applications" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_091_templates.sql
-- better-supabase module: templates
-- @bsb-block-data templates
-- @bsb-hash sha256:b8f109c9be802b16766dc2421c68f34cacf2322c02b9c507938fd08f01f94689
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "pgcrypto" with schema "extensions";

insert into better_supabase.blocks (name, version, mode)
values ('templates', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_091_templates.sql
-- better-supabase module: templates
-- @bsb-block templates@1 managed
-- @bsb-hash sha256:960c5b77a18e9c3db17c7105697f66f3c4e86a162ef5f2aa8745e65eda00972b
-- Typed, versioned templates (system starters and tenant forks) that create records, with merge fields and workflows started on each record they create.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."templates";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."templates";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."templates";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."templates";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."templates";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."template_applications";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."template_applications";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."template_applications";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."template_applications";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."template_applications";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create extension if not exists pgcrypto with schema extensions;

-- Templates of a type (an invoice, a project, an email): a tenant's own, or
-- a system starter (no tenant) that sync_templates keeps by key and tenants
-- fork, or with options.brand a starter of one brand. forked_from: the template and version a fork copied.
create table if not exists "better_supabase"."templates" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid,
  "scope" text not null default 'tenant' check ("scope" in ('tenant', 'system')),
  "key" text check ("key" ~ '^[a-z0-9][a-z0-9_.-]{0,99}$'),
  "type" text not null check ("type" ~ '^[a-z][a-z0-9_.-]{0,63}$'),
  "name" text not null check (length("name") between 1 and 200),
  "language" text not null default 'en' check ("language" ~ '^[a-z]{2,3}(-[A-Za-z0-9]{1,8})*$'),
  "is_default" boolean not null default false,
  "settings" jsonb not null default '{}'::jsonb
    check (jsonb_typeof("settings") = 'object' and pg_column_size("settings") <= 65536),
  "forked_from" uuid references "better_supabase"."templates" ("id") on delete set null,
  "forked_from_version" integer check ("forked_from_version" > 0),
  "created_by" uuid references auth.users (id) on delete set null,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  constraint templates_system_check check (("scope" = 'system') = ("tenant_id" is null))
);
create unique index if not exists templates_key_idx on "better_supabase"."templates" ("tenant_id", "key") nulls not distinct where "key" is not null;
create unique index if not exists templates_default_idx on "better_supabase"."templates" ("tenant_id", "type", "language") nulls not distinct where "is_default";
create index if not exists templates_type_idx on "better_supabase"."templates" ("tenant_id", "type");
create index if not exists templates_forked_from_idx on "better_supabase"."templates" ("forked_from") where "forked_from" is not null;
create index if not exists templates_created_by_idx on "better_supabase"."templates" ("created_by");
alter table "better_supabase"."templates" enable row level security;
revoke all on "better_supabase"."templates" from public, anon, authenticated;
grant select on "better_supabase"."templates" to authenticated;
grant all on "better_supabase"."templates" to service_role;
drop policy if exists templates_read on "better_supabase"."templates";
create policy templates_read on "better_supabase"."templates"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('templates.read'))
    or ("scope" = 'system' and exists (select better_supabase.tenant_ids_with('templates.read'))));

-- Numbered snapshots of a template's body: at most one draft, and published
-- versions that never change. hash: the SHA-256 of the body as text.
create table if not exists "better_supabase"."template_versions" (
  "id" uuid primary key default gen_random_uuid(),
  "template_id" uuid not null references "better_supabase"."templates" ("id") on delete cascade,
  "version" integer not null check ("version" > 0),
  "body" jsonb not null check (pg_column_size("body") <= 1048576),
  "hash" text not null,
  "published_at" timestamptz,
  "created_by" uuid references auth.users (id) on delete set null,
  "created_at" timestamptz not null default now(),
  constraint template_versions_template_version_key unique ("template_id", "version")
);
create unique index if not exists template_versions_one_draft_idx on "better_supabase"."template_versions" ("template_id") where "published_at" is null;
create index if not exists template_versions_created_by_idx on "better_supabase"."template_versions" ("created_by");
alter table "better_supabase"."template_versions" enable row level security;
revoke all on "better_supabase"."template_versions" from public, anon, authenticated;
grant select on "better_supabase"."template_versions" to authenticated;
grant all on "better_supabase"."template_versions" to service_role;
drop policy if exists template_versions_read on "better_supabase"."template_versions";
create policy template_versions_read on "better_supabase"."template_versions"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."templates" x where x."id" = "template_id"));

-- Each time a published version created a record, and which one.
create table if not exists "better_supabase"."template_applications" (
  "id" uuid primary key default gen_random_uuid(),
  "template_id" uuid not null references "better_supabase"."templates" ("id") on delete cascade,
  "version_id" uuid not null references "better_supabase"."template_versions" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "subject_type" text not null check (length("subject_type") between 1 and 100),
  "subject_id" text not null check (length("subject_id") between 1 and 200),
  "applied_by" uuid references auth.users (id) on delete set null,
  "applied_at" timestamptz not null default now()
);
create index if not exists template_applications_tenant_idx on "better_supabase"."template_applications" ("tenant_id", "applied_at" desc);
create index if not exists template_applications_template_idx on "better_supabase"."template_applications" ("template_id");
create index if not exists template_applications_version_idx on "better_supabase"."template_applications" ("version_id");
create index if not exists template_applications_subject_idx on "better_supabase"."template_applications" ("subject_type", "subject_id");
create index if not exists template_applications_applied_by_idx on "better_supabase"."template_applications" ("applied_by");
alter table "better_supabase"."template_applications" enable row level security;
revoke all on "better_supabase"."template_applications" from public, anon, authenticated;
grant select on "better_supabase"."template_applications" to authenticated;
grant all on "better_supabase"."template_applications" to service_role;
drop policy if exists template_applications_read on "better_supabase"."template_applications";
create policy template_applications_read on "better_supabase"."template_applications"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('templates.read')));

-- Creates a template (template_id null) or renames it and replaces its
-- settings. tenant null saves a system template, which only the service
-- role may; a tenant's needs templates.manage there.
-- fields: the extra columns (blocks.templates.options.extraColumns) to set.
drop function if exists "better_supabase"."save_template"(uuid, uuid, text, text, text, jsonb, jsonb);
create or replace function "better_supabase"."save_template"(template_id uuid, tenant uuid, type text, name text, language text, settings jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."templates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if save_template.settings is not null and jsonb_typeof(save_template.settings) <> 'object' then
    raise exception 'settings must be an object' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  if save_template.template_id is not null then
    select * into v_row from "better_supabase"."templates" x where x."id" = save_template.template_id for update;
    if not found or v_row."tenant_id" is distinct from save_template.tenant then
      raise exception 'No such template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_FOUND';
    end if;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_template.tenant is not null and coalesce(better_supabase.can('tenant', save_template.tenant, 'templates.manage'), false))) then
    raise exception 'You may not change templates here' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  if save_template.template_id is null and (save_template.type is null or save_template.type !~ '^[a-z][a-z0-9_.-]{0,63}$') then
    raise exception 'type must be lower-case letters, digits, dots, dashes or underscores' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  if save_template.template_id is null and save_template.name is null then
    raise exception 'A template needs a name' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_template_save"(uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::jsonb)', v_hook::oid::regproc)
        using save_template.tenant, coalesce(save_template.type, v_row."type"), save_template.settings;
    end if;
  end;
  if save_template.template_id is null then
    insert into "better_supabase"."templates" ("tenant_id", "scope", "type", "name", "language", "settings", "created_by")
    values (
      save_template.tenant,
      case when save_template.tenant is null then 'system' else 'tenant' end,
      save_template.type,
      save_template.name,
      coalesce(save_template.language, 'en'),
      coalesce(save_template.settings, '{}'::jsonb),
      (select auth.uid())
    )
    returning * into v_row;
  else
    update "better_supabase"."templates" x set
      "name" = coalesce(save_template.name, x."name"),
      "language" = coalesce(save_template.language, x."language"),
      "settings" = coalesce(save_template.settings, x."settings"),
      "is_default" = x."is_default" and coalesce(save_template.language, x."language") = x."language",
      "updated_at" = now()
    where x."id" = save_template.template_id
    returning * into v_row;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_template_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object(
    'id', v_row."id",
    'tenant', v_row."tenant_id",
    'scope', v_row."scope",
    'key', v_row."key",
    'type', v_row."type",
    'name', v_row."name",
    'language', v_row."language",
    'isDefault', v_row."is_default",
    'settings', v_row."settings",
    'forkedFrom', v_row."forked_from",
    'forkedFromVersion', v_row."forked_from_version",
    'publishedVersion', (select y."version" from "better_supabase"."template_versions" y where y."template_id" = v_row."id" and y."published_at" is not null order by y."version" desc limit 1),
    'upstreamVersion', case when v_row."forked_from" is not null then (select y."version" from "better_supabase"."template_versions" y where y."template_id" = v_row."forked_from" and y."published_at" is not null order by y."version" desc limit 1) end,
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'updatedAt', v_row."updated_at"
  );
end;
$$;
revoke execute on function "better_supabase"."save_template"(uuid, uuid, text, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."save_template"(uuid, uuid, text, text, text, jsonb) to authenticated, service_role;

-- The tenant's templates and the system ones (only the system ones without
-- a tenant), filtered by type and language, defaults first.
create or replace function "better_supabase"."templates_list"(tenant uuid, type text, language text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x."id",
    'tenant', x."tenant_id",
    'scope', x."scope",
    'key', x."key",
    'type', x."type",
    'name', x."name",
    'language', x."language",
    'isDefault', x."is_default",
    'settings', x."settings",
    'forkedFrom', x."forked_from",
    'forkedFromVersion', x."forked_from_version",
    'publishedVersion', (select y."version" from "better_supabase"."template_versions" y where y."template_id" = x."id" and y."published_at" is not null order by y."version" desc limit 1),
    'upstreamVersion', case when x."forked_from" is not null then (select y."version" from "better_supabase"."template_versions" y where y."template_id" = x."forked_from" and y."published_at" is not null order by y."version" desc limit 1) end,
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at"
  )
    order by x."is_default" desc, x."scope" desc, x."name", x."id"), '[]'::jsonb)
  from "better_supabase"."templates" x
  where (x."scope" = 'system' or x."tenant_id" = templates_list.tenant)
    and (templates_list.type is null or x."type" = templates_list.type)
    and (templates_list.language is null or x."language" = templates_list.language)
$$;
revoke execute on function "better_supabase"."templates_list"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."templates_list"(uuid, text, text) to authenticated, service_role;

-- One template with its newest published version and its draft, bodies
-- included; null when the caller can't read it.
create or replace function "better_supabase"."template_get"(template_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'id', x."id",
    'tenant', x."tenant_id",
    'scope', x."scope",
    'key', x."key",
    'type', x."type",
    'name', x."name",
    'language', x."language",
    'isDefault', x."is_default",
    'settings', x."settings",
    'forkedFrom', x."forked_from",
    'forkedFromVersion', x."forked_from_version",
    'publishedVersion', (select y."version" from "better_supabase"."template_versions" y where y."template_id" = x."id" and y."published_at" is not null order by y."version" desc limit 1),
    'upstreamVersion', case when x."forked_from" is not null then (select y."version" from "better_supabase"."template_versions" y where y."template_id" = x."forked_from" and y."published_at" is not null order by y."version" desc limit 1) end,
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at"
  ) || jsonb_build_object(
    'published', (select jsonb_build_object(
    'id', y."id",
    'template', y."template_id",
    'version', y."version",
    'hash', y."hash",
    'publishedAt', y."published_at",
    'createdBy', y."created_by",
    'createdAt', y."created_at",
    'body', y."body"
  ) from "better_supabase"."template_versions" y
      where y."template_id" = x."id" and y."published_at" is not null
      order by y."version" desc limit 1),
    'draft', (select jsonb_build_object(
    'id', y."id",
    'template', y."template_id",
    'version', y."version",
    'hash', y."hash",
    'publishedAt', y."published_at",
    'createdBy', y."created_by",
    'createdAt', y."created_at",
    'body', y."body"
  ) from "better_supabase"."template_versions" y
      where y."template_id" = x."id" and y."published_at" is null))
  from "better_supabase"."templates" x
  where x."id" = template_get.template_id
$$;
revoke execute on function "better_supabase"."template_get"(uuid) from public, anon;
grant execute on function "better_supabase"."template_get"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."remove_template"(template_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."templates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."templates" x where x."id" = remove_template.template_id;
  if not found then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'templates.manage'), false))) then
    raise exception 'You may not remove this template' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  delete from "better_supabase"."templates" x where x."id" = remove_template.template_id;
  return true;
end;
$$;
revoke execute on function "better_supabase"."remove_template"(uuid) from public, anon;
grant execute on function "better_supabase"."remove_template"(uuid) to authenticated, service_role;

-- Saves body as the template's draft: updates the open one, or opens one
-- numbered after the last version.
create or replace function "better_supabase"."save_template_draft"(template_id uuid, body jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tpl "better_supabase"."templates"%rowtype;
  v_row "better_supabase"."template_versions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_tpl from "better_supabase"."templates" x where x."id" = save_template_draft.template_id for update;
  if not found then
    raise exception 'No such template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tpl."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_tpl."tenant_id", 'templates.manage'), false))) then
    raise exception 'You may not edit this template' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  if save_template_draft.body is null then
    raise exception 'A template version needs a body' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  update "better_supabase"."template_versions" x set
    "body" = save_template_draft.body,
    "hash" = encode(extensions.digest(save_template_draft.body::text, 'sha256'), 'hex')
  where x."template_id" = save_template_draft.template_id and x."published_at" is null
  returning * into v_row;
  if not found then
    insert into "better_supabase"."template_versions" ("template_id", "version", "body", "hash", "created_by")
    values (
      save_template_draft.template_id,
      coalesce((select max(y."version") from "better_supabase"."template_versions" y where y."template_id" = save_template_draft.template_id), 0) + 1,
      save_template_draft.body,
      encode(extensions.digest(save_template_draft.body::text, 'sha256'), 'hex'),
      (select auth.uid())
    )
    returning * into v_row;
  end if;
  update "better_supabase"."templates" x set "updated_at" = now() where x."id" = save_template_draft.template_id;
  return jsonb_build_object(
    'id', v_row."id",
    'template', v_row."template_id",
    'version', v_row."version",
    'hash', v_row."hash",
    'publishedAt', v_row."published_at",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'body', v_row."body"
  );
end;
$$;
revoke execute on function "better_supabase"."save_template_draft"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_template_draft"(uuid, jsonb) to authenticated, service_role;

-- Publishes the template's draft. Applications use the newest published
-- version; published versions never change.
create or replace function "better_supabase"."publish_template_version"(template_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tpl "better_supabase"."templates"%rowtype;
  v_row "better_supabase"."template_versions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_tpl from "better_supabase"."templates" x where x."id" = publish_template_version.template_id for update;
  if not found then
    raise exception 'No such template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tpl."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_tpl."tenant_id", 'templates.manage'), false))) then
    raise exception 'You may not publish this template' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  update "better_supabase"."template_versions" x set "published_at" = now()
  where x."template_id" = publish_template_version.template_id and x."published_at" is null
  returning * into v_row;
  if not found then
    raise exception 'This template has no draft to publish' using errcode = 'P0002', hint = 'TEMPLATE_NO_DRAFT';
  end if;
  update "better_supabase"."templates" x set "updated_at" = now() where x."id" = publish_template_version.template_id;
  null;
  return jsonb_build_object(
    'id', v_row."id",
    'template', v_row."template_id",
    'version', v_row."version",
    'hash', v_row."hash",
    'publishedAt', v_row."published_at",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'body', v_row."body"
  );
end;
$$;
revoke execute on function "better_supabase"."publish_template_version"(uuid) from public, anon;
grant execute on function "better_supabase"."publish_template_version"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."template_versions_list"(template_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', y."id",
    'template', y."template_id",
    'version', y."version",
    'hash', y."hash",
    'publishedAt', y."published_at",
    'createdBy', y."created_by",
    'createdAt', y."created_at"
  ) order by y."version" desc), '[]'::jsonb)
  from "better_supabase"."template_versions" y where y."template_id" = template_versions_list.template_id
$$;
revoke execute on function "better_supabase"."template_versions_list"(uuid) from public, anon;
grant execute on function "better_supabase"."template_versions_list"(uuid) to authenticated, service_role;

-- One default per tenant, type and language.
create or replace function "better_supabase"."set_default_template"(template_id uuid, on_default boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."templates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."templates" x where x."id" = set_default_template.template_id for update;
  if not found then
    raise exception 'No such template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'templates.manage'), false))) then
    raise exception 'You may not change this template' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  if set_default_template.on_default then
    update "better_supabase"."templates" x set "is_default" = false, "updated_at" = now()
    where x."tenant_id" is not distinct from v_row."tenant_id"
      and x."type" = v_row."type" and x."language" = v_row."language"
      and x."is_default" and x."id" <> v_row."id";
  end if;
  update "better_supabase"."templates" x set "is_default" = coalesce(set_default_template.on_default, false), "updated_at" = now()
  where x."id" = set_default_template.template_id;
  return true;
end;
$$;
revoke execute on function "better_supabase"."set_default_template"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."set_default_template"(uuid, boolean) to authenticated, service_role;

-- Copies the newest published version of source (a system template, or one
-- in tenant) into a new template in tenant, published as its version 1, and
-- records the version it copied. templates.manage in tenant.
create or replace function "better_supabase"."fork_template"(source uuid, tenant uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_src "better_supabase"."templates"%rowtype;
  v_version "better_supabase"."template_versions"%rowtype;
  v_row "better_supabase"."templates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_src from "better_supabase"."templates" x where x."id" = fork_template.source;
  if not found or not (v_src."scope" = 'system' or v_src."tenant_id" = fork_template.tenant) then
    raise exception 'No such template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_FOUND';
  end if;
  if fork_template.tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (fork_template.tenant is not null and coalesce(better_supabase.can('tenant', fork_template.tenant, 'templates.manage'), false))) then
    raise exception 'You may not create templates here' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  select * into v_version from "better_supabase"."template_versions" y
  where y."template_id" = fork_template.source and y."published_at" is not null
  order by y."version" desc limit 1;
  if not found then
    raise exception 'This template has no published version' using errcode = 'P0002', hint = 'TEMPLATE_NOT_PUBLISHED';
  end if;
  insert into "better_supabase"."templates" ("tenant_id", "scope", "type", "name", "language", "settings", "forked_from", "forked_from_version", "created_by")
  values (fork_template.tenant, 'tenant', v_src."type", v_src."name", v_src."language", v_src."settings", v_src."id", v_version."version", (select auth.uid()))
  returning * into v_row;
  insert into "better_supabase"."template_versions" ("template_id", "version", "body", "hash", "published_at", "created_by")
  values (v_row."id", 1, v_version."body", v_version."hash", now(), (select auth.uid()));

  return jsonb_build_object(
    'id', v_row."id",
    'tenant', v_row."tenant_id",
    'scope', v_row."scope",
    'key', v_row."key",
    'type', v_row."type",
    'name', v_row."name",
    'language', v_row."language",
    'isDefault', v_row."is_default",
    'settings', v_row."settings",
    'forkedFrom', v_row."forked_from",
    'forkedFromVersion', v_row."forked_from_version",
    'publishedVersion', (select y."version" from "better_supabase"."template_versions" y where y."template_id" = v_row."id" and y."published_at" is not null order by y."version" desc limit 1),
    'upstreamVersion', case when v_row."forked_from" is not null then (select y."version" from "better_supabase"."template_versions" y where y."template_id" = v_row."forked_from" and y."published_at" is not null order by y."version" desc limit 1) end,
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'updatedAt', v_row."updated_at"
  );
end;
$$;
revoke execute on function "better_supabase"."fork_template"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."fork_template"(uuid, uuid) to authenticated, service_role;

-- Upserts the system templates by key from starters, a JSON array of
-- { key, type, name, language?, settings?, body }, and publishes a new
-- version of each whose body changed. Returns how many it published.
create or replace function "better_supabase"."sync_templates"(starters jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_starter jsonb;
  v_row "better_supabase"."templates"%rowtype;
  v_hash text;
  v_version "better_supabase"."template_versions"%rowtype;
  v_count integer := 0;
begin
  if jsonb_typeof(sync_templates.starters) <> 'array' then
    raise exception 'starters must be an array' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  for v_starter in select value from jsonb_array_elements(sync_templates.starters) loop
    if coalesce(v_starter ->> 'key', '') !~ '^[a-z0-9][a-z0-9_.-]{0,99}$' or not (v_starter ? 'body') then
      raise exception 'Each starter needs a key and a body' using errcode = '22023', hint = 'TEMPLATE_INVALID';
    end if;
    if v_starter ? 'brand' then
      raise exception 'this templates table has no brand column' using errcode = '22023', hint = 'TEMPLATE_BRAND_UNSUPPORTED';
    end if;
    select * into v_row from "better_supabase"."templates" x where x."tenant_id" is null and x."key" = v_starter ->> 'key' for update;
    if not found then
      insert into "better_supabase"."templates" ("tenant_id", "scope", "key", "type", "name", "language", "settings")
      values (null, 'system', v_starter ->> 'key', v_starter ->> 'type', v_starter ->> 'name',
        coalesce(v_starter ->> 'language', 'en'), coalesce(v_starter -> 'settings', '{}'::jsonb))
      returning * into v_row;
    else
      update "better_supabase"."templates" x set
        "type" = coalesce(v_starter ->> 'type', x."type"),
        "name" = coalesce(v_starter ->> 'name', x."name"),
        "language" = coalesce(v_starter ->> 'language', x."language"),
        "settings" = coalesce(v_starter -> 'settings', x."settings"),
        "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    end if;
    v_hash := encode(extensions.digest((v_starter -> 'body')::text, 'sha256'), 'hex');
    if v_hash is distinct from (select y."hash" from "better_supabase"."template_versions" y
        where y."template_id" = v_row."id" and y."published_at" is not null
        order by y."version" desc limit 1) then
      delete from "better_supabase"."template_versions" y where y."template_id" = v_row."id" and y."published_at" is null;
      insert into "better_supabase"."template_versions" ("template_id", "version", "body", "hash", "published_at")
      values (
        v_row."id",
        coalesce((select max(y."version") from "better_supabase"."template_versions" y where y."template_id" = v_row."id"), 0) + 1,
        v_starter -> 'body',
        v_hash,
        now()
      )
      returning * into v_version;
      v_count := v_count + 1;
      null;
    end if;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."sync_templates"(jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."sync_templates"(jsonb) to service_role;

-- What applying template in tenant needs: the template, its newest
-- published version with the body, and the enabled workflow attachments,
-- each input checked against the published version's input_schema
-- (TEMPLATE_WORKFLOW_INPUT_INVALID). templates.apply in tenant.
create or replace function "better_supabase"."template_apply_target"(template_id uuid, tenant uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tpl "better_supabase"."templates"%rowtype;
  v_version "better_supabase"."template_versions"%rowtype;
  v_workflows jsonb := '[]'::jsonb;
begin
  if template_apply_target.tenant is null then
    raise exception 'Applying a template needs a tenant' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', template_apply_target.tenant, 'templates.apply'), false)) then
    raise exception 'You may not apply templates here' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  select * into v_tpl from "better_supabase"."templates" x where x."id" = template_apply_target.template_id;
  if not found or not (v_tpl."scope" = 'system' or v_tpl."tenant_id" = template_apply_target.tenant) then
    raise exception 'No such template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_FOUND';
  end if;
  select * into v_version from "better_supabase"."template_versions" y
  where y."template_id" = v_tpl."id" and y."published_at" is not null
  order by y."version" desc limit 1;
  if not found then
    raise exception 'This template has no published version' using errcode = 'P0002', hint = 'TEMPLATE_NOT_PUBLISHED';
  end if;

  return jsonb_build_object(
    'template', jsonb_build_object(
    'id', v_tpl."id",
    'tenant', v_tpl."tenant_id",
    'scope', v_tpl."scope",
    'key', v_tpl."key",
    'type', v_tpl."type",
    'name', v_tpl."name",
    'language', v_tpl."language",
    'isDefault', v_tpl."is_default",
    'settings', v_tpl."settings",
    'forkedFrom', v_tpl."forked_from",
    'forkedFromVersion', v_tpl."forked_from_version",
    'publishedVersion', (select y."version" from "better_supabase"."template_versions" y where y."template_id" = v_tpl."id" and y."published_at" is not null order by y."version" desc limit 1),
    'upstreamVersion', case when v_tpl."forked_from" is not null then (select y."version" from "better_supabase"."template_versions" y where y."template_id" = v_tpl."forked_from" and y."published_at" is not null order by y."version" desc limit 1) end,
    'createdBy', v_tpl."created_by",
    'createdAt', v_tpl."created_at",
    'updatedAt', v_tpl."updated_at"
  ),
    'version', jsonb_build_object(
    'id', v_version."id",
    'template', v_version."template_id",
    'version', v_version."version",
    'hash', v_version."hash",
    'publishedAt', v_version."published_at",
    'createdBy', v_version."created_by",
    'createdAt', v_version."created_at",
    'body', v_version."body"
  ),
    'workflows', v_workflows
  );
end;
$$;
revoke execute on function "better_supabase"."template_apply_target"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."template_apply_target"(uuid, uuid) to authenticated, service_role;

-- Records that version of template created subject_type/subject_id in
-- tenant. templates.apply in tenant.
create or replace function "better_supabase"."record_template_application"(template_id uuid, version_id uuid, tenant uuid, subject_type text, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tpl "better_supabase"."templates"%rowtype;
  v_row "better_supabase"."template_applications"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if record_template_application.tenant is null then
    raise exception 'Applying a template needs a tenant' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', record_template_application.tenant, 'templates.apply'), false)) then
    raise exception 'You may not apply templates here' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  select * into v_tpl from "better_supabase"."templates" x where x."id" = record_template_application.template_id;
  if not found or not (v_tpl."scope" = 'system' or v_tpl."tenant_id" = record_template_application.tenant) then
    raise exception 'No such template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_FOUND';
  end if;
  if not exists (select 1 from "better_supabase"."template_versions" y where y."id" = record_template_application.version_id
      and y."template_id" = v_tpl."id" and y."published_at" is not null) then
    raise exception 'Not a published version of this template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_PUBLISHED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_template_apply"(uuid, uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text, $4::text)', v_hook::oid::regproc)
        using record_template_application.tenant, v_tpl."id", record_template_application.subject_type, record_template_application.subject_id;
    end if;
  end;
  insert into "better_supabase"."template_applications" ("template_id", "version_id", "tenant_id", "subject_type", "subject_id", "applied_by")
  values (v_tpl."id", record_template_application.version_id, record_template_application.tenant,
    record_template_application.subject_type, record_template_application.subject_id, (select auth.uid()))
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_template_apply"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object(
    'id', v_row."id",
    'template', v_row."template_id",
    'version', v_row."version_id",
    'tenant', v_row."tenant_id",
    'subjectType', v_row."subject_type",
    'subjectId', v_row."subject_id",
    'appliedBy', v_row."applied_by",
    'appliedAt', v_row."applied_at"
  );
end;
$$;
revoke execute on function "better_supabase"."record_template_application"(uuid, uuid, uuid, text, text) from public, anon;
grant execute on function "better_supabase"."record_template_application"(uuid, uuid, uuid, text, text) to authenticated, service_role;

-- The tenant's applications, newest first, of one template or onto one
-- subject when those are given.
create or replace function "better_supabase"."template_applications_list"(tenant uuid, template_id uuid, subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(r.value order by r.at desc, r.id), '[]'::jsonb)
  from (
    select jsonb_build_object(
    'id', a."id",
    'template', a."template_id",
    'version', a."version_id",
    'tenant', a."tenant_id",
    'subjectType', a."subject_type",
    'subjectId', a."subject_id",
    'appliedBy', a."applied_by",
    'appliedAt', a."applied_at"
  ) as value, a."applied_at" as at, a."id" as id
    from "better_supabase"."template_applications" a
    where a."tenant_id" = template_applications_list.tenant
      and (template_applications_list.template_id is null or a."template_id" = template_applications_list.template_id)
      and (template_applications_list.subject_type is null or a."subject_type" = template_applications_list.subject_type)
      and (template_applications_list.subject_id is null or a."subject_id" = template_applications_list.subject_id)
    order by a."applied_at" desc, a."id"
    limit 200
  ) r
$$;
revoke execute on function "better_supabase"."template_applications_list"(uuid, uuid, text, text) from public, anon;
grant execute on function "better_supabase"."template_applications_list"(uuid, uuid, text, text) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."templates";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."templates";
create policy bsb_tenant_scope_select on "better_supabase"."templates" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('templates.read'))
    or ("scope" = 'system' and exists (select better_supabase.tenant_ids_with('templates.read'))))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."templates";
create policy bsb_tenant_scope_insert on "better_supabase"."templates" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."templates";
create policy bsb_tenant_scope_update on "better_supabase"."templates" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."templates";
create policy bsb_tenant_scope_delete on "better_supabase"."templates" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."template_applications";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."template_applications";
create policy bsb_tenant_scope_select on "better_supabase"."template_applications" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('templates.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."template_applications";
create policy bsb_tenant_scope_insert on "better_supabase"."template_applications" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."template_applications";
create policy bsb_tenant_scope_update on "better_supabase"."template_applications" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."template_applications";
create policy bsb_tenant_scope_delete on "better_supabase"."template_applications" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.templates.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

drop function if exists "api"."save_template"(uuid, uuid, text, text, text, jsonb, jsonb);

create or replace function "api"."actor_may_write"()
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."actor_may_write"() $$;
revoke execute on function "api"."actor_may_write"() from public;
grant execute on function "api"."actor_may_write"() to anon, authenticated, service_role;

create or replace function "api"."raise_actor_readonly"()
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."raise_actor_readonly"() $$;
revoke execute on function "api"."raise_actor_readonly"() from public;
grant execute on function "api"."raise_actor_readonly"() to anon, authenticated, service_role;

create or replace function "api"."save_template"(template_id uuid, tenant uuid, type text, name text, language text, settings jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_template"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."save_template"(uuid, uuid, text, text, text, jsonb) from public, anon;
grant execute on function "api"."save_template"(uuid, uuid, text, text, text, jsonb) to authenticated, service_role;

create or replace function "api"."templates_list"(tenant uuid, type text, language text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."templates_list"($1, $2, $3) $$;
revoke execute on function "api"."templates_list"(uuid, text, text) from public, anon;
grant execute on function "api"."templates_list"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."template_get"(template_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."template_get"($1) $$;
revoke execute on function "api"."template_get"(uuid) from public, anon;
grant execute on function "api"."template_get"(uuid) to authenticated, service_role;

create or replace function "api"."remove_template"(template_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."remove_template"($1) $$;
revoke execute on function "api"."remove_template"(uuid) from public, anon;
grant execute on function "api"."remove_template"(uuid) to authenticated, service_role;

create or replace function "api"."save_template_draft"(template_id uuid, body jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_template_draft"($1, $2) $$;
revoke execute on function "api"."save_template_draft"(uuid, jsonb) from public, anon;
grant execute on function "api"."save_template_draft"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."publish_template_version"(template_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."publish_template_version"($1) $$;
revoke execute on function "api"."publish_template_version"(uuid) from public, anon;
grant execute on function "api"."publish_template_version"(uuid) to authenticated, service_role;

create or replace function "api"."template_versions_list"(template_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."template_versions_list"($1) $$;
revoke execute on function "api"."template_versions_list"(uuid) from public, anon;
grant execute on function "api"."template_versions_list"(uuid) to authenticated, service_role;

create or replace function "api"."set_default_template"(template_id uuid, on_default boolean)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_default_template"($1, $2) $$;
revoke execute on function "api"."set_default_template"(uuid, boolean) from public, anon;
grant execute on function "api"."set_default_template"(uuid, boolean) to authenticated, service_role;

create or replace function "api"."fork_template"(source uuid, tenant uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."fork_template"($1, $2) $$;
revoke execute on function "api"."fork_template"(uuid, uuid) from public, anon;
grant execute on function "api"."fork_template"(uuid, uuid) to authenticated, service_role;

create or replace function "api"."sync_templates"(starters jsonb)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."sync_templates"($1) $$;
revoke execute on function "api"."sync_templates"(jsonb) from public, anon, authenticated;
grant execute on function "api"."sync_templates"(jsonb) to service_role;

create or replace function "api"."template_apply_target"(template_id uuid, tenant uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."template_apply_target"($1, $2) $$;
revoke execute on function "api"."template_apply_target"(uuid, uuid) from public, anon;
grant execute on function "api"."template_apply_target"(uuid, uuid) to authenticated, service_role;

create or replace function "api"."record_template_application"(template_id uuid, version_id uuid, tenant uuid, subject_type text, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_template_application"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."record_template_application"(uuid, uuid, uuid, text, text) from public, anon;
grant execute on function "api"."record_template_application"(uuid, uuid, uuid, text, text) to authenticated, service_role;

create or replace function "api"."template_applications_list"(tenant uuid, template_id uuid, subject_type text, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."template_applications_list"($1, $2, $3, $4) $$;
revoke execute on function "api"."template_applications_list"(uuid, uuid, text, text) from public, anon;
grant execute on function "api"."template_applications_list"(uuid, uuid, text, text) to authenticated, service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_091_templates.sql
-- better-supabase module: templates
-- @bsb-block-data templates
-- @bsb-hash sha256:b8f109c9be802b16766dc2421c68f34cacf2322c02b9c507938fd08f01f94689
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "pgcrypto" with schema "extensions";

insert into better_supabase.blocks (name, version, mode)
values ('templates', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_091_templates.sql
-- better-supabase module: templates
-- @bsb-block templates@1 managed
-- @bsb-hash sha256:59df2860f01f1b42e740c691a7e84e758c0d7448648f6948a5a205286635e3bd
-- Typed, versioned templates (system starters and tenant forks) that create records, with merge fields and workflows started on each record they create.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.as_column_type(value text, target anyelement)
returns anyelement
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return value;
end;
$$;
revoke execute on function better_supabase.as_column_type(text, anyelement) from public;
grant execute on function better_supabase.as_column_type(text, anyelement) to anon, authenticated, service_role;

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."templates";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."templates";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."templates";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."templates";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."templates";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."template_applications";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."template_applications";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."template_applications";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."template_applications";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."template_applications";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create extension if not exists pgcrypto with schema extensions;

-- Templates of a type (an invoice, a project, an email): a tenant's own, or
-- a system starter (no tenant) that sync_templates keeps by key and tenants
-- fork, or with options.brand a starter of one brand. forked_from: the template and version a fork copied.
-- better_supabase.templates is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."templates" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."templates" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."templates" add column if not exists "scope" text not null default 'tenant' check ("scope" in ('tenant', 'system'));
alter table "better_supabase"."templates" add column if not exists "key" text check ("key" ~ '^[a-z0-9][a-z0-9_.-]{0,99}$');
alter table "better_supabase"."templates" add column if not exists "type" text check ("type" ~ '^[a-z][a-z0-9_.-]{0,63}$');
alter table "better_supabase"."templates" add column if not exists "name" text check (length("name") between 1 and 200);
alter table "better_supabase"."templates" add column if not exists "language" text not null default 'en' check ("language" ~ '^[a-z]{2,3}(-[A-Za-z0-9]{1,8})*$');
alter table "better_supabase"."templates" add column if not exists "is_default" boolean not null default false;
alter table "better_supabase"."templates" add column if not exists "settings" jsonb not null default '{}'::jsonb check (jsonb_typeof("settings") = 'object' and pg_column_size("settings") <= 65536);
alter table "better_supabase"."templates" add column if not exists "forked_from" uuid references "better_supabase"."templates" ("id") on delete set null;
alter table "better_supabase"."templates" add column if not exists "forked_from_version" integer check ("forked_from_version" > 0);
alter table "better_supabase"."templates" add column if not exists "created_by" uuid references auth.users (id) on delete set null;
alter table "better_supabase"."templates" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."templates" add column if not exists "updated_at" timestamptz not null default now();
create unique index if not exists templates_key_idx on "better_supabase"."templates" ("tenant_id", "key") nulls not distinct where "key" is not null;
create unique index if not exists templates_default_idx on "better_supabase"."templates" ("tenant_id", "type", "language") nulls not distinct where "is_default";
create index if not exists templates_type_idx on "better_supabase"."templates" ("tenant_id", "type");
create index if not exists templates_forked_from_idx on "better_supabase"."templates" ("forked_from") where "forked_from" is not null;
create index if not exists templates_created_by_idx on "better_supabase"."templates" ("created_by");
alter table "better_supabase"."templates" enable row level security;
grant select on "better_supabase"."templates" to authenticated;
grant all on "better_supabase"."templates" to service_role;
drop policy if exists bsb_templates_select on "better_supabase"."templates";
create policy bsb_templates_select on "better_supabase"."templates"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('templates.read'))
    or ("scope" = 'system' and exists (select better_supabase.tenant_ids_with('templates.read'))));

-- Numbered snapshots of a template's body: at most one draft, and published
-- versions that never change. hash: the SHA-256 of the body as text.
-- better_supabase.template_versions is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."template_versions" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."template_versions" add column if not exists "template_id" uuid references "better_supabase"."templates" ("id") on delete cascade;
alter table "better_supabase"."template_versions" add column if not exists "version" integer check ("version" > 0);
alter table "better_supabase"."template_versions" add column if not exists "body" jsonb check (pg_column_size("body") <= 1048576);
alter table "better_supabase"."template_versions" add column if not exists "hash" text;
alter table "better_supabase"."template_versions" add column if not exists "published_at" timestamptz;
alter table "better_supabase"."template_versions" add column if not exists "created_by" uuid references auth.users (id) on delete set null;
alter table "better_supabase"."template_versions" add column if not exists "created_at" timestamptz not null default now();
create unique index if not exists template_versions_one_draft_idx on "better_supabase"."template_versions" ("template_id") where "published_at" is null;
create unique index if not exists "template_versions_template_id_version_key" on "better_supabase"."template_versions" ("template_id", "version");
create index if not exists template_versions_created_by_idx on "better_supabase"."template_versions" ("created_by");
alter table "better_supabase"."template_versions" enable row level security;
grant select on "better_supabase"."template_versions" to authenticated;
grant all on "better_supabase"."template_versions" to service_role;
drop policy if exists bsb_template_versions_select on "better_supabase"."template_versions";
create policy bsb_template_versions_select on "better_supabase"."template_versions"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."templates" x where x."id" = "template_id"));

-- Each time a published version created a record, and which one.
-- better_supabase.template_applications is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."template_applications" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."template_applications" add column if not exists "template_id" uuid references "better_supabase"."templates" ("id") on delete cascade;
alter table "better_supabase"."template_applications" add column if not exists "version_id" uuid references "better_supabase"."template_versions" ("id") on delete cascade;
alter table "better_supabase"."template_applications" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."template_applications" add column if not exists "subject_type" text check (length("subject_type") between 1 and 100);
alter table "better_supabase"."template_applications" add column if not exists "subject_id" text check (length("subject_id") between 1 and 200);
alter table "better_supabase"."template_applications" add column if not exists "applied_by" uuid references auth.users (id) on delete set null;
alter table "better_supabase"."template_applications" add column if not exists "applied_at" timestamptz not null default now();
create index if not exists template_applications_tenant_idx on "better_supabase"."template_applications" ("tenant_id", "applied_at" desc);
create index if not exists template_applications_template_idx on "better_supabase"."template_applications" ("template_id");
create index if not exists template_applications_version_idx on "better_supabase"."template_applications" ("version_id");
create index if not exists template_applications_subject_idx on "better_supabase"."template_applications" ("subject_type", "subject_id");
create index if not exists template_applications_applied_by_idx on "better_supabase"."template_applications" ("applied_by");
alter table "better_supabase"."template_applications" enable row level security;
grant select on "better_supabase"."template_applications" to authenticated;
grant all on "better_supabase"."template_applications" to service_role;
drop policy if exists bsb_template_applications_select on "better_supabase"."template_applications";
create policy bsb_template_applications_select on "better_supabase"."template_applications"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('templates.read')));

-- Creates a template (template_id null) or renames it and replaces its
-- settings. tenant null saves a system template, which only the service
-- role may; a tenant's needs templates.manage there.
-- fields: the extra columns (blocks.templates.options.extraColumns) to set.
drop function if exists "better_supabase"."save_template"(uuid, uuid, text, text, text, jsonb, jsonb);
create or replace function "better_supabase"."save_template"(template_id uuid, tenant uuid, type text, name text, language text, settings jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."templates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if save_template.settings is not null and jsonb_typeof(save_template.settings) <> 'object' then
    raise exception 'settings must be an object' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  if save_template.template_id is not null then
    select * into v_row from "better_supabase"."templates" x where x."id" = save_template.template_id for update;
    if not found or v_row."tenant_id" is distinct from save_template.tenant then
      raise exception 'No such template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_FOUND';
    end if;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_template.tenant is not null and coalesce(better_supabase.can('tenant', save_template.tenant, 'templates.manage'), false))) then
    raise exception 'You may not change templates here' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  if save_template.template_id is null and (save_template.type is null or save_template.type !~ '^[a-z][a-z0-9_.-]{0,63}$') then
    raise exception 'type must be lower-case letters, digits, dots, dashes or underscores' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  if save_template.template_id is null and save_template.name is null then
    raise exception 'A template needs a name' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_template_save"(uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::jsonb)', v_hook::oid::regproc)
        using save_template.tenant, coalesce(save_template.type, v_row."type"), save_template.settings;
    end if;
  end;
  if save_template.template_id is null then
    insert into "better_supabase"."templates" ("tenant_id", "scope", "type", "name", "language", "settings", "created_by")
    values (
      save_template.tenant,
      better_supabase.as_column_type(case when save_template.tenant is null then 'system' else 'tenant' end, (null::"better_supabase"."templates")."scope"),
      save_template.type,
      save_template.name,
      coalesce(save_template.language, 'en'),
      coalesce(save_template.settings, '{}'::jsonb),
      (select auth.uid())
    )
    returning * into v_row;
  else
    update "better_supabase"."templates" x set
      "name" = coalesce(save_template.name, x."name"),
      "language" = coalesce(save_template.language, x."language"),
      "settings" = coalesce(save_template.settings, x."settings"),
      "is_default" = x."is_default" and coalesce(save_template.language, x."language") = x."language",
      "updated_at" = now()
    where x."id" = save_template.template_id
    returning * into v_row;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_template_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object(
    'id', v_row."id",
    'tenant', v_row."tenant_id",
    'scope', v_row."scope",
    'key', v_row."key",
    'type', v_row."type",
    'name', v_row."name",
    'language', v_row."language",
    'isDefault', v_row."is_default",
    'settings', v_row."settings",
    'forkedFrom', v_row."forked_from",
    'forkedFromVersion', v_row."forked_from_version",
    'publishedVersion', (select y."version" from "better_supabase"."template_versions" y where y."template_id" = v_row."id" and y."published_at" is not null order by y."version" desc limit 1),
    'upstreamVersion', case when v_row."forked_from" is not null then (select y."version" from "better_supabase"."template_versions" y where y."template_id" = v_row."forked_from" and y."published_at" is not null order by y."version" desc limit 1) end,
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'updatedAt', v_row."updated_at"
  );
end;
$$;
revoke execute on function "better_supabase"."save_template"(uuid, uuid, text, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."save_template"(uuid, uuid, text, text, text, jsonb) to authenticated, service_role;

-- The tenant's templates and the system ones (only the system ones without
-- a tenant), filtered by type and language, defaults first.
create or replace function "better_supabase"."templates_list"(tenant uuid, type text, language text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x."id",
    'tenant', x."tenant_id",
    'scope', x."scope",
    'key', x."key",
    'type', x."type",
    'name', x."name",
    'language', x."language",
    'isDefault', x."is_default",
    'settings', x."settings",
    'forkedFrom', x."forked_from",
    'forkedFromVersion', x."forked_from_version",
    'publishedVersion', (select y."version" from "better_supabase"."template_versions" y where y."template_id" = x."id" and y."published_at" is not null order by y."version" desc limit 1),
    'upstreamVersion', case when x."forked_from" is not null then (select y."version" from "better_supabase"."template_versions" y where y."template_id" = x."forked_from" and y."published_at" is not null order by y."version" desc limit 1) end,
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at"
  )
    order by x."is_default" desc, x."scope"::text desc, x."name", x."id"), '[]'::jsonb)
  from "better_supabase"."templates" x
  where (x."scope" = 'system' or x."tenant_id" = templates_list.tenant)
    and (templates_list.type is null or x."type" = templates_list.type)
    and (templates_list.language is null or x."language" = templates_list.language)
$$;
revoke execute on function "better_supabase"."templates_list"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."templates_list"(uuid, text, text) to authenticated, service_role;

-- One template with its newest published version and its draft, bodies
-- included; null when the caller can't read it.
create or replace function "better_supabase"."template_get"(template_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'id', x."id",
    'tenant', x."tenant_id",
    'scope', x."scope",
    'key', x."key",
    'type', x."type",
    'name', x."name",
    'language', x."language",
    'isDefault', x."is_default",
    'settings', x."settings",
    'forkedFrom', x."forked_from",
    'forkedFromVersion', x."forked_from_version",
    'publishedVersion', (select y."version" from "better_supabase"."template_versions" y where y."template_id" = x."id" and y."published_at" is not null order by y."version" desc limit 1),
    'upstreamVersion', case when x."forked_from" is not null then (select y."version" from "better_supabase"."template_versions" y where y."template_id" = x."forked_from" and y."published_at" is not null order by y."version" desc limit 1) end,
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at"
  ) || jsonb_build_object(
    'published', (select jsonb_build_object(
    'id', y."id",
    'template', y."template_id",
    'version', y."version",
    'hash', y."hash",
    'publishedAt', y."published_at",
    'createdBy', y."created_by",
    'createdAt', y."created_at",
    'body', y."body"
  ) from "better_supabase"."template_versions" y
      where y."template_id" = x."id" and y."published_at" is not null
      order by y."version" desc limit 1),
    'draft', (select jsonb_build_object(
    'id', y."id",
    'template', y."template_id",
    'version', y."version",
    'hash', y."hash",
    'publishedAt', y."published_at",
    'createdBy', y."created_by",
    'createdAt', y."created_at",
    'body', y."body"
  ) from "better_supabase"."template_versions" y
      where y."template_id" = x."id" and y."published_at" is null))
  from "better_supabase"."templates" x
  where x."id" = template_get.template_id
$$;
revoke execute on function "better_supabase"."template_get"(uuid) from public, anon;
grant execute on function "better_supabase"."template_get"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."remove_template"(template_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."templates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."templates" x where x."id" = remove_template.template_id;
  if not found then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'templates.manage'), false))) then
    raise exception 'You may not remove this template' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  delete from "better_supabase"."templates" x where x."id" = remove_template.template_id;
  return true;
end;
$$;
revoke execute on function "better_supabase"."remove_template"(uuid) from public, anon;
grant execute on function "better_supabase"."remove_template"(uuid) to authenticated, service_role;

-- Saves body as the template's draft: updates the open one, or opens one
-- numbered after the last version.
create or replace function "better_supabase"."save_template_draft"(template_id uuid, body jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tpl "better_supabase"."templates"%rowtype;
  v_row "better_supabase"."template_versions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_tpl from "better_supabase"."templates" x where x."id" = save_template_draft.template_id for update;
  if not found then
    raise exception 'No such template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tpl."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_tpl."tenant_id", 'templates.manage'), false))) then
    raise exception 'You may not edit this template' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  if save_template_draft.body is null then
    raise exception 'A template version needs a body' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  update "better_supabase"."template_versions" x set
    "body" = save_template_draft.body,
    "hash" = encode(extensions.digest(save_template_draft.body::text, 'sha256'), 'hex')
  where x."template_id" = save_template_draft.template_id and x."published_at" is null
  returning * into v_row;
  if not found then
    insert into "better_supabase"."template_versions" ("template_id", "version", "body", "hash", "created_by")
    values (
      save_template_draft.template_id,
      coalesce((select max(y."version") from "better_supabase"."template_versions" y where y."template_id" = save_template_draft.template_id), 0) + 1,
      save_template_draft.body,
      encode(extensions.digest(save_template_draft.body::text, 'sha256'), 'hex'),
      (select auth.uid())
    )
    returning * into v_row;
  end if;
  update "better_supabase"."templates" x set "updated_at" = now() where x."id" = save_template_draft.template_id;
  return jsonb_build_object(
    'id', v_row."id",
    'template', v_row."template_id",
    'version', v_row."version",
    'hash', v_row."hash",
    'publishedAt', v_row."published_at",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'body', v_row."body"
  );
end;
$$;
revoke execute on function "better_supabase"."save_template_draft"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_template_draft"(uuid, jsonb) to authenticated, service_role;

-- Publishes the template's draft. Applications use the newest published
-- version; published versions never change.
create or replace function "better_supabase"."publish_template_version"(template_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tpl "better_supabase"."templates"%rowtype;
  v_row "better_supabase"."template_versions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_tpl from "better_supabase"."templates" x where x."id" = publish_template_version.template_id for update;
  if not found then
    raise exception 'No such template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tpl."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_tpl."tenant_id", 'templates.manage'), false))) then
    raise exception 'You may not publish this template' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  update "better_supabase"."template_versions" x set "published_at" = now()
  where x."template_id" = publish_template_version.template_id and x."published_at" is null
  returning * into v_row;
  if not found then
    raise exception 'This template has no draft to publish' using errcode = 'P0002', hint = 'TEMPLATE_NO_DRAFT';
  end if;
  update "better_supabase"."templates" x set "updated_at" = now() where x."id" = publish_template_version.template_id;
  null;
  return jsonb_build_object(
    'id', v_row."id",
    'template', v_row."template_id",
    'version', v_row."version",
    'hash', v_row."hash",
    'publishedAt', v_row."published_at",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'body', v_row."body"
  );
end;
$$;
revoke execute on function "better_supabase"."publish_template_version"(uuid) from public, anon;
grant execute on function "better_supabase"."publish_template_version"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."template_versions_list"(template_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', y."id",
    'template', y."template_id",
    'version', y."version",
    'hash', y."hash",
    'publishedAt', y."published_at",
    'createdBy', y."created_by",
    'createdAt', y."created_at"
  ) order by y."version" desc), '[]'::jsonb)
  from "better_supabase"."template_versions" y where y."template_id" = template_versions_list.template_id
$$;
revoke execute on function "better_supabase"."template_versions_list"(uuid) from public, anon;
grant execute on function "better_supabase"."template_versions_list"(uuid) to authenticated, service_role;

-- One default per tenant, type and language.
create or replace function "better_supabase"."set_default_template"(template_id uuid, on_default boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."templates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."templates" x where x."id" = set_default_template.template_id for update;
  if not found then
    raise exception 'No such template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'templates.manage'), false))) then
    raise exception 'You may not change this template' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  if set_default_template.on_default then
    update "better_supabase"."templates" x set "is_default" = false, "updated_at" = now()
    where x."tenant_id" is not distinct from v_row."tenant_id"
      and x."type" = v_row."type" and x."language" = v_row."language"
      and x."is_default" and x."id" <> v_row."id";
  end if;
  update "better_supabase"."templates" x set "is_default" = coalesce(set_default_template.on_default, false), "updated_at" = now()
  where x."id" = set_default_template.template_id;
  return true;
end;
$$;
revoke execute on function "better_supabase"."set_default_template"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."set_default_template"(uuid, boolean) to authenticated, service_role;

-- Copies the newest published version of source (a system template, or one
-- in tenant) into a new template in tenant, published as its version 1, and
-- records the version it copied. templates.manage in tenant.
create or replace function "better_supabase"."fork_template"(source uuid, tenant uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_src "better_supabase"."templates"%rowtype;
  v_version "better_supabase"."template_versions"%rowtype;
  v_row "better_supabase"."templates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_src from "better_supabase"."templates" x where x."id" = fork_template.source;
  if not found or not (v_src."scope" = 'system' or v_src."tenant_id" = fork_template.tenant) then
    raise exception 'No such template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_FOUND';
  end if;
  if fork_template.tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (fork_template.tenant is not null and coalesce(better_supabase.can('tenant', fork_template.tenant, 'templates.manage'), false))) then
    raise exception 'You may not create templates here' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  select * into v_version from "better_supabase"."template_versions" y
  where y."template_id" = fork_template.source and y."published_at" is not null
  order by y."version" desc limit 1;
  if not found then
    raise exception 'This template has no published version' using errcode = 'P0002', hint = 'TEMPLATE_NOT_PUBLISHED';
  end if;
  insert into "better_supabase"."templates" ("tenant_id", "scope", "type", "name", "language", "settings", "forked_from", "forked_from_version", "created_by")
  values (fork_template.tenant, 'tenant', v_src."type", v_src."name", v_src."language", v_src."settings", v_src."id", v_version."version", (select auth.uid()))
  returning * into v_row;
  insert into "better_supabase"."template_versions" ("template_id", "version", "body", "hash", "published_at", "created_by")
  values (v_row."id", 1, v_version."body", v_version."hash", now(), (select auth.uid()));

  return jsonb_build_object(
    'id', v_row."id",
    'tenant', v_row."tenant_id",
    'scope', v_row."scope",
    'key', v_row."key",
    'type', v_row."type",
    'name', v_row."name",
    'language', v_row."language",
    'isDefault', v_row."is_default",
    'settings', v_row."settings",
    'forkedFrom', v_row."forked_from",
    'forkedFromVersion', v_row."forked_from_version",
    'publishedVersion', (select y."version" from "better_supabase"."template_versions" y where y."template_id" = v_row."id" and y."published_at" is not null order by y."version" desc limit 1),
    'upstreamVersion', case when v_row."forked_from" is not null then (select y."version" from "better_supabase"."template_versions" y where y."template_id" = v_row."forked_from" and y."published_at" is not null order by y."version" desc limit 1) end,
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'updatedAt', v_row."updated_at"
  );
end;
$$;
revoke execute on function "better_supabase"."fork_template"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."fork_template"(uuid, uuid) to authenticated, service_role;

-- Upserts the system templates by key from starters, a JSON array of
-- { key, type, name, language?, settings?, body }, and publishes a new
-- version of each whose body changed. Returns how many it published.
create or replace function "better_supabase"."sync_templates"(starters jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_starter jsonb;
  v_row "better_supabase"."templates"%rowtype;
  v_hash text;
  v_version "better_supabase"."template_versions"%rowtype;
  v_count integer := 0;
begin
  if jsonb_typeof(sync_templates.starters) <> 'array' then
    raise exception 'starters must be an array' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  for v_starter in select value from jsonb_array_elements(sync_templates.starters) loop
    if coalesce(v_starter ->> 'key', '') !~ '^[a-z0-9][a-z0-9_.-]{0,99}$' or not (v_starter ? 'body') then
      raise exception 'Each starter needs a key and a body' using errcode = '22023', hint = 'TEMPLATE_INVALID';
    end if;
    if v_starter ? 'brand' then
      raise exception 'this templates table has no brand column' using errcode = '22023', hint = 'TEMPLATE_BRAND_UNSUPPORTED';
    end if;
    select * into v_row from "better_supabase"."templates" x where x."tenant_id" is null and x."key" = v_starter ->> 'key' for update;
    if not found then
      insert into "better_supabase"."templates" ("tenant_id", "scope", "key", "type", "name", "language", "settings")
      values (null, 'system', v_starter ->> 'key', v_starter ->> 'type', v_starter ->> 'name',
        coalesce(v_starter ->> 'language', 'en'), coalesce(v_starter -> 'settings', '{}'::jsonb))
      returning * into v_row;
    else
      update "better_supabase"."templates" x set
        "type" = coalesce(v_starter ->> 'type', x."type"),
        "name" = coalesce(v_starter ->> 'name', x."name"),
        "language" = coalesce(v_starter ->> 'language', x."language"),
        "settings" = coalesce(v_starter -> 'settings', x."settings"),
        "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    end if;
    v_hash := encode(extensions.digest((v_starter -> 'body')::text, 'sha256'), 'hex');
    if v_hash is distinct from (select y."hash" from "better_supabase"."template_versions" y
        where y."template_id" = v_row."id" and y."published_at" is not null
        order by y."version" desc limit 1) then
      delete from "better_supabase"."template_versions" y where y."template_id" = v_row."id" and y."published_at" is null;
      insert into "better_supabase"."template_versions" ("template_id", "version", "body", "hash", "published_at")
      values (
        v_row."id",
        coalesce((select max(y."version") from "better_supabase"."template_versions" y where y."template_id" = v_row."id"), 0) + 1,
        v_starter -> 'body',
        v_hash,
        now()
      )
      returning * into v_version;
      v_count := v_count + 1;
      null;
    end if;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."sync_templates"(jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."sync_templates"(jsonb) to service_role;

-- What applying template in tenant needs: the template, its newest
-- published version with the body, and the enabled workflow attachments,
-- each input checked against the published version's input_schema
-- (TEMPLATE_WORKFLOW_INPUT_INVALID). templates.apply in tenant.
create or replace function "better_supabase"."template_apply_target"(template_id uuid, tenant uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tpl "better_supabase"."templates"%rowtype;
  v_version "better_supabase"."template_versions"%rowtype;
  v_workflows jsonb := '[]'::jsonb;
begin
  if template_apply_target.tenant is null then
    raise exception 'Applying a template needs a tenant' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', template_apply_target.tenant, 'templates.apply'), false)) then
    raise exception 'You may not apply templates here' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  select * into v_tpl from "better_supabase"."templates" x where x."id" = template_apply_target.template_id;
  if not found or not (v_tpl."scope" = 'system' or v_tpl."tenant_id" = template_apply_target.tenant) then
    raise exception 'No such template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_FOUND';
  end if;
  select * into v_version from "better_supabase"."template_versions" y
  where y."template_id" = v_tpl."id" and y."published_at" is not null
  order by y."version" desc limit 1;
  if not found then
    raise exception 'This template has no published version' using errcode = 'P0002', hint = 'TEMPLATE_NOT_PUBLISHED';
  end if;

  return jsonb_build_object(
    'template', jsonb_build_object(
    'id', v_tpl."id",
    'tenant', v_tpl."tenant_id",
    'scope', v_tpl."scope",
    'key', v_tpl."key",
    'type', v_tpl."type",
    'name', v_tpl."name",
    'language', v_tpl."language",
    'isDefault', v_tpl."is_default",
    'settings', v_tpl."settings",
    'forkedFrom', v_tpl."forked_from",
    'forkedFromVersion', v_tpl."forked_from_version",
    'publishedVersion', (select y."version" from "better_supabase"."template_versions" y where y."template_id" = v_tpl."id" and y."published_at" is not null order by y."version" desc limit 1),
    'upstreamVersion', case when v_tpl."forked_from" is not null then (select y."version" from "better_supabase"."template_versions" y where y."template_id" = v_tpl."forked_from" and y."published_at" is not null order by y."version" desc limit 1) end,
    'createdBy', v_tpl."created_by",
    'createdAt', v_tpl."created_at",
    'updatedAt', v_tpl."updated_at"
  ),
    'version', jsonb_build_object(
    'id', v_version."id",
    'template', v_version."template_id",
    'version', v_version."version",
    'hash', v_version."hash",
    'publishedAt', v_version."published_at",
    'createdBy', v_version."created_by",
    'createdAt', v_version."created_at",
    'body', v_version."body"
  ),
    'workflows', v_workflows
  );
end;
$$;
revoke execute on function "better_supabase"."template_apply_target"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."template_apply_target"(uuid, uuid) to authenticated, service_role;

-- Records that version of template created subject_type/subject_id in
-- tenant. templates.apply in tenant.
create or replace function "better_supabase"."record_template_application"(template_id uuid, version_id uuid, tenant uuid, subject_type text, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tpl "better_supabase"."templates"%rowtype;
  v_row "better_supabase"."template_applications"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if record_template_application.tenant is null then
    raise exception 'Applying a template needs a tenant' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', record_template_application.tenant, 'templates.apply'), false)) then
    raise exception 'You may not apply templates here' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  select * into v_tpl from "better_supabase"."templates" x where x."id" = record_template_application.template_id;
  if not found or not (v_tpl."scope" = 'system' or v_tpl."tenant_id" = record_template_application.tenant) then
    raise exception 'No such template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_FOUND';
  end if;
  if not exists (select 1 from "better_supabase"."template_versions" y where y."id" = record_template_application.version_id
      and y."template_id" = v_tpl."id" and y."published_at" is not null) then
    raise exception 'Not a published version of this template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_PUBLISHED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_template_apply"(uuid, uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text, $4::text)', v_hook::oid::regproc)
        using record_template_application.tenant, v_tpl."id", record_template_application.subject_type, record_template_application.subject_id;
    end if;
  end;
  insert into "better_supabase"."template_applications" ("template_id", "version_id", "tenant_id", "subject_type", "subject_id", "applied_by")
  values (v_tpl."id", record_template_application.version_id, record_template_application.tenant,
    record_template_application.subject_type, record_template_application.subject_id, (select auth.uid()))
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_template_apply"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object(
    'id', v_row."id",
    'template', v_row."template_id",
    'version', v_row."version_id",
    'tenant', v_row."tenant_id",
    'subjectType', v_row."subject_type",
    'subjectId', v_row."subject_id",
    'appliedBy', v_row."applied_by",
    'appliedAt', v_row."applied_at"
  );
end;
$$;
revoke execute on function "better_supabase"."record_template_application"(uuid, uuid, uuid, text, text) from public, anon;
grant execute on function "better_supabase"."record_template_application"(uuid, uuid, uuid, text, text) to authenticated, service_role;

-- The tenant's applications, newest first, of one template or onto one
-- subject when those are given.
create or replace function "better_supabase"."template_applications_list"(tenant uuid, template_id uuid, subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(r.value order by r.at desc, r.id), '[]'::jsonb)
  from (
    select jsonb_build_object(
    'id', a."id",
    'template', a."template_id",
    'version', a."version_id",
    'tenant', a."tenant_id",
    'subjectType', a."subject_type",
    'subjectId', a."subject_id",
    'appliedBy', a."applied_by",
    'appliedAt', a."applied_at"
  ) as value, a."applied_at" as at, a."id" as id
    from "better_supabase"."template_applications" a
    where a."tenant_id" = template_applications_list.tenant
      and (template_applications_list.template_id is null or a."template_id" = template_applications_list.template_id)
      and (template_applications_list.subject_type is null or a."subject_type" = template_applications_list.subject_type)
      and (template_applications_list.subject_id is null or a."subject_id" = template_applications_list.subject_id)
    order by a."applied_at" desc, a."id"
    limit 200
  ) r
$$;
revoke execute on function "better_supabase"."template_applications_list"(uuid, uuid, text, text) from public, anon;
grant execute on function "better_supabase"."template_applications_list"(uuid, uuid, text, text) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."templates";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."templates";
create policy bsb_tenant_scope_select on "better_supabase"."templates" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('templates.read'))
    or ("scope" = 'system' and exists (select better_supabase.tenant_ids_with('templates.read'))))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."templates";
create policy bsb_tenant_scope_insert on "better_supabase"."templates" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."templates";
create policy bsb_tenant_scope_update on "better_supabase"."templates" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."templates";
create policy bsb_tenant_scope_delete on "better_supabase"."templates" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."template_applications";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."template_applications";
create policy bsb_tenant_scope_select on "better_supabase"."template_applications" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('templates.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."template_applications";
create policy bsb_tenant_scope_insert on "better_supabase"."template_applications" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."template_applications";
create policy bsb_tenant_scope_update on "better_supabase"."template_applications" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."template_applications";
create policy bsb_tenant_scope_delete on "better_supabase"."template_applications" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_091_templates.sql
-- better-supabase module: templates
-- @bsb-block-data templates
-- @bsb-hash sha256:b8f109c9be802b16766dc2421c68f34cacf2322c02b9c507938fd08f01f94689
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "pgcrypto" with schema "extensions";

insert into better_supabase.blocks (name, version, mode)
values ('templates', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_091_templates.sql
-- better-supabase module: templates
-- @bsb-block templates@1 managed
-- @bsb-hash sha256:69e65b53c96df0cf4378b86c9c0d725adc4ef1ed0b997fb7ad3081ed8ea4dca7
-- Typed, versioned templates (system starters and tenant forks) that create records, with merge fields and workflows started on each record they create.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."templates";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."templates";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."templates";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."templates";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."templates";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."template_applications";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."template_applications";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."template_applications";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."template_applications";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."template_applications";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create extension if not exists pgcrypto with schema extensions;

-- Templates of a type (an invoice, a project, an email): a tenant's own, or
-- a system starter (no tenant) that sync_templates keeps by key and tenants
-- fork, or with options.brand a starter of one brand. forked_from: the template and version a fork copied.
create table if not exists "better_supabase"."templates" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid,
  "scope" text not null default 'tenant' check ("scope" in ('tenant', 'system')),
  "key" text check ("key" ~ '^[a-z0-9][a-z0-9_.-]{0,99}$'),
  "type" text not null check ("type" ~ '^[a-z][a-z0-9_.-]{0,63}$'),
  "name" text not null check (length("name") between 1 and 200),
  "language" text not null default 'en' check ("language" ~ '^[a-z]{2,3}(-[A-Za-z0-9]{1,8})*$'),
  "is_default" boolean not null default false,
  "settings" jsonb not null default '{}'::jsonb
    check (jsonb_typeof("settings") = 'object' and pg_column_size("settings") <= 65536),
  "forked_from" uuid references "better_supabase"."templates" ("id") on delete set null,
  "forked_from_version" integer check ("forked_from_version" > 0),
  "created_by" uuid references auth.users (id) on delete set null,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  constraint templates_system_check check (("scope" = 'system') = ("org_id" is null))
);
create unique index if not exists templates_key_idx on "better_supabase"."templates" ("org_id", "key") nulls not distinct where "key" is not null;
create unique index if not exists templates_default_idx on "better_supabase"."templates" ("org_id", "type", "language") nulls not distinct where "is_default";
create index if not exists templates_type_idx on "better_supabase"."templates" ("org_id", "type");
create index if not exists templates_forked_from_idx on "better_supabase"."templates" ("forked_from") where "forked_from" is not null;
create index if not exists templates_created_by_idx on "better_supabase"."templates" ("created_by");
alter table "better_supabase"."templates" enable row level security;
revoke all on "better_supabase"."templates" from public, anon, authenticated;
grant select on "better_supabase"."templates" to authenticated;
grant all on "better_supabase"."templates" to service_role;
drop policy if exists templates_read on "better_supabase"."templates";
create policy templates_read on "better_supabase"."templates"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('templates.read'))
    or ("scope" = 'system' and exists (select better_supabase.tenant_ids_with('templates.read'))));

-- Numbered snapshots of a template's body: at most one draft, and published
-- versions that never change. hash: the SHA-256 of the body as text.
create table if not exists "better_supabase"."template_versions" (
  "id" uuid primary key default gen_random_uuid(),
  "template_id" uuid not null references "better_supabase"."templates" ("id") on delete cascade,
  "version" integer not null check ("version" > 0),
  "body" jsonb not null check (pg_column_size("body") <= 1048576),
  "hash" text not null,
  "published_at" timestamptz,
  "created_by" uuid references auth.users (id) on delete set null,
  "created_at" timestamptz not null default now(),
  constraint template_versions_template_version_key unique ("template_id", "version")
);
create unique index if not exists template_versions_one_draft_idx on "better_supabase"."template_versions" ("template_id") where "published_at" is null;
create index if not exists template_versions_created_by_idx on "better_supabase"."template_versions" ("created_by");
alter table "better_supabase"."template_versions" enable row level security;
revoke all on "better_supabase"."template_versions" from public, anon, authenticated;
grant select on "better_supabase"."template_versions" to authenticated;
grant all on "better_supabase"."template_versions" to service_role;
drop policy if exists template_versions_read on "better_supabase"."template_versions";
create policy template_versions_read on "better_supabase"."template_versions"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."templates" x where x."id" = "template_id"));

-- Each time a published version created a record, and which one.
create table if not exists "better_supabase"."template_applications" (
  "id" uuid primary key default gen_random_uuid(),
  "template_id" uuid not null references "better_supabase"."templates" ("id") on delete cascade,
  "version_id" uuid not null references "better_supabase"."template_versions" ("id") on delete cascade,
  "org_id" uuid not null,
  "subject_type" text not null check (length("subject_type") between 1 and 100),
  "subject_id" text not null check (length("subject_id") between 1 and 200),
  "applied_by" uuid references auth.users (id) on delete set null,
  "applied_at" timestamptz not null default now()
);
create index if not exists template_applications_tenant_idx on "better_supabase"."template_applications" ("org_id", "applied_at" desc);
create index if not exists template_applications_template_idx on "better_supabase"."template_applications" ("template_id");
create index if not exists template_applications_version_idx on "better_supabase"."template_applications" ("version_id");
create index if not exists template_applications_subject_idx on "better_supabase"."template_applications" ("subject_type", "subject_id");
create index if not exists template_applications_applied_by_idx on "better_supabase"."template_applications" ("applied_by");
alter table "better_supabase"."template_applications" enable row level security;
revoke all on "better_supabase"."template_applications" from public, anon, authenticated;
grant select on "better_supabase"."template_applications" to authenticated;
grant all on "better_supabase"."template_applications" to service_role;
drop policy if exists template_applications_read on "better_supabase"."template_applications";
create policy template_applications_read on "better_supabase"."template_applications"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('templates.read')));

-- Creates a template (template_id null) or renames it and replaces its
-- settings. tenant null saves a system template, which only the service
-- role may; a tenant's needs templates.manage there.
-- fields: the extra columns (blocks.templates.options.extraColumns) to set.
drop function if exists "better_supabase"."save_template"(uuid, uuid, text, text, text, jsonb, jsonb);
create or replace function "better_supabase"."save_template"(template_id uuid, tenant uuid, type text, name text, language text, settings jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."templates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if save_template.settings is not null and jsonb_typeof(save_template.settings) <> 'object' then
    raise exception 'settings must be an object' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  if save_template.template_id is not null then
    select * into v_row from "better_supabase"."templates" x where x."id" = save_template.template_id for update;
    if not found or v_row."org_id" is distinct from save_template.tenant then
      raise exception 'No such template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_FOUND';
    end if;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_template.tenant is not null and coalesce(better_supabase.can('tenant', save_template.tenant, 'templates.manage'), false))) then
    raise exception 'You may not change templates here' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  if save_template.template_id is null and (save_template.type is null or save_template.type !~ '^[a-z][a-z0-9_.-]{0,63}$') then
    raise exception 'type must be lower-case letters, digits, dots, dashes or underscores' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  if save_template.template_id is null and save_template.name is null then
    raise exception 'A template needs a name' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_template_save"(uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::jsonb)', v_hook::oid::regproc)
        using save_template.tenant, coalesce(save_template.type, v_row."type"), save_template.settings;
    end if;
  end;
  if save_template.template_id is null then
    insert into "better_supabase"."templates" ("org_id", "scope", "type", "name", "language", "settings", "created_by")
    values (
      save_template.tenant,
      case when save_template.tenant is null then 'system' else 'tenant' end,
      save_template.type,
      save_template.name,
      coalesce(save_template.language, 'en'),
      coalesce(save_template.settings, '{}'::jsonb),
      (select auth.uid())
    )
    returning * into v_row;
  else
    update "better_supabase"."templates" x set
      "name" = coalesce(save_template.name, x."name"),
      "language" = coalesce(save_template.language, x."language"),
      "settings" = coalesce(save_template.settings, x."settings"),
      "is_default" = x."is_default" and coalesce(save_template.language, x."language") = x."language",
      "updated_at" = now()
    where x."id" = save_template.template_id
    returning * into v_row;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_template_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object(
    'id', v_row."id",
    'tenant', v_row."org_id",
    'scope', v_row."scope",
    'key', v_row."key",
    'type', v_row."type",
    'name', v_row."name",
    'language', v_row."language",
    'isDefault', v_row."is_default",
    'settings', v_row."settings",
    'forkedFrom', v_row."forked_from",
    'forkedFromVersion', v_row."forked_from_version",
    'publishedVersion', (select y."version" from "better_supabase"."template_versions" y where y."template_id" = v_row."id" and y."published_at" is not null order by y."version" desc limit 1),
    'upstreamVersion', case when v_row."forked_from" is not null then (select y."version" from "better_supabase"."template_versions" y where y."template_id" = v_row."forked_from" and y."published_at" is not null order by y."version" desc limit 1) end,
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'updatedAt', v_row."updated_at"
  );
end;
$$;
revoke execute on function "better_supabase"."save_template"(uuid, uuid, text, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."save_template"(uuid, uuid, text, text, text, jsonb) to authenticated, service_role;

-- The tenant's templates and the system ones (only the system ones without
-- a tenant), filtered by type and language, defaults first.
create or replace function "better_supabase"."templates_list"(tenant uuid, type text, language text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x."id",
    'tenant', x."org_id",
    'scope', x."scope",
    'key', x."key",
    'type', x."type",
    'name', x."name",
    'language', x."language",
    'isDefault', x."is_default",
    'settings', x."settings",
    'forkedFrom', x."forked_from",
    'forkedFromVersion', x."forked_from_version",
    'publishedVersion', (select y."version" from "better_supabase"."template_versions" y where y."template_id" = x."id" and y."published_at" is not null order by y."version" desc limit 1),
    'upstreamVersion', case when x."forked_from" is not null then (select y."version" from "better_supabase"."template_versions" y where y."template_id" = x."forked_from" and y."published_at" is not null order by y."version" desc limit 1) end,
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at"
  )
    order by x."is_default" desc, x."scope" desc, x."name", x."id"), '[]'::jsonb)
  from "better_supabase"."templates" x
  where (x."scope" = 'system' or x."org_id" = templates_list.tenant)
    and (templates_list.type is null or x."type" = templates_list.type)
    and (templates_list.language is null or x."language" = templates_list.language)
$$;
revoke execute on function "better_supabase"."templates_list"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."templates_list"(uuid, text, text) to authenticated, service_role;

-- One template with its newest published version and its draft, bodies
-- included; null when the caller can't read it.
create or replace function "better_supabase"."template_get"(template_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'id', x."id",
    'tenant', x."org_id",
    'scope', x."scope",
    'key', x."key",
    'type', x."type",
    'name', x."name",
    'language', x."language",
    'isDefault', x."is_default",
    'settings', x."settings",
    'forkedFrom', x."forked_from",
    'forkedFromVersion', x."forked_from_version",
    'publishedVersion', (select y."version" from "better_supabase"."template_versions" y where y."template_id" = x."id" and y."published_at" is not null order by y."version" desc limit 1),
    'upstreamVersion', case when x."forked_from" is not null then (select y."version" from "better_supabase"."template_versions" y where y."template_id" = x."forked_from" and y."published_at" is not null order by y."version" desc limit 1) end,
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at"
  ) || jsonb_build_object(
    'published', (select jsonb_build_object(
    'id', y."id",
    'template', y."template_id",
    'version', y."version",
    'hash', y."hash",
    'publishedAt', y."published_at",
    'createdBy', y."created_by",
    'createdAt', y."created_at",
    'body', y."body"
  ) from "better_supabase"."template_versions" y
      where y."template_id" = x."id" and y."published_at" is not null
      order by y."version" desc limit 1),
    'draft', (select jsonb_build_object(
    'id', y."id",
    'template', y."template_id",
    'version', y."version",
    'hash', y."hash",
    'publishedAt', y."published_at",
    'createdBy', y."created_by",
    'createdAt', y."created_at",
    'body', y."body"
  ) from "better_supabase"."template_versions" y
      where y."template_id" = x."id" and y."published_at" is null))
  from "better_supabase"."templates" x
  where x."id" = template_get.template_id
$$;
revoke execute on function "better_supabase"."template_get"(uuid) from public, anon;
grant execute on function "better_supabase"."template_get"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."remove_template"(template_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."templates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."templates" x where x."id" = remove_template.template_id;
  if not found then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'templates.manage'), false))) then
    raise exception 'You may not remove this template' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  delete from "better_supabase"."templates" x where x."id" = remove_template.template_id;
  return true;
end;
$$;
revoke execute on function "better_supabase"."remove_template"(uuid) from public, anon;
grant execute on function "better_supabase"."remove_template"(uuid) to authenticated, service_role;

-- Saves body as the template's draft: updates the open one, or opens one
-- numbered after the last version.
create or replace function "better_supabase"."save_template_draft"(template_id uuid, body jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tpl "better_supabase"."templates"%rowtype;
  v_row "better_supabase"."template_versions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_tpl from "better_supabase"."templates" x where x."id" = save_template_draft.template_id for update;
  if not found then
    raise exception 'No such template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tpl."org_id" is not null and coalesce(better_supabase.can('tenant', v_tpl."org_id", 'templates.manage'), false))) then
    raise exception 'You may not edit this template' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  if save_template_draft.body is null then
    raise exception 'A template version needs a body' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  update "better_supabase"."template_versions" x set
    "body" = save_template_draft.body,
    "hash" = encode(extensions.digest(save_template_draft.body::text, 'sha256'), 'hex')
  where x."template_id" = save_template_draft.template_id and x."published_at" is null
  returning * into v_row;
  if not found then
    insert into "better_supabase"."template_versions" ("template_id", "version", "body", "hash", "created_by")
    values (
      save_template_draft.template_id,
      coalesce((select max(y."version") from "better_supabase"."template_versions" y where y."template_id" = save_template_draft.template_id), 0) + 1,
      save_template_draft.body,
      encode(extensions.digest(save_template_draft.body::text, 'sha256'), 'hex'),
      (select auth.uid())
    )
    returning * into v_row;
  end if;
  update "better_supabase"."templates" x set "updated_at" = now() where x."id" = save_template_draft.template_id;
  return jsonb_build_object(
    'id', v_row."id",
    'template', v_row."template_id",
    'version', v_row."version",
    'hash', v_row."hash",
    'publishedAt', v_row."published_at",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'body', v_row."body"
  );
end;
$$;
revoke execute on function "better_supabase"."save_template_draft"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_template_draft"(uuid, jsonb) to authenticated, service_role;

-- Publishes the template's draft. Applications use the newest published
-- version; published versions never change.
create or replace function "better_supabase"."publish_template_version"(template_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tpl "better_supabase"."templates"%rowtype;
  v_row "better_supabase"."template_versions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_tpl from "better_supabase"."templates" x where x."id" = publish_template_version.template_id for update;
  if not found then
    raise exception 'No such template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tpl."org_id" is not null and coalesce(better_supabase.can('tenant', v_tpl."org_id", 'templates.manage'), false))) then
    raise exception 'You may not publish this template' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  update "better_supabase"."template_versions" x set "published_at" = now()
  where x."template_id" = publish_template_version.template_id and x."published_at" is null
  returning * into v_row;
  if not found then
    raise exception 'This template has no draft to publish' using errcode = 'P0002', hint = 'TEMPLATE_NO_DRAFT';
  end if;
  update "better_supabase"."templates" x set "updated_at" = now() where x."id" = publish_template_version.template_id;
  null;
  return jsonb_build_object(
    'id', v_row."id",
    'template', v_row."template_id",
    'version', v_row."version",
    'hash', v_row."hash",
    'publishedAt', v_row."published_at",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'body', v_row."body"
  );
end;
$$;
revoke execute on function "better_supabase"."publish_template_version"(uuid) from public, anon;
grant execute on function "better_supabase"."publish_template_version"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."template_versions_list"(template_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', y."id",
    'template', y."template_id",
    'version', y."version",
    'hash', y."hash",
    'publishedAt', y."published_at",
    'createdBy', y."created_by",
    'createdAt', y."created_at"
  ) order by y."version" desc), '[]'::jsonb)
  from "better_supabase"."template_versions" y where y."template_id" = template_versions_list.template_id
$$;
revoke execute on function "better_supabase"."template_versions_list"(uuid) from public, anon;
grant execute on function "better_supabase"."template_versions_list"(uuid) to authenticated, service_role;

-- One default per tenant, type and language.
create or replace function "better_supabase"."set_default_template"(template_id uuid, on_default boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."templates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."templates" x where x."id" = set_default_template.template_id for update;
  if not found then
    raise exception 'No such template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'templates.manage'), false))) then
    raise exception 'You may not change this template' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  if set_default_template.on_default then
    update "better_supabase"."templates" x set "is_default" = false, "updated_at" = now()
    where x."org_id" is not distinct from v_row."org_id"
      and x."type" = v_row."type" and x."language" = v_row."language"
      and x."is_default" and x."id" <> v_row."id";
  end if;
  update "better_supabase"."templates" x set "is_default" = coalesce(set_default_template.on_default, false), "updated_at" = now()
  where x."id" = set_default_template.template_id;
  return true;
end;
$$;
revoke execute on function "better_supabase"."set_default_template"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."set_default_template"(uuid, boolean) to authenticated, service_role;

-- Copies the newest published version of source (a system template, or one
-- in tenant) into a new template in tenant, published as its version 1, and
-- records the version it copied. templates.manage in tenant.
create or replace function "better_supabase"."fork_template"(source uuid, tenant uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_src "better_supabase"."templates"%rowtype;
  v_version "better_supabase"."template_versions"%rowtype;
  v_row "better_supabase"."templates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_src from "better_supabase"."templates" x where x."id" = fork_template.source;
  if not found or not (v_src."scope" = 'system' or v_src."org_id" = fork_template.tenant) then
    raise exception 'No such template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_FOUND';
  end if;
  if fork_template.tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (fork_template.tenant is not null and coalesce(better_supabase.can('tenant', fork_template.tenant, 'templates.manage'), false))) then
    raise exception 'You may not create templates here' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  select * into v_version from "better_supabase"."template_versions" y
  where y."template_id" = fork_template.source and y."published_at" is not null
  order by y."version" desc limit 1;
  if not found then
    raise exception 'This template has no published version' using errcode = 'P0002', hint = 'TEMPLATE_NOT_PUBLISHED';
  end if;
  insert into "better_supabase"."templates" ("org_id", "scope", "type", "name", "language", "settings", "forked_from", "forked_from_version", "created_by")
  values (fork_template.tenant, 'tenant', v_src."type", v_src."name", v_src."language", v_src."settings", v_src."id", v_version."version", (select auth.uid()))
  returning * into v_row;
  insert into "better_supabase"."template_versions" ("template_id", "version", "body", "hash", "published_at", "created_by")
  values (v_row."id", 1, v_version."body", v_version."hash", now(), (select auth.uid()));

  return jsonb_build_object(
    'id', v_row."id",
    'tenant', v_row."org_id",
    'scope', v_row."scope",
    'key', v_row."key",
    'type', v_row."type",
    'name', v_row."name",
    'language', v_row."language",
    'isDefault', v_row."is_default",
    'settings', v_row."settings",
    'forkedFrom', v_row."forked_from",
    'forkedFromVersion', v_row."forked_from_version",
    'publishedVersion', (select y."version" from "better_supabase"."template_versions" y where y."template_id" = v_row."id" and y."published_at" is not null order by y."version" desc limit 1),
    'upstreamVersion', case when v_row."forked_from" is not null then (select y."version" from "better_supabase"."template_versions" y where y."template_id" = v_row."forked_from" and y."published_at" is not null order by y."version" desc limit 1) end,
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'updatedAt', v_row."updated_at"
  );
end;
$$;
revoke execute on function "better_supabase"."fork_template"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."fork_template"(uuid, uuid) to authenticated, service_role;

-- Upserts the system templates by key from starters, a JSON array of
-- { key, type, name, language?, settings?, body }, and publishes a new
-- version of each whose body changed. Returns how many it published.
create or replace function "better_supabase"."sync_templates"(starters jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_starter jsonb;
  v_row "better_supabase"."templates"%rowtype;
  v_hash text;
  v_version "better_supabase"."template_versions"%rowtype;
  v_count integer := 0;
begin
  if jsonb_typeof(sync_templates.starters) <> 'array' then
    raise exception 'starters must be an array' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  for v_starter in select value from jsonb_array_elements(sync_templates.starters) loop
    if coalesce(v_starter ->> 'key', '') !~ '^[a-z0-9][a-z0-9_.-]{0,99}$' or not (v_starter ? 'body') then
      raise exception 'Each starter needs a key and a body' using errcode = '22023', hint = 'TEMPLATE_INVALID';
    end if;
    if v_starter ? 'brand' then
      raise exception 'this templates table has no brand column' using errcode = '22023', hint = 'TEMPLATE_BRAND_UNSUPPORTED';
    end if;
    select * into v_row from "better_supabase"."templates" x where x."org_id" is null and x."key" = v_starter ->> 'key' for update;
    if not found then
      insert into "better_supabase"."templates" ("org_id", "scope", "key", "type", "name", "language", "settings")
      values (null, 'system', v_starter ->> 'key', v_starter ->> 'type', v_starter ->> 'name',
        coalesce(v_starter ->> 'language', 'en'), coalesce(v_starter -> 'settings', '{}'::jsonb))
      returning * into v_row;
    else
      update "better_supabase"."templates" x set
        "type" = coalesce(v_starter ->> 'type', x."type"),
        "name" = coalesce(v_starter ->> 'name', x."name"),
        "language" = coalesce(v_starter ->> 'language', x."language"),
        "settings" = coalesce(v_starter -> 'settings', x."settings"),
        "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    end if;
    v_hash := encode(extensions.digest((v_starter -> 'body')::text, 'sha256'), 'hex');
    if v_hash is distinct from (select y."hash" from "better_supabase"."template_versions" y
        where y."template_id" = v_row."id" and y."published_at" is not null
        order by y."version" desc limit 1) then
      delete from "better_supabase"."template_versions" y where y."template_id" = v_row."id" and y."published_at" is null;
      insert into "better_supabase"."template_versions" ("template_id", "version", "body", "hash", "published_at")
      values (
        v_row."id",
        coalesce((select max(y."version") from "better_supabase"."template_versions" y where y."template_id" = v_row."id"), 0) + 1,
        v_starter -> 'body',
        v_hash,
        now()
      )
      returning * into v_version;
      v_count := v_count + 1;
      null;
    end if;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."sync_templates"(jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."sync_templates"(jsonb) to service_role;

-- What applying template in tenant needs: the template, its newest
-- published version with the body, and the enabled workflow attachments,
-- each input checked against the published version's input_schema
-- (TEMPLATE_WORKFLOW_INPUT_INVALID). templates.apply in tenant.
create or replace function "better_supabase"."template_apply_target"(template_id uuid, tenant uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tpl "better_supabase"."templates"%rowtype;
  v_version "better_supabase"."template_versions"%rowtype;
  v_workflows jsonb := '[]'::jsonb;
begin
  if template_apply_target.tenant is null then
    raise exception 'Applying a template needs a tenant' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', template_apply_target.tenant, 'templates.apply'), false)) then
    raise exception 'You may not apply templates here' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  select * into v_tpl from "better_supabase"."templates" x where x."id" = template_apply_target.template_id;
  if not found or not (v_tpl."scope" = 'system' or v_tpl."org_id" = template_apply_target.tenant) then
    raise exception 'No such template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_FOUND';
  end if;
  select * into v_version from "better_supabase"."template_versions" y
  where y."template_id" = v_tpl."id" and y."published_at" is not null
  order by y."version" desc limit 1;
  if not found then
    raise exception 'This template has no published version' using errcode = 'P0002', hint = 'TEMPLATE_NOT_PUBLISHED';
  end if;

  return jsonb_build_object(
    'template', jsonb_build_object(
    'id', v_tpl."id",
    'tenant', v_tpl."org_id",
    'scope', v_tpl."scope",
    'key', v_tpl."key",
    'type', v_tpl."type",
    'name', v_tpl."name",
    'language', v_tpl."language",
    'isDefault', v_tpl."is_default",
    'settings', v_tpl."settings",
    'forkedFrom', v_tpl."forked_from",
    'forkedFromVersion', v_tpl."forked_from_version",
    'publishedVersion', (select y."version" from "better_supabase"."template_versions" y where y."template_id" = v_tpl."id" and y."published_at" is not null order by y."version" desc limit 1),
    'upstreamVersion', case when v_tpl."forked_from" is not null then (select y."version" from "better_supabase"."template_versions" y where y."template_id" = v_tpl."forked_from" and y."published_at" is not null order by y."version" desc limit 1) end,
    'createdBy', v_tpl."created_by",
    'createdAt', v_tpl."created_at",
    'updatedAt', v_tpl."updated_at"
  ),
    'version', jsonb_build_object(
    'id', v_version."id",
    'template', v_version."template_id",
    'version', v_version."version",
    'hash', v_version."hash",
    'publishedAt', v_version."published_at",
    'createdBy', v_version."created_by",
    'createdAt', v_version."created_at",
    'body', v_version."body"
  ),
    'workflows', v_workflows
  );
end;
$$;
revoke execute on function "better_supabase"."template_apply_target"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."template_apply_target"(uuid, uuid) to authenticated, service_role;

-- Records that version of template created subject_type/subject_id in
-- tenant. templates.apply in tenant.
create or replace function "better_supabase"."record_template_application"(template_id uuid, version_id uuid, tenant uuid, subject_type text, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tpl "better_supabase"."templates"%rowtype;
  v_row "better_supabase"."template_applications"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if record_template_application.tenant is null then
    raise exception 'Applying a template needs a tenant' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', record_template_application.tenant, 'templates.apply'), false)) then
    raise exception 'You may not apply templates here' using errcode = '42501', hint = 'TEMPLATE_FORBIDDEN';
  end if;
  select * into v_tpl from "better_supabase"."templates" x where x."id" = record_template_application.template_id;
  if not found or not (v_tpl."scope" = 'system' or v_tpl."org_id" = record_template_application.tenant) then
    raise exception 'No such template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_FOUND';
  end if;
  if not exists (select 1 from "better_supabase"."template_versions" y where y."id" = record_template_application.version_id
      and y."template_id" = v_tpl."id" and y."published_at" is not null) then
    raise exception 'Not a published version of this template' using errcode = 'P0002', hint = 'TEMPLATE_NOT_PUBLISHED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_template_apply"(uuid, uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text, $4::text)', v_hook::oid::regproc)
        using record_template_application.tenant, v_tpl."id", record_template_application.subject_type, record_template_application.subject_id;
    end if;
  end;
  insert into "better_supabase"."template_applications" ("template_id", "version_id", "org_id", "subject_type", "subject_id", "applied_by")
  values (v_tpl."id", record_template_application.version_id, record_template_application.tenant,
    record_template_application.subject_type, record_template_application.subject_id, (select auth.uid()))
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_template_apply"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object(
    'id', v_row."id",
    'template', v_row."template_id",
    'version', v_row."version_id",
    'tenant', v_row."org_id",
    'subjectType', v_row."subject_type",
    'subjectId', v_row."subject_id",
    'appliedBy', v_row."applied_by",
    'appliedAt', v_row."applied_at"
  );
end;
$$;
revoke execute on function "better_supabase"."record_template_application"(uuid, uuid, uuid, text, text) from public, anon;
grant execute on function "better_supabase"."record_template_application"(uuid, uuid, uuid, text, text) to authenticated, service_role;

-- The tenant's applications, newest first, of one template or onto one
-- subject when those are given.
create or replace function "better_supabase"."template_applications_list"(tenant uuid, template_id uuid, subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(r.value order by r.at desc, r.id), '[]'::jsonb)
  from (
    select jsonb_build_object(
    'id', a."id",
    'template', a."template_id",
    'version', a."version_id",
    'tenant', a."org_id",
    'subjectType', a."subject_type",
    'subjectId', a."subject_id",
    'appliedBy', a."applied_by",
    'appliedAt', a."applied_at"
  ) as value, a."applied_at" as at, a."id" as id
    from "better_supabase"."template_applications" a
    where a."org_id" = template_applications_list.tenant
      and (template_applications_list.template_id is null or a."template_id" = template_applications_list.template_id)
      and (template_applications_list.subject_type is null or a."subject_type" = template_applications_list.subject_type)
      and (template_applications_list.subject_id is null or a."subject_id" = template_applications_list.subject_id)
    order by a."applied_at" desc, a."id"
    limit 200
  ) r
$$;
revoke execute on function "better_supabase"."template_applications_list"(uuid, uuid, text, text) from public, anon;
grant execute on function "better_supabase"."template_applications_list"(uuid, uuid, text, text) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."templates";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."templates";
create policy bsb_tenant_scope_select on "better_supabase"."templates" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('templates.read'))
    or ("scope" = 'system' and exists (select better_supabase.tenant_ids_with('templates.read'))))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."templates";
create policy bsb_tenant_scope_insert on "better_supabase"."templates" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."templates";
create policy bsb_tenant_scope_update on "better_supabase"."templates" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."templates";
create policy bsb_tenant_scope_delete on "better_supabase"."templates" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."template_applications";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."template_applications";
create policy bsb_tenant_scope_select on "better_supabase"."template_applications" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('templates.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."template_applications";
create policy bsb_tenant_scope_insert on "better_supabase"."template_applications" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."template_applications";
create policy bsb_tenant_scope_update on "better_supabase"."template_applications" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."template_applications";
create policy bsb_tenant_scope_delete on "better_supabase"."template_applications" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_091_templates.sql
-- better-supabase module: templates
-- @bsb-block-data templates
-- @bsb-hash sha256:b8f109c9be802b16766dc2421c68f34cacf2322c02b9c507938fd08f01f94689
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "pgcrypto" with schema "extensions";

insert into better_supabase.blocks (name, version, mode)
values ('templates', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
