-- Sequences on the fixture's access contract: the admin (…00a1) of Acme
-- (…0001) builds a sequence with an email, a wait and a task step, the
-- member (…00a2) enrolls people, the sync job sends the email steps, a
-- reply ends a run and Globex (…0002) sees nothing.
begin;
select plan(24);

create temporary table ids (name text primary key, id uuid) on commit drop;
grant all on ids to authenticated, anon, service_role;

insert into better_supabase.people (id, tenant_id, name, email, lifecycle) values
  ('00000000-0000-4000-8000-00000000f101', '00000000-0000-4000-8000-000000000001', 'Ann Lead', 'ann@lead.test', 'lead'),
  ('00000000-0000-4000-8000-00000000f102', '00000000-0000-4000-8000-000000000001', 'Ben Lead', 'ben@lead.test', 'lead'),
  ('00000000-0000-4000-8000-00000000f103', '00000000-0000-4000-8000-000000000001', 'Cat Lead', 'cat@lead.test', 'lead');

-- Acme admin.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

insert into ids
select 'box', (api.connect_mail_account(
  '00000000-0000-4000-8000-000000000001', 'gmail', 'sales@acme.test',
  '{"tenant":"00000000-0000-4000-8000-000000000001","key":"mail/sales"}', null
) ->> 'id')::uuid;

select throws_ok(
  $$select api.save_sequence('00000000-0000-4000-8000-000000000001',
    '{"key":"bad","name":"Bad","steps":[{"id":"s1","kind":"call"}]}')$$,
  '22023',
  null,
  'a step kind is email, task or wait'
);
select throws_ok(
  $$select api.save_sequence('00000000-0000-4000-8000-000000000001',
    '{"key":"bad","name":"Bad","steps":[{"id":"s1","kind":"wait","minutes":5},{"id":"s1","kind":"wait","minutes":5}]}')$$,
  '22023',
  null,
  'step ids are unique'
);
select throws_ok(
  $$select api.save_sequence('00000000-0000-4000-8000-000000000001', '{"key":"empty","name":"Empty","status":"active"}')$$,
  '22023',
  null,
  'an active sequence needs a step'
);

insert into ids
select 'seq', (api.save_sequence('00000000-0000-4000-8000-000000000001', jsonb_build_object(
  'key', 'intro', 'name', 'Intro', 'status', 'active', 'accountId', (select id from ids where name = 'box'),
  'steps', '[
    {"id":"hello","kind":"email","subject":"Hi {{firstName}}","text":"Hello"},
    {"id":"pause","kind":"wait","minutes":60},
    {"id":"call","kind":"task","title":"Call the lead"}
  ]'::jsonb)) ->> 'id')::uuid;

select is(
  (api.get_sequence((select id from ids where name = 'seq')) ->> 'version')::integer,
  1,
  'an admin saves an active sequence'
);

-- Acme member.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);

select throws_ok(
  $$select api.save_sequence('00000000-0000-4000-8000-000000000001', '{"key":"mine","name":"Mine"}')$$,
  '42501',
  null,
  'a member can''t manage sequences'
);
select throws_ok(
  $$select api.enroll_in_sequence((select id from ids where name = 'seq'), 'person', '00000000-0000-4000-8000-00000000f101',
    jsonb_build_object('accountId', (select id from ids where name = 'box')))$$,
  '42501',
  null,
  'a member can''t send from another user''s mailbox'
);

insert into ids
select 'ann', (api.enroll_in_sequence((select id from ids where name = 'seq'), 'person', '00000000-0000-4000-8000-00000000f101',
  '{"variables":{"firstName":"Ann"}}') ->> 'id')::uuid;

select is(
  (select x.address || ' ' || x.step from better_supabase.sequence_enrollments x where x.enrollment_id = (select id from ids where name = 'ann')),
  'ann@lead.test hello',
  'a member enrolls a person, who gets their address and the first step'
);
select is(
  api.enroll_in_sequence((select id from ids where name = 'seq'), 'person', '00000000-0000-4000-8000-00000000f101') ->> 'id',
  (select id from ids where name = 'ann')::text,
  'enrolling a running recipient again returns their run'
);
select is(
  (select e.program from better_supabase.enrollments e where e.id = (select id from ids where name = 'ann')),
  'sequence:' || (select id from ids where name = 'seq'),
  'the run is an enrollment in the program sequence:<id>'
);
select throws_ok(
  $$select api.run_due_sequences(10)$$,
  '42501',
  null,
  'a member can''t run sequences'
);

-- Globex owner.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);

select throws_ok(
  $$select api.get_sequence((select id from ids where name = 'seq'))$$,
  'P0002',
  null,
  'another organization can''t read the sequence'
);
select is(
  (select count(*)::integer from better_supabase.sequence_enrollments),
  0,
  'another organization sees no recipients'
);

-- The runner.
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

select is(
  (select jsonb_agg(e ->> 'step' || ':' || (e -> 'to' ->> 'address'))
    from jsonb_array_elements(api.run_due_sequences(10) -> 'emails') e),
  '["{\"id\": \"hello\", \"kind\": \"email\", \"text\": \"Hello\", \"subject\": \"Hi {{firstName}}\"}:ann@lead.test"]'::jsonb,
  'the runner claims the due email step with its recipient'
);
select is(
  jsonb_array_length(api.run_due_sequences(10) -> 'emails'),
  0,
  'a claimed email step is not handed out twice'
);
select is(
  api.sequence_step_sent((select id from ids where name = 'ann'), 'hello', null) ->> 'step',
  'pause',
  'a sent email moves the recipient to the wait step'
);
select is(
  (api.run_due_sequences(10) ->> 'ran')::integer,
  0,
  'a wait step is not due before its minutes pass'
);

reset role;
update better_supabase.sequence_enrollments set next_run_at = now() - interval '1 minute'
where enrollment_id = (select id from ids where name = 'ann');
set local role service_role;

select is(
  (api.run_due_sequences(10) ->> 'ran')::integer,
  2,
  'once due, the wait and the task step run'
);
select is(
  (select x.status from better_supabase.sequence_enrollments x where x.enrollment_id = (select id from ids where name = 'ann')),
  'completed',
  'a recipient with every step done completes'
);
select is(
  (select count(*)::integer from better_supabase.work_items w
    where w.tenant_id = '00000000-0000-4000-8000-000000000001' and w.title = 'Call the lead'),
  1,
  'the task step creates a work item'
);

-- A reply ends a run.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

insert into ids
select 'ben', (api.enroll_in_sequence((select id from ids where name = 'seq'), 'person', '00000000-0000-4000-8000-00000000f102') ->> 'id')::uuid;
select api.change_sequence_enrollment((select id from ids where name = 'ben'), 'pause');

select is(
  api.change_sequence_enrollment((select id from ids where name = 'ben'), 'resume') ->> 'status',
  'active',
  'a member pauses and resumes a run'
);

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

select api.ingest_mail((select id from ids where name = 'box'), '[
  {"externalId":"r1","threadId":"rt1","from":{"address":"Ben@Lead.test"},"to":[{"address":"sales@acme.test"}],
   "subject":"Re: Hi","sentAt":"2026-10-01T09:00:00Z"}
]', null);

select is(
  (select x.status || ':' || x.exit_reason from better_supabase.sequence_enrollments x where x.enrollment_id = (select id from ids where name = 'ben')),
  'exited:replied',
  'an inbound message from the recipient ends their run'
);
select is(
  (select e.status from better_supabase.enrollments e where e.id = (select id from ids where name = 'ben')),
  'cancelled',
  'the exited run cancels its enrollment'
);

-- Three failed sends end a run.
reset role;
insert into ids
select 'cat', (better_supabase.enroll_in_sequence((select id from ids where name = 'seq'), 'person', '00000000-0000-4000-8000-00000000f103') ->> 'id')::uuid;
set local role service_role;

select api.run_due_sequences(10);
select api.sequence_step_failed((select id from ids where name = 'cat'), 'hello', 'smtp down');
reset role;
update better_supabase.sequence_enrollments set next_run_at = now() - interval '1 minute' where enrollment_id = (select id from ids where name = 'cat');
set local role service_role;
select api.run_due_sequences(10);
select api.sequence_step_failed((select id from ids where name = 'cat'), 'hello', 'smtp down');
reset role;
update better_supabase.sequence_enrollments set next_run_at = now() - interval '1 minute' where enrollment_id = (select id from ids where name = 'cat');
set local role service_role;
select api.run_due_sequences(10);

select is(
  api.sequence_step_failed((select id from ids where name = 'cat'), 'hello', 'smtp down') ->> 'exitReason',
  'failed',
  'the third failed send ends the run'
);

-- Archiving ends every run.
reset role;
insert into ids
select 'ann2', (better_supabase.enroll_in_sequence((select id from ids where name = 'seq'), 'person', '00000000-0000-4000-8000-00000000f101') ->> 'id')::uuid;
select better_supabase.save_sequence('00000000-0000-4000-8000-000000000001',
  jsonb_build_object('id', (select id from ids where name = 'seq'), 'status', 'archived'));

select is(
  (select x.exit_reason from better_supabase.sequence_enrollments x where x.enrollment_id = (select id from ids where name = 'ann2')),
  'archived',
  'archiving a sequence ends its running recipients'
);

select * from finish();
rollback;
