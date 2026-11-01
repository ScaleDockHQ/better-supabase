-- Caller flags and name search for the drive helpers.
-- Ann (…a1) owns Acme (…0001); Carl (…a3) owns Globex (…0002) (supabase/seed.sql).
begin;
select plan(5);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config(
  'test.created',
  api.drive_create_file('00000000-0000-4000-8000-000000000001', null, 'Zebra 100%.txt', 'text/plain', 4)::text,
  true
);
select set_config('test.node', current_setting('test.created')::jsonb -> 'node' ->> 'id', true);

select ok(
  (api.drive_node_access(current_setting('test.node')::uuid) ->> 'write')::boolean,
  'the owner may write'
);
select ok(
  (api.drive_node_access(current_setting('test.node')::uuid) ->> 'share')::boolean,
  'the owner may share'
);
select is(
  jsonb_array_length(api.drive_search('00000000-0000-4000-8000-000000000001', 'zebra')),
  1,
  'search finds the file by name'
);
select is(
  jsonb_array_length(api.drive_search('00000000-0000-4000-8000-000000000001', '%')),
  1,
  'a like wildcard is matched literally'
);
select is(
  jsonb_array_length(api.drive_search('00000000-0000-4000-8000-000000000001', '')),
  0,
  'an empty query finds nothing'
);

select * from finish();
rollback;
