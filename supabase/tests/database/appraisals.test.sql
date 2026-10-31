-- The appraisals module against the seed: the Acme owner (…a1) opens a cycle
-- for the member (…a2) with themselves as manager. Both write their review,
-- the owner calibrates and signs off. The member can't manage cycles or read
-- the manager's review, and the Globex owner (…a3) sees none of it. Run with
-- `supabase test db`.
begin;
select plan(16);

select is(
  (select count(*) from pg_catalog.pg_tables
   where schemaname = 'better_supabase'
     and tablename in ('appraisal_cycles', 'appraisals', 'appraisal_reviews', 'appraisal_calibrations', 'appraisal_goals')
     and rowsecurity),
  5::bigint,
  'the appraisal tables have RLS enabled'
);
select table_privs_are('better_supabase', 'appraisals', 'anon', '{}'::text[],
  'anon has no privileges on appraisals');
select table_privs_are('better_supabase', 'appraisal_reviews', 'anon', '{}'::text[],
  'anon has no privileges on reviews');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

create temporary table ids (name text primary key, id uuid) on commit drop;
insert into ids values ('cycle', (better_supabase.create_appraisal_cycle(
  '00000000-0000-4000-8000-000000000001',
  '{"name": "2031 review", "startsOn": "2031-01-01", "endsOn": "2031-03-31"}'::jsonb) ->> 'id')::uuid);

select throws_ok(
  $$select better_supabase.create_appraisal_cycle('00000000-0000-4000-8000-000000000001', '{"name": "Odd", "startsOn": "2031-02-01", "endsOn": "2031-01-01"}'::jsonb)$$,
  '22023',
  null,
  'a cycle ends on or after it starts'
);

select is(
  (better_supabase.open_appraisal_cycle(
    (select id from ids where name = 'cycle'),
    '[{"subjectUserId": "00000000-0000-4000-8000-0000000000a2", "managerId": "00000000-0000-4000-8000-0000000000a1"}]'::jsonb
  ) ->> 'appraisalsCreated')::integer,
  1,
  'opening the cycle creates the appraisal'
);
select is(
  (better_supabase.open_appraisal_cycle(
    (select id from ids where name = 'cycle'),
    '[{"subjectUserId": "00000000-0000-4000-8000-0000000000a2", "managerId": "00000000-0000-4000-8000-0000000000a1"}]'::jsonb
  ) ->> 'appraisalsCreated')::integer,
  0,
  'a person keeps the appraisal they have'
);

insert into ids
select 'appraisal', (a ->> 'id')::uuid
from jsonb_array_elements(better_supabase.list_appraisals('00000000-0000-4000-8000-000000000001')) a;
insert into ids
select 'managerReview', (r ->> 'id')::uuid
from jsonb_array_elements(better_supabase.get_appraisal((select id from ids where name = 'appraisal')) -> 'reviews') r
where r ->> 'kind' = 'manager';
insert into ids
select 'selfReview', (r ->> 'id')::uuid
from jsonb_array_elements(better_supabase.get_appraisal((select id from ids where name = 'appraisal')) -> 'reviews') r
where r ->> 'kind' = 'self';

select throws_ok(
  format($$select better_supabase.submit_appraisal_review(%L, '{"rating": 4}'::jsonb)$$, (select id from ids where name = 'selfReview')),
  '42501',
  null,
  'only the assigned reviewer submits a review'
);
select throws_ok(
  format($$select better_supabase.submit_appraisal_review(%L, '{"rating": 9}'::jsonb)$$, (select id from ids where name = 'managerReview')),
  '22023',
  null,
  'a rating is from 1 to 5'
);
select is(
  better_supabase.submit_appraisal_review((select id from ids where name = 'managerReview'), '{"rating": 3}'::jsonb) ->> 'status',
  'pending',
  'the appraisal waits for the other reviews'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select is(
  better_supabase.submit_appraisal_review((select id from ids where name = 'selfReview'), '{"rating": 5}'::jsonb) ->> 'status',
  'reviewed',
  'the last review moves the appraisal to reviewed'
);
select throws_ok(
  $$select better_supabase.create_appraisal_cycle('00000000-0000-4000-8000-000000000001', '{"name": "Nope", "startsOn": "2031-01-01", "endsOn": "2031-02-01"}'::jsonb)$$,
  '42501',
  null,
  'a member can''t manage cycles'
);
select is(
  jsonb_array_length(better_supabase.get_appraisal((select id from ids where name = 'appraisal')) -> 'reviews'),
  1,
  'a member sees only their own review'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select throws_ok(
  format($$select better_supabase.calibrate_appraisal(%L, 3, ' ')$$, (select id from ids where name = 'appraisal')),
  '22023',
  null,
  'a calibration needs a reason'
);
select is(
  better_supabase.calibrate_appraisal((select id from ids where name = 'appraisal'), 4, 'Matches the team bar') ->> 'calibratedRating',
  '4',
  'calibration sets the rating'
);
select ok(
  better_supabase.sign_off_appraisal((select id from ids where name = 'appraisal')) ->> 'status'
    in ('signed_off', 'awaiting_signoff'),
  'sign-off finishes or waits for its approval'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
select is(
  (select count(*) from better_supabase.appraisals),
  0::bigint,
  'another organization sees no appraisals'
);

select * from finish();
rollback;
