-- ==== alone: schema supabase/schemas/900_better_supabase_13_grants.sql
-- better-supabase module: grants
-- @bs-module grants@1 managed
-- Writes the complete Data API privileges of the tables and functions in the `expose` config for anon, authenticated and service_role, or derives table grants from the policies. Supabase no longer grants new tables to the Data API roles automatically.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

-- List tables and functions in `expose` (better-supabase.config.ts); `sql sync` rewrites the grants below.
-- Each listed table or function gets exactly the listed privileges: the rest is revoked.
-- RLS still decides which rows each role sees; grants decide whether the role reaches the table at all.

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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_13_grants.sql
-- better-supabase module: grants
-- @bs-module-data grants
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('grants', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_13_grants.sql
-- better-supabase module: grants
-- @bs-module grants@1 managed
-- Writes the complete Data API privileges of the tables and functions in the `expose` config for anon, authenticated and service_role, or derives table grants from the policies. Supabase no longer grants new tables to the Data API roles automatically.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

-- List tables and functions in `expose` (better-supabase.config.ts); `sql sync` rewrites the grants below.
-- Each listed table or function gets exactly the listed privileges: the rest is revoked.
-- RLS still decides which rows each role sees; grants decide whether the role reaches the table at all.

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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_13_grants.sql
-- better-supabase module: grants
-- @bs-module-data grants
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('grants', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_13_grants.sql
-- better-supabase module: grants
-- @bs-module grants@1 managed
-- Writes the complete Data API privileges of the tables and functions in the `expose` config for anon, authenticated and service_role, or derives table grants from the policies. Supabase no longer grants new tables to the Data API roles automatically.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

-- List tables and functions in `expose` (better-supabase.config.ts); `sql sync` rewrites the grants below.
-- Each listed table or function gets exactly the listed privileges: the rest is revoked.
-- RLS still decides which rows each role sees; grants decide whether the role reaches the table at all.

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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_13_grants.sql
-- better-supabase module: grants
-- @bs-module-data grants
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('grants', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_13_grants.sql
-- better-supabase module: grants
-- @bs-module grants@1 managed
-- Writes the complete Data API privileges of the tables and functions in the `expose` config for anon, authenticated and service_role, or derives table grants from the policies. Supabase no longer grants new tables to the Data API roles automatically.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

-- List tables and functions in `expose` (better-supabase.config.ts); `sql sync` rewrites the grants below.
-- Each listed table or function gets exactly the listed privileges: the rest is revoked.
-- RLS still decides which rows each role sees; grants decide whether the role reaches the table at all.

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_13_grants.sql
-- better-supabase module: grants
-- @bs-module-data grants
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('grants', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
