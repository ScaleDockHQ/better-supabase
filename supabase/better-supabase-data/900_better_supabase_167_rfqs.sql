-- better-supabase module: rfqs
-- @bsb-block-data rfqs
-- @bsb-hash sha256:7db726433f155e331334955c97aeedd219f47b8859c76f820b4923852ac240b1
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.rfqs', target_type => 'rfq', event_prefix => 'rfq', deferred => true);
select better_supabase.audit('better_supabase.rfq_lines', target_type => 'rfq_line', event_prefix => 'rfq_line', deferred => true);
select better_supabase.audit('better_supabase.rfq_suppliers', target_type => 'rfq_supplier', event_prefix => 'rfq_supplier', deferred => true);
select better_supabase.audit('better_supabase.rfq_quotes', target_type => 'rfq_quote', event_prefix => 'rfq_quote', deferred => true);
select better_supabase.audit('better_supabase.rfq_quote_lines', target_type => 'rfq_quote_line', event_prefix => 'rfq_quote_line', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('rfqs', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
