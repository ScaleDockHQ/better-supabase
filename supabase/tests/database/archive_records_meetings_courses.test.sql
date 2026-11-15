-- Archive, restore and purge for meetings and courses (ADR 1045). A held or
-- cancelled meeting is archived and leaves list_meetings; purge replaces
-- delete. A course archives through its status and restores as a draft.
-- Run with `supabase test db`.
begin;
select plan(12);

create function pg_temp.n(t text) returns integer language sql security definer as $$
  select count(*)::integer from better_supabase.outbox_events where type = t
$$;

select set_config('request.jwt.claims', '{"role":"service_role"}', true);

select set_config('test.meeting', (better_supabase.create_meeting(
  '00000000-0000-4000-8000-000000000001',
  '{"kind": "meeting", "title": "Weekly", "startsAt": "2027-02-01T10:00:00Z"}'::jsonb
) ->> 'id'), true);
select set_config('test.planned', (better_supabase.create_meeting(
  '00000000-0000-4000-8000-000000000001',
  '{"kind": "meeting", "title": "Never held", "startsAt": "2027-02-02T10:00:00Z"}'::jsonb
) ->> 'id'), true);

select throws_ok(
  $$select better_supabase.archive_meeting(current_setting('test.meeting')::uuid)$$,
  '22023', null, 'a planned meeting is not archived'
);

select better_supabase.start_meeting(current_setting('test.meeting')::uuid);
select better_supabase.hold_meeting(current_setting('test.meeting')::uuid, null);

select isnt(
  better_supabase.archive_meeting(current_setting('test.meeting')::uuid) ->> 'archivedAt',
  null, 'archive sets archivedAt'
);
select is(pg_temp.n('meeting.archived'), 1, 'archive records meeting.archived once');
select better_supabase.archive_meeting(current_setting('test.meeting')::uuid);
select is(pg_temp.n('meeting.archived'), 1, 'archiving twice records nothing more');
select is(
  (select count(*)::integer from jsonb_array_elements(better_supabase.list_meetings('00000000-0000-4000-8000-000000000001', '{}'))
    where value ->> 'id' = current_setting('test.meeting')),
  0, 'the list hides an archived meeting'
);
select is(
  (select count(*)::integer from jsonb_array_elements(better_supabase.list_meetings('00000000-0000-4000-8000-000000000001', '{"archived": true}'))
    where value ->> 'id' = current_setting('test.meeting')),
  1, 'the archived filter lists it'
);
select throws_ok(
  format($$select better_supabase.update_meeting(%L::uuid, '{"title": "Changed"}'::jsonb)$$, current_setting('test.meeting')),
  '22023', null, 'an archived meeting takes no changes'
);
select is(
  better_supabase.restore_meeting(current_setting('test.meeting')::uuid) ->> 'archivedAt',
  null, 'restore clears archivedAt'
);
select is(pg_temp.n('meeting.restored'), 1, 'restore records meeting.restored once');
select is(
  better_supabase.purge_meeting(current_setting('test.planned')::uuid) ->> 'title',
  'Never held', 'purge removes a planned meeting'
);

select set_config('test.course', (better_supabase.save_course(
  '00000000-0000-4000-8000-000000000001',
  '{"key": "y2-safety", "title": "Safety", "status": "published"}'::jsonb
) ->> 'id'), true);
select is(
  better_supabase.archive_course(current_setting('test.course')::uuid) ->> 'status',
  'archived', 'archive_course sets the archived status'
);
select is(
  better_supabase.restore_course(current_setting('test.course')::uuid) ->> 'status',
  'draft', 'restore_course brings it back as a draft'
);

select * from finish();
rollback;
