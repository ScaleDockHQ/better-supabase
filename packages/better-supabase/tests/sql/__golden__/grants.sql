-- ==== alone: schema supabase/schemas/900_better_supabase_013_grants.sql
-- better-supabase module: grants
-- @bsb-block grants@1 managed
-- @bsb-hash sha256:c43480db762ccd6d20d22b0e1281d0a61644087233118024f72206c1cbaae8dd
-- Writes the complete Data API privileges of the tables and functions in the `expose` config for anon, authenticated and service_role, or derives table grants from the policies. A project with default privileges turned off grants new tables to no Data API role.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- List tables and functions in `expose` (better-supabase.config.ts); `upgrade` rewrites the grants below.
-- Each listed table or function gets exactly the listed privileges: the rest is revoked.
-- RLS still decides which rows each role sees; grants decide whether the role reaches the table at all.

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_013_grants.sql
-- better-supabase module: grants
-- @bsb-block-data grants
-- @bsb-hash sha256:0ba55323e7817c5de5e92708f94298e2bd72c705930cd43976ed48b1cad04b56
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('grants', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_013_grants.sql
-- better-supabase module: grants
-- @bsb-block grants@1 managed
-- @bsb-hash sha256:c43480db762ccd6d20d22b0e1281d0a61644087233118024f72206c1cbaae8dd
-- Writes the complete Data API privileges of the tables and functions in the `expose` config for anon, authenticated and service_role, or derives table grants from the policies. A project with default privileges turned off grants new tables to no Data API role.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- List tables and functions in `expose` (better-supabase.config.ts); `upgrade` rewrites the grants below.
-- Each listed table or function gets exactly the listed privileges: the rest is revoked.
-- RLS still decides which rows each role sees; grants decide whether the role reaches the table at all.

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_013_grants.sql
-- better-supabase module: grants
-- @bsb-block-data grants
-- @bsb-hash sha256:0ba55323e7817c5de5e92708f94298e2bd72c705930cd43976ed48b1cad04b56
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('grants', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_013_grants.sql
-- better-supabase module: grants
-- @bsb-block grants@1 managed
-- @bsb-hash sha256:c43480db762ccd6d20d22b0e1281d0a61644087233118024f72206c1cbaae8dd
-- Writes the complete Data API privileges of the tables and functions in the `expose` config for anon, authenticated and service_role, or derives table grants from the policies. A project with default privileges turned off grants new tables to no Data API role.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- List tables and functions in `expose` (better-supabase.config.ts); `upgrade` rewrites the grants below.
-- Each listed table or function gets exactly the listed privileges: the rest is revoked.
-- RLS still decides which rows each role sees; grants decide whether the role reaches the table at all.

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_013_grants.sql
-- better-supabase module: grants
-- @bsb-block-data grants
-- @bsb-hash sha256:0ba55323e7817c5de5e92708f94298e2bd72c705930cd43976ed48b1cad04b56
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('grants', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_013_grants.sql
-- better-supabase module: grants
-- @bsb-block grants@1 managed
-- @bsb-hash sha256:c43480db762ccd6d20d22b0e1281d0a61644087233118024f72206c1cbaae8dd
-- Writes the complete Data API privileges of the tables and functions in the `expose` config for anon, authenticated and service_role, or derives table grants from the policies. A project with default privileges turned off grants new tables to no Data API role.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- List tables and functions in `expose` (better-supabase.config.ts); `upgrade` rewrites the grants below.
-- Each listed table or function gets exactly the listed privileges: the rest is revoked.
-- RLS still decides which rows each role sees; grants decide whether the role reaches the table at all.

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_013_grants.sql
-- better-supabase module: grants
-- @bsb-block-data grants
-- @bsb-hash sha256:0ba55323e7817c5de5e92708f94298e2bd72c705930cd43976ed48b1cad04b56
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('grants', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
