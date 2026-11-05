-- ==== alone: schema supabase/schemas/900_better_supabase_176_seeds.sql
-- better-supabase module: seeds
-- @bsb-block seeds@1 managed
-- @bsb-hash sha256:e3ee57f3e6959e24446ba9e0a5f861500727ced9dc9b4bbf23ff77b1e4ec2b8b
-- seed_tenant_defaults(tenant, variants, locale) applies the defaults every installed block declares, in install order. The organizations block calls it when an organization is created.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

-- Applies the defaults of every installed module to an organization. Call it
-- from the organization's create hook or with `better-supabase db seed --defaults`.
create or replace function "better_supabase".seed_tenant_defaults(p_tenant uuid, p_variants jsonb default '{}'::jsonb, p_locale text default 'en')
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  null;
end;
$$;
revoke execute on function "better_supabase".seed_tenant_defaults(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase".seed_tenant_defaults(uuid, jsonb, text) to service_role;

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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_176_seeds.sql
-- better-supabase module: seeds
-- @bsb-block-data seeds
-- @bsb-hash sha256:49123fe2bbaa6795eeef6340e266e39b99ae4c5a7e4063877a73cec726f8a194
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('seeds', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_176_seeds.sql
-- better-supabase module: seeds
-- @bsb-block seeds@1 managed
-- @bsb-hash sha256:221179289099a4d760f2469418b7c3b05202dae2334f9873ae23a57382f4f8b8
-- seed_tenant_defaults(tenant, variants, locale) applies the defaults every installed block declares, in install order. The organizations block calls it when an organization is created.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

-- Applies the defaults of every installed module to an organization. Call it
-- from the organization's create hook or with `better-supabase db seed --defaults`.
create or replace function "better_supabase".seed_tenant_defaults(p_tenant uuid, p_variants jsonb default '{}'::jsonb, p_locale text default 'en')
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform "better_supabase"."seed_attachments_defaults"(p_tenant, p_variants ->> 'attachments', p_locale);
  perform "better_supabase"."seed_inbox_defaults"(p_tenant, p_variants ->> 'inbox', p_locale);
  perform "better_supabase"."seed_calendar_defaults"(p_tenant, p_variants ->> 'calendar', p_locale);
  perform "better_supabase"."seed_cases_defaults"(p_tenant, p_variants ->> 'cases', p_locale);
  perform "better_supabase"."seed_pipelines_defaults"(p_tenant, p_variants ->> 'pipelines', p_locale);
  perform "better_supabase"."seed_leave_defaults"(p_tenant, p_variants ->> 'leave', p_locale);
  perform "better_supabase"."seed_risks_defaults"(p_tenant, p_variants ->> 'risks', p_locale);
  perform "better_supabase"."seed_tax_defaults"(p_tenant, p_variants ->> 'tax', p_locale);
  perform "better_supabase"."seed_accounting_defaults"(p_tenant, p_variants ->> 'accounting', p_locale);
end;
$$;
revoke execute on function "better_supabase".seed_tenant_defaults(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase".seed_tenant_defaults(uuid, jsonb, text) to service_role;

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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_176_seeds.sql
-- better-supabase module: seeds
-- @bsb-block-data seeds
-- @bsb-hash sha256:49123fe2bbaa6795eeef6340e266e39b99ae4c5a7e4063877a73cec726f8a194
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('seeds', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_176_seeds.sql
-- better-supabase module: seeds
-- @bsb-block seeds@1 managed
-- @bsb-hash sha256:0a1703e05ed5bb3ba04f37f93aa84f7840a962201c62d8099de83ff05dacba60
-- seed_tenant_defaults(tenant, variants, locale) applies the defaults every installed block declares, in install order. The organizations block calls it when an organization is created.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on functions from public, anon, authenticated;

-- Applies the defaults of every installed module to an organization. Call it
-- from the organization's create hook or with `better-supabase db seed --defaults`.
create or replace function "app_private".seed_tenant_defaults(p_tenant uuid, p_variants jsonb default '{}'::jsonb, p_locale text default 'en')
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  null;
end;
$$;
revoke execute on function "app_private".seed_tenant_defaults(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "app_private".seed_tenant_defaults(uuid, jsonb, text) to service_role;

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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_176_seeds.sql
-- better-supabase module: seeds
-- @bsb-block-data seeds
-- @bsb-hash sha256:49123fe2bbaa6795eeef6340e266e39b99ae4c5a7e4063877a73cec726f8a194
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('seeds', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_176_seeds.sql
-- better-supabase module: seeds
-- @bsb-block seeds@1 managed
-- @bsb-hash sha256:fd494a762b8cc8a5f67e34d98a73b3347cd2ad176f09c49b88e4ba0681166349
-- seed_tenant_defaults(tenant, variants, locale) applies the defaults every installed block declares, in install order. The organizations block calls it when an organization is created.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

-- Applies the defaults of every installed module to an organization. Call it
-- from the organization's create hook or with `better-supabase db seed --defaults`.
create or replace function "better_supabase".seed_tenant_defaults(p_tenant uuid, p_variants jsonb default '{}'::jsonb, p_locale text default 'en')
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  null;
end;
$$;
revoke execute on function "better_supabase".seed_tenant_defaults(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase".seed_tenant_defaults(uuid, jsonb, text) to service_role;

-- blocks.seeds.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."seed_tenant_defaults"(p_tenant uuid, p_variants jsonb default '{}'::jsonb, p_locale text default 'en')
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."seed_tenant_defaults"($1, $2, $3) $$;
revoke execute on function "api"."seed_tenant_defaults"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "api"."seed_tenant_defaults"(uuid, jsonb, text) to service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_176_seeds.sql
-- better-supabase module: seeds
-- @bsb-block-data seeds
-- @bsb-hash sha256:49123fe2bbaa6795eeef6340e266e39b99ae4c5a7e4063877a73cec726f8a194
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('seeds', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
