-- ==== alone: schema supabase/schemas/900_better_supabase_74_ensure_rls.sql
-- better-supabase module: ensure-rls
-- @bs-module ensure-rls@1 managed
-- An event trigger that enables row level security on every table created outside the Supabase-managed schemas, so a new table is never readable through the Data API before it has policies. Install it as postgres: supautils lets that role create event triggers.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

-- Runs after CREATE TABLE, CREATE TABLE AS and SELECT INTO. A table without
-- policies then denies every API role until you add one.
create or replace function better_supabase.enable_rls_on_new_table()
returns event_trigger
language plpgsql
set search_path = ''
as $$
declare
  command record;
begin
  for command in
    select objid, schema_name
    from pg_event_trigger_ddl_commands()
    where object_type = 'table'
      and command_tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
  loop
    continue when command.schema_name in ('auth', 'storage', 'realtime', '_realtime', '_analytics', 'extensions', 'graphql', 'graphql_public', 'vault', 'pgsodium', 'pgsodium_masks', 'net', 'cron', 'pgbouncer', 'supabase_functions', 'supabase_migrations', 'information_schema')
      or command.schema_name like 'pg\_%';
    execute format('alter table %s enable row level security', command.objid::regclass);
  end loop;
end;
$$;

revoke execute on function better_supabase.enable_rls_on_new_table() from public, anon, authenticated;

drop event trigger if exists bs_ensure_rls;
create event trigger bs_ensure_rls on ddl_command_end
  when tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
  execute function better_supabase.enable_rls_on_new_table();

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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_74_ensure_rls.sql
-- better-supabase module: ensure-rls
-- @bs-module-data ensure-rls
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

drop event trigger if exists bs_ensure_rls;
create event trigger bs_ensure_rls on ddl_command_end
  when tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
  execute function better_supabase.enable_rls_on_new_table();

insert into better_supabase.modules (name, version, mode)
values ('ensure-rls', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_74_ensure_rls.sql
-- better-supabase module: ensure-rls
-- @bs-module ensure-rls@1 managed
-- An event trigger that enables row level security on every table created outside the Supabase-managed schemas, so a new table is never readable through the Data API before it has policies. Install it as postgres: supautils lets that role create event triggers.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

-- Runs after CREATE TABLE, CREATE TABLE AS and SELECT INTO. A table without
-- policies then denies every API role until you add one.
create or replace function better_supabase.enable_rls_on_new_table()
returns event_trigger
language plpgsql
set search_path = ''
as $$
declare
  command record;
begin
  for command in
    select objid, schema_name
    from pg_event_trigger_ddl_commands()
    where object_type = 'table'
      and command_tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
  loop
    continue when command.schema_name in ('auth', 'storage', 'realtime', '_realtime', '_analytics', 'extensions', 'graphql', 'graphql_public', 'vault', 'pgsodium', 'pgsodium_masks', 'net', 'cron', 'pgbouncer', 'supabase_functions', 'supabase_migrations', 'information_schema')
      or command.schema_name like 'pg\_%';
    execute format('alter table %s enable row level security', command.objid::regclass);
  end loop;
end;
$$;

revoke execute on function better_supabase.enable_rls_on_new_table() from public, anon, authenticated;

drop event trigger if exists bs_ensure_rls;
create event trigger bs_ensure_rls on ddl_command_end
  when tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
  execute function better_supabase.enable_rls_on_new_table();

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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_74_ensure_rls.sql
-- better-supabase module: ensure-rls
-- @bs-module-data ensure-rls
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

drop event trigger if exists bs_ensure_rls;
create event trigger bs_ensure_rls on ddl_command_end
  when tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
  execute function better_supabase.enable_rls_on_new_table();

insert into better_supabase.modules (name, version, mode)
values ('ensure-rls', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_74_ensure_rls.sql
-- better-supabase module: ensure-rls
-- @bs-module ensure-rls@1 managed
-- An event trigger that enables row level security on every table created outside the Supabase-managed schemas, so a new table is never readable through the Data API before it has policies. Install it as postgres: supautils lets that role create event triggers.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

-- Runs after CREATE TABLE, CREATE TABLE AS and SELECT INTO. A table without
-- policies then denies every API role until you add one.
create or replace function better_supabase.enable_rls_on_new_table()
returns event_trigger
language plpgsql
set search_path = ''
as $$
declare
  command record;
begin
  for command in
    select objid, schema_name
    from pg_event_trigger_ddl_commands()
    where object_type = 'table'
      and command_tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
  loop
    continue when command.schema_name in ('auth', 'storage', 'realtime', '_realtime', '_analytics', 'extensions', 'graphql', 'graphql_public', 'vault', 'pgsodium', 'pgsodium_masks', 'net', 'cron', 'pgbouncer', 'supabase_functions', 'supabase_migrations', 'information_schema')
      or command.schema_name like 'pg\_%';
    execute format('alter table %s enable row level security', command.objid::regclass);
  end loop;
end;
$$;

revoke execute on function better_supabase.enable_rls_on_new_table() from public, anon, authenticated;

drop event trigger if exists bs_ensure_rls;
create event trigger bs_ensure_rls on ddl_command_end
  when tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
  execute function better_supabase.enable_rls_on_new_table();

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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_74_ensure_rls.sql
-- better-supabase module: ensure-rls
-- @bs-module-data ensure-rls
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

drop event trigger if exists bs_ensure_rls;
create event trigger bs_ensure_rls on ddl_command_end
  when tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
  execute function better_supabase.enable_rls_on_new_table();

insert into better_supabase.modules (name, version, mode)
values ('ensure-rls', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_74_ensure_rls.sql
-- better-supabase module: ensure-rls
-- @bs-module ensure-rls@1 managed
-- An event trigger that enables row level security on every table created outside the Supabase-managed schemas, so a new table is never readable through the Data API before it has policies. Install it as postgres: supautils lets that role create event triggers.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

-- Runs after CREATE TABLE, CREATE TABLE AS and SELECT INTO. A table without
-- policies then denies every API role until you add one.
create or replace function better_supabase.enable_rls_on_new_table()
returns event_trigger
language plpgsql
set search_path = ''
as $$
declare
  command record;
begin
  for command in
    select objid, schema_name
    from pg_event_trigger_ddl_commands()
    where object_type = 'table'
      and command_tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
  loop
    continue when command.schema_name in ('auth', 'storage', 'realtime', '_realtime', '_analytics', 'extensions', 'graphql', 'graphql_public', 'vault', 'pgsodium', 'pgsodium_masks', 'net', 'cron', 'pgbouncer', 'supabase_functions', 'supabase_migrations', 'information_schema')
      or command.schema_name like 'pg\_%';
    execute format('alter table %s enable row level security', command.objid::regclass);
  end loop;
end;
$$;

revoke execute on function better_supabase.enable_rls_on_new_table() from public, anon, authenticated;

drop event trigger if exists bs_ensure_rls;
create event trigger bs_ensure_rls on ddl_command_end
  when tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
  execute function better_supabase.enable_rls_on_new_table();

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_74_ensure_rls.sql
-- better-supabase module: ensure-rls
-- @bs-module-data ensure-rls
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

drop event trigger if exists bs_ensure_rls;
create event trigger bs_ensure_rls on ddl_command_end
  when tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
  execute function better_supabase.enable_rls_on_new_table();

insert into better_supabase.modules (name, version, mode)
values ('ensure-rls', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
