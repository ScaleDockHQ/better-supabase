-- better-supabase module: funding
-- @bsb-block-data funding
-- @bsb-hash sha256:a6a2308f7e3ee5c5c7351fa0895f6e71538e61a77d2f2ea798d4b4306098a07d
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.funding_products', target_type => 'funding_product', event_prefix => 'funding_product', deferred => true);
select better_supabase.audit('better_supabase.funding_awards', target_type => 'funding_award', event_prefix => 'funding_award', deferred => true);
select better_supabase.audit('better_supabase.funding_deliveries', target_type => 'funding_delivery', event_prefix => 'funding_delivery', deferred => true);
select better_supabase.audit('better_supabase.funding_claims', target_type => 'funding_claim', event_prefix => 'funding_claim', deferred => true);
select better_supabase.audit('better_supabase.funding_claim_lines', target_type => 'funding_claim_line', event_prefix => 'funding_claim_line', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('funding', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
