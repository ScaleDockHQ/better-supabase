-- The drive's upload-only role and file requests on the fixture's access
-- contract (options.uploadRole is "contributor"). Ann (…a1) owns Acme
-- (…0001) and Ben (…a2) is a member; Carl (…a3) owns Globex (…0002) and is
-- not an Acme member (supabase/seed.sql).
begin;
select plan(20);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

-- Ann makes an inbox folder and lets Ben contribute to it.
select set_config(
  'test.folder',
  api.drive_create_folder('00000000-0000-4000-8000-000000000001', null, 'Inbox') ->> 'id',
  true
);
select set_config(
  'test.other',
  api.drive_create_folder('00000000-0000-4000-8000-000000000001', null, 'Private') ->> 'id',
  true
);
select set_config(
  'test.file',
  api.drive_create_file('00000000-0000-4000-8000-000000000001', current_setting('test.folder')::uuid, 'Brief.pdf', 'application/pdf', 10) -> 'node' ->> 'id',
  true
);
select is(
  api.drive_share(current_setting('test.folder')::uuid, 'user', '00000000-0000-4000-8000-0000000000a2', 'contributor') ->> 'role',
  'contributor',
  'the owner grants the upload role on a folder'
);
select throws_like(
  $$ select api.drive_share(current_setting('test.file')::uuid, 'user', '00000000-0000-4000-8000-0000000000a2', 'contributor') $$,
  '%upload role is for folders%',
  'the upload role is refused on a file'
);

-- Ben adds a file he can't read back.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select is(
  api.drive_can_upload(current_setting('test.folder')::uuid),
  true,
  'a contributor may upload to the folder'
);
select is(
  api.drive_can_upload(current_setting('test.other')::uuid),
  false,
  'but not to a folder without the grant'
);
select throws_like(
  $$ select api.drive_get(current_setting('test.folder')::uuid) $$,
  '%not found%',
  'a contributor cannot open the folder'
);
select throws_like(
  $$ select api.drive_get(current_setting('test.file')::uuid) $$,
  '%not found%',
  'nor read the files in it'
);
select set_config(
  'test.contributed',
  api.drive_create_file('00000000-0000-4000-8000-000000000001', current_setting('test.folder')::uuid, 'Brief.pdf', 'application/pdf', 12)::text,
  true
);
select ok(
  not (current_setting('test.contributed')::jsonb ? 'node')
    and current_setting('test.contributed')::jsonb ? 'attachment',
  'a contribution returns its id and upload, not the node'
);
select throws_like(
  $$ select api.drive_create_file('00000000-0000-4000-8000-000000000001', current_setting('test.other')::uuid, 'Notes.txt', 'text/plain', 3) $$,
  '%not%',
  'a folder without the grant takes no files'
);
reset role;
update better_supabase.attachments set uploaded_at = now()
where id = (current_setting('test.contributed')::jsonb -> 'attachment' ->> 'id')::uuid;
set local role authenticated;
select is(
  (api.drive_commit(
    (current_setting('test.contributed')::jsonb ->> 'id')::uuid,
    (current_setting('test.contributed')::jsonb -> 'attachment' ->> 'id')::uuid
  ) ->> 'committed')::boolean,
  true,
  'the contributor commits the upload without seeing the node'
);
select ok(
  not (api.drive_upload_revision((current_setting('test.contributed')::jsonb ->> 'id')::uuid, 'application/pdf', 14) ? 'node'),
  'and uploads a new revision of their own file'
);
select throws_like(
  $$ select api.drive_upload_revision(current_setting('test.file')::uuid, 'application/pdf', 14) $$,
  '%not found%',
  'but not of anyone else''s'
);
select throws_like(
  $$ select api.drive_request_files(current_setting('test.folder')::uuid) $$,
  '%not found%',
  'a contributor cannot create a file request'
);

-- Ann asks people outside Acme for files.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select set_config(
  'test.request',
  api.drive_request_files(current_setting('test.folder')::uuid) ->> 'token',
  true
);
select set_config(
  'test.locked',
  api.drive_request_files(current_setting('test.folder')::uuid, password => 'open sesame') ->> 'token',
  true
);
select set_config(
  'test.view',
  api.create_share_link('00000000-0000-4000-8000-000000000001', 'drive_node', current_setting('test.folder'), 'view') ->> 'token',
  true
);
select is(
  (api.drive_get(current_setting('test.folder')::uuid) ->> 'id'),
  current_setting('test.folder'),
  'the owner still reads the folder'
);

reset role;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;
select set_config(
  'test.sent',
  api.drive_link_upload(current_setting('test.request'), 'Invoice.pdf', 'application/pdf', 5)::text,
  true
);
select ok(
  current_setting('test.sent')::jsonb ? 'nodeId'
    and current_setting('test.sent')::jsonb ->> 'path' is not null,
  'anyone with the token gets an upload for a new file'
);
select is(
  api.drive_link_upload(current_setting('test.locked'), 'Invoice.pdf', 'application/pdf', 5),
  '{"passwordRequired": true}'::jsonb,
  'a request with a password asks for it'
);
select ok(
  api.drive_link_upload(current_setting('test.locked'), 'Invoice.pdf', 'application/pdf', 5, 'open sesame') ? 'nodeId',
  'and takes the file once it gets it'
);
select throws_like(
  $$ select api.drive_link_upload(current_setting('test.view'), 'Invoice.pdf', 'application/pdf', 5) $$,
  '%only an upload link takes files%',
  'a view link takes no files'
);
select throws_like(
  $$ select api.drive_link_upload('not-a-token', 'Invoice.pdf', 'application/pdf', 5) $$,
  '%does not exist%',
  'an unknown token takes no files'
);

reset role;
select is(
  (select array[source, coalesce(created_by::text, 'none'), name] from better_supabase.drive_nodes
   where id = (current_setting('test.sent')::jsonb ->> 'nodeId')::uuid),
  array['request', 'none', 'Invoice.pdf'],
  'a request upload has no creator and source request'
);

select isnt(
  (select name from better_supabase.drive_nodes
   where id = (current_setting('test.contributed')::jsonb ->> 'id')::uuid),
  'Brief.pdf',
  'a contribution takes a free name next to a file of the same name'
);

select * from finish();
rollback;
