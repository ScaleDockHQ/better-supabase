-- The meetings module against the seed: the Acme owner (…a1) plans a meeting
-- with the member …a2 as attendee, starts it, records and decides a decision
-- and opens an action item as a task. The member can't start or decide, and
-- the Globex owner (…a3) sees none of it. Run with `supabase test db`.
begin;
select plan(23);

select is(
  (select count(*) from pg_catalog.pg_tables
   where schemaname = 'better_supabase'
     and tablename in ('meetings', 'meeting_attendees', 'meeting_agenda_items', 'meeting_decisions', 'meeting_action_items')
     and rowsecurity),
  5::bigint,
  'the meetings tables have RLS enabled'
);
select table_privs_are('better_supabase', 'meetings', 'anon', '{}'::text[],
  'anon has no privileges on meetings');
select table_privs_are('better_supabase', 'meeting_decisions', 'anon', '{}'::text[],
  'anon has no privileges on decisions');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

create temporary table ids (name text primary key, id uuid) on commit drop;
insert into ids values ('board', (better_supabase.create_meeting(
  '00000000-0000-4000-8000-000000000001',
  jsonb_build_object(
    'kind', 'board',
    'title', 'Quarterly board meeting',
    'startsAt', '2027-03-01T10:00:00Z',
    'endsAt', '2027-03-01T11:00:00Z',
    'attendees', jsonb_build_array(jsonb_build_object(
      'userId', '00000000-0000-4000-8000-0000000000a2', 'role', 'attendee')),
    'agenda', jsonb_build_array(jsonb_build_object('title', 'Budget'))
  )) ->> 'id')::uuid);

select is(
  (select status from better_supabase.meetings where id = (select id from ids where name = 'board')),
  'planned',
  'a new meeting starts planned'
);
select is(
  (select count(*) from better_supabase.meeting_agenda_items
   where meeting_id = (select id from ids where name = 'board')),
  1::bigint,
  'the agenda comes with the meeting'
);
select is(
  better_supabase.get_meeting((select id from ids where name = 'board')) -> 'fields' ->> 'room_code',
  null,
  'a meeting without fields reads an empty room code'
);
select is(
  better_supabase.update_meeting((select id from ids where name = 'board'),
    jsonb_build_object('fields', jsonb_build_object('room_code', 'B-12'))) -> 'fields' ->> 'room_code',
  'B-12',
  'update_meeting sets a custom field'
);
select is(
  better_supabase.update_meeting((select id from ids where name = 'board'),
    jsonb_build_object('title', 'Quarterly board')) -> 'fields' ->> 'room_code',
  'B-12',
  'an update that leaves fields out keeps them'
);
select is(
  (better_supabase.create_meeting(
    '00000000-0000-4000-8000-000000000001',
    jsonb_build_object('title', 'Standup', 'startsAt', '2027-03-02T10:00:00Z',
      'fields', jsonb_build_object('room_code', 'A-1'))) -> 'fields' ->> 'room_code'),
  'A-1',
  'create_meeting sets a custom field in the insert'
);
select throws_ok(
  $$select better_supabase.update_meeting((select id from ids where name = 'board'), '{"fields": "x"}'::jsonb)$$,
  '22023',
  null,
  'fields must be an object'
);
select is(
  better_supabase.set_meeting_attendee(
    (select id from ids where name = 'board'),
    '00000000-0000-4000-8000-0000000000a2', 'secretary') ->> 'role',
  'secretary',
  'setting an attendee again changes the role'
);
select is(
  better_supabase.set_meeting_attendee(
    (select id from ids where name = 'board'),
    '00000000-0000-4000-8000-0000000000a2', 'attendee', 'present') ->> 'attendance',
  'present',
  'the attendance is recorded on the attendee'
);
select throws_ok(
  $$select better_supabase.create_meeting('00000000-0000-4000-8000-000000000001', '{"kind": "astrology", "title": "Odd", "startsAt": "2027-03-01T10:00:00Z"}'::jsonb)$$,
  '22023',
  null,
  'a kind outside options.kinds is refused'
);
select throws_ok(
  $$select better_supabase.record_meeting_decision((select id from ids where name = 'board'), '{"title": ""}'::jsonb)$$,
  '22023',
  null,
  'a decision needs a title'
);

select is(
  better_supabase.start_meeting((select id from ids where name = 'board')) ->> 'status',
  'in_progress',
  'the creator starts the meeting'
);
insert into ids values ('budget', (better_supabase.record_meeting_decision(
  (select id from ids where name = 'board'), '{"title": "Approve the budget"}'::jsonb) ->> 'id')::uuid);
select is(
  better_supabase.decide_meeting_decision((select id from ids where name = 'budget'), 'passed') ->> 'status',
  'passed',
  'the decision passes with an explicit status'
);
select isnt(
  better_supabase.add_meeting_action_item(
    (select id from ids where name = 'board'),
    '{"title": "Send the budget to the bank"}'::jsonb,
    array['00000000-0000-4000-8000-0000000000a2']::uuid[],
    null,
    (select id from ids where name = 'budget')) ->> 'id',
  null,
  'an action item opens a task'
);
select is(
  (select count(*) from better_supabase.meeting_action_items
   where meeting_id = (select id from ids where name = 'board')),
  1::bigint,
  'the action item is linked to the meeting'
);
select is(
  better_supabase.hold_meeting((select id from ids where name = 'board'), 'Budget approved') ->> 'status',
  'held',
  'the creator holds the meeting'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select throws_ok(
  $$select better_supabase.decide_meeting_decision((select id from ids where name = 'budget'), 'rejected')$$,
  '42501',
  null,
  'an attendee cannot decide'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;

select is(
  (select count(*) from better_supabase.meetings),
  0::bigint,
  'another tenant sees no meetings'
);
select throws_ok(
  $$select better_supabase.get_meeting((select id from ids where name = 'board'))$$,
  'P0002',
  null,
  'another tenant cannot read the meeting'
);
select is(
  (select count(*) from better_supabase.meeting_decisions),
  0::bigint,
  'another tenant sees no decisions'
);

select * from finish();
rollback;
