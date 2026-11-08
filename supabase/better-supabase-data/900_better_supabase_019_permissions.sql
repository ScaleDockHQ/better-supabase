-- better-supabase module: permissions
-- @bsb-block-data permissions
-- @bsb-hash sha256:316be62db73bdebd45f5bc4fb3dfe894446a4f49695c081142fb5b63b0bb4185
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- The roles every organization can assign: one row each for the database.
insert into "better_supabase"."roles" ("key", "scope")
select v.k, v.s
from (values ('owner', 'tenant'), ('admin', 'tenant'), ('member', 'tenant')) as v (k, s)
where not exists (select 1 from "better_supabase"."roles" x where x."key" = v.k);

insert into better_supabase.blocks (name, version, mode)
values ('permissions', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
