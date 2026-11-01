-- better-supabase module: pipelines
-- @bsb-block-data pipelines
-- @bsb-hash sha256:500735436af3b07e078f741b31c4b5cbfb52786b147142e567a3ddae0bcaa2bc
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.pipelines', target_type => 'pipeline', event_prefix => 'pipeline', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('pipelines', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
