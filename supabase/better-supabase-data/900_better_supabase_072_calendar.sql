-- better-supabase module: calendar
-- @bsb-block-data calendar
-- @bsb-hash sha256:4d8dd7e441db819c4e13867c386a86b4100e19b62d27e6ee55671c376504be23
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.calendar_events', target_type => 'calendar_event', event_prefix => 'calendar_event', deferred => true);
select better_supabase.audit('better_supabase.calendars', target_type => 'calendar', event_prefix => 'calendar', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('calendar', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
