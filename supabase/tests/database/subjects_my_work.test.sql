-- my_work on the fixture: what waits on the caller across the installed
-- blocks. Acme (…0001) owns Road Runner Inc (…a001) and Globex (…0002) owns
-- Initech (…a003) (supabase/seed.sql). The caller is the Acme member …00a2;
-- the admin …00a1 writes the comments, since a self-mention is dropped.
begin;
select plan(6);

-- The seed assigns the member to Acme's work items; start from none.
delete from better_supabase.work_item_assignees where user_id = '00000000-0000-4000-8000-0000000000a2';

insert into better_supabase.work_items (id, tenant_id, number, identifier, title, due_at, archived_at) values
  ('00000000-0000-4000-8000-00000000f001', '00000000-0000-4000-8000-000000000001', 9001, 'MW-9001', 'Ship it', '2026-12-01T00:00:00Z', null),
  ('00000000-0000-4000-8000-00000000f002', '00000000-0000-4000-8000-000000000001', 9002, 'MW-9002', 'Archived', null, '2026-01-01T00:00:00Z');

insert into better_supabase.work_item_assignees (tenant_id, work_item_id, user_id) values
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000f001', '00000000-0000-4000-8000-0000000000a2'),
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000f002', '00000000-0000-4000-8000-0000000000a2');

insert into better_supabase.conversations (id, tenant_id, kind, access, subject_type, subject_id) values
  ('00000000-0000-4000-8000-0000000cf001', '00000000-0000-4000-8000-000000000001', 'subject', 'subject', 'customer', '00000000-0000-4000-8000-00000000a001'),
  ('00000000-0000-4000-8000-0000000cf002', '00000000-0000-4000-8000-000000000002', 'subject', 'subject', 'customer', '00000000-0000-4000-8000-00000000a003');
insert into better_supabase.messages (tenant_id, conversation_id, author_id, body, mentions, sent_at) values
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000cf001', '00000000-0000-4000-8000-0000000000a1', 'Look', array['00000000-0000-4000-8000-0000000000a2']::uuid[], now()),
  ('00000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-0000000cf002', '00000000-0000-4000-8000-0000000000a1', 'Elsewhere', array['00000000-0000-4000-8000-0000000000a2']::uuid[], now());

insert into better_supabase.reminders (id, tenant_id, subject_type, subject_id, user_id, offset_minutes) values
  ('00000000-0000-4000-8000-00000000f101', '00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', '00000000-0000-4000-8000-0000000000a2', 0),
  ('00000000-0000-4000-8000-00000000f102', '00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', '00000000-0000-4000-8000-0000000000a1', 0);

insert into better_supabase.reminder_deliveries (reminder_id, occurrence_at, sent_at) values
  ('00000000-0000-4000-8000-00000000f101', now(), now()),
  ('00000000-0000-4000-8000-00000000f102', now(), now());

select is(
  (select api.my_work()),
  '[]'::jsonb,
  'a caller without a user has no work'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  (select jsonb_agg(w ->> 'kind' order by w ->> 'kind') from jsonb_array_elements(api.my_work()) w),
  '["assigned", "mention", "reminder"]'::jsonb,
  'lists the open assigned item, the visible mention and the caller''s own reminder'
);
select is(
  (select w - 'url' from jsonb_array_elements(api.my_work()) w where w ->> 'kind' = 'assigned'),
  jsonb_build_object(
    'kind', 'assigned',
    'subject', jsonb_build_object('type', 'task', 'id', '00000000-0000-4000-8000-00000000f001'),
    'ref', '00000000-0000-4000-8000-00000000f001',
    'title', 'Ship it',
    'at', '2026-12-01T00:00:00+00:00'
  ),
  'an assigned item carries its title and due date'
);
select is(
  (select w ->> 'title' from jsonb_array_elements(api.my_work()) w where w ->> 'kind' = 'mention'),
  'Road Runner Inc',
  'a mention takes its subject''s title'
);
select is(
  jsonb_array_length(api.my_work(page_size => 1)),
  1,
  'page_size caps the items'
);
select is(
  api.my_work('00000000-0000-4000-8000-000000000002'),
  '[]'::jsonb,
  'another tenant has no work for the caller'
);

select * from finish();
rollback;
