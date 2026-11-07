-- The workflows run registry: one run per idempotency key, and a queued run
-- that one caller leases, starts and records once.
begin;
select plan(9);

set local role service_role;

create temporary table ids (name text primary key, id uuid) on commit drop;
insert into ids
select 'first', better_supabase.record_workflow_run(
  'workflow-sdk', 'pending:a', 'onboard', 'queued',
  '00000000-0000-4000-8000-000000000001', null, '{}', null, null, null,
  null, null, null, null, null, null, 'key-1'
);

select is(
  better_supabase.record_workflow_run(
    'workflow-sdk', 'pending:b', 'onboard', 'queued',
    '00000000-0000-4000-8000-000000000001', null, '{}', null, null, null,
    null, null, null, null, null, null, 'key-1'
  ),
  (select id from ids where name = 'first'),
  'a second report with the same key returns the first run'
);

select is(
  (select count(*)::int from better_supabase.workflow_runs where idempotency_key = 'key-1'),
  1,
  'one run holds the key'
);

select is(
  better_supabase.claim_workflow_run_dispatch((select id from ids where name = 'first'), 60) ->> 'externalId',
  'pending:a',
  'the first caller leases the queued run'
);

select is(
  better_supabase.claim_workflow_run_dispatch((select id from ids where name = 'first'), 60),
  null::jsonb,
  'a second caller finds the lease held'
);

update better_supabase.workflow_runs set dispatch_expires_at = now() - interval '1 second'
where id = (select id from ids where name = 'first');

select isnt(
  better_supabase.claim_workflow_run_dispatch((select id from ids where name = 'first'), 60),
  null::jsonb,
  'a lease that ran out can be claimed again'
);

select is(
  better_supabase.set_workflow_run_engine((select id from ids where name = 'first'), 'workflow-sdk', 'wrun_1') ->> 'externalId',
  'wrun_1',
  'set_workflow_run_engine records the engine run'
);

select is(
  better_supabase.claim_workflow_run_dispatch((select id from ids where name = 'first'), 60),
  null::jsonb,
  'a started run can no longer be leased'
);

-- The engine's own report came first: its row keeps its id and takes the key.
insert into ids
select 'second', better_supabase.record_workflow_run(
  'workflow-sdk', 'pending:c', 'onboard', 'queued', null, null, '{}', null, null, null,
  null, null, null, null, null, null, 'key-2'
);
insert into ids
select 'engine', better_supabase.record_workflow_run(
  'workflow-sdk', 'wrun_2', 'onboard', 'running', null, null, '{}'
);
select is(
  (better_supabase.set_workflow_run_engine((select id from ids where name = 'second'), 'workflow-sdk', 'wrun_2') ->> 'id')::uuid,
  (select id from ids where name = 'engine'),
  'the engine row survives and the queued row is merged into it'
);

select is(
  (select idempotency_key from better_supabase.workflow_runs where id = (select id from ids where name = 'engine')),
  'key-2',
  'the surviving run holds the key'
);

select * from finish();
rollback;
