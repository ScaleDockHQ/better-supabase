-- With employees installed, team_members keeps an employee's row when the
-- user's account or membership goes, and deletes it on an explicit removal,
-- a team delete or an employee delete. Users …e1 to …e5 are members of
-- organization …e0; employees …c1 to …c4 have accounts, …c7 has none.
begin;
select plan(11);

insert into public.organizations (id, name, slug)
values ('00000000-0000-4000-8000-0000000000e0', 'Keep', 'keep-team-members');
insert into auth.users (id, email)
select ('00000000-0000-4000-8000-0000000000e' || i)::uuid, 'keep' || i || '@example.test'
from generate_series(1, 5) i;
insert into public.memberships (organization_id, user_id, role)
select '00000000-0000-4000-8000-0000000000e0', ('00000000-0000-4000-8000-0000000000e' || i)::uuid,
  (select id from better_supabase.roles limit 1)
from generate_series(1, 5) i;
insert into better_supabase.teams (id, tenant_id, name, slug) values
  ('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000e0', 'Field', 'keep-field'),
  ('00000000-0000-4000-8000-0000000000b2', '00000000-0000-4000-8000-0000000000e0', 'Office', 'keep-office');
insert into better_supabase.employees (id, tenant_id, user_id, name, team_id)
select ('00000000-0000-4000-8000-0000000000c' || i)::uuid, '00000000-0000-4000-8000-0000000000e0',
  ('00000000-0000-4000-8000-0000000000e' || i)::uuid, 'Employee ' || i, '00000000-0000-4000-8000-0000000000b1'
from generate_series(1, 4) i;
insert into better_supabase.employees (id, tenant_id, user_id, name, team_id)
values ('00000000-0000-4000-8000-0000000000c7', '00000000-0000-4000-8000-0000000000e0', null, 'Employee 7', '00000000-0000-4000-8000-0000000000b1');
insert into better_supabase.team_members (team_id, user_id, tenant_id)
values ('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000e5', '00000000-0000-4000-8000-0000000000e0');

select is(
  (select count(*)::int from better_supabase.team_members where team_id = '00000000-0000-4000-8000-0000000000b1'),
  6,
  'the primary team holds five employees and one user without an employee record'
);

delete from auth.users where id = '00000000-0000-4000-8000-0000000000e1';

select is(
  (select user_id from better_supabase.team_members where employee_id = '00000000-0000-4000-8000-0000000000c1'),
  null,
  'deleting the auth user keeps the employee on the team without a user'
);

select is(
  (select count(*)::int from better_supabase.team_members where employee_id = '00000000-0000-4000-8000-0000000000c1'),
  1,
  'deleting the auth user leaves one row for the employee'
);

delete from public.memberships
where organization_id = '00000000-0000-4000-8000-0000000000e0'
  and user_id = '00000000-0000-4000-8000-0000000000e2';

select is(
  (select user_id from better_supabase.team_members where employee_id = '00000000-0000-4000-8000-0000000000c2'),
  null,
  'removing the membership keeps the employee on the team without a user'
);

delete from auth.users where id = '00000000-0000-4000-8000-0000000000e5';

select is(
  (select count(*)::int from better_supabase.team_members where user_id = '00000000-0000-4000-8000-0000000000e5'),
  0,
  'deleting the auth user of a member without an employee record deletes the row'
);

delete from better_supabase.team_members where employee_id = '00000000-0000-4000-8000-0000000000c3';

select is(
  (select count(*)::int from better_supabase.team_members where employee_id = '00000000-0000-4000-8000-0000000000c3'),
  0,
  'an explicit removal of an employee with an account deletes the row'
);

delete from better_supabase.team_members where employee_id = '00000000-0000-4000-8000-0000000000c1';

select is(
  (select count(*)::int from better_supabase.team_members where employee_id = '00000000-0000-4000-8000-0000000000c1'),
  0,
  'an explicit removal of an employee without a user deletes the row'
);

delete from better_supabase.employees where id = '00000000-0000-4000-8000-0000000000c4';

select is(
  (select count(*)::int from better_supabase.team_members where employee_id = '00000000-0000-4000-8000-0000000000c4'),
  0,
  'deleting the employee deletes the row'
);

delete from better_supabase.teams where id = '00000000-0000-4000-8000-0000000000b1';

select is(
  (select count(*)::int from better_supabase.team_members where team_id = '00000000-0000-4000-8000-0000000000b1'),
  0,
  'deleting the team deletes its rows'
);

delete from better_supabase.employees where id = '00000000-0000-4000-8000-0000000000c3';
insert into better_supabase.employees (id, tenant_id, user_id, name, team_id)
values ('00000000-0000-4000-8000-0000000000c6', '00000000-0000-4000-8000-0000000000e0', '00000000-0000-4000-8000-0000000000e3', 'Employee 6', '00000000-0000-4000-8000-0000000000b2');
delete from public.organizations where id = '00000000-0000-4000-8000-0000000000e0';

select is(
  (select count(*)::int from better_supabase.team_members where tenant_id = '00000000-0000-4000-8000-0000000000e0' and user_id is not null),
  0,
  'deleting the organization leaves no row that names a user'
);

select is(
  (select count(*)::int from better_supabase.team_members where employee_id = '00000000-0000-4000-8000-0000000000c6'),
  1,
  'deleting the organization keeps the employee on a team that still exists'
);

select * from finish();
rollback;
