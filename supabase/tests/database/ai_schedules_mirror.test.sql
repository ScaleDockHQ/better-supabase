-- Mirrored tasks: another scheduler's tasks (source eve) are stored and
-- recorded through the service-role functions, claim_due_ai_tasks never
-- claims them, and members and anon may not call the functions. Acme
-- (…0001) has the admin …a1 and the member …a2 (supabase/seed.sql).
begin;
select plan(16);

-- A mirror is created by the service role for a user of the tenant.
set local role service_role;

select is(
  api.mirror_ai_task(
    '00000000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8000-0000000000a2',
    'eve',
    'eve:requests:ns:digest',
    '{"title":"Digest","prompt":"Send the digest","cron":"* * * * *"}',
    now() - interval '1 minute'
  ) ->> 'source',
  'eve',
  'the service role mirrors a task with source eve'
);

select is(
  api.mirror_ai_task(
    '00000000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8000-0000000000a2',
    'eve',
    'eve:requests:ns:digest',
    '{"title":"Digest v2"}',
    now() - interval '1 minute'
  ) ->> 'title',
  'Digest v2',
  'mirroring the same external id updates the task'
);

select is(
  (select count(*)::int from better_supabase.ai_scheduled_tasks where external_id = 'eve:requests:ns:digest'),
  1,
  'the same external id stays one row'
);

select throws_ok(
  $$select api.mirror_ai_task('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a2', 'ai-schedules', 'x', '{"title":"t","prompt":"p","cron":"* * * * *"}')$$,
  '22023',
  null,
  'the ai-schedules source is reserved'
);

select throws_ok(
  $$select api.mirror_ai_task('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a2', 'eve', '', '{"title":"t","prompt":"p","cron":"* * * * *"}')$$,
  '22023',
  null,
  'an external id is required'
);

-- A due mirrored task is not claimed, a due native task is.
insert into better_supabase.ai_scheduled_tasks (tenant_id, user_id, title, prompt, cron, next_run_at)
values ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a2', 'Native', 'Run', '* * * * *', now() - interval '1 minute');

select is(
  jsonb_array_length(api.claim_due_ai_tasks() -> 'runs'),
  1,
  'claim_due_ai_tasks claims the native task only'
);

select is(
  (select count(*)::int from better_supabase.ai_task_runs r join better_supabase.ai_scheduled_tasks t on t.id = r.task_id where t.source = 'eve'),
  0,
  'the mirrored task has no claimed run'
);

select is(
  (select next_run_at is not null from better_supabase.ai_scheduled_tasks where external_id = 'eve:requests:ns:digest'),
  true,
  'the mirrored task keeps the next run the other scheduler gave it'
);

update better_supabase.ai_scheduled_tasks set next_run_at = null where external_id = 'eve:requests:ns:digest';

select is(
  (select count(*)::int from jsonb_array_elements(api.claim_due_ai_tasks() -> 'unscheduled') u
    where u ->> 'id' = (select id::text from better_supabase.ai_scheduled_tasks where external_id = 'eve:requests:ns:digest')),
  0,
  'a mirrored task without a next run never appears as unscheduled'
);

-- Occurrences are recorded once per scheduled time.
select is(
  api.record_ai_task_run(
    '00000000-0000-4000-8000-000000000001', 'eve', 'eve:requests:ns:digest',
    '2027-01-01T10:00:00Z', 'running'
  ) ->> 'status',
  'running',
  'an occurrence starts as running'
);

select is(
  api.record_ai_task_run(
    '00000000-0000-4000-8000-000000000001', 'eve', 'eve:requests:ns:digest',
    '2027-01-01T10:00:00Z', 'failed', 'the creator lost access'
  ) ->> 'error',
  'the creator lost access',
  'the same scheduled time updates the run with its error'
);

select is(
  (select count(*)::int from better_supabase.ai_task_runs r join better_supabase.ai_scheduled_tasks t on t.id = r.task_id where t.external_id = 'eve:requests:ns:digest'),
  1,
  'one run per scheduled time'
);

select is(
  api.record_ai_task_run(
    '00000000-0000-4000-8000-000000000001', 'eve', 'unknown', now(), 'completed'
  ),
  null,
  'an unknown task records nothing'
);

select is(
  api.delete_mirrored_ai_task('00000000-0000-4000-8000-000000000001', 'eve', 'eve:requests:ns:digest'),
  true,
  'the mirror is removed with its runs'
);

-- Members and anon may not call them.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select throws_ok(
  $$select api.mirror_ai_task('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a2', 'eve', 'x', '{}')$$,
  '42501',
  null,
  'a member cannot mirror a task'
);

reset role;
set local role anon;

select throws_ok(
  $$select api.record_ai_task_run('00000000-0000-4000-8000-000000000001', 'eve', 'x', now(), 'running')$$,
  '42501',
  null,
  'anon cannot record a run'
);

select * from finish();
rollback;
