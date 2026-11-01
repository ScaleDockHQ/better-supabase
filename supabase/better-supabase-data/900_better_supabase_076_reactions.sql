-- better-supabase module: reactions
-- @bsb-block-data reactions
-- @bsb-hash sha256:cc19685ca3c64ff6c3e3e6de0c1ffd2193fc1c3d0f79cba5f8d00a7895f780e9
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.reactions', target_type => 'reaction', event_prefix => 'reaction', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('reactions', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
