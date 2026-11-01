-- better-supabase module: sequences
-- @bsb-block-data sequences
-- @bsb-hash sha256:0e7477ca878df5210bfd1b528e079ee325e6f14489c8545afd57d5ccd6de3db7
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.sequences', target_type => 'sequence', event_prefix => 'sequence', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('sequences', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
