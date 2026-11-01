-- better-supabase module: e-prescribing
-- @bsb-block-data e-prescribing
-- @bsb-hash sha256:bef76d645dc97e2cb4cd8effb4ace78ad5b1ef3e81e0ba6bc88fb029b95ac98b
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.prescriptions', target_type => 'prescription', event_prefix => 'prescription', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('e-prescribing', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
