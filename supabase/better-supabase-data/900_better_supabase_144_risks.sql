-- better-supabase module: risks
-- @bsb-block-data risks
-- @bsb-hash sha256:d7942bd4fdbd32cae27560b35f4a24701829819cb001858a4a7eda22438ae4c4
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.risks', target_type => 'risk', event_prefix => 'risk', deferred => true);
select better_supabase.audit('better_supabase.risk_matrices', target_type => 'risk_matrix', event_prefix => 'risk_matrix', deferred => true);
select better_supabase.audit('better_supabase.risk_assessments', target_type => 'risk_assessment', event_prefix => 'risk_assessment', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('risks', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
