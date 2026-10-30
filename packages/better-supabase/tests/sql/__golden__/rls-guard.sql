-- ==== alone: schema supabase/schemas/900_better_supabase_153_rls_guard.sql
-- better-supabase module: rls-guard
-- @bsb-block rls-guard@1 managed
-- @bsb-hash sha256:d32966f654bb5088310207bf84e3fad61a5e6f56c1bc7f6c3e852dfce05a6cfc
-- An event trigger that enables row level security on every table created outside the Supabase-managed schemas, so a new table is never readable through the Data API before it has policies. Install it as postgres: supautils lets that role create event triggers.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

-- Runs after CREATE TABLE, CREATE TABLE AS and SELECT INTO, and after an
-- ALTER TABLE that turned row level security off. A table without policies
-- then denies every API role until you add one.
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
      and command_tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO', 'ALTER TABLE')
  loop
    continue when command.schema_name in ('auth', 'storage', 'realtime', '_realtime', '_analytics', 'extensions', 'graphql', 'graphql_public', 'vault', 'pgsodium', 'pgsodium_masks', 'net', 'cron', 'pgbouncer', 'supabase_functions', 'supabase_migrations', 'information_schema')
      or command.schema_name like 'pg\_%';
    continue when exists (
      select 1 from pg_catalog.pg_class
      where oid = command.objid and relrowsecurity
    );
    execute format('alter table %s enable row level security', command.objid::regclass);
  end loop;
end;
$$;

revoke execute on function better_supabase.enable_rls_on_new_table() from public, anon, authenticated;

drop event trigger if exists bsb_ensure_rls;
create event trigger bsb_ensure_rls on ddl_command_end
  when tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO', 'ALTER TABLE')
  execute function better_supabase.enable_rls_on_new_table();

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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_153_rls_guard.sql
-- better-supabase module: rls-guard
-- @bsb-block-data rls-guard
-- @bsb-hash sha256:b20ee84ae3af8ffef11d625c16a0408f5a38ede4b92c843bdac1e5460d517399
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

drop event trigger if exists bsb_ensure_rls;
create event trigger bsb_ensure_rls on ddl_command_end
  when tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO', 'ALTER TABLE')
  execute function better_supabase.enable_rls_on_new_table();

insert into better_supabase.blocks (name, version, mode)
values ('rls-guard', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_153_rls_guard.sql
-- better-supabase module: rls-guard
-- @bsb-block rls-guard@1 managed
-- @bsb-hash sha256:d32966f654bb5088310207bf84e3fad61a5e6f56c1bc7f6c3e852dfce05a6cfc
-- An event trigger that enables row level security on every table created outside the Supabase-managed schemas, so a new table is never readable through the Data API before it has policies. Install it as postgres: supautils lets that role create event triggers.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

-- Runs after CREATE TABLE, CREATE TABLE AS and SELECT INTO, and after an
-- ALTER TABLE that turned row level security off. A table without policies
-- then denies every API role until you add one.
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
      and command_tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO', 'ALTER TABLE')
  loop
    continue when command.schema_name in ('auth', 'storage', 'realtime', '_realtime', '_analytics', 'extensions', 'graphql', 'graphql_public', 'vault', 'pgsodium', 'pgsodium_masks', 'net', 'cron', 'pgbouncer', 'supabase_functions', 'supabase_migrations', 'information_schema')
      or command.schema_name like 'pg\_%';
    continue when exists (
      select 1 from pg_catalog.pg_class
      where oid = command.objid and relrowsecurity
    );
    execute format('alter table %s enable row level security', command.objid::regclass);
  end loop;
end;
$$;

revoke execute on function better_supabase.enable_rls_on_new_table() from public, anon, authenticated;

drop event trigger if exists bsb_ensure_rls;
create event trigger bsb_ensure_rls on ddl_command_end
  when tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO', 'ALTER TABLE')
  execute function better_supabase.enable_rls_on_new_table();

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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_153_rls_guard.sql
-- better-supabase module: rls-guard
-- @bsb-block-data rls-guard
-- @bsb-hash sha256:b20ee84ae3af8ffef11d625c16a0408f5a38ede4b92c843bdac1e5460d517399
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

drop event trigger if exists bsb_ensure_rls;
create event trigger bsb_ensure_rls on ddl_command_end
  when tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO', 'ALTER TABLE')
  execute function better_supabase.enable_rls_on_new_table();

insert into better_supabase.blocks (name, version, mode)
values ('rls-guard', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_153_rls_guard.sql
-- better-supabase module: rls-guard
-- @bsb-block rls-guard@1 managed
-- @bsb-hash sha256:d32966f654bb5088310207bf84e3fad61a5e6f56c1bc7f6c3e852dfce05a6cfc
-- An event trigger that enables row level security on every table created outside the Supabase-managed schemas, so a new table is never readable through the Data API before it has policies. Install it as postgres: supautils lets that role create event triggers.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

-- Runs after CREATE TABLE, CREATE TABLE AS and SELECT INTO, and after an
-- ALTER TABLE that turned row level security off. A table without policies
-- then denies every API role until you add one.
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
      and command_tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO', 'ALTER TABLE')
  loop
    continue when command.schema_name in ('auth', 'storage', 'realtime', '_realtime', '_analytics', 'extensions', 'graphql', 'graphql_public', 'vault', 'pgsodium', 'pgsodium_masks', 'net', 'cron', 'pgbouncer', 'supabase_functions', 'supabase_migrations', 'information_schema')
      or command.schema_name like 'pg\_%';
    continue when exists (
      select 1 from pg_catalog.pg_class
      where oid = command.objid and relrowsecurity
    );
    execute format('alter table %s enable row level security', command.objid::regclass);
  end loop;
end;
$$;

revoke execute on function better_supabase.enable_rls_on_new_table() from public, anon, authenticated;

drop event trigger if exists bsb_ensure_rls;
create event trigger bsb_ensure_rls on ddl_command_end
  when tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO', 'ALTER TABLE')
  execute function better_supabase.enable_rls_on_new_table();

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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_153_rls_guard.sql
-- better-supabase module: rls-guard
-- @bsb-block-data rls-guard
-- @bsb-hash sha256:b20ee84ae3af8ffef11d625c16a0408f5a38ede4b92c843bdac1e5460d517399
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

drop event trigger if exists bsb_ensure_rls;
create event trigger bsb_ensure_rls on ddl_command_end
  when tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO', 'ALTER TABLE')
  execute function better_supabase.enable_rls_on_new_table();

insert into better_supabase.blocks (name, version, mode)
values ('rls-guard', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_153_rls_guard.sql
-- better-supabase module: rls-guard
-- @bsb-block rls-guard@1 managed
-- @bsb-hash sha256:d32966f654bb5088310207bf84e3fad61a5e6f56c1bc7f6c3e852dfce05a6cfc
-- An event trigger that enables row level security on every table created outside the Supabase-managed schemas, so a new table is never readable through the Data API before it has policies. Install it as postgres: supautils lets that role create event triggers.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

-- Runs after CREATE TABLE, CREATE TABLE AS and SELECT INTO, and after an
-- ALTER TABLE that turned row level security off. A table without policies
-- then denies every API role until you add one.
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
      and command_tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO', 'ALTER TABLE')
  loop
    continue when command.schema_name in ('auth', 'storage', 'realtime', '_realtime', '_analytics', 'extensions', 'graphql', 'graphql_public', 'vault', 'pgsodium', 'pgsodium_masks', 'net', 'cron', 'pgbouncer', 'supabase_functions', 'supabase_migrations', 'information_schema')
      or command.schema_name like 'pg\_%';
    continue when exists (
      select 1 from pg_catalog.pg_class
      where oid = command.objid and relrowsecurity
    );
    execute format('alter table %s enable row level security', command.objid::regclass);
  end loop;
end;
$$;

revoke execute on function better_supabase.enable_rls_on_new_table() from public, anon, authenticated;

drop event trigger if exists bsb_ensure_rls;
create event trigger bsb_ensure_rls on ddl_command_end
  when tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO', 'ALTER TABLE')
  execute function better_supabase.enable_rls_on_new_table();

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_153_rls_guard.sql
-- better-supabase module: rls-guard
-- @bsb-block-data rls-guard
-- @bsb-hash sha256:b20ee84ae3af8ffef11d625c16a0408f5a38ede4b92c843bdac1e5460d517399
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

drop event trigger if exists bsb_ensure_rls;
create event trigger bsb_ensure_rls on ddl_command_end
  when tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO', 'ALTER TABLE')
  execute function better_supabase.enable_rls_on_new_table();

insert into better_supabase.blocks (name, version, mode)
values ('rls-guard', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
