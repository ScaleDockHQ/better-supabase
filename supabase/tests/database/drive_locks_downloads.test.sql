-- Drive check-out locks, download blocks, link downloads and previews on the
-- fixture's access contract. Ann (…a1) owns Acme (…0001) and Ben (…a2) is a
-- member; Carl (…a3) owns Globex (…0002) and is not an Acme member
-- (supabase/seed.sql).
begin;
select plan(24);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

-- Ann uploads a file and shares it with Ben as a viewer.
select set_config(
  'test.created',
  api.drive_create_file('00000000-0000-4000-8000-000000000001', null, 'Spec.pdf', 'application/pdf', 10)::text,
  true
);
select set_config('test.node', current_setting('test.created')::jsonb -> 'node' ->> 'id', true);
select set_config('test.v1', current_setting('test.created')::jsonb -> 'attachment' ->> 'id', true);
reset role;
update better_supabase.attachments set uploaded_at = now() where id = current_setting('test.v1')::uuid;
set local role authenticated;
select api.drive_commit(current_setting('test.node')::uuid, current_setting('test.v1')::uuid);
select api.drive_share(current_setting('test.node')::uuid, 'user', '00000000-0000-4000-8000-0000000000a2', 'viewer');

-- Download blocks.
select is(
  (api.drive_set_download_blocked('node', current_setting('test.node')::uuid, true) ->> 'downloadBlocked')::boolean,
  true,
  'the owner blocks downloads of the file'
);
select is(
  api.drive_can_download(current_setting('test.node')::uuid),
  true,
  'the owner still downloads'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select is(
  api.drive_can_download(current_setting('test.node')::uuid),
  false,
  'a viewer cannot download a blocked file'
);
select is(
  (api.drive_get(current_setting('test.node')::uuid) ->> 'downloadable')::boolean,
  false,
  'the node tells the viewer it is not downloadable'
);
select throws_like(
  $$ select api.drive_set_download_blocked('node', current_setting('test.node')::uuid, false) $$,
  '%not allowed to change downloads%',
  'a viewer cannot lift the block'
);

-- Share links honor the block and their own download flag.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select set_config(
  'test.token',
  api.create_share_link('00000000-0000-4000-8000-000000000001', 'drive_node', current_setting('test.node'), 'view') ->> 'token',
  true
);
select is(
  (api.drive_link(current_setting('test.token')) -> 'link' ->> 'downloadAllowed')::boolean,
  false,
  'a link on a blocked file does not allow downloads'
);
select is(
  api.drive_link(current_setting('test.token')) -> 'object',
  'null'::jsonb,
  'and returns no original'
);
select api.drive_set_download_blocked('node', current_setting('test.node')::uuid, false);
select isnt(
  api.drive_link(current_setting('test.token')) -> 'object',
  'null'::jsonb,
  'lifting the block returns the original'
);
select set_config(
  'test.preview_token',
  api.create_share_link('00000000-0000-4000-8000-000000000001', 'drive_node', current_setting('test.node'), 'download', download_allowed => false) ->> 'token',
  true
);
select is(
  (api.drive_link(current_setting('test.preview_token')) -> 'link' ->> 'downloadAllowed')::boolean,
  false,
  'a link created without downloads keeps the original back'
);
select throws_like(
  $$ select api.create_share_link('00000000-0000-4000-8000-000000000001', 'drive_node', current_setting('test.node'), 'upload') $$,
  '%names a folder%',
  'an upload link on a file is refused'
);

-- Check-out locks. Ben becomes an editor.
select api.drive_share(current_setting('test.node')::uuid, 'user', '00000000-0000-4000-8000-0000000000a2', 'editor');
select is(
  api.drive_lock(current_setting('test.node')::uuid, note => 'Reviewing') ->> 'lockedBy',
  '00000000-0000-4000-8000-0000000000a1',
  'the owner checks the file out'
);
select lives_ok(
  $$ select api.drive_rename(current_setting('test.node')::uuid, 'Spec v2.pdf') $$,
  'the holder still renames it'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select is(
  api.drive_get(current_setting('test.node')::uuid) ->> 'lockNote',
  'Reviewing',
  'others see the lock note'
);
select throws_like(
  $$ select api.drive_rename(current_setting('test.node')::uuid, 'Mine.pdf') $$,
  '%checked out by someone else%',
  'another editor cannot rename a checked-out file'
);
select throws_like(
  $$ select api.drive_upload_revision(current_setting('test.node')::uuid, 'application/pdf', 12) $$,
  '%checked out by someone else%',
  'nor upload a new version'
);
select throws_like(
  $$ select api.drive_trash(current_setting('test.node')::uuid) $$,
  '%checked out by someone else%',
  'nor trash it'
);
select throws_like(
  $$ select api.drive_lock(current_setting('test.node')::uuid) $$,
  '%checked out by someone else%',
  'nor take the lock'
);
select throws_like(
  $$ select api.drive_unlock(current_setting('test.node')::uuid) $$,
  '%checked out by someone else%',
  'nor release it'
);
select throws_like(
  $$ select api.drive_unlock(current_setting('test.node')::uuid, true) $$,
  '%break someone else''s lock%',
  'an editor cannot force it open'
);

-- The service role bypasses the lock and records previews.
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select is(
  (better_supabase.drive_set_previews(current_setting('test.node')::uuid, current_setting('test.v1')::uuid, 3) ->> 'pages')::integer,
  3,
  'the service role records three preview pages'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;
select is(
  (api.drive_unlock(current_setting('test.node')::uuid, true) ->> 'lockedBy'),
  null,
  'the holder checks the file back in'
);
select is(
  api.drive_previews(current_setting('test.node')::uuid) ->> 'prefix',
  '_previews/00000000-0000-4000-8000-000000000001/' || current_setting('test.node') || '/' || current_setting('test.v1'),
  'previews live under the tenant, node and version'
);
select is(
  jsonb_array_length(api.drive_link(current_setting('test.preview_token')) -> 'previews' -> 'paths'),
  3,
  'a link without downloads still lists the previews'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
select throws_like(
  $$ select api.drive_previews(current_setting('test.node')::uuid) $$,
  '%not found%',
  'a stranger cannot read the previews'
);

select * from finish();
rollback;
