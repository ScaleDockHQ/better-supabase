-- better-supabase module: banking
-- @bsb-block-data banking
-- @bsb-hash sha256:a723e247d390d739daca9a78934d908a2a7603e82973f63a373b10fc0abbef13
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.bank_transactions', target_type => 'bank_transaction', event_prefix => 'bank_transaction', deferred => true);
select better_supabase.audit('better_supabase.bank_accounts', target_type => 'bank_account', event_prefix => 'bank_account', deferred => true);
select better_supabase.audit('better_supabase.bank_statements', target_type => 'bank_statement', event_prefix => 'bank_statement', deferred => true);
select better_supabase.audit('better_supabase.bank_matches', target_type => 'bank_match', event_prefix => 'bank_match', deferred => true);
select better_supabase.audit('better_supabase.bank_rules', target_type => 'bank_rule', event_prefix => 'bank_rule', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('banking', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
