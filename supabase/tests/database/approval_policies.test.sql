-- Tenant approval policies over the config floors, confirm mode, the
-- requester's manager as approver, and consume-once fingerprints. Ann (…a1)
-- owns Acme (…0001) and Ben (…a2) is a member; Carl (…a3) owns Globex
-- (…0002) (supabase/seed.sql). The fixture's floors: customer.refund asks
-- for nothing, customer.export is confirm mode with the manager as approver.
begin;
select plan(28);

create temporary table ids (name text primary key, id uuid) on commit drop;
grant all on ids to authenticated, anon, service_role;

insert into better_supabase.automation_fields (subject_type, field_id, label, type, path, column_type, nullable)
values ('customer', 'amount', 'Amount', 'number', 'amount', 'numeric', true);

-- Ann manages Ben.
with ann as (
  insert into better_supabase.employees (tenant_id, user_id, name, status)
  values ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a1', 'Ann', 'active')
  returning id
)
insert into ids select 'ann_employee', id from ann;
insert into better_supabase.employees (tenant_id, user_id, name, status, manager_id)
select '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a2', 'Ben', 'active', id
from ids where name = 'ann_employee';

-- Ben, a member.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  api.approval_requirement('00000000-0000-4000-8000-000000000001', 'customer', 'refund', '{"amount": 500}'),
  null,
  'a floor without steps requires nothing before a tenant policy'
);
select throws_ok(
  $$select api.request_approval('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', 'refund')$$,
  '22023',
  'no approval is required for this request',
  'request_approval refuses a request that needs nothing'
);
select throws_ok(
  $$select api.save_approval_policy('00000000-0000-4000-8000-000000000001',
    '{"subjectType":"customer","action":"refund","name":"Large refunds","steps":[{"approvers":{"permission":"approvals.manage"}}]}')$$,
  '42501',
  null,
  'a member without approvals.manage cannot save a tenant policy'
);

-- Ann, the owner.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select throws_ok(
  $$select api.save_approval_policy('00000000-0000-4000-8000-000000000001',
    '{"subjectType":"customer","action":"merge","name":"No floor","steps":[]}')$$,
  '22023',
  null,
  'a tenant policy needs a config floor for its subject type and action'
);
select throws_ok(
  $$select api.save_approval_policy('00000000-0000-4000-8000-000000000001',
    '{"subjectType":"customer","action":"refund","name":"Bad","steps":[{"approvers":{}}]}')$$,
  '22023',
  null,
  'a step must name an approver'
);
select throws_ok(
  $$select api.save_approval_policy('00000000-0000-4000-8000-000000000001',
    '{"subjectType":"customer","action":"refund","name":"Bad","mode":"skip","steps":[]}')$$,
  '22023',
  null,
  'an unknown mode is refused'
);
select throws_ok(
  $$select api.save_approval_policy('00000000-0000-4000-8000-000000000001',
    '{"subjectType":"customer","action":"refund","name":"Bad","steps":[{"approvers":{"users":[
      "00000000-0000-4000-8000-0000000000a1","00000000-0000-4000-8000-0000000000a2"]},"required":3}]}')$$,
  '22023',
  null,
  'a step can not require more approvals than the users it lists'
);

insert into ids
select 'both', (api.save_approval_policy('00000000-0000-4000-8000-000000000001',
  '{"subjectType":"customer","action":"refund","name":"Both owners","enabled":false,
    "steps":[{"approvers":{"users":["00000000-0000-4000-8000-0000000000a1",
      "00000000-0000-4000-8000-0000000000a2"]},"required":"all"}]}') ->> 'id')::uuid;
select is(
  (select p -> 'steps' -> 0 -> 'required'
   from jsonb_array_elements(api.list_approval_policies('00000000-0000-4000-8000-000000000001')) p
   where (p ->> 'id')::uuid = (select id from ids where name = 'both')),
  '2'::jsonb,
  'required "all" on a list of users saves as their count'
);
select api.remove_approval_policy((select id from ids where name = 'both'));

insert into ids
select 'large', (api.save_approval_policy('00000000-0000-4000-8000-000000000001',
  '{"subjectType":"customer","action":"refund","name":"Large refunds","expiresIn":"P2D",
    "conditions":{"id":"root","type":"group","combinator":"and","rules":[
      {"id":"r1","type":"rule","path":["amount"],"operator":"gt","value":100}]},
    "steps":[{"approvers":{"permission":"approvals.manage"},"required":1}]}') ->> 'id')::uuid;

select is(
  jsonb_array_length(api.list_approval_policies('00000000-0000-4000-8000-000000000001')),
  1,
  'the owner lists the tenant policy'
);

-- Carl, in Globex, sees none of them and changes none of them.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;

select is(
  (select count(*) from better_supabase.approval_policies)::integer,
  0,
  'another tenant reads no tenant policies'
);
select throws_ok(
  format($$select api.remove_approval_policy(%L)$$, (select id from ids where name = 'large')),
  '42501',
  null,
  'another tenant cannot remove a tenant policy'
);

-- Ben again.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  api.approval_requirement('00000000-0000-4000-8000-000000000001', 'customer', 'refund', '{"amount": 50}'),
  null,
  'a policy whose conditions do not match requires nothing'
);
select is(
  jsonb_array_length(api.approval_requirement('00000000-0000-4000-8000-000000000001', 'customer', 'refund', '{"amount": 500}') -> 'steps'),
  1,
  'a matching tenant policy adds its step to the floor'
);
select is(
  api.approval_requirement('00000000-0000-4000-8000-000000000001', 'customer', 'refund', '{"amount": 500}') ->> 'mode',
  'authorize',
  'a policy with steps authorizes'
);
select throws_ok(
  $$select api.request_approval('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', 'refund',
    null, '{"amount": 500}', 'not-a-hash')$$,
  '22023',
  null,
  'a fingerprint must be a hex SHA-256'
);

insert into ids
select 'refund', (api.request_approval('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', 'refund',
  'Broken anvil', '{"amount": 500}', encode(extensions.digest('refund:a001:500', 'sha256'), 'hex')) ->> 'id')::uuid;

select ok(
  (select expires_at is not null from better_supabase.approval_requests where id = (select id from ids where name = 'refund')),
  'the tenant policy''s expiry applies'
);
select throws_ok(
  format($$select api.consume_approval(%L, %L)$$, (select id from ids where name = 'refund'),
    encode(extensions.digest('refund:a001:500', 'sha256'), 'hex')),
  '22023',
  'this request is not approved',
  'a pending request cannot be consumed'
);
select throws_ok(
  format($$select api.decide_approval(%L, 'approved')$$, (select id from ids where name = 'refund')),
  '42501',
  null,
  'the requester cannot approve an authorize request'
);

-- Ann approves the refund.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;
select api.decide_approval((select id from ids where name = 'refund'), 'approved');

-- Ben consumes it.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select throws_ok(
  format($$select api.consume_approval(%L, %L)$$, (select id from ids where name = 'refund'),
    encode(extensions.digest('refund:a001:900', 'sha256'), 'hex')),
  '22023',
  'the request changed after it was approved; ask for approval again',
  'a different fingerprint does not consume the approval'
);
select ok(
  api.consume_approval((select id from ids where name = 'refund'),
    encode(extensions.digest('refund:a001:500', 'sha256'), 'hex')) ->> 'consumedAt' is not null,
  'the matching fingerprint consumes the approval'
);
select throws_ok(
  format($$select api.consume_approval(%L, %L)$$, (select id from ids where name = 'refund'),
    encode(extensions.digest('refund:a001:500', 'sha256'), 'hex')),
  '22023',
  'this approval was already used',
  'an approval is consumed once'
);
select ok(
  api.is_approved('customer', '00000000-0000-4000-8000-00000000a001', 'refund'),
  'is_approved still reports the approved request'
);

-- Confirm mode: the requester's own approval completes the request.
insert into ids
select 'export', (api.request_approval('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a002', 'export') ->> 'id')::uuid;

select is(
  api.get_approval((select id from ids where name = 'export')) ->> 'mode',
  'confirm',
  'the export request is in confirm mode'
);
select is(
  api.decide_approval((select id from ids where name = 'export'), 'approved') ->> 'status',
  'approved',
  'the requester confirms a confirm-mode request'
);

-- A second export: Ann, Ben's manager, may approve it too.
insert into ids
select 'export2', (api.request_approval('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', 'export') ->> 'id')::uuid;

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select ok(
  (api.get_approval((select id from ids where name = 'export2')) ->> 'canDecide')::boolean,
  'the requester''s manager can decide'
);
select is(
  api.decide_approval((select id from ids where name = 'export2'), 'approved') ->> 'status',
  'approved',
  'the manager''s approval completes the step'
);

-- Ann's own export: Ann has no manager, so only she can confirm it.
insert into ids
select 'export3', (api.request_approval('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a002', 'export') ->> 'id')::uuid;

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select ok(
  not (api.get_approval((select id from ids where name = 'export3')) ->> 'canDecide')::boolean,
  'a report is not the requester''s manager'
);

-- A tenant policy can tighten confirm to authorize.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;
select api.save_approval_policy('00000000-0000-4000-8000-000000000001',
  '{"subjectType":"customer","action":"export","name":"Exports need an admin","mode":"authorize",
    "steps":[{"approvers":{"permission":"approvals.manage"}}]}');

select is(
  api.approval_requirement('00000000-0000-4000-8000-000000000001', 'customer', 'export') ->> 'mode',
  'authorize',
  'an authorize tenant policy outranks a confirm floor'
);

select * from finish();
rollback;
