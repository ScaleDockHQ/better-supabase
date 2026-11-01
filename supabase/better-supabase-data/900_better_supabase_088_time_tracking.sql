-- better-supabase module: time-tracking
-- @bsb-block-data time-tracking
-- @bsb-hash sha256:c6d1cd3ca463ac0703d56fe4a6025fa8212d2c79603642dd75d9c94291e44ba3
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "btree_gist" with schema "extensions";

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.time_entries', target_type => 'time_entry', event_prefix => 'time_entry', deferred => true);
select better_supabase.audit('better_supabase.timesheets', target_type => 'timesheet', event_prefix => 'timesheet', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('time-tracking', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
