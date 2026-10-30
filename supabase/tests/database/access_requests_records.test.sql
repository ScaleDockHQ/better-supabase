-- Record access requests and emergency access on the fixture's customer type
-- (subjects.customer.team grants read and write). Acme (…0001) owns Road
-- Runner Inc (…a001), with a1 as its owner and a2 as a member, who reads
-- customers but can't write them (supabase/seed.sql).
begin;
select plan(15);

create temporary table ids (name text primary key, id uuid) on commit drop;
grant all on ids to authenticated;

-- Acme member.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select throws_ok(
  $$select better_supabase.request_record_access('customer', '00000000-0000-4000-8000-00000000a001', 'read')$$,
  '22023',
  'you already have this access',
  'a member who reads customers has no read access to ask for'
);
select throws_ok(
  $$select better_supabase.request_record_access('customer', '00000000-0000-4000-8000-00000000a001', 'delete')$$,
  '22023',
  'this record or action can''t be requested',
  'an action the team does not grant can''t be requested'
);

insert into ids select 'request', (better_supabase.request_record_access(
  'customer', '00000000-0000-4000-8000-00000000a001', 'write', 'Covering this week', interval '2 days') ->> 'id')::uuid;

select is(
  (select approval_id is not null and granted_at is null
   from better_supabase.access_requests where id = (select id from ids where name = 'request')),
  true,
  'the request waits on an approval'
);
select throws_ok(
  $$select better_supabase.request_record_access('customer', '00000000-0000-4000-8000-00000000a001', 'write')$$,
  '23505',
  'you already have a pending access request for this record',
  'one pending request per record'
);

-- Acme owner, who holds subjects.manage since the record has no lead.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

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
  (select ends_at::date from better_supabase.subject_members
   where subject_type = 'customer' and subject_id = '00000000-0000-4000-8000-00000000a001'
     and user_id = '00000000-0000-4000-8000-0000000000a2'),
  (now() + interval '2 days')::date,
  'the approval adds a team row that ends with the grant'
);

-- Acme member.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select ok(
  better_supabase.can_subject('customer', '00000000-0000-4000-8000-00000000a001', 'write'),
  'the granted member writes the record'
);

select is(
  better_supabase.end_access((select id from ids where name = 'request')) ->> 'status',
  'ended',
  'the member gives the access up'
);
select ok(
  not better_supabase.can_subject('customer', '00000000-0000-4000-8000-00000000a001', 'write'),
  'ending the request ends the team row'
);

select throws_ok(
  $$select better_supabase.open_emergency_access('customer', '00000000-0000-4000-8000-00000000a001', 'urgent')$$,
  '22023',
  'say why you need emergency access, in at least 10 characters',
  'emergency access needs a reason of 10 characters'
);
select throws_ok(
  $$select better_supabase.open_emergency_access('customer', '00000000-0000-4000-8000-00000000a001', 'The account is down tonight')$$,
  '42501',
  'not allowed to open emergency access here',
  'members don''t hold access_requests.emergency'
);

-- An on-call grant for members, in this transaction only.
reset role;
insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id from better_supabase.roles r, better_supabase.permissions p
where r.scope = 'tenant' and r.key = 'member' and p.key = 'access_requests.emergency';
set local role authenticated;

insert into ids select 'emergency', (better_supabase.open_emergency_access(
  'customer', '00000000-0000-4000-8000-00000000a001', 'The account is down tonight') ->> 'id')::uuid;

reset role;
select is(
  (select m.emergency and m.ends_at <= now() + interval '8 hours'
   from better_supabase.access_requests r
   join better_supabase.subject_members m on m.id = r.member_id
   where r.id = (select id from ids where name = 'emergency')),
  true,
  'emergency access is an emergency team row that ends within 8 hours'
);

-- Acme owner reviews it.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  better_supabase.review_emergency_access((select id from ids where name = 'emergency'), 'justified', 'Confirmed on call')
    -> 'review' ->> 'verdict',
  'justified',
  'the owner records a verdict'
);
select throws_ok(
  format($$select better_supabase.review_emergency_access(%L, 'unjustified', null)$$, (select id from ids where name = 'emergency')),
  '22023',
  'this emergency access is already reviewed',
  'a grant is reviewed once'
);
select is(
  jsonb_array_length(better_supabase.list_emergency_access('00000000-0000-4000-8000-000000000001')),
  0,
  'a reviewed grant leaves the unreviewed list'
);

select * from finish();
rollback;
