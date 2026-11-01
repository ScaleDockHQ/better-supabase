-- better-supabase module: acknowledgements
-- @bsb-block-data acknowledgements
-- @bsb-hash sha256:a85a51f7724de98242442b4d1689c9d37875253e10b13364a40f59d91ae5c0a5
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.acknowledgements', target_type => 'acknowledgement', event_prefix => 'acknowledgement', deferred => true);
select better_supabase.audit('better_supabase.acknowledgement_assignments', target_type => 'acknowledgement_assignment', event_prefix => 'acknowledgement_assignment', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('acknowledgements', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
