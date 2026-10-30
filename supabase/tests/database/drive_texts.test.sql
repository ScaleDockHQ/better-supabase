-- Extracted drive text on the fixture's access contract.
-- Ann (…a1) owns Acme (…0001) and Ben (…a2) is a member without a grant on
-- the file; Carl (…a3) owns Globex (…0002) (supabase/seed.sql).
begin;
select plan(11);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config(
  'test.created',
  api.drive_create_file('00000000-0000-4000-8000-000000000001', null, 'Minutes.txt', 'text/plain', 40)::text,
  true
);
select set_config('test.node', current_setting('test.created')::jsonb -> 'node' ->> 'id', true);
select set_config('test.v1', current_setting('test.created')::jsonb -> 'attachment' ->> 'id', true);
reset role;
update better_supabase.attachments set uploaded_at = now() where id = current_setting('test.v1')::uuid;
set local role authenticated;
select api.drive_commit(current_setting('test.node')::uuid, current_setting('test.v1')::uuid);

select throws_like(
  $$ select api.drive_set_text(current_setting('test.node')::uuid, current_setting('test.v1')::uuid, 'forged') $$,
  '%permission denied%',
  'a member cannot write extracted text'
);

-- The service role finds the file by its attachment and stores its text.
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select is(
  api.drive_text_source(attachment => current_setting('test.v1')::uuid) ->> 'nodeId',
  current_setting('test.node'),
  'drive_text_source finds the file by its current attachment'
);
select is(
  api.drive_text_source(attachment => gen_random_uuid()),
  null,
  'an attachment that is no file content has no source'
);
select ok(
  api.drive_set_text(current_setting('test.node')::uuid, current_setting('test.v1')::uuid, 'The quarterly zebra review', 'plain-text'),
  'the service role stores the text of the current attachment'
);
select ok(
  not api.drive_set_text(current_setting('test.node')::uuid, gen_random_uuid(), 'stale'),
  'text of an attachment that is not the current one is not stored'
);

-- Ann reads and finds the file by its content.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;
select is(
  (select content from better_supabase.drive_node_texts where node_id = current_setting('test.node')::uuid),
  'The quarterly zebra review',
  'the owner reads the text'
);
select ok(
  api.search('zebra', array['drive_node'], '00000000-0000-4000-8000-000000000001')::text like '%' || current_setting('test.node') || '%',
  'search finds the file by its content'
);
select throws_like(
  $$ select 1 from better_supabase.drive_node_search $$,
  '%permission denied%',
  'the search view is the service role''s'
);

-- Ben is a member without a grant on the file.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select is(
  (select count(*)::integer from better_supabase.drive_node_texts where node_id = current_setting('test.node')::uuid),
  0,
  'a member without a grant does not read the text'
);
select ok(
  api.search('zebra', array['drive_node'], '00000000-0000-4000-8000-000000000001')::text not like '%' || current_setting('test.node') || '%',
  'nor finds the file by its content'
);

-- Blank text clears the row.
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select api.drive_set_text(current_setting('test.node')::uuid, current_setting('test.v1')::uuid, '   ');
select is(
  (select count(*)::integer from better_supabase.drive_node_texts where node_id = current_setting('test.node')::uuid),
  0,
  'blank text clears the stored text'
);

select * from finish();
rollback;
