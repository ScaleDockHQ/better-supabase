-- ==== alone: schema supabase/schemas/900_better_supabase_176_seeds.sql
-- better-supabase module: seeds
-- @bsb-block seeds@1 managed
-- @bsb-hash sha256:1e4cce5facffe816a70a06feeaaa9923d75ac0088ae86054faa36ca30bbd829d
-- seed_tenant_defaults(tenant, variants, locale) applies the defaults every installed block declares, in install order. The organizations block calls it when an organization is created.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

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
-- @bsb-hash sha256:95c8de0ce76682a5330244a932e580bb0aada3d5a22a9700cda1e29274f636c8
-- seed_tenant_defaults(tenant, variants, locale) applies the defaults every installed block declares, in install order. The organizations block calls it when an organization is created.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

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
  perform "better_supabase"."seed_document_templates_defaults"(p_tenant, p_variants ->> 'document-templates', p_locale);
end;
$$;
revoke execute on function "better_supabase".seed_tenant_defaults(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase".seed_tenant_defaults(uuid, jsonb, text) to service_role;

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
-- @bsb-hash sha256:bfd9e24aa5d6e598905f8fa7cb3198fc0c5d4c0e1f2fa950a9c045c3806188f2
-- seed_tenant_defaults(tenant, variants, locale) applies the defaults every installed block declares, in install order. The organizations block calls it when an organization is created.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

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
-- @bsb-hash sha256:f73419376142d3a8774db1c0d59700521b0dc2d0461ac1a391671af6ec323398
-- seed_tenant_defaults(tenant, variants, locale) applies the defaults every installed block declares, in install order. The organizations block calls it when an organization is created.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

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
