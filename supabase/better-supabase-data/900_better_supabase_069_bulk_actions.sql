-- better-supabase module: bulk-actions
-- @bsb-block-data bulk-actions
-- @bsb-hash sha256:c992fa8d4fb0cbcfc96dc022a0825a34f22cc4b24cefeab3d2d1cdc1c1ee15ce
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

delete from better_supabase.blocks
  where name = 'bulk'
    and exists (select 1 from better_supabase.blocks where name = 'bulk-actions');
update better_supabase.blocks set name = 'bulk-actions'
  where name = 'bulk'
    and not exists (select 1 from better_supabase.blocks where name = 'bulk-actions');
insert into better_supabase.blocks (name, version, mode)
values ('bulk-actions', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
