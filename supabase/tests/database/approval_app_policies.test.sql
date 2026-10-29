-- Requests under the app's own policy: the service role names the requester,
-- who can't approve; a policy only tightens a floor; a signed-in caller can't
-- pass one; managerOf points a manager step at an employee's manager; a floor
-- under subject type * holds a dotted action; tenant policies keep a
-- description. Ann (…a1) owns Acme (…0001) and Ben (…a2) is a member
-- (supabase/seed.sql).
begin;
select plan(12);

create temporary table ids (name text primary key, id uuid) on commit drop;
grant all on ids to authenticated, anon, service_role;

-- Ann manages Ben.
with ann as (
  insert into better_supabase.employees (tenant_id, user_id, name, status)
  values ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a1', 'Ann', 'active')
  returning id
)
insert into ids select 'ann_employee', id from ann;
with ben as (
  insert into better_supabase.employees (tenant_id, user_id, name, status, manager_id)
  select '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a2', 'Ben', 'active', id
  from ids where name = 'ann_employee'
  returning id
)
insert into ids select 'ben_employee', id from ben;

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
insert into ids select 'workflow', (api.request_approval('00000000-0000-4000-8000-000000000001', 'workflow_run', 'run-1', 'approval',
  policy => '{"steps": [{"approvers": {"users": ["00000000-0000-4000-8000-0000000000a1", "00000000-0000-4000-8000-0000000000a2"]}, "required": 1}]}',
  requested_by => '00000000-0000-4000-8000-0000000000a1') ->> 'id')::uuid;
select is(
  (select requested_by from better_supabase.approval_requests where id = (select id from ids where name = 'workflow')),
  '00000000-0000-4000-8000-0000000000a1'::uuid,
  'the service role files the request for Ann'
);
select is(
  api.request_approval('00000000-0000-4000-8000-000000000001', 'customer', 'c-1', 'discount',
    policy => '{"mode": "confirm", "steps": [], "selfApproval": true}') ->> 'mode',
  'authorize',
  'an own policy does not loosen the floor''s authorize mode'
);
insert into ids select 'managed', (api.request_approval('00000000-0000-4000-8000-000000000001', 'workflow_run', 'run-2', 'approval',
  policy => jsonb_build_object('steps', '[{"approvers": {"manager": true}}]'::jsonb, 'managerOf', (select id from ids where name = 'ben_employee')::text)) ->> 'id')::uuid;

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;
select throws_ok(
  format($$select api.decide_approval(%L, 'approved')$$, (select id from ids where name = 'workflow')),
  '42501',
  'not an approver for this step',
  'Ann cannot approve the request filed for her'
);
select ok(
  better_supabase.approval_eligible((select id from ids where name = 'managed')),
  'managerOf makes Ben''s manager the approver of a manager step'
);
select throws_ok(
  $$select api.request_approval('00000000-0000-4000-8000-000000000001', 'customer', 'c-2', 'discount', policy => '{"mode": "confirm", "steps": []}')$$,
  '42501',
  'only the service role files a request under its own policy',
  'a signed-in caller cannot pass a policy'
);
select throws_ok(
  $$select api.request_approval('00000000-0000-4000-8000-000000000001', 'customer', 'c-2', 'discount', requested_by => '00000000-0000-4000-8000-0000000000a2')$$,
  '42501',
  'only the service role files a request for another user',
  'a signed-in caller cannot file for someone else'
);
select is(
  api.approval_requirement('00000000-0000-4000-8000-000000000001', 'chat_thread', 'quote.send', '{}'),
  null,
  'the * floor for quote.send asks for nothing by itself'
);
select lives_ok(
  $$select api.save_approval_policy('00000000-0000-4000-8000-000000000001',
    '{"subjectType":"chat_thread","action":"quote.send","name":"Quotes from chats","steps":[{"approvers":{"users":["00000000-0000-4000-8000-0000000000a2"]}}],"fields":{"description":"Agents ask Ben"}}')$$,
  'a tenant policy tightens the * floor for one subject type'
);
select is(
  jsonb_array_length(api.approval_requirement('00000000-0000-4000-8000-000000000001', 'chat_thread', 'quote.send', '{}') -> 'steps'),
  1,
  'the tenant policy adds its step on a chat thread'
);
select is(
  api.approval_requirement('00000000-0000-4000-8000-000000000001', 'mcp_client', 'quote.send', '{}'),
  null,
  'and leaves other subject types on the floor'
);
select is(
  (select description from better_supabase.approval_policies where name = 'Quotes from chats'),
  'Agents ask Ben',
  'the policy keeps its description'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;
select is(
  api.decide_approval((select id from ids where name = 'workflow'), 'approved') ->> 'status',
  'approved',
  'Ben approves the workflow request'
);

select * from finish();
rollback;
