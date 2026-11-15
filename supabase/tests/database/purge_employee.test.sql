-- An employee is purged by someone with employees.write, and offboarding is the
-- archive: the owner (…00a1) of Acme (…0001) offboards one employee and purges
-- another, and the member (…00a2) can do neither.
begin;
select plan(5);

create temporary table ids (name text primary key, id uuid) on commit drop;
grant all on ids to authenticated, anon, service_role;

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

insert into ids
select 'kept', (api.create_employee('00000000-0000-4000-8000-000000000001', '{"name":"Kept"}') ->> 'id')::uuid;
insert into ids
select 'mistake', (api.create_employee('00000000-0000-4000-8000-000000000001', '{"name":"Mistake"}') ->> 'id')::uuid;

select is(
  api.offboard_employee((select id from ids where name = 'kept'), null, 'moved') ->> 'status',
  'offboarded',
  'offboarding archives an employee and keeps the row'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select throws_ok(
  $$select api.purge_employee((select id from ids where name = 'mistake'))$$,
  'P0002',
  null,
  'a member can''t purge an employee'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select is(
  api.purge_employee((select id from ids where name = 'mistake')) ->> 'id',
  (select id::text from ids where name = 'mistake'),
  'the owner purges an employee'
);
select is(
  (select count(*)::int from better_supabase.employees where id = (select id from ids where name = 'mistake')),
  0,
  'the purged employee is gone'
);
select is(
  (select count(*)::int from better_supabase.employees where id = (select id from ids where name = 'kept')),
  1,
  'the offboarded employee stays'
);

select * from finish();
rollback;
