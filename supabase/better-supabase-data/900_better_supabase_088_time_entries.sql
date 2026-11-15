-- better-supabase module: time-entries
-- @bsb-block-data time-entries
-- @bsb-hash sha256:f85ff49e3b22289036c5d7c2dc2d3e6a0e5277a0eb522b1451ced706e9f0828e
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "btree_gist" with schema "extensions";

delete from better_supabase.blocks
  where name = 'time-tracking'
    and exists (select 1 from better_supabase.blocks where name = 'time-entries');
update better_supabase.blocks set name = 'time-entries'
  where name = 'time-tracking'
    and not exists (select 1 from better_supabase.blocks where name = 'time-entries');
insert into better_supabase.blocks (name, version, mode)
values ('time-entries', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
