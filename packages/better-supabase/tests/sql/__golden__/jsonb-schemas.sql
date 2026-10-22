-- ==== alone: schema supabase/schemas/900_better_supabase_11_jsonb_schemas.sql
-- better-supabase module: jsonb-schemas
-- @bsb-block jsonb-schemas@1 managed
-- pg_jsonschema check constraints for jsonb columns with a `schema` in the `json` config, so the database enforces the same shape as the types. A trigger reports what failed through jsonschema_validation_errors, which the client maps to a validation error.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists pg_jsonschema with schema extensions;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

-- check_json_schema(column, schema[, where_column, where_value]) runs before the
-- check constraint of the same name and raises 23514 with the schema errors as
-- a JSON array in DETAIL and the hint JSON_SCHEMA_INVALID. A SQL null passes,
-- as it does for the check.
create or replace function better_supabase.check_json_schema()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  row_data jsonb := to_jsonb(new);
  value jsonb;
  errors text[];
begin
  if tg_nargs > 2 and row_data ->> tg_argv[2] is distinct from tg_argv[3] then
    return new;
  end if;
  value := row_data -> tg_argv[0];
  if value is null or jsonb_typeof(value) = 'null' then
    return new;
  end if;
  errors := extensions.jsonschema_validation_errors(tg_argv[1]::json, value::json);
  if cardinality(errors) > 0 then
    raise exception '%.% does not match its JSON Schema: %',
      tg_table_name, tg_argv[0], array_to_string(errors, '; ')
      using errcode = '23514',
        constraint = tg_name,
        schema = tg_table_schema,
        table = tg_table_name,
        column = tg_argv[0],
        detail = to_jsonb(errors)::text,
        hint = 'JSON_SCHEMA_INVALID';
  end if;
  return new;
end;
$$;

revoke execute on function better_supabase.check_json_schema() from public, anon, authenticated;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_11_jsonb_schemas.sql
-- better-supabase module: jsonb-schemas
-- @bsb-block-data jsonb-schemas
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "pg_jsonschema" with schema "extensions";

insert into better_supabase.blocks (name, version, mode)
values ('jsonb-schemas', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_11_jsonb_schemas.sql
-- better-supabase module: jsonb-schemas
-- @bsb-block jsonb-schemas@1 managed
-- pg_jsonschema check constraints for jsonb columns with a `schema` in the `json` config, so the database enforces the same shape as the types. A trigger reports what failed through jsonschema_validation_errors, which the client maps to a validation error.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists pg_jsonschema with schema extensions;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

-- check_json_schema(column, schema[, where_column, where_value]) runs before the
-- check constraint of the same name and raises 23514 with the schema errors as
-- a JSON array in DETAIL and the hint JSON_SCHEMA_INVALID. A SQL null passes,
-- as it does for the check.
create or replace function better_supabase.check_json_schema()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  row_data jsonb := to_jsonb(new);
  value jsonb;
  errors text[];
begin
  if tg_nargs > 2 and row_data ->> tg_argv[2] is distinct from tg_argv[3] then
    return new;
  end if;
  value := row_data -> tg_argv[0];
  if value is null or jsonb_typeof(value) = 'null' then
    return new;
  end if;
  errors := extensions.jsonschema_validation_errors(tg_argv[1]::json, value::json);
  if cardinality(errors) > 0 then
    raise exception '%.% does not match its JSON Schema: %',
      tg_table_name, tg_argv[0], array_to_string(errors, '; ')
      using errcode = '23514',
        constraint = tg_name,
        schema = tg_table_schema,
        table = tg_table_name,
        column = tg_argv[0],
        detail = to_jsonb(errors)::text,
        hint = 'JSON_SCHEMA_INVALID';
  end if;
  return new;
end;
$$;

revoke execute on function better_supabase.check_json_schema() from public, anon, authenticated;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_11_jsonb_schemas.sql
-- better-supabase module: jsonb-schemas
-- @bsb-block-data jsonb-schemas
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "pg_jsonschema" with schema "extensions";

insert into better_supabase.blocks (name, version, mode)
values ('jsonb-schemas', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_11_jsonb_schemas.sql
-- better-supabase module: jsonb-schemas
-- @bsb-block jsonb-schemas@1 managed
-- pg_jsonschema check constraints for jsonb columns with a `schema` in the `json` config, so the database enforces the same shape as the types. A trigger reports what failed through jsonschema_validation_errors, which the client maps to a validation error.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists pg_jsonschema with schema extensions;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

-- check_json_schema(column, schema[, where_column, where_value]) runs before the
-- check constraint of the same name and raises 23514 with the schema errors as
-- a JSON array in DETAIL and the hint JSON_SCHEMA_INVALID. A SQL null passes,
-- as it does for the check.
create or replace function better_supabase.check_json_schema()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  row_data jsonb := to_jsonb(new);
  value jsonb;
  errors text[];
begin
  if tg_nargs > 2 and row_data ->> tg_argv[2] is distinct from tg_argv[3] then
    return new;
  end if;
  value := row_data -> tg_argv[0];
  if value is null or jsonb_typeof(value) = 'null' then
    return new;
  end if;
  errors := extensions.jsonschema_validation_errors(tg_argv[1]::json, value::json);
  if cardinality(errors) > 0 then
    raise exception '%.% does not match its JSON Schema: %',
      tg_table_name, tg_argv[0], array_to_string(errors, '; ')
      using errcode = '23514',
        constraint = tg_name,
        schema = tg_table_schema,
        table = tg_table_name,
        column = tg_argv[0],
        detail = to_jsonb(errors)::text,
        hint = 'JSON_SCHEMA_INVALID';
  end if;
  return new;
end;
$$;

revoke execute on function better_supabase.check_json_schema() from public, anon, authenticated;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_11_jsonb_schemas.sql
-- better-supabase module: jsonb-schemas
-- @bsb-block-data jsonb-schemas
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "pg_jsonschema" with schema "extensions";

insert into better_supabase.blocks (name, version, mode)
values ('jsonb-schemas', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_11_jsonb_schemas.sql
-- better-supabase module: jsonb-schemas
-- @bsb-block jsonb-schemas@1 managed
-- pg_jsonschema check constraints for jsonb columns with a `schema` in the `json` config, so the database enforces the same shape as the types. A trigger reports what failed through jsonschema_validation_errors, which the client maps to a validation error.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists pg_jsonschema with schema extensions;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

-- check_json_schema(column, schema[, where_column, where_value]) runs before the
-- check constraint of the same name and raises 23514 with the schema errors as
-- a JSON array in DETAIL and the hint JSON_SCHEMA_INVALID. A SQL null passes,
-- as it does for the check.
create or replace function better_supabase.check_json_schema()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  row_data jsonb := to_jsonb(new);
  value jsonb;
  errors text[];
begin
  if tg_nargs > 2 and row_data ->> tg_argv[2] is distinct from tg_argv[3] then
    return new;
  end if;
  value := row_data -> tg_argv[0];
  if value is null or jsonb_typeof(value) = 'null' then
    return new;
  end if;
  errors := extensions.jsonschema_validation_errors(tg_argv[1]::json, value::json);
  if cardinality(errors) > 0 then
    raise exception '%.% does not match its JSON Schema: %',
      tg_table_name, tg_argv[0], array_to_string(errors, '; ')
      using errcode = '23514',
        constraint = tg_name,
        schema = tg_table_schema,
        table = tg_table_name,
        column = tg_argv[0],
        detail = to_jsonb(errors)::text,
        hint = 'JSON_SCHEMA_INVALID';
  end if;
  return new;
end;
$$;

revoke execute on function better_supabase.check_json_schema() from public, anon, authenticated;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_11_jsonb_schemas.sql
-- better-supabase module: jsonb-schemas
-- @bsb-block-data jsonb-schemas
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "pg_jsonschema" with schema "extensions";

insert into better_supabase.blocks (name, version, mode)
values ('jsonb-schemas', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
