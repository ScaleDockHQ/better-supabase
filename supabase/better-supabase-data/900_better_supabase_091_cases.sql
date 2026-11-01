-- better-supabase module: cases
-- @bsb-block-data cases
-- @bsb-hash sha256:c35f9f117664486d222ee7c239990212bfa05568b858028b5621537641ec3332
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.cases', target_type => 'case', event_prefix => 'case', deferred => true);
select better_supabase.audit('better_supabase.case_kinds', target_type => 'case_kind', event_prefix => 'case_kind', deferred => true);
select better_supabase.audit('better_supabase.case_actions', target_type => 'case_action', event_prefix => 'case_action', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('cases', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
