-- better-supabase module: donations
-- @bsb-block-data donations
-- @bsb-hash sha256:16f1acb7c5d7b4939d5b1ede742178ea14dc0129b25739202d47f15536f3710c
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.donations', target_type => 'donation', event_prefix => 'donation', deferred => true);
select better_supabase.audit('better_supabase.pledges', target_type => 'pledge', event_prefix => 'pledge', deferred => true);
select better_supabase.audit('better_supabase.donation_funds', target_type => 'donation_fund', event_prefix => 'donation_fund', deferred => true);
select better_supabase.audit('better_supabase.donation_receipts', target_type => 'donation_receipt', event_prefix => 'donation_receipt', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('donations', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
