-- better-supabase module: deals
-- @bsb-block-data deals
-- @bsb-hash sha256:49c83bad4d4b53c4051e1d5ebc7fefa63bd25abd0c9109519f21f622fd4aed58
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.deals', target_type => 'deal', event_prefix => 'deal', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('deals', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
