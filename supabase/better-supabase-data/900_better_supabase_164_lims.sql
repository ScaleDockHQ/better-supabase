-- better-supabase module: lims
-- @bsb-block-data lims
-- @bsb-hash sha256:9beb6dbc0b29ce01115a2fbe7261ca42a515f17eec3ab330216c14bf716552ab
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.lims_samples', target_type => 'lims_sample', event_prefix => 'lims_sample', deferred => true);
select better_supabase.audit('better_supabase.lims_methods', target_type => 'lims_method', event_prefix => 'lims_method', deferred => true);
select better_supabase.audit('better_supabase.lims_results', target_type => 'lims_result', event_prefix => 'lims_result', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('lims', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
