-- The care-plans module against the seed: the Acme owner (…a1) drafts a plan
-- for the customer Road Runner, publishes it and evaluates a goal; a
-- restrictive measure waits for an approval; the Acme member (…a2) reads the
-- plan but can't draft or evaluate; the Globex owner (…a3) sees none of it.
-- Run with `supabase test db`.
begin;
select plan(18);

select is(
  (select count(*) from pg_catalog.pg_tables
   where schemaname = 'better_supabase'
     and tablename in ('care_plans', 'care_plan_problems', 'care_plan_goals', 'care_plan_actions', 'care_plan_evaluations')
     and rowsecurity),
  5::bigint,
  'the care plans tables have RLS enabled'
);
select table_privs_are('better_supabase', 'care_plans', 'anon', '{}'::text[],
  'anon has no privileges on care_plans');
select table_privs_are('better_supabase', 'care_plan_actions', 'authenticated', array['SELECT'],
  'authenticated only reads actions; writes go through the functions');
select ok(
  not has_function_privilege('authenticated',
    'better_supabase.due_care_plan_reviews()', 'execute'),
  'only the service role reports due reviews'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

create temporary table ids (name text primary key, id uuid) on commit drop;
insert into ids values ('plan', (better_supabase.create_care_plan(
  '00000000-0000-4000-8000-000000000001',
  '{"subjectType": "customer", "subjectId": "00000000-0000-4000-8000-00000000a001", "title": "Support plan"}'::jsonb
) ->> 'id')::uuid);
insert into ids values ('problem', (better_supabase.add_care_plan_problem(
  (select id from ids where name = 'plan'), '{"code": "25", "title": "Risk of falls"}'::jsonb) ->> 'id')::uuid);
insert into ids values ('goal', (better_supabase.add_care_plan_goal(
  (select id from ids where name = 'problem'), '{"title": "Walks with a frame"}'::jsonb) ->> 'id')::uuid);
insert into ids values ('task', (better_supabase.add_care_plan_action(
  (select id from ids where name = 'goal'), '{"title": "Walk twice a day"}'::jsonb) ->> 'id')::uuid);
insert into ids values ('measure', (better_supabase.add_care_plan_action(
  (select id from ids where name = 'goal'),
  '{"kind": "measure", "measureKind": "bed_rails", "title": "Bed rail at night"}'::jsonb) ->> 'id')::uuid);

select is(
  (select status from better_supabase.care_plans where id = (select id from ids where name = 'plan')),
  'draft',
  'the owner drafts a plan for a customer'
);
select is(
  (select requires_approval from better_supabase.care_plan_actions where id = (select id from ids where name = 'measure')),
  true,
  'a restrictive measure always requires an approval'
);
select throws_ok(
  $$select better_supabase.record_care_plan_evaluation((select id from ids where name = 'goal'), 'achieved')$$,
  '55000',
  null,
  'a goal of a draft plan cannot be evaluated'
);

select is(
  better_supabase.publish_care_plan((select id from ids where name = 'plan')) ->> 'status',
  'active',
  'publishing makes the plan active'
);
select is(
  (select status from better_supabase.care_plan_actions where id = (select id from ids where name = 'task')),
  'active',
  'publishing starts the actions that need no approval'
);
select is(
  (select status from better_supabase.care_plan_actions where id = (select id from ids where name = 'measure')),
  'planned',
  'the measure waits for its approval'
);
select throws_ok(
  $$select better_supabase.update_care_plan_problem((select id from ids where name = 'problem'), '{"title": "Other"}'::jsonb)$$,
  '55000',
  null,
  'an active plan only changes a problem status'
);
select is(
  better_supabase.record_care_plan_evaluation((select id from ids where name = 'goal'), 'in_progress', 'Walks to the door') ->> 'status',
  'in_progress',
  'the owner evaluates a goal'
);
select is(
  (select status from better_supabase.care_plan_goals where id = (select id from ids where name = 'goal')),
  'in_progress',
  'the evaluation becomes the goal status'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  better_supabase.get_care_plan((select id from ids where name = 'plan')) ->> 'title',
  'Support plan',
  'a member reads the plan'
);
select throws_ok(
  $$select better_supabase.create_care_plan('00000000-0000-4000-8000-000000000001',
    '{"subjectType": "customer", "subjectId": "00000000-0000-4000-8000-00000000a002", "title": "Other"}'::jsonb)$$,
  '42501',
  null,
  'a member cannot draft a plan'
);
select throws_ok(
  $$select better_supabase.record_care_plan_evaluation((select id from ids where name = 'goal'), 'achieved')$$,
  '42501',
  null,
  'a member cannot evaluate a goal'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;

select is(
  (select count(*) from better_supabase.care_plans),
  0::bigint,
  'another organization sees none of the plans'
);
select throws_ok(
  $$select better_supabase.get_care_plan((select id from ids where name = 'plan'))$$,
  null,
  null,
  'another organization cannot read the plan'
);

select * from finish();
rollback;
