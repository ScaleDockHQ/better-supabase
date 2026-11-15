-- Restoring a care plan (ADR 1032): an archived plan comes back as a draft,
-- its actions stay ended and publishing it starts nothing, and a plan that is
-- not archived is returned unchanged. Run with `supabase test db`.
begin;
select plan(9);

create function pg_temp.n(t text) returns integer language sql security definer as $$
  select count(*)::integer from better_supabase.outbox_events where type = t
$$;

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

create temporary table ids (name text primary key, id uuid) on commit drop;
insert into ids values ('plan', (better_supabase.create_care_plan(
  '00000000-0000-4000-8000-000000000001',
  '{"subjectType": "customer", "subjectId": "00000000-0000-4000-8000-00000000a001", "title": "Restore plan"}'::jsonb
) ->> 'id')::uuid);
insert into ids values ('problem', (better_supabase.add_care_plan_problem(
  (select id from ids where name = 'plan'), '{"code": "25", "title": "Risk of falls"}'::jsonb) ->> 'id')::uuid);
insert into ids values ('goal', (better_supabase.add_care_plan_goal(
  (select id from ids where name = 'problem'), '{"title": "Walks with a frame"}'::jsonb) ->> 'id')::uuid);
insert into ids values ('task', (better_supabase.add_care_plan_action(
  (select id from ids where name = 'goal'), '{"title": "Walk twice a day"}'::jsonb) ->> 'id')::uuid);

select is(
  better_supabase.restore_care_plan((select id from ids where name = 'plan')) ->> 'status', 'draft',
  'restoring a draft returns it unchanged'
);
select is(pg_temp.n('care_plan.restored'), 0, 'a plan that is not archived records no event');

select better_supabase.publish_care_plan((select id from ids where name = 'plan'));
select is(
  better_supabase.archive_care_plan((select id from ids where name = 'plan')) ->> 'status', 'archived',
  'the active plan is archived'
);
select is(
  (select status from better_supabase.care_plan_actions where id = (select id from ids where name = 'task')), 'ended',
  'archiving ended the action'
);

select is(
  better_supabase.restore_care_plan((select id from ids where name = 'plan')) ->> 'status', 'draft',
  'restoring an archived plan makes it a draft'
);
select is(
  (select archived_at from better_supabase.care_plans where id = (select id from ids where name = 'plan')), null,
  'restoring clears archivedAt'
);
select is(pg_temp.n('care_plan.restored'), 1, 'restoring records care_plan.restored');
select is(
  (select status from better_supabase.care_plan_actions where id = (select id from ids where name = 'task')), 'ended',
  'the action stays ended'
);

select better_supabase.publish_care_plan((select id from ids where name = 'plan'));
select is(
  (select count(*)::integer from better_supabase.care_plan_actions
   where plan_id = (select id from ids where name = 'plan') and status = 'active'),
  0,
  'publishing the restored plan starts no action'
);

select * from finish();
rollback;
