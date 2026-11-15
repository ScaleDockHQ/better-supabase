-- Archive, restore and purge for time entries and activities (ADR 1046 and
-- 1047). An archived entry leaves lists, timesheet totals and the overlap
-- check, a running timer and a locked week refuse it, and a restore into a
-- locked week or over another entry fails. An archived activity leaves the
-- timeline, next step and task list and takes no changes.
-- Run with `supabase test db`.
begin;
select plan(28);

create function pg_temp.n(t text) returns integer language sql security definer as $$
  select count(*)::integer from better_supabase.outbox_events where type = t
$$;

select set_config('request.jwt.claims', '{"role":"service_role"}', true);

insert into better_supabase.time_entries (id, tenant_id, user_id, started_at, ended_at, billable) values
  ('00000000-0000-4000-8000-00000000e101', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a1',
    '2027-03-01 09:00+00', '2027-03-01 11:00+00', true),
  ('00000000-0000-4000-8000-00000000e102', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a1',
    '2027-03-02 09:00+00', '2027-03-02 10:00+00', false),
  ('00000000-0000-4000-8000-00000000e103', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a2',
    '2027-03-03 09:00+00', null, false),
  ('00000000-0000-4000-8000-00000000e104', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a1',
    '2027-04-05 09:00+00', '2027-04-05 10:00+00', false);

select isnt(
  better_supabase.archive_time_entry('00000000-0000-4000-8000-00000000e101') ->> 'archivedAt',
  null, 'archive sets archivedAt on a finished entry'
);
select is(pg_temp.n('time_entry.archived'), 1, 'archive records time_entry.archived once');
select better_supabase.archive_time_entry('00000000-0000-4000-8000-00000000e101');
select is(pg_temp.n('time_entry.archived'), 1, 'archiving twice records nothing more');
select throws_ok(
  $$select better_supabase.archive_time_entry('00000000-0000-4000-8000-00000000e103')$$,
  '55000', null, 'a running timer is not archived'
);

select is(
  (select count(*)::integer from jsonb_array_elements(better_supabase.list_time_entries(
    '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a1', everyone => true))
    where value ->> 'id' = '00000000-0000-4000-8000-00000000e101'),
  0, 'the list hides an archived entry'
);
select is(
  (select count(*)::integer from jsonb_array_elements(better_supabase.list_time_entries(
    '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a1', everyone => true, archived => true))
    where value ->> 'id' = '00000000-0000-4000-8000-00000000e101'),
  1, 'the archived filter lists it'
);
select is(
  better_supabase.get_timesheet('00000000-0000-4000-8000-000000000001', '2027-03-01', '00000000-0000-4000-8000-0000000000a1') -> 'totals' ->> 'seconds',
  '3600', 'the timesheet total leaves the archived entry out'
);
select is(
  better_supabase.get_timesheet('00000000-0000-4000-8000-000000000001', '2027-03-01', '00000000-0000-4000-8000-0000000000a1') -> 'totals' ->> 'billableSeconds',
  '0', 'the billable total leaves it out'
);

-- The archived entry no longer blocks the time it covered.
select lives_ok(
  $$select better_supabase.log_time('00000000-0000-4000-8000-000000000001', '2027-03-01 10:00+00', '2027-03-01 10:30+00',
    user_id => '00000000-0000-4000-8000-0000000000a1')$$,
  'an archived entry does not block an overlapping entry'
);
select throws_ok(
  $$select better_supabase.restore_time_entry('00000000-0000-4000-8000-00000000e101')$$,
  '23P01', null, 'a restore over another entry is refused'
);

delete from better_supabase.time_entries
  where tenant_id = '00000000-0000-4000-8000-000000000001' and started_at = '2027-03-01 10:00+00';

select is(
  better_supabase.restore_time_entry('00000000-0000-4000-8000-00000000e101') ->> 'archivedAt',
  null, 'restore clears archivedAt'
);
select is(pg_temp.n('time_entry.restored'), 1, 'restore records time_entry.restored once');
select is(
  better_supabase.get_timesheet('00000000-0000-4000-8000-000000000001', '2027-03-01', '00000000-0000-4000-8000-0000000000a1') -> 'totals' ->> 'seconds',
  '10800', 'the total counts a restored entry again'
);

-- A locked week refuses an archive, a purge and a restore.
select better_supabase.archive_time_entry('00000000-0000-4000-8000-00000000e104');
insert into better_supabase.time_entries (id, tenant_id, user_id, started_at, ended_at) values
  ('00000000-0000-4000-8000-00000000e105', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a1',
    '2027-04-06 09:00+00', '2027-04-06 10:00+00');
insert into better_supabase.timesheets (tenant_id, user_id, week, submitted_at, approved_at) values
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a1', '2027-04-05', now(), now());
select throws_ok(
  $$select better_supabase.restore_time_entry('00000000-0000-4000-8000-00000000e104')$$,
  '55000', null, 'an archived entry is not restored into a locked week'
);
select throws_ok(
  $$select better_supabase.archive_time_entry('00000000-0000-4000-8000-00000000e105')$$,
  '55000', null, 'a locked week refuses an archive'
);
select throws_ok(
  $$select better_supabase.purge_time_entry('00000000-0000-4000-8000-00000000e105')$$,
  '55000', null, 'a locked week refuses a purge'
);

select better_supabase.archive_time_entry('00000000-0000-4000-8000-00000000e102');
select is(
  better_supabase.purge_time_entry('00000000-0000-4000-8000-00000000e102') ->> 'id',
  '00000000-0000-4000-8000-00000000e102', 'purge removes an archived entry'
);
select is(pg_temp.n('time_entry.purged'), 1, 'purge records time_entry.purged');

-- Activities.
select set_config('test.activity', (better_supabase.log_activity(
  '00000000-0000-4000-8000-000000000001',
  '{"type": "task", "title": "Call back", "ownerId": "00000000-0000-4000-8000-0000000000a1", "dueAt": "2027-06-01T09:00:00Z"}'::jsonb,
  '[{"type": "customer", "id": "00000000-0000-4000-8000-00000000a001"}]'::jsonb
) ->> 'id'), true);

select isnt(
  better_supabase.archive_activity(current_setting('test.activity')::uuid) ->> 'archived_at',
  null, 'archive sets archived_at'
);
select is(pg_temp.n('activity.archived'), 1, 'archive records activity.archived once');
select better_supabase.archive_activity(current_setting('test.activity')::uuid);
select is(pg_temp.n('activity.archived'), 1, 'archiving twice records nothing more');
select is(
  jsonb_array_length(better_supabase.activities_of('customer', '00000000-0000-4000-8000-00000000a001', null, null, 50)),
  0, 'the timeline hides an archived activity'
);
select is(
  jsonb_array_length(better_supabase.activities_of('customer', '00000000-0000-4000-8000-00000000a001', null, null, 50, true)),
  1, 'the archived filter lists it'
);
select is(
  better_supabase.next_activity('customer', '00000000-0000-4000-8000-00000000a001'),
  null, 'it is no longer the next step'
);
select throws_ok(
  format($$select better_supabase.complete_activity(%L::uuid, true, null)$$, current_setting('test.activity')),
  '55000', null, 'an archived activity takes no changes'
);
select is(
  better_supabase.restore_activity(current_setting('test.activity')::uuid) ->> 'archived_at',
  null, 'restore clears archived_at'
);
select is(
  jsonb_array_length(better_supabase.open_activities('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a1', null, 50)) > 0,
  true, 'a restored activity is back in the task list'
);
select is(
  better_supabase.purge_activity(current_setting('test.activity')::uuid),
  true, 'purge removes an activity'
);

select * from finish();
rollback;
