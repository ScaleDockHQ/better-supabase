-- offboard_with_work (ADR 1235): people.offboard as one function. The owner
-- (…a1) of Acme (…0001) offboards an seeded employee of the member (…a2). The
-- function ends the employment, cancels the active enrollment and releases the
-- upcoming assigned shift; a shift outside the window stays.
begin;
select plan(8);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

create temporary table ids (name text primary key, id uuid) on commit drop;
grant all on ids to authenticated;

insert into ids select 'emp', id from better_supabase.employees
where user_id = '00000000-0000-4000-8000-0000000000a2' limit 1;

select better_supabase.save_enrollment_program(
  '00000000-0000-4000-8000-000000000001',
  '{"key":"leaver-setup","name":"Leaver setup","subjectTypes":["employee"],"steps":[{"id":"kickoff"}]}');
insert into ids values ('enrollment', (better_supabase.enroll(
  '00000000-0000-4000-8000-000000000001', 'leaver-setup', 'employee',
  (select id::text from ids where name = 'emp')) ->> 'id')::uuid);

insert into ids values ('soon', (better_supabase.save_shift('00000000-0000-4000-8000-000000000001',
  ((current_date + 3) + time '06:00') at time zone 'UTC',
  ((current_date + 3) + time '14:00') at time zone 'UTC') ->> 'id')::uuid);
insert into ids values ('later', (better_supabase.save_shift('00000000-0000-4000-8000-000000000001',
  ((current_date + 60) + time '06:00') at time zone 'UTC',
  ((current_date + 60) + time '14:00') at time zone 'UTC') ->> 'id')::uuid);
insert into ids values ('soon_assignment', (better_supabase.assign_shift(
  (select id from ids where name = 'soon'), '00000000-0000-4000-8000-0000000000a2') ->> 'id')::uuid);
insert into ids values ('later_assignment', (better_supabase.assign_shift(
  (select id from ids where name = 'later'), '00000000-0000-4000-8000-0000000000a2') ->> 'id')::uuid);

select set_config(
  'test.result',
  better_supabase.offboard_with_work((select id from ids where name = 'emp'), null, 'moved')::text,
  true);

select is(current_setting('test.result')::jsonb #>> '{employee,status}', 'offboarded', 'the employee is offboarded');
select is((current_setting('test.result')::jsonb ->> 'enrollments')::int, 1, 'one enrollment ended');
select is((current_setting('test.result')::jsonb ->> 'assignments')::int, 1, 'one assignment released');
select is(
  (select status from better_supabase.enrollments where id = (select id from ids where name = 'enrollment')),
  'cancelled', 'the enrollment is cancelled');
select is(
  (select status from better_supabase.shift_assignments where id = (select id from ids where name = 'soon_assignment')),
  'released', 'the shift inside the window is released');
select is(
  (select status from better_supabase.shift_assignments where id = (select id from ids where name = 'later_assignment')),
  'assigned', 'the shift outside the window stays');
select is(
  (better_supabase.offboard_with_work((select id from ids where name = 'emp'), null, 'moved') ->> 'enrollments')::int,
  0, 'running it again ends nothing more');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true);
select throws_ok(
  $$select better_supabase.offboard_with_work((select id from ids where name = 'emp'), null, null)$$,
  'P0002', null, 'a member can''t offboard');

select * from finish();
rollback;
