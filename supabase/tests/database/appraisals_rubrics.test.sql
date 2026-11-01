-- Appraisal rubrics and reviewer anonymity against the seed: the Acme owner
-- (…a1) runs a cycle with two weighted competencies and peer reviewers hidden
-- from everyone. The member (…a2) is the appraised person, the Globex owner
-- (…a3), made an Acme owner here, is the peer. Run with `supabase test db`.
begin;
select plan(24);

insert into public.memberships (organization_id, user_id, role)
select '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a3', r.id
from better_supabase.roles r where r.key = 'owner';

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

create temporary table ids (name text primary key, id uuid) on commit drop;
grant all on ids to authenticated;

select is(
  better_supabase.create_appraisal_cycle(
    '00000000-0000-4000-8000-000000000001',
    '{"name": "Plain", "startsOn": "2031-01-01", "endsOn": "2031-02-01"}'::jsonb) ->> 'anonymity',
  'subject',
  'peer reviewers are hidden from the appraised person by default'
);
select throws_ok(
  $$select better_supabase.create_appraisal_cycle('00000000-0000-4000-8000-000000000001', '{"name": "X", "startsOn": "2031-01-01", "endsOn": "2031-02-01", "anonymity": "some"}'::jsonb)$$,
  '22023', null, 'anonymity is none, subject or all'
);
select throws_ok(
  $$select better_supabase.create_appraisal_cycle('00000000-0000-4000-8000-000000000001', '{"name": "X", "startsOn": "2031-01-01", "endsOn": "2031-02-01", "competencies": [{"key": "a", "name": "A"}, {"key": "a", "name": "B"}]}'::jsonb)$$,
  '22023', null, 'a competency key appears once'
);
select throws_ok(
  $$select better_supabase.create_appraisal_cycle('00000000-0000-4000-8000-000000000001', '{"name": "X", "startsOn": "2031-01-01", "endsOn": "2031-02-01", "competencies": [{"key": "a", "name": "A", "weight": 0}]}'::jsonb)$$,
  '22023', null, 'a competency weight is above zero'
);

insert into ids values ('cycle', (better_supabase.create_appraisal_cycle(
  '00000000-0000-4000-8000-000000000001',
  '{"name": "Rubric", "startsOn": "2031-01-01", "endsOn": "2031-03-31", "anonymity": "all", "shareFeedback": true,
    "competencies": [{"key": "craft", "name": "Craft", "weight": 3}, {"key": "teamwork", "name": "Teamwork"}]}'::jsonb) ->> 'id')::uuid);

select is(
  jsonb_array_length(better_supabase.set_appraisal_competencies(
    (select id from ids where name = 'cycle'),
    '[{"key": "craft", "name": "Craft", "weight": 3}, {"key": "teamwork", "name": "Teamwork", "weight": 1}]'::jsonb) -> 'competencies'),
  2,
  'a draft cycle takes a new rubric'
);

select better_supabase.open_appraisal_cycle(
  (select id from ids where name = 'cycle'),
  '[{"subjectUserId": "00000000-0000-4000-8000-0000000000a2", "managerId": "00000000-0000-4000-8000-0000000000a1", "peerIds": ["00000000-0000-4000-8000-0000000000a3"]}]'::jsonb);

select throws_ok(
  format($$select better_supabase.set_appraisal_competencies(%L, '[]'::jsonb)$$, (select id from ids where name = 'cycle')),
  '55000', null, 'the rubric is fixed once the cycle is open'
);

insert into ids
select 'appraisal', (a ->> 'id')::uuid
from jsonb_array_elements(better_supabase.list_appraisals(
  '00000000-0000-4000-8000-000000000001',
  jsonb_build_object('cycleId', (select id from ids where name = 'cycle')))) a;
insert into ids
select k, (r ->> 'id')::uuid
from jsonb_array_elements(better_supabase.get_appraisal((select id from ids where name = 'appraisal')) -> 'reviews') r,
  lateral (select case r ->> 'kind' when 'self' then 'selfReview' when 'manager' then 'managerReview' else 'peerReview' end as k) z;

select is(
  jsonb_array_length(better_supabase.get_appraisal((select id from ids where name = 'appraisal')) -> 'rubric'),
  2,
  'the appraisal carries the rubric'
);

-- The member rates themselves.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select throws_ok(
  format($$select better_supabase.submit_appraisal_review(%L, '{"rating": 4}'::jsonb)$$, (select id from ids where name = 'selfReview')),
  '22023', null, 'a rubric cycle takes competency ratings, not one rating'
);
select throws_ok(
  format($$select better_supabase.submit_appraisal_review(%L, '{"ratings": [{"competency": "craft", "rating": 4}]}'::jsonb)$$, (select id from ids where name = 'selfReview')),
  '22023', null, 'every competency is rated'
);
select throws_ok(
  format($$select better_supabase.submit_appraisal_review(%L, '{"ratings": [{"competency": "craft", "rating": 4}, {"competency": "speed", "rating": 4}]}'::jsonb)$$, (select id from ids where name = 'selfReview')),
  '22023', null, 'a competency outside the rubric is refused'
);
select is(
  (select r ->> 'rating'
   from jsonb_array_elements(better_supabase.submit_appraisal_review(
     (select id from ids where name = 'selfReview'),
     '{"ratings": [{"competency": "craft", "rating": 5}, {"competency": "teamwork", "rating": 1, "comment": "Works alone"}]}'::jsonb) -> 'reviews') r
   where r ->> 'kind' = 'self'),
  '4',
  'the review rating is the weighted average of its competencies'
);
select is(
  jsonb_array_length(better_supabase.get_appraisal((select id from ids where name = 'appraisal')) -> 'competencies'),
  0,
  'the appraised person doesn''t see competency results before sign-off'
);
select is(
  (select count(*) from better_supabase.appraisal_reviews),
  0::bigint,
  'a member reads no review rows through the table'
);

-- The manager and the peer rate.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select better_supabase.submit_appraisal_review(
  (select id from ids where name = 'managerReview'),
  '{"ratings": [{"competency": "craft", "rating": 3}, {"competency": "teamwork", "rating": 3}]}'::jsonb);
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select is(
  better_supabase.submit_appraisal_review(
    (select id from ids where name = 'peerReview'),
    '{"ratings": [{"competency": "craft", "rating": 4}, {"competency": "teamwork", "rating": 2}]}'::jsonb) ->> 'status',
  'reviewed',
  'the last review moves the appraisal to reviewed'
);
select is(
  (select count(*) from jsonb_array_elements(better_supabase.get_appraisal((select id from ids where name = 'appraisal')) -> 'reviews') r
   where r ->> 'reviewerId' is null),
  0::bigint,
  'a peer reviewer sees their own name on their review'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select is(
  better_supabase.get_appraisal((select id from ids where name = 'appraisal')) ->> 'rating',
  '3.50',
  'the appraisal rating weighs each competency average by its weight'
);
select is(
  (select r ->> 'kind' from jsonb_array_elements(better_supabase.get_appraisal((select id from ids where name = 'appraisal')) -> 'reviews') r
   where r ->> 'reviewerId' is null),
  'peer',
  'a manager does not see who wrote a peer review in an all-anonymous cycle'
);
select is(
  (select count(*) from better_supabase.appraisal_reviews),
  2::bigint,
  'the table hides the same peer review'
);
select is(
  (select count(*) from better_supabase.appraisal_review_ratings),
  4::bigint,
  'the ratings of the hidden review are hidden too'
);

select throws_ok(
  format($$select better_supabase.calibrate_appraisal_competencies(%L, '{"speed": 4}'::jsonb, 'x')$$, (select id from ids where name = 'appraisal')),
  '22023', null, 'calibration names competencies of the rubric'
);
select is(
  better_supabase.calibrate_appraisal_competencies(
    (select id from ids where name = 'appraisal'), '{"teamwork": 4}'::jsonb, 'Team feedback was one-sided') ->> 'calibratedRating',
  '4',
  'calibrating a competency recomputes the weighted rating'
);

-- Sign-off waits for approvals when it is installed, so close the appraisal
-- here to see what the appraised person reads afterwards.
reset role;
update better_supabase.appraisals set status = 'signed_off', signed_off_at = now()
where id = (select id from ids where name = 'appraisal');
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select is(
  jsonb_array_length(better_supabase.get_appraisal((select id from ids where name = 'appraisal')) -> 'reviews'),
  3,
  'a signed-off appraisal in a sharing cycle shows the appraised person every review'
);
select is(
  (select count(*) from jsonb_array_elements(better_supabase.get_appraisal((select id from ids where name = 'appraisal')) -> 'reviews') r
   where r ->> 'reviewerId' is null and r ->> 'kind' = 'peer'),
  1::bigint,
  'the peer reviewer stays hidden from the appraised person'
);
select is(
  (select c ->> 'calibrated' from jsonb_array_elements(better_supabase.get_appraisal((select id from ids where name = 'appraisal')) -> 'competencies') c
   where c ->> 'key' = 'teamwork'),
  '4',
  'the appraised person reads the calibrated competency results'
);

select * from finish();
rollback;
