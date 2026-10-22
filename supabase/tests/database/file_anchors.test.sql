-- File anchors on the fixture's access contract: the Acme owner (…a1)
-- comments on a page, a region and a moment of a file on the customer Road
-- Runner (…a001). A file on another record or in Globex (…0002) can't be
-- anchored, and the Globex owner (…a3) lists none of Acme's anchored comments.
begin;
select plan(12);

insert into better_supabase.attachments (id, organization_id, subject_type, subject_id, name, mime_type, size, status, uploaded_by) values
  ('00000000-0000-4000-8000-0000000f1001', '00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', 'contract.pdf', 'application/pdf', 1024, 'clean', '00000000-0000-4000-8000-0000000000a1'),
  ('00000000-0000-4000-8000-0000000f1002', '00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a002', 'quote.pdf', 'application/pdf', 1024, 'clean', '00000000-0000-4000-8000-0000000000a1'),
  ('00000000-0000-4000-8000-0000000f1003', '00000000-0000-4000-8000-000000000002', 'customer', '00000000-0000-4000-8000-00000000a003', 'globex.pdf', 'application/pdf', 1024, 'clean', '00000000-0000-4000-8000-0000000000a3');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  api.create_comment(
    '00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001',
    'Check this clause',
    '{"anchor":{"kind":"file","attachmentId":"00000000-0000-4000-8000-0000000f1001","page":3,"region":{"x":0.1,"y":0.2,"width":0.5,"height":0.1}}}'
  ) -> 'anchor' ->> 'page',
  '3',
  'a comment points at a region on a page of the record''s file'
);
select is(
  api.create_comment(
    '00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001',
    'The intro runs long',
    '{"anchor":{"kind":"file","attachmentId":"00000000-0000-4000-8000-0000000f1001","start":12.5,"end":20}}'
  ) -> 'anchor' ->> 'end',
  '20',
  'a comment points at a span of time'
);
select is(
  api.create_comment(
    '00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001',
    'Typo here',
    '{"anchor":{"from":4,"to":9}}'
  ) -> 'anchor' ->> 'to',
  '9',
  'an anchor that isn''t a file stays any JSON'
);
select throws_ok(
  $$select api.create_comment('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', 'x',
    '{"anchor":{"kind":"file","attachmentId":"00000000-0000-4000-8000-0000000f1001","page":0}}')$$,
  '22023',
  null,
  'a page starts at 1'
);
select throws_ok(
  $$select api.create_comment('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', 'x',
    '{"anchor":{"kind":"file","attachmentId":"00000000-0000-4000-8000-0000000f1001","region":{"x":0.8,"y":0,"width":0.5,"height":0.1}}}')$$,
  '22023',
  null,
  'a region stays inside the page'
);
select throws_ok(
  $$select api.create_comment('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', 'x',
    '{"anchor":{"kind":"file","attachmentId":"00000000-0000-4000-8000-0000000f1001","end":5}}')$$,
  '22023',
  null,
  'a span needs a start'
);
select throws_ok(
  $$select api.create_comment('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', 'x',
    '{"anchor":{"kind":"file","attachmentId":"00000000-0000-4000-8000-0000000f1002","page":1}}')$$,
  '22023',
  null,
  'a file on another record cannot be anchored'
);
select throws_ok(
  $$select api.create_comment('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', 'x',
    '{"anchor":{"kind":"file","attachmentId":"00000000-0000-4000-8000-0000000f1003","page":1}}')$$,
  '22023',
  null,
  'a file in another organization cannot be anchored'
);
select ok(
  not api.messaging_file_anchor_valid('{"kind":"file","page":2}'),
  'a file anchor needs an attachment id'
);
select is(
  jsonb_array_length(api.list_file_comments('00000000-0000-4000-8000-0000000f1001')),
  2,
  'the comments anchored to a file are listed by the file'
);
select is(
  api.list_file_comments('00000000-0000-4000-8000-0000000f1001') -> 0 ->> 'subject_id',
  '00000000-0000-4000-8000-00000000a001',
  'each anchored comment names its record'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;

select is(
  jsonb_array_length(api.list_file_comments('00000000-0000-4000-8000-0000000f1001')),
  0,
  'an outsider lists none of the anchored comments'
);

select * from finish();
rollback;
