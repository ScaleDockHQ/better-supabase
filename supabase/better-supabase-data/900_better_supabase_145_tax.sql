-- better-supabase module: tax
-- @bsb-block-data tax
-- @bsb-hash sha256:f9d77d7101f4ad48002434ceb0f9c36b6daac7a217a7370f9673c6a8e2e8ce89
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.tax_codes', target_type => 'tax_code', event_prefix => 'tax_code', deferred => true);
select better_supabase.audit('better_supabase.tax_rates', target_type => 'tax_rate', event_prefix => 'tax_rate', deferred => true);
select better_supabase.audit('better_supabase.tax_returns', target_type => 'tax_return', event_prefix => 'tax_return', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('tax', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
