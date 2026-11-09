-- better-supabase module: time-entries
-- @bsb-block-data time-entries
-- @bsb-hash sha256:04ad8678759e0c6a8aeac364974d74d2c8d1ac906659d266f388a426a6a63345
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "btree_gist" with schema "extensions";

update better_supabase.blocks set name = 'time-entries'
  where name = 'time-tracking'
    and not exists (select 1 from better_supabase.blocks where name = 'time-entries');
insert into better_supabase.blocks (name, version, mode)
values ('time-entries', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
