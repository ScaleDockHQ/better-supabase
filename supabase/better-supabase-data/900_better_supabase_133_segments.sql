-- better-supabase module: segments
-- @bsb-block-data segments
-- @bsb-hash sha256:5efc77b1fec9aad8da02903f7301a28f486b846f3843ad99bdea56930fe19acd
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.segments', target_type => 'segment', event_prefix => 'segment', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('segments', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
