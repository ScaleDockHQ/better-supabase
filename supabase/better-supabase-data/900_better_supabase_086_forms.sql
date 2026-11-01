-- better-supabase module: forms
-- @bsb-block-data forms
-- @bsb-hash sha256:8e99a94610f4c467685597591c474373e790f006e3cfe57ff10fea1f360011e9
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.forms', target_type => 'form', event_prefix => 'form', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('forms', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
