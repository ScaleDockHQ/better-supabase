-- The read log on the fixture's customer type (subjects.customer.auditReads).
-- Acme (…0001) owns Road Runner Inc (…a001), with a1 as its owner and a2 as a
-- member who reads customers; a3 belongs to another organization
-- (supabase/seed.sql).
begin;
select plan(16);

create temporary view reads_of_a001 as
select actor_id, metadata
from better_supabase.audit_events
where event_type = 'subject.accessed'
  and record_id = '00000000-0000-4000-8000-00000000a001';
grant select on reads_of_a001 to authenticated;

-- Acme member.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select lives_ok(
  $$select better_supabase.record_summary('customer', '00000000-0000-4000-8000-00000000a001', '{}')$$,
  'the member reads the record summary'
);
select lives_ok(
  $$select better_supabase.record_summary('customer', '00000000-0000-4000-8000-00000000a001', '{}')$$,
  'and reads it again'
);

reset role;
select is(
  (select count(*)::int from reads_of_a001),
  1,
  'two reads within the window write one entry'
);
select is(
  (select metadata - 'organizationId' from reads_of_a001),
  jsonb_build_object(
    'subjectType', 'customer',
    'subjectId', '00000000-0000-4000-8000-00000000a001',
    'purpose', null,
    'emergency', false,
    'block', 'subjects',
    'function', 'record_summary'
  ),
  'the entry names the record, the block and the read function'
);
select is(
  (select category from better_supabase.audit_events
   where event_type = 'subject.accessed' and record_id = '00000000-0000-4000-8000-00000000a001'),
  'read',
  'the entry is under the read category'
);

set local role authenticated;
select lives_ok(
  $$select better_supabase.record_subject_read('customer', '00000000-0000-4000-8000-00000000a001', 'Renewal call')$$,
  'the member logs a read with a purpose'
);
select throws_ok(
  format($$select better_supabase.record_subject_read('customer', '00000000-0000-4000-8000-00000000a001', %L)$$, repeat('x', 501)),
  '22023',
  'purpose takes at most 500 characters',
  'a purpose is at most 500 characters'
);
select throws_ok(
  $$select better_supabase.subject_access_log('customer', '00000000-0000-4000-8000-00000000a001')$$,
  '42501',
  'you may not see who read this record',
  'a member without audit.read or a lead role can''t list the reads'
);

-- An emergency team row for the member.
reset role;
insert into better_supabase.subject_members (tenant_id, subject_type, subject_id, user_id, role, emergency, reason, ends_at)
values ('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001',
  '00000000-0000-4000-8000-0000000000a2', 'member', true, 'The account is down tonight', now() + interval '1 hour');
set local role authenticated;

select lives_ok(
  $$select better_supabase.record_summary('customer', '00000000-0000-4000-8000-00000000a001', '{}')$$,
  'the member reads the record under emergency access'
);

reset role;
select is(
  (select array_agg(coalesce(metadata ->> 'purpose', '-') || ':' || (metadata ->> 'emergency') order by metadata ->> 'purpose' nulls first, metadata ->> 'emergency')
   from reads_of_a001),
  array['-:false', '-:true', 'Renewal call:false'],
  'a new purpose and emergency access each write their own entry'
);

-- Another organization's owner.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;

select lives_ok(
  $$select better_supabase.record_subject_read('customer', '00000000-0000-4000-8000-00000000a001', 'Snooping')$$,
  'an outsider''s call returns'
);
select throws_ok(
  $$select better_supabase.subject_access_log('customer', '00000000-0000-4000-8000-00000000a001')$$,
  '42501',
  'you may not see who read this record',
  'an outsider can''t list the reads'
);

reset role;
select is(
  (select count(*)::int from reads_of_a001 where actor_id = '00000000-0000-4000-8000-0000000000a3'),
  0,
  'a record the caller can''t read logs nothing'
);

-- Acme owner.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  jsonb_array_length(better_supabase.subject_access_log('customer', '00000000-0000-4000-8000-00000000a001')),
  3,
  'the owner lists every read'
);
select throws_ok(
  $$select better_supabase.subject_access_log('application', '00000000-0000-4000-8000-00000000a001')$$,
  '22023',
  'this subject type does not log reads',
  'a type without auditReads has no read log'
);
select throws_ok(
  $$select better_supabase.subject_access_log('customer', '00000000-0000-4000-8000-00000000ffff')$$,
  'P0002',
  'subject not found',
  'a missing record has no read log'
);

select * from finish();
rollback;
