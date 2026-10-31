-- The payroll-export module against the seed: two time entries of the member
-- …a2 in March 2027 are collected by the Acme owner (…a1) into a run, which is
-- exported and then locked. The member can't create or read runs, and the
-- Globex owner (…a3) sees none of it. Run with `supabase test db`.
begin;
select plan(17);

select is(
  (select count(*) from pg_catalog.pg_tables
   where schemaname = 'better_supabase'
     and tablename in ('payroll_runs', 'payroll_lines')
     and rowsecurity),
  2::bigint,
  'the payroll tables have RLS enabled'
);
select table_privs_are('better_supabase', 'payroll_runs', 'anon', '{}'::text[],
  'anon has no privileges on payroll runs');
select table_privs_are('better_supabase', 'payroll_lines', 'anon', '{}'::text[],
  'anon has no privileges on payroll lines');

insert into better_supabase.time_entries (tenant_id, user_id, started_at, ended_at)
values
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a2',
   '2027-03-02T08:00:00Z', '2027-03-02T10:00:00Z'),
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a2',
   '2027-03-03T08:00:00Z', '2027-03-03T09:30:00Z'),
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a2',
   '2027-04-02T08:00:00Z', '2027-04-02T10:00:00Z');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

create temporary table ids (name text primary key, id uuid) on commit drop;
insert into ids values ('march', (better_supabase.create_payroll_run(
  '00000000-0000-4000-8000-000000000001',
  '{"from": "2027-03-01", "to": "2027-03-31", "label": "March"}'::jsonb) ->> 'id')::uuid);

select is(
  (select status from better_supabase.payroll_runs where id = (select id from ids where name = 'march')),
  'draft',
  'a new run is a draft'
);
select is(
  (select quantity from better_supabase.payroll_lines
   where run_id = (select id from ids where name = 'march') and kind = 'worked'),
  3.50::numeric,
  'the worked hours of the period add up, and other months stay out'
);
select throws_ok(
  $$select better_supabase.create_payroll_run('00000000-0000-4000-8000-000000000001', '{"from": "2027-03-31", "to": "2027-03-01"}'::jsonb)$$,
  '22023',
  null,
  'a period that ends before it starts is refused'
);
select throws_ok(
  $$select better_supabase.create_payroll_run('00000000-0000-4000-8000-000000000001', '{"from": "2027-03-01"}'::jsonb)$$,
  '22023',
  null,
  'a run needs both dates'
);
select is(
  better_supabase.mark_payroll_run_exported(
    (select id from ids where name = 'march'), 'csv', repeat('a', 64)) ->> 'status',
  'exported',
  'exporting locks the run'
);
select is(
  better_supabase.mark_payroll_run_exported(
    (select id from ids where name = 'march'), 'csv', repeat('a', 64)) ->> 'status',
  'exported',
  'exporting the same file again changes nothing'
);
select throws_ok(
  $$select better_supabase.mark_payroll_run_exported((select id from ids where name = 'march'), 'csv', repeat('b', 64))$$,
  '55000',
  null,
  'a different file is refused'
);
select throws_ok(
  $$select better_supabase.refresh_payroll_run((select id from ids where name = 'march'))$$,
  '55000',
  null,
  'a locked run is not refreshed'
);
select throws_ok(
  $$select better_supabase.delete_payroll_run((select id from ids where name = 'march'))$$,
  '55000',
  null,
  'a locked run is not deleted'
);
select throws_ok(
  $$select better_supabase.create_payroll_run('00000000-0000-4000-8000-000000000001', '{"from": "2027-03-15", "to": "2027-04-15"}'::jsonb)$$,
  '55000',
  null,
  'a period that overlaps an exported run is refused'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select throws_ok(
  $$select better_supabase.create_payroll_run('00000000-0000-4000-8000-000000000001', '{"from": "2027-05-01", "to": "2027-05-31"}'::jsonb)$$,
  '42501',
  null,
  'a member cannot create a run'
);
select is(
  (select count(*) from better_supabase.payroll_runs),
  0::bigint,
  'a member sees no runs'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;

select is(
  (select count(*) from better_supabase.payroll_lines),
  0::bigint,
  'another tenant sees no lines'
);
select is(
  better_supabase.get_payroll_run((select id from ids where name = 'march')),
  null::jsonb,
  'another tenant cannot read the run'
);

select * from finish();
rollback;
