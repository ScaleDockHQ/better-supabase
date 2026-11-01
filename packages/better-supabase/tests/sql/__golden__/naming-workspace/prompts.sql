-- ==== schema supabase/schemas/900_better_supabase_170_prompts.sql
-- better-supabase module: prompts
-- @bsb-block prompts@1 managed
-- @bsb-hash sha256:641caf320729eae1a25f6eb6ca47a50c988ee659b27f3d9a78e4c4905e7d513c
-- Versioned prompt templates by name, per tenant or for the whole system, with labels such as production that point at one version; only the service role reads and writes them.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."prompt_versions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."prompt_versions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."prompt_versions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."prompt_versions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."prompt_versions";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."prompt_labels";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."prompt_labels";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."prompt_labels";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."prompt_labels";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."prompt_labels";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Prompt templates the application versions by name, per tenant or for the
-- whole system (tenant is null). A version never changes once saved; a label
-- such as production points at one version. Templates can hold instructions
-- and secrets, so only the service role reads and writes them.
create table if not exists "better_supabase"."prompt_versions" (
  "id" uuid primary key default gen_random_uuid(),
  "workspace_id" uuid,
  "name" text not null check ("name" ~ '^[a-z0-9][a-z0-9_.:/-]{0,127}$'),
  "version" integer not null check ("version" >= 1),
  "template" text not null check (length("template") between 1 and 102400),
  "variables" jsonb not null default '[]'::jsonb check (jsonb_typeof("variables") = 'array'),
  "created_at" timestamptz not null default now()
);
create unique index if not exists "bsb_prompt_versions_key" on "better_supabase"."prompt_versions" ((coalesce("workspace_id"::text, '')), "name", "version");
create index if not exists "prompt_versions_tenant_idx" on "better_supabase"."prompt_versions" ("workspace_id");
alter table "better_supabase"."prompt_versions" enable row level security;
revoke all on "better_supabase"."prompt_versions" from public, anon, authenticated;
grant all on "better_supabase"."prompt_versions" to service_role;

create table if not exists "better_supabase"."prompt_labels" (
  "workspace_id" uuid,
  "name" text not null,
  "label" text not null check ("label" ~ '^[a-z0-9][a-z0-9_-]{0,63}$'),
  "version" integer not null check ("version" >= 1),
  "updated_at" timestamptz not null default now()
);
create unique index if not exists "bsb_prompt_labels_key" on "better_supabase"."prompt_labels" ((coalesce("workspace_id"::text, '')), "name", "label");
create index if not exists "prompt_labels_tenant_idx" on "better_supabase"."prompt_labels" ("workspace_id");
alter table "better_supabase"."prompt_labels" enable row level security;
revoke all on "better_supabase"."prompt_labels" from public, anon, authenticated;
grant all on "better_supabase"."prompt_labels" to service_role;

-- Creates template as the next version of name and returns it. A label moves to
-- the new version in the same call.
create or replace function "better_supabase"."create_prompt_version"(name text, template text, tenant uuid default null, variables jsonb default '[]'::jsonb, label text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."prompt_versions"%rowtype;
  v_next integer;
begin
  perform pg_advisory_xact_lock(hashtextextended(coalesce(create_prompt_version.tenant::text, '') || ':' || create_prompt_version.name, 0));
  select coalesce(max(x."version"), 0) + 1 into v_next from "better_supabase"."prompt_versions" x
  where coalesce(x."workspace_id"::text, '') = coalesce(create_prompt_version.tenant::text, '') and x."name" = create_prompt_version.name;
  insert into "better_supabase"."prompt_versions" ("workspace_id", "name", "version", "template", "variables")
  values (create_prompt_version.tenant, create_prompt_version.name, v_next, create_prompt_version.template, coalesce(create_prompt_version.variables, '[]'::jsonb))
  returning * into v_row;
  if create_prompt_version.label is not null then
    insert into "better_supabase"."prompt_labels" ("workspace_id", "name", "label", "version")
    values (create_prompt_version.tenant, create_prompt_version.name, create_prompt_version.label, v_next)
    on conflict ((coalesce("workspace_id"::text, '')), "name", "label") do update set
      "version" = excluded."version",
      "updated_at" = now();
  end if;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."workspace_id", 'name', v_row."name", 'version', v_row."version", 'template', v_row."template", 'variables', v_row."variables", 'created_at', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."create_prompt_version"(text, text, uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."create_prompt_version"(text, text, uuid, jsonb, text) to service_role;

-- The version of name that label (default production) points at, or the
-- exact version when one is given. A tenant's own prompt wins over the
-- system prompt of the same name. Null when there is none.
create or replace function "better_supabase"."get_prompt"(name text, label text default 'production', version integer default null, tenant uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."prompt_versions"%rowtype;
begin
  select x.* into v_row from "better_supabase"."prompt_versions" x
  where x."name" = get_prompt.name
    and (x."workspace_id" is null or x."workspace_id" = get_prompt.tenant)
    and (
      (get_prompt.version is not null and x."version" = get_prompt.version)
      or (get_prompt.version is null and exists (
        select 1 from "better_supabase"."prompt_labels" y
        where coalesce(y."workspace_id"::text, '') = coalesce(x."workspace_id"::text, '')
          and y."name" = x."name"
          and y."label" = get_prompt.label
          and y."version" = x."version"
      ))
    )
  order by (x."workspace_id" is null), x."version" desc
  limit 1;
  if not found then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."workspace_id", 'name', v_row."name", 'version', v_row."version", 'template', v_row."template", 'variables', v_row."variables", 'created_at', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."get_prompt"(text, text, integer, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."get_prompt"(text, text, integer, uuid) to service_role;

-- Points label at an existing version of name and returns the version.
create or replace function "better_supabase"."set_prompt_label"(name text, label text, version integer, tenant uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."prompt_versions"%rowtype;
begin
  select x.* into v_row from "better_supabase"."prompt_versions" x
  where x."name" = set_prompt_label.name
    and x."version" = set_prompt_label.version
    and coalesce(x."workspace_id"::text, '') = coalesce(set_prompt_label.tenant::text, '');
  if not found then
    raise exception 'No version % of prompt %', set_prompt_label.version, set_prompt_label.name using errcode = 'P0002', hint = 'PROMPT_NOT_FOUND';
  end if;
  insert into "better_supabase"."prompt_labels" ("workspace_id", "name", "label", "version")
  values (set_prompt_label.tenant, set_prompt_label.name, set_prompt_label.label, set_prompt_label.version)
  on conflict ((coalesce("workspace_id"::text, '')), "name", "label") do update set
    "version" = excluded."version",
    "updated_at" = now();
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."workspace_id", 'name', v_row."name", 'version', v_row."version", 'template', v_row."template", 'variables', v_row."variables", 'created_at', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."set_prompt_label"(text, text, integer, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."set_prompt_label"(text, text, integer, uuid) to service_role;

-- Every version of name for a tenant (or the system when tenant is null),
-- newest first, each with the labels that point at it.
create or replace function "better_supabase"."list_prompt_versions"(name text, tenant uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organization_id', x."workspace_id", 'name', x."name", 'version', x."version", 'template', x."template", 'variables', x."variables", 'created_at', x."created_at") || jsonb_build_object('labels', coalesce((
      select jsonb_agg(y."label" order by y."label") from "better_supabase"."prompt_labels" y
      where coalesce(y."workspace_id"::text, '') = coalesce(x."workspace_id"::text, '')
        and y."name" = x."name" and y."version" = x."version"
    ), '[]'::jsonb)) order by x."version" desc), '[]'::jsonb)
    from "better_supabase"."prompt_versions" x
    where x."name" = list_prompt_versions.name
      and coalesce(x."workspace_id"::text, '') = coalesce(list_prompt_versions.tenant::text, '')
  );
end;
$$;
revoke execute on function "better_supabase"."list_prompt_versions"(text, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."list_prompt_versions"(text, uuid) to service_role;

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

-- ==== data supabase/better-supabase-data/900_better_supabase_170_prompts.sql
-- better-supabase module: prompts
-- @bsb-block-data prompts
-- @bsb-hash sha256:6d90da15641b1eaef7619745e7292b6267b22f2a04096c5141bb18d15584c34e
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('prompts', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
