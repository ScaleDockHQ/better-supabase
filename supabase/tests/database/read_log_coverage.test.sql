-- Read logging beyond record_summary (subjects.customer.auditReads): the
-- activity list and the attachment list log a read of the record they return.
-- Acme (…0001) owns Road Runner Inc (…a001), with a1 as its owner and a2 as a
-- member who reads customers (supabase/seed.sql).
begin;
select plan(5);

insert into better_supabase.activities (id, tenant_id, type, title, created_by) values
  ('00000000-0000-4000-8000-0000000ac001', '00000000-0000-4000-8000-000000000001', 'note', 'Called back', '00000000-0000-4000-8000-0000000000a2');
insert into better_supabase.engagement_subjects (tenant_id, activity_id, subject_type, subject_id) values
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000ac001', 'customer', '00000000-0000-4000-8000-00000000a001');
insert into better_supabase.attachments (organization_id, subject_type, subject_id, name, mime_type, size, status, uploaded_at) values
  ('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', 'a.pdf', 'application/pdf', 10, 'clean', '2026-01-01T09:00:00Z');

create temporary view reads_of_a001 as
select actor_id, metadata ->> 'function' as fn
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

select is(
  jsonb_array_length(better_supabase.activities_of('customer', '00000000-0000-4000-8000-00000000a001', null, null, 10)),
  1,
  'the member lists the record''s activities'
);

reset role;
select is(
  (select array_agg(fn) from reads_of_a001 where actor_id = '00000000-0000-4000-8000-0000000000a2'),
  array['activities_of'],
  'listing activities logs a read of the record'
);

-- Acme owner.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  jsonb_array_length(better_supabase.list_attachments('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001')),
  1,
  'the owner lists the record''s attachments'
);

reset role;
select is(
  (select array_agg(fn) from reads_of_a001 where actor_id = '00000000-0000-4000-8000-0000000000a1'),
  array['list_attachments'],
  'listing attachments logs a read of the record'
);

set local role authenticated;
select lives_ok(
  $$select better_supabase.list_attachments('00000000-0000-4000-8000-000000000001')$$,
  'listing every attachment of the organization logs no single record'
);

select * from finish();
rollback;
