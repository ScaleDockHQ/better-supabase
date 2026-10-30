-- Assignment: queues that pick an owner for new companies, by round robin
-- or weight, within a territory. Acme (…0001) has the owner …a1 and the
-- member …a2; Globex (…0002) has the owner …a3 (supabase/seed.sql).
begin;
select plan(18);

create temporary table ids (name text primary key, id uuid) on commit drop;
grant all on ids to authenticated, anon, service_role;

insert into better_supabase.automation_fields (subject_type, field_id, label, type, path, column_type, nullable)
values ('company', 'lifecycle', 'Lifecycle', 'select', 'lifecycle', 'text', false);

-- Acme member: sees the queues, can't change them.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select throws_ok(
  $$select api.save_assignment_queue('00000000-0000-4000-8000-000000000001',
    '{"name":"Leads","subjectType":"company","strategy":"round_robin"}')$$,
  '42501',
  null,
  'a member without assignment.manage cannot create a queue'
);

-- Acme owner.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

insert into ids
select 'leads', (api.save_assignment_queue('00000000-0000-4000-8000-000000000001', '{"name":"Leads","subjectType":"company",
  "strategy":"round_robin","rank":0,"conditions":{"id":"root","type":"group","combinator":"and","rules":[
    {"id":"r1","type":"rule","path":["lifecycle"],"operator":"is","value":"lead"}]}}') ->> 'id')::uuid;
insert into ids
select 'rest', (api.save_assignment_queue('00000000-0000-4000-8000-000000000001',
  '{"name":"Everyone else","subjectType":"company","strategy":"weighted","rank":1}') ->> 'id')::uuid;

select throws_ok(
  $$select api.save_assignment_queue('00000000-0000-4000-8000-000000000001',
    '{"name":"Leads","subjectType":"company","strategy":"weighted"}')$$,
  '23505',
  null,
  'two queues in one organization cannot share a name'
);
select throws_ok(
  $$select api.save_assignment_queue('00000000-0000-4000-8000-000000000001',
    '{"name":"Random","subjectType":"company","strategy":"random"}')$$,
  '22023',
  null,
  'an unknown strategy is refused'
);
select throws_ok(
  $$select api.set_assignment_members((select id from ids where name = 'leads'),
    '[{"userId":"00000000-0000-4000-8000-0000000000a3"}]')$$,
  '22023',
  null,
  'a user outside the organization cannot join a queue'
);
select throws_ok(
  $$select api.set_assignment_members((select id from ids where name = 'rest'),
    '[{"userId":"00000000-0000-4000-8000-0000000000a1","weight":101}]')$$,
  '22023',
  null,
  'a weight above 100 is refused'
);

select is(
  jsonb_array_length(api.set_assignment_members((select id from ids where name = 'leads'),
    '[{"userId":"00000000-0000-4000-8000-0000000000a1"},{"userId":"00000000-0000-4000-8000-0000000000a2"}]') -> 'members'),
  2,
  'the owner puts both members in the leads queue'
);
select is(
  jsonb_array_length(api.set_assignment_members((select id from ids where name = 'rest'),
    '[{"userId":"00000000-0000-4000-8000-0000000000a1","weight":3},{"userId":"00000000-0000-4000-8000-0000000000a2","weight":1}]') -> 'members'),
  2,
  'the owner weighs the members of the other queue three to one'
);

select is(
  array[
    api.assign_subject('00000000-0000-4000-8000-000000000001', 'company', 'c1', '{"lifecycle":"lead"}') ->> 'userId',
    api.assign_subject('00000000-0000-4000-8000-000000000001', 'company', 'c2', '{"lifecycle":"lead"}') ->> 'userId',
    api.assign_subject('00000000-0000-4000-8000-000000000001', 'company', 'c3', '{"lifecycle":"lead"}') ->> 'userId'
  ],
  array['00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000a2', '00000000-0000-4000-8000-0000000000a1'],
  'the leads queue takes turns'
);

create temporary table picks on commit drop as
select api.assign_subject('00000000-0000-4000-8000-000000000001', 'company', 'w' || n, '{"lifecycle":"customer"}') as pick
from generate_series(1, 4) n;

select is(
  (select count(*)::int from picks where pick ->> 'queueId' = (select id::text from ids where name = 'rest')),
  4,
  'a company outside the leads territory falls through to the next queue'
);
select is(
  (select count(*)::int from picks where pick ->> 'userId' = '00000000-0000-4000-8000-0000000000a1'),
  3,
  'the weighted queue gives the heavier member three of four'
);
select is(
  api.assign_subject('00000000-0000-4000-8000-000000000001', 'person', 'p1', '{}'),
  null,
  'no queue for the subject type assigns nobody'
);
select is(
  jsonb_array_length(api.assignment_history('00000000-0000-4000-8000-000000000001', 'company', 'c1', null)),
  1,
  'the history keeps every pick for a record'
);

reset role;
select is(
  (select count(*)::int from better_supabase.outbox_events where type = 'subject.assigned'),
  7,
  'every pick emits subject.assigned'
);

-- Acme member.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  jsonb_array_length(api.list_assignment_queues('00000000-0000-4000-8000-000000000001', 'company')),
  2,
  'a member lists the queues'
);
select throws_ok(
  $$select api.assign_subject('00000000-0000-4000-8000-000000000001', 'company', 'c9', '{}')$$,
  '42501',
  null,
  'a member without assignment.assign cannot assign'
);

-- Globex owner.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;

select throws_ok(
  $$select api.list_assignment_queues('00000000-0000-4000-8000-000000000001', null)$$,
  '42501',
  null,
  'another organization cannot list the queues'
);

-- Acme owner.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  api.remove_assignment_queue((select id from ids where name = 'leads')),
  true,
  'the owner removes a queue'
);
select is(
  api.assignment_history('00000000-0000-4000-8000-000000000001', 'company', 'c1', null) -> 0 -> 'queueId',
  'null'::jsonb,
  'the history keeps the pick after its queue is removed'
);

select * from finish();
rollback;
