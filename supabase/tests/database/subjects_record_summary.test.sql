-- record_summary on the fixture: the record header and tab badges in one
-- call. Acme (…0001) owns Road Runner Inc (…a001) and Globex
-- (…0002) owns Initech (…a003) (supabase/seed.sql). Tags aren't counted:
-- taggings are read through subject_tags.
begin;
select plan(6);

insert into better_supabase.comments (organization_id, subject_type, subject_id, author_id, body, created_at, deleted_at) values
  ('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', '00000000-0000-4000-8000-0000000000a2', 'First', '2026-01-01T10:00:00Z', null),
  ('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', '00000000-0000-4000-8000-0000000000a2', 'Second', '2026-01-02T10:00:00Z', null),
  ('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', '00000000-0000-4000-8000-0000000000a2', '', '2026-01-03T10:00:00Z', '2026-01-03T11:00:00Z');

insert into better_supabase.attachments (organization_id, subject_type, subject_id, name, mime_type, size, status, uploaded_at) values
  ('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', 'a.pdf', 'application/pdf', 10, 'clean', '2026-01-01T09:00:00Z'),
  ('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', 'b.pdf', 'application/pdf', 10, 'infected', '2026-01-04T09:00:00Z'),
  ('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', 'c.pdf', 'application/pdf', 10, 'pending', null);

-- Acme member.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  api.record_summary('customer', '00000000-0000-4000-8000-00000000a001', array['comments', 'attachments', 'tags']),
  jsonb_build_object(
    'type', 'customer',
    'id', '00000000-0000-4000-8000-00000000a001',
    'title', 'Road Runner Inc',
    'url', '/customers/00000000-0000-4000-8000-00000000a001',
    'counts', '{"comments":2,"attachments":1}'::jsonb,
    'unread', '{"comments":false,"attachments":false}'::jsonb
  ),
  'counts uploaded, uninfected attachments and live comments, and leaves out a section it can''t count'
);
select is(
  api.record_summary('customer', '00000000-0000-4000-8000-00000000a001', array['comments'], '2026-01-01T12:00:00Z') -> 'unread',
  '{"comments":true}'::jsonb,
  'a comment newer than seen_at marks the section unread'
);
select is(
  api.record_summary('customer', '00000000-0000-4000-8000-00000000a001', array['comments', 'attachments'], '2026-01-02T12:00:00Z') -> 'unread',
  '{"comments":false,"attachments":false}'::jsonb,
  'a deleted comment or an infected file newer than seen_at does not'
);
select is(
  api.record_summary('customer', '00000000-0000-4000-8000-00000000a001', '{}') -> 'counts',
  '{}'::jsonb,
  'no sections, no counts'
);
select is(
  api.record_summary('customer', '00000000-0000-4000-8000-00000000a003', array['comments']),
  null,
  'a subject the caller can''t read has no summary'
);
select throws_ok(
  $$select api.record_summary('customer', '00000000-0000-4000-8000-00000000a001', array_fill('comments'::text, array[21]))$$,
  '22023',
  'record_summary takes at most 20 sections',
  'more than 20 sections is refused'
);

select * from finish();
rollback;
