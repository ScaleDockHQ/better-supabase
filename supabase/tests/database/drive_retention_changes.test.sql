-- Drive retention per label and the changes feed on the fixture's access
-- contract. Ann (…a1) owns Acme (…0001); Carl (…a3) owns Globex (…0002) and is
-- not an Acme member (supabase/seed.sql).
begin;
select plan(13);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  api.drive_retention_kind('Final  Contract!'),
  'drive_label_final_contract',
  'a label name becomes a policy kind'
);

-- Two labeled files: one stays, one is held.
select set_config(
  'test.a',
  api.drive_create_file('00000000-0000-4000-8000-000000000001', null, 'Old.pdf', 'application/pdf', 10) -> 'node' ->> 'id',
  true
);
select set_config(
  'test.b',
  api.drive_create_file('00000000-0000-4000-8000-000000000001', null, 'Held.pdf', 'application/pdf', 10) -> 'node' ->> 'id',
  true
);
select set_config(
  'test.tag',
  api.create_tag('00000000-0000-4000-8000-000000000001', 'label', 'Contract', null, null) ->> 'id',
  true
);
select api.drive_label(current_setting('test.a')::uuid, current_setting('test.tag')::uuid);
select api.drive_label(current_setting('test.b')::uuid, current_setting('test.tag')::uuid);
select api.drive_hold(current_setting('test.b')::uuid, now() + interval '1 year');

-- Retention: the policy is the tenant's, the sweep is the service role's.
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

select is(
  api.drive_retention_sweep('00000000-0000-4000-8000-000000000001'),
  0,
  'without a policy the sweep bins nothing'
);
select api.set_retention_policy('drive_label_contract', interval '30 days', '00000000-0000-4000-8000-000000000001');
select is(
  api.drive_retention_sweep('00000000-0000-4000-8000-000000000001'),
  0,
  'a fresh labeled file is kept'
);

reset role;
update better_supabase.drive_nodes set updated_at = now() - interval '60 days'
where id in (current_setting('test.a')::uuid, current_setting('test.b')::uuid);
set local role service_role;

select is(
  api.drive_retention_sweep('00000000-0000-4000-8000-000000000001'),
  1,
  'the sweep bins the old file and skips the held one'
);
select is(
  api.drive_retention_sweep('00000000-0000-4000-8000-000000000001'),
  0,
  'a second sweep finds nothing more'
);

reset role;
select isnt(
  (select deleted_at from better_supabase.drive_nodes where id = current_setting('test.a')::uuid),
  null,
  'the swept file is in the bin'
);
select is(
  (select deleted_at from better_supabase.drive_nodes where id = current_setting('test.b')::uuid),
  null,
  'the held file is not'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;
select throws_like(
  $$ select api.drive_retention_sweep('00000000-0000-4000-8000-000000000001') $$,
  '%permission denied%',
  'a signed-in user cannot run the sweep'
);

-- The changes feed waits five seconds, orders by change and ends on a cursor.
select is(
  jsonb_array_length(api.drive_changes('00000000-0000-4000-8000-000000000001') -> 'changes'),
  1,
  'a node binned in the last seconds waits while the older held node is listed'
);
reset role;
update better_supabase.drive_nodes set updated_at = now() - interval '1 minute'
where id in (current_setting('test.a')::uuid, current_setting('test.b')::uuid);
set local role authenticated;

select set_config(
  'test.feed',
  api.drive_changes('00000000-0000-4000-8000-000000000001')::text,
  true
);
select is(
  (select count(*)::integer from jsonb_array_elements(current_setting('test.feed')::jsonb -> 'changes') c where (c ->> 'removed')::boolean),
  1,
  'the binned file comes back as removed and the held one as a node'
);
select is(
  jsonb_array_length(
    api.drive_changes('00000000-0000-4000-8000-000000000001', current_setting('test.feed')::jsonb ->> 'cursor') -> 'changes'
  ),
  0,
  'nothing changed after the cursor'
);
select throws_like(
  $$ select api.drive_changes('00000000-0000-4000-8000-000000000001', 'nonsense') $$,
  '%cursor is not valid%',
  'a bad cursor is refused'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
select throws_like(
  $$ select api.drive_changes('00000000-0000-4000-8000-000000000001') $$,
  '%not allowed%',
  'another organization cannot read the feed'
);

select * from finish();
rollback;
