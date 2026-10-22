-- Drive labels and file approvals on the fixture's access contract.
-- Ann (…a1) owns Acme (…0001) and Ben (…a2) is a member; Carl (…a3) owns
-- Globex (…0002) and is not an Acme member (supabase/seed.sql).
begin;
select plan(13);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

-- Ann uploads a file in two versions.
select set_config(
  'test.created',
  api.drive_create_file('00000000-0000-4000-8000-000000000001', null, 'Plan.pdf', 'application/pdf', 10)::text,
  true
);
select set_config('test.node', current_setting('test.created')::jsonb -> 'node' ->> 'id', true);
select set_config('test.v1', current_setting('test.created')::jsonb -> 'attachment' ->> 'id', true);
reset role;
update better_supabase.attachments set uploaded_at = now() where id = current_setting('test.v1')::uuid;
set local role authenticated;
select api.drive_commit(current_setting('test.node')::uuid, current_setting('test.v1')::uuid);

select set_config(
  'test.v2',
  api.drive_upload_revision(current_setting('test.node')::uuid, 'application/pdf', 12) -> 'attachment' ->> 'id',
  true
);
reset role;
update better_supabase.attachments set uploaded_at = now() where id = current_setting('test.v2')::uuid;
set local role authenticated;
select api.drive_commit(current_setting('test.node')::uuid, current_setting('test.v2')::uuid);

-- Labels.
select set_config(
  'test.tag',
  api.create_tag('00000000-0000-4000-8000-000000000001', 'label', 'Final', 'green', null) ->> 'id',
  true
);
select is(
  api.drive_label(current_setting('test.node')::uuid, current_setting('test.tag')::uuid) -> 'labels' -> 0 ->> 'name',
  'Final',
  'an editor labels a file and the node carries the label'
);
select is(
  jsonb_array_length(api.drive_labeled('00000000-0000-4000-8000-000000000001', current_setting('test.tag')::uuid)),
  1,
  'drive_labeled lists the labeled node'
);
select is(
  jsonb_array_length(api.subject_tags('00000000-0000-4000-8000-000000000001', 'drive_node', current_setting('test.node'))),
  1,
  'tags reads the label through the drive grant'
);

-- Approvals target one version.
select is(
  api.drive_request_approval(current_setting('test.node')::uuid, current_setting('test.v1')::uuid, 'Sign off v1') -> 'payload' ->> 'attachmentId',
  current_setting('test.v1'),
  'a request names the version it is for'
);
select is(
  (api.drive_approvals(current_setting('test.node')::uuid) -> 0 ->> 'revision')::integer,
  1,
  'the request carries the revision number'
);
select is(
  (api.drive_approvals(current_setting('test.node')::uuid) -> 0 ->> 'current')::boolean,
  false,
  'an older version is not the current one'
);
select is(
  api.drive_get(current_setting('test.node')::uuid) -> 'approval',
  'null'::jsonb,
  'the current version has no approval yet'
);
select throws_like(
  $$ select api.drive_request_approval(current_setting('test.node')::uuid, gen_random_uuid()) $$,
  '%version of the file was not found%',
  'an attachment of another file is refused'
);
select throws_like(
  $$ select api.drive_request_approval(current_setting('test.node')::uuid) $$,
  '%pending%',
  'one pending request per file'
);

-- Carl is outside Acme and holds no grant on the file.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
select throws_like(
  $$ select api.drive_label(current_setting('test.node')::uuid, current_setting('test.tag')::uuid, false) $$,
  '%not found%',
  'a stranger cannot label the file'
);
select throws_like(
  $$ select api.tag('00000000-0000-4000-8000-000000000001', 'drive_node', current_setting('test.node'), current_setting('test.tag')::uuid) $$,
  '%not allowed%',
  'nor tag it through tags'
);

-- Restoring the first version makes its approval current again.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select api.drive_restore_revision(
  current_setting('test.node')::uuid,
  (select (r ->> 'id')::uuid from jsonb_array_elements(api.drive_revisions(current_setting('test.node')::uuid)) r where (r ->> 'number')::integer = 1)
);
select is(
  api.drive_get(current_setting('test.node')::uuid) -> 'approval' ->> 'status',
  'pending',
  'the restored version brings its approval back'
);
select is(
  jsonb_array_length(api.drive_label(current_setting('test.node')::uuid, current_setting('test.tag')::uuid, false) -> 'labels'),
  0,
  'an editor takes the label off'
);

select * from finish();
rollback;
