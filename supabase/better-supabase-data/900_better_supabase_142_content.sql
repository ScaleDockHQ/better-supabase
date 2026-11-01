-- better-supabase module: content
-- @bsb-block-data content
-- @bsb-hash sha256:76e708a61bdb9a4d609624df66659251b66685572dc7d3231d8f4f18cf2598a7
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.content_entries', target_type => 'content_entry', event_prefix => 'content_entry', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('content', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
