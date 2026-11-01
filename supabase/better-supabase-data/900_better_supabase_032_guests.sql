-- better-supabase module: guests
-- @bsb-block-data guests
-- @bsb-hash sha256:dced392f17ba7c319610f3dac193505ba8b94dd6bac885fb9ad100284945e077
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.guests', target_type => 'guest', event_prefix => 'guest', deferred => true);
select better_supabase.audit('better_supabase.guest_grants', target_type => 'guest_grant', event_prefix => 'guest_grant', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('guests', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
