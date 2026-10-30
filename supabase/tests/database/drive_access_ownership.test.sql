-- Drive access requests, ownership transfer and the organization's sharing
-- policy on the fixture's drive_node subject (accessRequests on). Ann (…a1)
-- owns Acme (…0001) and Ben (…a2) is a member; Carl (…a3) owns Globex
-- (…0002) and is not an Acme member (supabase/seed.sql).
begin;
select plan(17);

create temporary table ids (name text primary key, id uuid) on commit drop;
grant all on ids to authenticated;

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

-- Ann uploads a file she keeps to herself.
insert into ids select 'node', (api.drive_create_file(
  '00000000-0000-4000-8000-000000000001', null, 'Budget.xlsx', 'application/vnd.ms-excel', 10) -> 'node' ->> 'id')::uuid;

reset role;
select is(
  better_supabase.drive_access_approvers((select id::text from ids where name = 'node')),
  array['00000000-0000-4000-8000-0000000000a1']::uuid[],
  'the owner approves access to the file'
);

-- Ben asks to read it.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select throws_like(
  format($$ select api.drive_get(%L) $$, (select id from ids where name = 'node')),
  '%not found%',
  'a member does not see a file nobody shared'
);

insert into ids select 'request', (better_supabase.request_record_access(
  'drive_node', (select id::text from ids where name = 'node'), 'read', 'Quarterly review', interval '3 days') ->> 'id')::uuid;

select is(
  jsonb_array_length(api.list_record_access_requests('drive_node', (select id::text from ids where name = 'node'))),
  1,
  'the requester sees their own request'
);

-- Ann approves it.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);

select is(
  api.list_record_access_requests('drive_node', (select id::text from ids where name = 'node'), 'pending') -> 0 ->> 'userId',
  '00000000-0000-4000-8000-0000000000a2',
  'the owner lists the pending request'
);
select is(
  api.decide_approval(
    (select approval_id from better_supabase.access_requests where id = (select id from ids where name = 'request')),
    'approved'
  ) ->> 'status',
  'approved',
  'the owner approves the request'
);

reset role;
select is(
  (select role::text || ':' || access_request::text || ':' || (expires_at::date = (now() + interval '3 days')::date)::text
   from better_supabase.drive_grants
   where node_id = (select id from ids where name = 'node') and principal_id = '00000000-0000-4000-8000-0000000000a2'),
  'viewer:true:true',
  'the approval adds a viewer grant marked as an access request that ends with it'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  api.drive_get((select id from ids where name = 'node')) ->> 'name',
  'Budget.xlsx',
  'the granted member reads the file'
);
select is(
  api.list_record_access_requests('drive_node', (select id::text from ids where name = 'node'), 'granted') -> 0 ->> 'status',
  'granted',
  'the request lists as granted'
);
select is(
  better_supabase.end_access((select id from ids where name = 'request')) ->> 'status',
  'ended',
  'the member gives the access up'
);
select throws_like(
  format($$ select api.drive_get(%L) $$, (select id from ids where name = 'node')),
  '%not found%',
  'ending the request removes the grant'
);

-- Ownership moves to Ben.
select throws_like(
  $$ select api.drive_transfer_ownership('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000a2') $$,
  '%can''t transfer items%',
  'a member without drive.manage cannot transfer ownership'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);

select throws_like(
  $$ select api.drive_transfer_ownership('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000a3') $$,
  '%not an active member%',
  'ownership only moves to a member'
);
select cmp_ok(
  (api.drive_transfer_ownership('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000a2') ->> 'nodes')::integer,
  '>=',
  1,
  'the owner moves their items to Ben'
);

reset role;
select is(
  (select principal_id from better_supabase.drive_grants
   where node_id = (select id from ids where name = 'node') and role = 'owner'),
  '00000000-0000-4000-8000-0000000000a2',
  'Ben owns the file'
);

-- The sharing policy turns links and guests off.
insert into better_supabase.organization_settings (organization_id, key, value)
values ('00000000-0000-4000-8000-000000000001', 'drive.sharing', '{"guests": false, "links": "none"}');

select is(
  better_supabase.drive_sharing('00000000-0000-4000-8000-000000000001'),
  '{"guests": false, "links": "none"}'::jsonb,
  'the organization setting overrides the defaults'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select throws_like(
  format($$ select api.create_share_link('00000000-0000-4000-8000-000000000001', 'drive_node', %L, 'view') $$, (select id from ids where name = 'node')),
  '%turned off share links%',
  'a share link is refused when links are off'
);

reset role;
insert into better_supabase.guests (id, tenant_id, email)
values ('00000000-0000-4000-8000-0000000c0001', '00000000-0000-4000-8000-000000000001', 'auditor@example.com');

select throws_like(
  format($$ insert into better_supabase.guest_grants (tenant_id, guest_id, subject_type, subject_id, actions)
    values ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000c0001', 'drive_node', %L, array['read']) $$,
    (select id from ids where name = 'node')),
  '%turned off sharing drive items with guests%',
  'a guest grant on a drive item is refused when guests are off'
);

select * from finish();
rollback;
