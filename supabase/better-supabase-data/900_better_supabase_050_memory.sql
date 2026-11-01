-- better-supabase module: memory
-- @bsb-block-data memory
-- @bsb-hash sha256:8fa217c66b59ec0ddeaadbd7b7660889e297fd1a5bbe3c8940422f04d358c450
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.memories', target_type => 'memory', event_prefix => 'memory', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('memory', 5, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
