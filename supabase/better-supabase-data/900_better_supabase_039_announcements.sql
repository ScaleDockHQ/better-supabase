-- better-supabase module: announcements
-- @bsb-block-data announcements
-- @bsb-hash sha256:a7c59a8035fae5fac0fb10bfed79e91e2989caf12ede2d22f941b3858b3a924e
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.announcements', target_type => 'announcement', event_prefix => 'announcement', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('announcements', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
