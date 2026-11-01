-- better-supabase module: tills
-- @bsb-block-data tills
-- @bsb-hash sha256:5eddc235e69bc74f6e85f5e17ada478a7601a9e029516666989514d37c8fa306
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.tills', target_type => 'till', event_prefix => 'till', deferred => true);
select better_supabase.audit('better_supabase.till_sessions', target_type => 'till_session', event_prefix => 'till_session', deferred => true);
select better_supabase.audit('better_supabase.till_movements', target_type => 'till_movement', event_prefix => 'till_movement', deferred => true);
select better_supabase.audit('better_supabase.till_counts', target_type => 'till_count', event_prefix => 'till_count', deferred => true);
select better_supabase.audit('better_supabase.till_deposits', target_type => 'till_deposit', event_prefix => 'till_deposit', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('tills', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
