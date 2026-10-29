-- The courses module on the fixture's access contract: the admin (…00a1) of
-- Acme (…0001) builds a course with a content lesson and a scored quiz, the
-- member (…00a2) enrolls, completes it and gets a certificate, and Globex
-- (…0002) sees nothing.
begin;
select plan(24);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('test.course', better_supabase.save_course(
  '00000000-0000-4000-8000-000000000001',
  '{"key":"onboarding","title":"Onboarding","validForMonths":12}'
) ->> 'id', true);
select throws_ok(
  $$select better_supabase.save_course('00000000-0000-4000-8000-000000000001', '{"key":"onboarding","title":"Onboarding","validForMonths":300}')$$,
  '22023',
  'validForMonths must be a whole number of months from 1 to 240, or null',
  'a validity over 240 months is refused'
);
select set_config('test.module', better_supabase.save_course_module(
  current_setting('test.course')::uuid, '{"title":"Basics"}'
) ->> 'id', true);
select set_config('test.form', better_supabase.create_form(
  '00000000-0000-4000-8000-000000000001', 'course-quiz', 'Quiz'
) ->> 'id', true);
select better_supabase.publish_form_version(
  current_setting('test.form')::uuid,
  '{"scoring":{"passMark":50},"steps":[{"key":"quiz","fields":[{"key":"capital","label":"Capital","type":"text","correct":"Paris"},{"key":"planet","label":"Planet","type":"text","correct":"Mars"}]}]}'
);
select better_supabase.update_form(current_setting('test.form')::uuid, null, null, 'open');

select set_config('test.intro', better_supabase.save_course_lesson(
  current_setting('test.course')::uuid,
  jsonb_build_object('moduleId', current_setting('test.module'), 'title', 'Welcome', 'body', '{"text":"Hello"}'::jsonb)
) ->> 'id', true);
select set_config('test.quiz', better_supabase.save_course_lesson(
  current_setting('test.course')::uuid,
  jsonb_build_object('moduleId', current_setting('test.module'), 'title', 'Check', 'kind', 'quiz', 'formId', current_setting('test.form'))
) ->> 'id', true);

select ok(
  (select x."rank" from better_supabase.course_lessons x where x."id" = current_setting('test.intro')::uuid)
    < (select x."rank" from better_supabase.course_lessons x where x."id" = current_setting('test.quiz')::uuid),
  'a new lesson ranks after the last one'
);
select throws_ok(
  format($$select better_supabase.save_course_lesson(%L, jsonb_build_object('moduleId', %L, 'title', 'Bad', 'kind', 'quiz'))$$,
    current_setting('test.course'), current_setting('test.module')),
  '22023',
  null,
  'a quiz lesson needs a form'
);
select throws_ok(
  format($$select better_supabase.save_course_lesson(%L, jsonb_build_object('moduleId', %L, 'title', 'Bad', 'rank', 'not a rank'))$$,
    current_setting('test.course'), current_setting('test.module')),
  '22023',
  null,
  'a rank is a rank key'
);
select throws_ok(
  format($$select better_supabase.enroll_in_course(%L)$$, current_setting('test.course')),
  '55000',
  null,
  'a draft course takes no enrollments'
);
select is(
  better_supabase.save_course(
    '00000000-0000-4000-8000-000000000001',
    jsonb_build_object('id', current_setting('test.course'), 'status', 'published')
  ) ->> 'status',
  'published',
  'an admin publishes the course'
);
select throws_ok(
  $$select better_supabase.enroll(
    '00000000-0000-4000-8000-000000000001', 'course:' || current_setting('test.course'),
    'user', '00000000-0000-4000-8000-0000000000a2'
  )$$,
  null,
  null,
  'the enrollments block refuses a course program'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);

select is(
  jsonb_array_length(better_supabase.list_courses('00000000-0000-4000-8000-000000000001')),
  1,
  'a member lists the published course'
);
select throws_ok(
  $$select better_supabase.save_course('00000000-0000-4000-8000-000000000001', '{"key":"other","title":"Other"}')$$,
  '42501',
  null,
  'a member can''t manage courses'
);
select throws_ok(
  format($$select better_supabase.course_lesson(%L)$$, current_setting('test.intro')),
  'P0002',
  null,
  'a lesson needs an enrollment'
);
select is(
  (better_supabase.enroll_in_course(current_setting('test.course')::uuid) ->> 'totalLessons')::integer,
  2,
  'a member enrolls, with a step per required lesson'
);
select is(
  (select count(*)::integer from better_supabase.enrollments x
    where x."program" = 'course:' || current_setting('test.course')),
  1,
  'the enrollment lives in the enrollments block'
);
select throws_ok(
  format($$select better_supabase.complete_course_lesson(%L)$$, current_setting('test.quiz')),
  '22023',
  null,
  'a quiz lesson completes only by passing it'
);
select is(
  (better_supabase.complete_course_lesson(current_setting('test.intro')::uuid) ->> 'completedLessons')::integer,
  1,
  'completing a content lesson counts it'
);
select is(
  better_supabase.submit_course_quiz(current_setting('test.quiz')::uuid, '{"capital":"Lyon","planet":"Venus"}') ->> 'passed',
  'false',
  'a failed quiz doesn''t complete the lesson'
);
select is(
  (better_supabase.submit_course_quiz(current_setting('test.quiz')::uuid, '{"capital":"Paris","planet":"Mars"}') -> 'progress' ->> 'status'),
  'completed',
  'passing the quiz completes the course'
);
select is(
  (select x."attempts" from better_supabase.course_lesson_progress x where x."lesson_id" = current_setting('test.quiz')::uuid),
  2,
  'every attempt counts'
);
select set_config('test.code', better_supabase.course_progress(current_setting('test.course')::uuid) -> 'certificate' ->> 'code', true);
select isnt(current_setting('test.code'), '', 'completing the course issues a certificate');
select throws_ok(
  format($$select better_supabase.course_progress(%L, '00000000-0000-4000-8000-0000000000a1')$$, current_setting('test.course')),
  '42501',
  null,
  'a member can''t read another learner''s progress'
);

set local role anon;
select is(
  (better_supabase.verify_course_certificate(current_setting('test.code')) ->> 'valid')::boolean,
  true,
  'anyone with the code verifies the certificate'
);
select is(
  (better_supabase.verify_course_certificate(current_setting('test.code')) ->> 'expired')::boolean,
  false,
  'a certificate inside its validity is not expired'
);
reset role;
update better_supabase.course_certificates set expires_at = now() - interval '1 day'
  where code = current_setting('test.code');
set local role anon;
select is(
  (select jsonb_build_object('valid', c -> 'valid', 'expired', c -> 'expired')
   from better_supabase.verify_course_certificate(current_setting('test.code')) c),
  '{"valid":false,"expired":true}'::jsonb,
  'an expired certificate verifies as expired and not valid'
);
set local role authenticated;

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);

select is(
  (select count(*)::integer from better_supabase.courses
    where tenant_id = '00000000-0000-4000-8000-000000000001'),
  0,
  'another organization sees none of its courses'
);
select throws_ok(
  format($$select better_supabase.course_outline(%L)$$, current_setting('test.course')),
  'P0002',
  null,
  'another organization can''t read the outline'
);

select * from finish();
rollback;
