-- better-supabase module: moderation
-- @bsb-block-data moderation
-- @bsb-hash sha256:755a622e513363a5ad764ac2121afcc8138e5ff9fc3e1233cda4714f79881159
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.moderation_items', target_type => 'moderation_item', event_prefix => 'moderation_item', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('moderation', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
