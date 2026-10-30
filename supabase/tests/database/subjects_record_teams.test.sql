-- Record teams on the fixture's customer type (subjects.customer.team grants
-- read and write). Acme (…0001) owns Road Runner Inc (…a001), with a1 as its
-- owner and a2 as a member; Globex (…0002) owns Initech (…a003), where a1 is
-- a member (supabase/seed.sql).
begin;
select plan(8);

-- Acme owner, with Acme as the active tenant.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  (better_supabase.add_subject_member('customer', '00000000-0000-4000-8000-00000000a001',
    '00000000-0000-4000-8000-0000000000a2', ends_on => current_date - 1)) ->> 'active',
  'false',
  'a membership that ended yesterday is not active'
);
select throws_ok(
  $$select better_supabase.add_subject_member('customer', '00000000-0000-4000-8000-00000000a003',
    '00000000-0000-4000-8000-0000000000a1')$$,
  '42501',
  'not allowed to manage this record''s team',
  'a plain member of Globex may not manage its records'' teams'
);

-- Acme member.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select ok(
  not better_supabase.is_subject_member('customer', '00000000-0000-4000-8000-00000000a001'),
  'an ended membership gives no access'
);
select throws_ok(
  $$select better_supabase.add_subject_member('customer', '00000000-0000-4000-8000-00000000a001',
    '00000000-0000-4000-8000-0000000000a2', role => 'lead')$$,
  '42501',
  'not allowed to manage this record''s team',
  'a member without subjects.manage may not add to a team'
);

-- Acme owner.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  (better_supabase.add_subject_member('customer', '00000000-0000-4000-8000-00000000a001',
    '00000000-0000-4000-8000-0000000000a2', role => 'lead')) ->> 'active',
  'true',
  'the owner puts the member on the team as lead'
);

-- Acme member.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select ok(
  better_supabase.can_subject('customer', '00000000-0000-4000-8000-00000000a001', 'write'),
  'a current team member may write the record'
);
select is(
  better_supabase.my_subjects('00000000-0000-4000-8000-000000000001') -> 'items' -> 0 ->> 'title',
  'Road Runner Inc',
  'my_subjects lists the record with its title'
);
select is(
  jsonb_array_length(better_supabase.list_subject_members('customer', '00000000-0000-4000-8000-00000000a001')),
  2,
  'the member reads the record''s team, ended rows included'
);

select * from finish();
rollback;
