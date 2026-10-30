-- Brand starters, recurring template schedules, a workflow-driven state
-- machine (change_request on the `change-requests` workflow) and the
-- timeline's transition source, against the seed: Acme (…01) runs under brand
-- acme, Globex (…02) under none; …a1 is an Acme admin. Run with
-- `supabase test db`.
begin;
select plan(22);

update public.organizations set brand = 'acme' where id = '00000000-0000-4000-8000-000000000001';

-- Brand starters.
set local role service_role;
select is(
  better_supabase.sync_templates('[
    {"key":"kickoff","brand":"acme","type":"project","name":"Acme kickoff","settings":{},"body":{"tasks":["Brief"]}},
    {"key":"kickoff","type":"project","name":"Kickoff","settings":{},"body":{"tasks":["Plan"]}}
  ]'::jsonb),
  2,
  'sync publishes a brand starter and a system starter with the same key'
);
select is(
  (select scope from better_supabase.templates where name = 'Acme kickoff'),
  'brand',
  'a starter with a brand gets the brand scope'
);
reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  (select array_agg(t ->> 'name' order by t ->> 'name')
   from jsonb_array_elements(better_supabase.templates_list('00000000-0000-4000-8000-000000000001', 'project', null)) t),
  array['Acme kickoff', 'Kickoff'],
  'an Acme member lists the brand starter next to the system one'
);
select is(
  (select array_agg(t ->> 'name')
   from jsonb_array_elements(better_supabase.templates_list('00000000-0000-4000-8000-000000000002', 'project', null)) t),
  array['Kickoff'],
  'in Globex, which has no brand, only the system starter shows'
);

-- Recurring records.
select isnt(
  better_supabase.save_template_schedule(
    null,
    (select id from better_supabase.templates where name = 'Acme kickoff'),
    '00000000-0000-4000-8000-000000000001',
    '2026-11-01T09:00:00Z',
    'Europe/Amsterdam',
    'FREQ=MONTHLY;BYMONTHDAY=1',
    '{"owner":"a1"}'::jsonb,
    true
  ) ->> 'id',
  null,
  'an admin schedules a visible brand starter'
);
select is(
  (select t ->> 'rrule'
   from jsonb_array_elements(better_supabase.template_schedules_list('00000000-0000-4000-8000-000000000001', null)) t),
  'FREQ=MONTHLY;BYMONTHDAY=1',
  'the schedule keeps its rule in recurrence_rules'
);
select throws_ok(
  $$select better_supabase.list_template_schedule()$$,
  '42501',
  null,
  'only the service role lists every schedule'
);
reset role;

set local role service_role;
select is(
  (select count(*) from jsonb_array_elements(better_supabase.list_template_schedule())),
  1::bigint,
  'the service role lists the enabled schedule'
);
select is(
  better_supabase.claim_template_occurrence(
    (select id from better_supabase.template_schedules limit 1), '2026-11-01T08:00:00Z'
  ) ->> 'tzid',
  'Europe/Amsterdam',
  'the first claim of an occurrence returns the schedule'
);
select ok(
  better_supabase.finish_template_occurrence(
    (select id from better_supabase.template_schedules limit 1), '2026-11-01T08:00:00Z',
    (with t as (select id from better_supabase.templates where name = 'Acme kickoff'),
      v as (select v.id from better_supabase.template_versions v, t where v.template_id = t.id)
     select (better_supabase.record_template_application(
       (select id from t), (select id from v), '00000000-0000-4000-8000-000000000001', 'project', 'p1'
     ) ->> 'id')::uuid)
  ),
  'finishing records the application'
);
select is(
  better_supabase.claim_template_occurrence(
    (select id from better_supabase.template_schedules limit 1), '2026-11-01T08:00:00Z'
  ),
  null,
  'an occurrence that made an application is not claimed again'
);
reset role;

-- A workflow-driven state machine.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select throws_ok(
  $$insert into public.change_requests (organization_id, title) values ('00000000-0000-4000-8000-000000000001', 'Early')$$,
  '55000',
  null,
  'a record needs a published version of the machine''s workflow'
);
select is(
  (better_supabase.publish_workflow_version(
    (better_supabase.save_workflow_draft(
      (better_supabase.save_workflow_definition('00000000-0000-4000-8000-000000000001', 'change-requests', 'Change requests') ->> 'id')::uuid,
      '{"nodes":[
        {"id":"t","kind":"trigger","config":{"stage":"draft"}},
        {"id":"r","kind":"approval","config":{"stage":"review","returnsTo":["draft"]}},
        {"id":"a","kind":"condition","config":{"stage":"approved"}}
      ],"edges":[{"id":"e1","source":"t","target":"r"},{"id":"e2","source":"r","target":"a"}]}'::jsonb
    ) ->> 'id')::uuid
  ) ->> 'status'),
  'published',
  'an admin publishes the stages'
);

insert into public.change_requests (organization_id, title) values ('00000000-0000-4000-8000-000000000001', 'Rotate keys');

select is(
  (select status from public.change_requests where title = 'Rotate keys'),
  'draft',
  'a new record starts at the trigger''s stage'
);
select throws_ok(
  $$update public.change_requests set status = 'approved' where title = 'Rotate keys'$$,
  '22023',
  null,
  'a move the workflow has no path for fails'
);

update public.change_requests set status = 'review' where title = 'Rotate keys';
update public.change_requests set status = 'draft' where title = 'Rotate keys';

select is(
  (select status from public.change_requests where title = 'Rotate keys'),
  'draft',
  'returnsTo allows the move back'
);
select is(
  (select s ->> 'workflow' from better_supabase.status_state('change_request', (select id::text from public.change_requests where title = 'Rotate keys')) s),
  'change-requests',
  'the state names the workflow'
);

select better_supabase.publish_workflow_version(
  (better_supabase.save_workflow_draft(
    (select id from better_supabase.workflow_definitions where slug = 'change-requests'),
    '{"nodes":[
      {"id":"t","kind":"trigger","config":{"stage":"intake"}},
      {"id":"a","kind":"condition","config":{"stage":"approved"}}
    ],"edges":[{"id":"e1","source":"t","target":"a"}]}'::jsonb
  ) ->> 'id')::uuid
);

update public.change_requests set status = 'review' where title = 'Rotate keys';

select is(
  (select status from public.change_requests where title = 'Rotate keys'),
  'review',
  'a record keeps the version it was pinned to after a new one is published'
);

insert into public.change_requests (organization_id, title) values ('00000000-0000-4000-8000-000000000001', 'Renew cert');

select is(
  (select status from public.change_requests where title = 'Renew cert'),
  'intake',
  'a new record follows the newest published version'
);

-- The timeline reads status_history.
select is(
  (select array_agg(e ->> 'type')
   from jsonb_array_elements(better_supabase.list_activity(
     '00000000-0000-4000-8000-000000000001', 'change_request',
     (select id::text from public.change_requests where title = 'Rotate keys'),
     null, 50, array['transition']
   )) e),
  array['status.changed', 'status.changed', 'status.changed'],
  'the transition source lists each status change of the record'
);

-- A status change the sink also stored shows once, from status_history.
set local role service_role;
insert into better_supabase.timeline_entries (organization_id, event_id, type, subject_type, subject_id)
values (
  '00000000-0000-4000-8000-000000000001', 'test:status-changed', 'status.changed', 'change_request',
  (select id::text from public.change_requests where title = 'Rotate keys')
);
reset role;

select is(
  (select count(*)::int
   from jsonb_array_elements(better_supabase.list_activity(
     '00000000-0000-4000-8000-000000000001', 'change_request',
     (select id::text from public.change_requests where title = 'Rotate keys')
   )) e
   where e ->> 'type' = 'status.changed'),
  3,
  'the feed drops the stored status change the transition source returns'
);
select is(
  (select array_agg(e ->> 'source')
   from jsonb_array_elements(better_supabase.list_activity(
     '00000000-0000-4000-8000-000000000001', 'change_request',
     (select id::text from public.change_requests where title = 'Rotate keys'),
     null, 50, array['event']
   )) e),
  array['event'],
  'the stored status change stays when the transition source is not asked for'
);

select * from finish();
rollback;
