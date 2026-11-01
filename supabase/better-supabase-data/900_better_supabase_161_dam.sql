-- better-supabase module: dam
-- @bsb-block-data dam
-- @bsb-hash sha256:07b7ff0a13da4c61ddfc371dcc06e2f965a1fc6c13c3f7e2901e9936582d93b6
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.dam_usage_rights', target_type => 'dam_usage_right', event_prefix => 'dam_usage_right', deferred => true);
select better_supabase.audit('better_supabase.dam_renditions', target_type => 'dam_rendition', event_prefix => 'dam_rendition', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('dam', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
