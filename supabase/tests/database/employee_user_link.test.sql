-- Linking an employee to an account opens that employee's own private details
-- and contracts to the account, so setting the link needs the sensitive read
-- key as well as employees.write. The member (…00a2) of Acme (…0001) gets
-- employees.write here but not employees.read_sensitive; the owner (…00a1)
-- holds both.
begin;
select plan(5);

create temporary table ids (name text primary key, id uuid) on commit drop;
grant all on ids to authenticated, anon, service_role;

update better_supabase.employees set user_id = null where id = '00000000-0000-4000-8000-0000000e0002';

insert into better_supabase.permission_overrides (tenant_id, role_id, permission_id, granted)
select '00000000-0000-4000-8000-000000000001', m.role, p.id, true
from public.memberships m, better_supabase.permissions p
where m.organization_id = '00000000-0000-4000-8000-000000000001'
  and m.user_id = '00000000-0000-4000-8000-0000000000a2'
  and p.key = 'employees.write';

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}', true);
insert into ids
select 'colleague', (api.create_employee('00000000-0000-4000-8000-000000000001', '{"name":"Colleague"}') ->> 'id')::uuid;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated"}', true);
select throws_ok(
  $$select api.create_employee('00000000-0000-4000-8000-000000000001', '{"name":"Me","userId":"00000000-0000-4000-8000-0000000000a2"}')$$,
  '42501', null, 'employees.write alone does not create an employee linked to an account'
);
select is(
  api.update_employees(jsonb_build_array(jsonb_build_object(
    'employeeId', (select id from ids where name = 'colleague'),
    'field', 'userId', 'value', '00000000-0000-4000-8000-0000000000a2'))) -> 'rejected' -> 0 ->> 'hint',
  'EMPLOYEE_LINK_FORBIDDEN',
  'employees.write alone does not relink an employee to an account'
);
select lives_ok(
  $$select api.update_employees(jsonb_build_array(jsonb_build_object(
    'employeeId', (select id from ids where name = 'colleague'), 'field', 'jobTitle', 'value', 'Engineer')))$$,
  'employees.write still edits the other fields'
);

select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}', true);
select is(
  jsonb_array_length(api.update_employees(jsonb_build_array(jsonb_build_object(
    'employeeId', (select id from ids where name = 'colleague'),
    'field', 'userId', 'value', '00000000-0000-4000-8000-0000000000a2'))) -> 'accepted'),
  1,
  'the sensitive read key links an employee to an account'
);
reset role;
select is(
  (select user_id from better_supabase.employees where id = (select id from ids where name = 'colleague')),
  '00000000-0000-4000-8000-0000000000a2'::uuid,
  'the link is stored'
);

select * from finish();
rollback;
