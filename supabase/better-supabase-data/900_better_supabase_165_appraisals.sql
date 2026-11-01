-- better-supabase module: appraisals
-- @bsb-block-data appraisals
-- @bsb-hash sha256:e07017c77593318bef7a55993e9fe01f0dbfa4e65b34f3c58cbd11dec090180d
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.appraisals', target_type => 'appraisal', event_prefix => 'appraisal', deferred => true);
select better_supabase.audit('better_supabase.appraisal_cycles', target_type => 'appraisal_cycle', event_prefix => 'appraisal_cycle', deferred => true);
select better_supabase.audit('better_supabase.appraisal_reviews', target_type => 'appraisal_review', event_prefix => 'appraisal_review', deferred => true);
select better_supabase.audit('better_supabase.appraisal_calibrations', target_type => 'appraisal_calibration', event_prefix => 'appraisal_calibration', deferred => true);
select better_supabase.audit('better_supabase.appraisal_goals', target_type => 'appraisal_goal', event_prefix => 'appraisal_goal', deferred => true);
select better_supabase.audit('better_supabase.appraisal_competencies', target_type => 'appraisal_competency', event_prefix => 'appraisal_competency', deferred => true);
select better_supabase.audit('better_supabase.appraisal_review_ratings', target_type => 'appraisal_review_rating', event_prefix => 'appraisal_review_rating', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('appraisals', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
