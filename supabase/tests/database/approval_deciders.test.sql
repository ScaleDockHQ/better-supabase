-- The service role decides an approval for a user, who is recorded as the
-- approver; a member can't decide for someone else; a tenant policy for every
-- action of a subject type tightens each of its floors. Ann (…a1) owns Acme
-- (…0001) and Ben (…a2) is a member (supabase/seed.sql).
begin;
select plan(5);

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select set_config('test.request', api.request_approval('00000000-0000-4000-8000-000000000001', 'customer',
  '00000000-0000-4000-8000-00000000a001', 'discount') ->> 'id', true);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;
select throws_ok(
  format($$select api.decide_approval(%L, 'approved', null, '00000000-0000-4000-8000-0000000000a1')$$, current_setting('test.request')),
  '42501',
  'only the service role decides for another user',
  'a member cannot decide for someone else'
);

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select is(
  api.decide_approval(current_setting('test.request')::uuid, 'approved', 'by phone', '00000000-0000-4000-8000-0000000000a1') ->> 'status',
  'approved',
  'the service role decides for Ann'
);
select is(
  (select approver from better_supabase.approval_decisions where request_id = current_setting('test.request')::uuid),
  '00000000-0000-4000-8000-0000000000a1'::uuid,
  'Ann is recorded as the approver'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;
select lives_ok(
  $$select api.save_approval_policy('00000000-0000-4000-8000-000000000001',
    '{"subjectType":"customer","action":"*","name":"Every customer action","steps":[{"approvers":{"users":["00000000-0000-4000-8000-0000000000a2"]}}]}')$$,
  'a tenant policy covers every action of a subject type with a floor'
);
select is(
  jsonb_array_length(api.approval_requirement('00000000-0000-4000-8000-000000000001', 'customer', 'refund', '{}') -> 'steps'),
  1,
  'the catch-all policy adds its step to a floor that asked for nothing'
);

select * from finish();
rollback;
