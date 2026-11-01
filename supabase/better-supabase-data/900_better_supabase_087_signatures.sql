-- better-supabase module: signatures
-- @bsb-block-data signatures
-- @bsb-hash sha256:fd9e09efd53e6f9147a8545444b2a1b699c830304cc7ff4adc37234d1976057a
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.signature_requests', target_type => 'signature_request', event_prefix => 'signature_request', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('signatures', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
