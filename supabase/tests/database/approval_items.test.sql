-- Approval items: a request that lists what to approve, items that wait for
-- the items they depend on, records created while approving, and settling a
-- request for the system. Ann (…a1) owns Acme (…0001) and Ben (…a2) is a
-- member (supabase/seed.sql). Needs the approvals module at version 2 or later,
-- so run it after the fixture is regenerated.
begin;
select plan(10);

-- Ben files a request with two items; the second depends on the first.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('test.request', better_supabase.request_approval_items(
  '00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', 'discount',
  '[{"key":"credit","label":"Credit note"},{"key":"refund","label":"Refund","dependsOn":["credit"]}]'
) ->> 'id', true);

select is(
  (select status from better_supabase.approval_requests where id = current_setting('test.request')::uuid),
  'pending',
  'a request with items is pending'
);
select is(
  (select count(*)::integer from better_supabase.approval_items where request_id = current_setting('test.request')::uuid),
  2,
  'each item is stored'
);
select throws_ok(
  format($$select better_supabase.decide_approval_items(%L, '[{"key":"credit","decision":"approved"}]')$$, current_setting('test.request')),
  null,
  null,
  'a member who is not an approver cannot decide an item'
);

-- The service role decides for Ann.
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

select throws_ok(
  format($$select better_supabase.decide_approval_items(%L, '[{"key":"refund","decision":"approved"}]', '00000000-0000-4000-8000-0000000000a1')$$, current_setting('test.request')),
  null,
  null,
  'an item cannot be approved before the item it depends on'
);
select is(
  better_supabase.decide_approval_items(current_setting('test.request')::uuid, '[{"key":"credit","decision":"approved"}]', '00000000-0000-4000-8000-0000000000a1') ->> 'status',
  'pending',
  'the request stays pending while an item is pending'
);
select is(
  (select status from better_supabase.approval_items where request_id = current_setting('test.request')::uuid and key = 'credit'),
  'approved',
  'the decided item is approved'
);
select better_supabase.record_approval_created(current_setting('test.request')::uuid, 'credit', 'credit_note', 'cn-1');
select is(
  (select created_id from better_supabase.approval_items where request_id = current_setting('test.request')::uuid and key = 'credit'),
  'cn-1',
  'the record created for an item is stored on the item'
);
select is(
  better_supabase.decide_approval_items(current_setting('test.request')::uuid, '[{"key":"refund","decision":"approved"}]', '00000000-0000-4000-8000-0000000000a1') ->> 'status',
  'approved',
  'the request settles approved once no item is pending'
);

-- Settling for the system: refused for a member, allowed for the service role.
select set_config('test.second', better_supabase.request_approval_items(
  '00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', 'discount',
  '[{"key":"only"}]', null, '{}', null, null, '00000000-0000-4000-8000-0000000000a2'
) ->> 'id', true);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;
select throws_ok(
  format($$select better_supabase.settle_approval(%L, 'rejected', 'timed out')$$, current_setting('test.second')),
  null,
  null,
  'a member cannot settle a request'
);

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select is(
  better_supabase.settle_approval(current_setting('test.second')::uuid, 'rejected', 'timed out') ->> 'status',
  'rejected',
  'the service role settles a pending request'
);

select * from finish();
rollback;
