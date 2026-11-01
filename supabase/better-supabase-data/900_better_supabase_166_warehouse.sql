-- better-supabase module: warehouse
-- @bsb-block-data warehouse
-- @bsb-hash sha256:7eb84d3df10db098cffb1c8894901dc9a88b541c7746e636e271130607d3750e
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.pick_lists', target_type => 'pick_list', event_prefix => 'pick_list', deferred => true);
select better_supabase.audit('better_supabase.pick_waves', target_type => 'pick_wave', event_prefix => 'pick_wave', deferred => true);
select better_supabase.audit('better_supabase.pick_lines', target_type => 'pick_line', event_prefix => 'pick_line', deferred => true);
select better_supabase.audit('better_supabase.count_plans', target_type => 'count_plan', event_prefix => 'count_plan', deferred => true);
select better_supabase.audit('better_supabase.putaway_rules', target_type => 'putaway_rule', event_prefix => 'putaway_rule', deferred => true);
select better_supabase.audit('better_supabase.bin_slots', target_type => 'bin_slot', event_prefix => 'bin_slot', deferred => true);
select better_supabase.audit('better_supabase.variant_sizes', target_type => 'variant_size', event_prefix => 'variant_size', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('warehouse', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
