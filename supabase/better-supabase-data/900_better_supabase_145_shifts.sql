-- better-supabase module: shifts
-- @bsb-block-data shifts
-- @bsb-hash sha256:90f5aab7632a746c32b6d54486dbf09cf6d9cca59b4a5844c8c43408530bed51
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "btree_gist" with schema "extensions";

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.shifts', target_type => 'shift', event_prefix => 'shift', deferred => true);
select better_supabase.audit('better_supabase.shift_templates', target_type => 'shift_template', event_prefix => 'shift_template', deferred => true);
select better_supabase.audit('better_supabase.shift_assignments', target_type => 'shift_assignment', event_prefix => 'shift_assignment', deferred => true);
select better_supabase.audit('better_supabase.shift_swaps', target_type => 'shift_swap', event_prefix => 'shift_swap', deferred => true);
select better_supabase.audit('better_supabase.shift_availability', target_type => 'shift_availability', event_prefix => 'shift_availability', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('shifts', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
