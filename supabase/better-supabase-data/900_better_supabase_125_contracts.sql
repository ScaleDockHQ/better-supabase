-- better-supabase module: contracts
-- @bsb-block-data contracts
-- @bsb-hash sha256:6f10c53545266be5593649485dde39b4db4206bfd269e0e2508052992a5cfc9f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.contracts', target_type => 'contract', event_prefix => 'contract', deferred => true);
select better_supabase.audit('better_supabase.contract_obligations', target_type => 'contract_obligation', event_prefix => 'contract_obligation', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('contracts', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
