-- better-supabase module: teams
-- @bsb-block-data teams
-- @bsb-hash sha256:af0781564dfd49e1eea7753d2287f72934866bb6541918fb9238d95aae9fb425
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.teams', target_type => 'team', event_prefix => 'team', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('teams', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
