-- better-supabase module: care-plans
-- @bsb-block-data care-plans
-- @bsb-hash sha256:f16daa3b5a35edb939ff9ca2e6a94f3c0bb55fbdc6d71a6e1aeceb2dbfb2389a
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.care_plans', target_type => 'care_plan', event_prefix => 'care_plan', deferred => true);
select better_supabase.audit('better_supabase.care_plan_problems', target_type => 'care_plan_problem', event_prefix => 'care_plan_problem', deferred => true);
select better_supabase.audit('better_supabase.care_plan_goals', target_type => 'care_plan_goal', event_prefix => 'care_plan_goal', deferred => true);
select better_supabase.audit('better_supabase.care_plan_actions', target_type => 'care_plan_action', event_prefix => 'care_plan_action', deferred => true);
select better_supabase.audit('better_supabase.care_plan_evaluations', target_type => 'care_plan_evaluation', event_prefix => 'care_plan_evaluation', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('care-plans', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
