-- ready_job_queues names only the queues with a job claim_jobs takes now.
begin;
select plan(4);

set local role service_role;

select better_supabase.enqueue_job('ready_test_due', '{}', 0, 5, null);
select better_supabase.enqueue_job('ready_test_later', '{}', 3600, 5, null);

select is(
  (select array_agg(queue order by queue) from better_supabase.ready_job_queues(array['ready_test_due', 'ready_test_later', 'ready_test_missing'])),
  array['ready_test_due'],
  'a due queue is ready; a delayed or missing one is not'
);

select is(
  (select count(*)::int from better_supabase.claim_jobs('ready_test_due', 60, 10)),
  1,
  'the ready queue has the job'
);

select is(
  (select count(*)::int from better_supabase.ready_job_queues(array['ready_test_due'])),
  0,
  'a claimed job leaves its queue not ready'
);

select is(
  (select count(*)::int from better_supabase.ready_job_queues('{}')),
  0,
  'no queues, no rows'
);

select * from finish();
rollback;
