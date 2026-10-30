-- The cases module against the seed: the Acme owner (…a1) opens a
-- nonconformity, can't close it until the root cause and a corrective action
-- are in, an Acme member (…a2) reports a case but can't close one, and the
-- Globex owner (…a3) sees none of it. Run with `supabase test db`.
begin;
select plan(19);

select is(
  (select count(*) from pg_catalog.pg_tables
   where schemaname = 'better_supabase'
     and tablename in ('case_kinds', 'cases', 'case_actions')
     and rowsecurity),
  3::bigint,
  'the cases tables have RLS enabled'
);
select table_privs_are('better_supabase', 'cases', 'anon', '{}'::text[],
  'anon has no privileges on cases');
select table_privs_are('better_supabase', 'case_actions', 'anon', '{}'::text[],
  'anon has no privileges on case actions');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

create temporary table ids (name text primary key, id uuid) on commit drop;
insert into ids values ('burr', (better_supabase.open_case(
  '00000000-0000-4000-8000-000000000001', 'nonconformity', 'Burr on bracket batch 12') ->> 'id')::uuid);

select is(
  jsonb_array_length(better_supabase.list_case_kinds('00000000-0000-4000-8000-000000000001')),
  8,
  'the organization gets the eight default kinds'
);
select matches(
  (select number from better_supabase.cases where id = (select id from ids where name = 'burr')),
  '^NC-',
  'the case number takes the kind''s prefix'
);
select throws_ok(
  $$select better_supabase.open_case('00000000-0000-4000-8000-000000000001', 'astrology', 'Odd')$$,
  'P0002',
  null,
  'an unknown kind is refused'
);
select throws_ok(
  $$select better_supabase.open_case('00000000-0000-4000-8000-000000000001', 'complaint', 'Late delivery', severity => 'apocalyptic')$$,
  '22023',
  null,
  'a severity outside the list is refused'
);
select is(
  better_supabase.case_close_blockers((select id from ids where name = 'burr')),
  array['CASE_ROOT_CAUSE_REQUIRED', 'CASE_ACTIONS_REQUIRED'],
  'a new nonconformity lacks a root cause and an action'
);
select throws_ok(
  $$select better_supabase.close_case((select id from ids where name = 'burr'))$$,
  '55000',
  null,
  'a blocked case does not close'
);

select lives_ok(
  $$select better_supabase.record_case_root_cause((select id from ids where name = 'burr'), 'Worn deburring tool')$$,
  'the owner records the root cause'
);
select lives_ok(
  $$select better_supabase.create_case_action((select id from ids where name = 'burr'), 'corrective', 'Replace the deburring tool')$$,
  'the owner adds a corrective action as a task'
);
select is(
  better_supabase.case_close_blockers((select id from ids where name = 'burr')),
  array['CASE_ACTIONS_OPEN'],
  'an open required action still blocks closing'
);
reset role;
update better_supabase.work_items set state = 'completed'
where id = (select task_id from better_supabase.case_actions where case_id = (select id from ids where name = 'burr'));
set local role authenticated;
select is(
  better_supabase.close_case((select id from ids where name = 'burr'), 'Tool replaced') ->> 'status',
  'closed',
  'the case closes once the action is done'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

insert into ids values ('door', (better_supabase.open_case(
  '00000000-0000-4000-8000-000000000001', 'observation', 'Fire door propped open') ->> 'id')::uuid);
select is(
  jsonb_array_length(better_supabase.list_cases('00000000-0000-4000-8000-000000000001') -> 'items'),
  2,
  'a member reads the cases and reports one'
);
select throws_ok(
  $$select better_supabase.close_case((select id from ids where name = 'door'))$$,
  '42501',
  null,
  'a member cannot close a case they do not own'
);
select throws_ok(
  $$select better_supabase.create_case_action((select id from ids where name = 'door'), 'corrective', 'Fit a closer')$$,
  '42501',
  null,
  'a member cannot add actions'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;

select is(
  (select count(*) from better_supabase.cases) + (select count(*) from better_supabase.case_actions),
  0::bigint,
  'the Globex owner sees no Acme cases or actions'
);
select throws_ok(
  $$select better_supabase.get_case((select id from ids where name = 'burr'))$$,
  '42501',
  null,
  'the Globex owner cannot read an Acme case'
);
select throws_ok(
  $$select better_supabase.close_case((select id from ids where name = 'door'))$$,
  '42501',
  null,
  'the Globex owner cannot close an Acme case'
);
select * from finish();
rollback;
