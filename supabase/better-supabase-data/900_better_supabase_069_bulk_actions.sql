-- better-supabase module: bulk-actions
-- @bsb-block-data bulk-actions
-- @bsb-hash sha256:04e5d6184660b4a59fe93acb078e4b2450346622dba3a9bcdb44ba3f8f87a14a
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

update better_supabase.blocks set name = 'bulk-actions'
  where name = 'bulk'
    and not exists (select 1 from better_supabase.blocks where name = 'bulk-actions');
insert into better_supabase.blocks (name, version, mode)
values ('bulk-actions', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
