-- Mail sync: mailboxes, ingested threads matched to parties and logged as
-- engagements. Acme (…0001) has the owner …a1 and the member …a2; Globex
-- (…0002) has the owner …a3 (supabase/seed.sql).
begin;
select plan(17);

create temporary table ids (name text primary key, id uuid) on commit drop;
grant all on ids to authenticated, anon, service_role;

insert into better_supabase.people (id, tenant_id, name, email, lifecycle)
values ('00000000-0000-4000-8000-00000000e001', '00000000-0000-4000-8000-000000000001',
  'Ann Client', 'ann@client.test', 'lead');
insert into better_supabase.companies (id, tenant_id, name, domain, lifecycle)
values ('00000000-0000-4000-8000-00000000e002', '00000000-0000-4000-8000-000000000001',
  'Client', 'client.test', 'lead');

-- Acme member.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

insert into ids
select 'box', (api.connect_mail_account(
  '00000000-0000-4000-8000-000000000001',
  'gmail',
  ' Bob@Acme.test ',
  '{"tenant":"00000000-0000-4000-8000-000000000001","key":"mail/bob"}',
  null
) ->> 'id')::uuid;

select is(
  api.get_mail_account((select id from ids where name = 'box')) ->> 'address',
  'bob@acme.test',
  'a member connects a mailbox; the address is trimmed and lowercased'
);
select throws_ok(
  $$select api.connect_mail_account('00000000-0000-4000-8000-000000000001', 'gmail', 'bob@acme.test',
    '{"tenant":"00000000-0000-4000-8000-000000000002","key":"mail/bob"}', null)$$,
  '42501',
  null,
  'a credential reference of another organization is refused'
);
select throws_ok(
  $$select api.ingest_mail((select id from ids where name = 'box'), '[]', null)$$,
  '42501',
  null,
  'a member cannot ingest mail; only the sync job can'
);

-- Globex owner.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;

select throws_ok(
  $$select api.connect_mail_account('00000000-0000-4000-8000-000000000001', 'gmail', 'eve@globex.test',
    '{"tenant":"00000000-0000-4000-8000-000000000001","key":"mail/eve"}', null)$$,
  '42501',
  null,
  'a member of another organization cannot connect a mailbox here'
);

-- The sync job.
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

select is(
  api.ingest_mail((select id from ids where name = 'box'), '[
    {"externalId":"m1","threadId":"t1","messageId":"<m1@client.test>","from":{"address":"Ann@Client.test","name":"Ann"},
     "to":[{"address":"bob@acme.test"}],"subject":"Pricing","snippet":"What does it cost?","sentAt":"2026-10-01T09:00:00Z"},
    {"externalId":"m2","threadId":"t1","from":{"address":"bob@acme.test"},"to":["ann@client.test"],
     "subject":"Re: Pricing","snippet":"Here is our offer","sentAt":"2026-10-01T10:00:00Z"}
  ]', 'cursor-1'),
  '{"stored": 2, "threads": 1}'::jsonb,
  'the sync job stores two messages on one thread'
);
select is(
  api.ingest_mail((select id from ids where name = 'box'), '[
    {"externalId":"m1","threadId":"t1","from":{"address":"ann@client.test"},"sentAt":"2026-10-01T09:00:00Z"}
  ]', null) ->> 'stored',
  '0',
  'ingesting a message again stores nothing'
);

reset role;
insert into ids select 'thread', x.id from better_supabase.mail_threads x where x.external_id = 't1';

select is(
  (select array_agg(direction order by sent_at) from better_supabase.mail_messages
   where thread_id = (select id from ids where name = 'thread')),
  array['inbound', 'outbound'],
  'the direction follows the mailbox address'
);
select is(
  (select array_agg(subject_type order by subject_type) from better_supabase.mail_thread_subjects
   where thread_id = (select id from ids where name = 'thread')),
  array['company', 'person'],
  'the thread links to the person its address names and the company of its domain'
);
select is(
  (select e.type || ':' || e.title from better_supabase.engagements e
   join better_supabase.mail_threads x on x.engagement_id = e.id
   where x.id = (select id from ids where name = 'thread')),
  'email:Pricing',
  'the thread is logged as an email engagement'
);
select is(
  (select sync_cursor from better_supabase.mail_accounts where id = (select id from ids where name = 'box')),
  'cursor-1',
  'the next sync starts from the saved cursor'
);

-- Acme owner: reads the record, not the mailbox.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  jsonb_array_length(api.mail_threads_of('person', '00000000-0000-4000-8000-00000000e001', null, null)),
  1,
  'a member who can read the person sees the shared thread'
);
select throws_ok(
  $$select api.link_mail_thread((select id from ids where name = 'thread'), '[]')$$,
  'P0002',
  null,
  'only the mailbox owner links its threads'
);

-- Globex owner.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;

select is(
  api.get_mail_thread((select id from ids where name = 'thread')),
  null,
  'another organization cannot read the thread'
);

-- Acme member makes the mailbox private and replies.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  api.record_sent_mail((select id from ids where name = 'box'),
    '{"externalId":"m3","threadId":"t1","from":{"address":"ann@client.test"},"subject":"Re: Pricing","sentAt":"2026-10-02T09:00:00Z"}'
  ) ->> 'direction',
  'outbound',
  'a sent message is stored as outbound whatever its sender says'
);
select is(
  api.update_mail_account((select id from ids where name = 'box'), 'private', null) ->> 'share',
  'private',
  'the owner makes the mailbox private'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  api.get_mail_thread((select id from ids where name = 'thread')),
  null,
  'a private mailbox hides its threads from other members'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select api.disconnect_mail_account((select id from ids where name = 'box'), true);

reset role;
select is(
  (select count(*)::int from better_supabase.mail_threads where account_id = (select id from ids where name = 'box')),
  0,
  'disconnecting with purge deletes the synced threads'
);

select * from finish();
rollback;
