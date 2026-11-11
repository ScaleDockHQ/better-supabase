-- Comment and message reads check each conversation once and read the rows
-- as their owner; what each caller sees stays the same. Acme (…0001) has the
-- owner …a1 and the member …a2; Globex (…0002) has the owner …a3
-- (supabase/seed.sql).
begin;
select plan(20);

create temp table ids (name text primary key, id uuid);
grant select on ids to public;

insert into ids values
  ('acme_project', gen_random_uuid()),
  ('globex_project', gen_random_uuid()),
  ('acme_conv', gen_random_uuid()),
  ('globex_conv', gen_random_uuid()),
  ('sent', gen_random_uuid()),
  ('draft', gen_random_uuid()),
  ('globex_sent', gen_random_uuid());

insert into public.projects (id, organization_id, name)
select (select id from ids where name = 'acme_project'), '00000000-0000-4000-8000-000000000001', 'Acme comments'
union all
select (select id from ids where name = 'globex_project'), '00000000-0000-4000-8000-000000000002', 'Globex comments';

insert into better_supabase.conversations (id, tenant_id, kind, access, subject_type, subject_id)
select (select id from ids where name = 'acme_conv'), '00000000-0000-4000-8000-000000000001', 'subject', 'subject', 'project', (select id from ids where name = 'acme_project')::text
union all
select (select id from ids where name = 'globex_conv'), '00000000-0000-4000-8000-000000000002', 'subject', 'subject', 'project', (select id from ids where name = 'globex_project')::text;

insert into better_supabase.messages (id, tenant_id, conversation_id, author_id, body, sent_at, scheduled_at)
values
  ((select id from ids where name = 'sent'), '00000000-0000-4000-8000-000000000001', (select id from ids where name = 'acme_conv'), '00000000-0000-4000-8000-0000000000a1', 'Sent comment', now(), null),
  ((select id from ids where name = 'draft'), '00000000-0000-4000-8000-000000000001', (select id from ids where name = 'acme_conv'), '00000000-0000-4000-8000-0000000000a2', 'Scheduled comment', null, now() + interval '1 day'),
  ((select id from ids where name = 'globex_sent'), '00000000-0000-4000-8000-000000000002', (select id from ids where name = 'globex_conv'), '00000000-0000-4000-8000-0000000000a3', 'Globex comment', now(), null);

select id as acme_project from ids where name = 'acme_project' \gset
select id as globex_project from ids where name = 'globex_project' \gset
select id as sent from ids where name = 'sent' \gset
select id as draft from ids where name = 'draft' \gset
select id as globex_sent from ids where name = 'globex_sent' \gset

-- Acme member, the author of the scheduled comment.
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated"}', true);
set local role authenticated;

select is(
  jsonb_array_length(better_supabase.list_comments('00000000-0000-4000-8000-000000000001', 'project', :'acme_project')),
  1,
  'a member reads the sent comment on a record'
);
select is(
  better_supabase.list_comments('00000000-0000-4000-8000-000000000001', 'project', :'acme_project') -> 0 ->> 'subject_id',
  :'acme_project',
  'a listed comment carries its record'
);
select is(
  better_supabase.get_message(:'draft') ->> 'body',
  'Scheduled comment',
  'the author reads their own scheduled comment'
);
select is(
  jsonb_array_length(better_supabase.messaging_messages_json(array[:'sent', :'draft']::uuid[])),
  2,
  'the author reads the sent comment and their own scheduled one'
);
select is(
  better_supabase.comment_counts('00000000-0000-4000-8000-000000000001', 'project', array[:'acme_project']) ->> :'acme_project',
  '1',
  'comment_counts counts the sent comment only'
);
select is(
  better_supabase.list_comments('00000000-0000-4000-8000-000000000002', 'project', :'globex_project'),
  '[]'::jsonb,
  'a user outside the tenant reads no comments on its record'
);
select is(
  better_supabase.messaging_messages_json(array[:'globex_sent']::uuid[]),
  '[]'::jsonb,
  'a user outside the tenant reads none of its messages by id'
);
select is(
  (select count(*) from better_supabase.messaging_message_rows(array[:'globex_sent']::uuid[])),
  0::bigint,
  'the message rows helper returns no message of a conversation the caller cannot read'
);
select is(
  better_supabase.comment_counts('00000000-0000-4000-8000-000000000002', 'project', array[:'globex_project']),
  '{}'::jsonb,
  'a user outside the tenant counts no comments'
);
select is(
  has_function_privilege('better_supabase.list_comments_unchecked(uuid, text, text, timestamptz, integer, integer, uuid, boolean)', 'execute'),
  false,
  'a signed-in user cannot call list_comments_unchecked'
);
select is(
  has_function_privilege('better_supabase.messaging_messages_json_unchecked(uuid[])', 'execute'),
  false,
  'a signed-in user cannot call messaging_messages_json_unchecked'
);

-- Acme owner, not the author.
reset role;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}', true);
set local role authenticated;

select is(
  better_supabase.get_message(:'draft'),
  null,
  'another member does not read a scheduled comment'
);
select is(
  jsonb_array_length(better_supabase.messaging_messages_json(array[:'sent', :'draft']::uuid[])),
  1,
  'another member reads the sent comment only'
);
select is(
  (select count(*) from better_supabase.messaging_message_rows(array[:'sent', :'draft']::uuid[])),
  1::bigint,
  'the message rows helper leaves out another author''s scheduled comment'
);

-- The member again, with a token whose session was signed out: the record's
-- policies refuse it, and so does every read of its comments.
reset role;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","session_id":"00000000-0000-4000-8000-00000000dead"}', true);
set local role authenticated;

select is(
  better_supabase.list_comments('00000000-0000-4000-8000-000000000001', 'project', :'acme_project'),
  '[]'::jsonb,
  'an ended session reads no comments'
);
select is(
  better_supabase.get_message(:'sent'),
  null,
  'an ended session reads no message by id'
);
select is(
  better_supabase.comment_counts('00000000-0000-4000-8000-000000000001', 'project', array[:'acme_project']),
  '{}'::jsonb,
  'an ended session counts no comments'
);

-- Anonymous.
reset role;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;

select is(
  has_function_privilege('better_supabase.messaging_message_rows(uuid[])', 'execute'),
  false,
  'anon cannot call the message rows helper'
);

-- The service role, for an app's own security definer read after its check.
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

select is(
  jsonb_array_length(better_supabase.list_comments_unchecked('00000000-0000-4000-8000-000000000001', 'project', :'acme_project')),
  1,
  'list_comments_unchecked returns the record''s sent comments'
);
select is(
  better_supabase.list_comments_unchecked('00000000-0000-4000-8000-000000000001', 'project', :'acme_project'),
  better_supabase.list_comments('00000000-0000-4000-8000-000000000001', 'project', :'acme_project'),
  'list_comments_unchecked returns what list_comments returns'
);

select * from finish();
rollback;
