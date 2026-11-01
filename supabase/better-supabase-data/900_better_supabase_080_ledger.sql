-- better-supabase module: ledger
-- @bsb-block-data ledger
-- @bsb-hash sha256:90addac4d2e916c61bfa5c0644276aa3b3f57e3c2d62590a1b387072a2a47a30
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.ledger_accounts', target_type => 'ledger_account', event_prefix => 'ledger_account', deferred => true);
select better_supabase.audit('better_supabase.ledger_transactions', target_type => 'ledger_transaction', event_prefix => 'ledger_transaction', deferred => true);
select better_supabase.audit('better_supabase.ledger_holds', target_type => 'ledger_hold', event_prefix => 'ledger_hold', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('ledger', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
