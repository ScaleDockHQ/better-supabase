-- better-supabase module: drive
-- @bsb-block-data drive
-- @bsb-hash sha256:23c2a6ccc1ffbc453bc0c6ede3924ce3127c7a0b62cd6d32fb6b49a0aec25820
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.drive_nodes', target_type => 'drive_node', event_prefix => 'drive_node', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('drive', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
