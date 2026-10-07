-- The fixture's own constraints and defaults, as the Acme member (…00a2).
begin;
select plan(4);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select throws_ok(
  $$insert into public.locations (organization_id, customer_id, label, is_primary)
    values ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000a001', 'Branch', true)$$,
  '23505',
  null,
  'a customer has one primary location'
);
select lives_ok(
  $$insert into public.locations (organization_id, customer_id, label)
    values ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000a001', 'Branch')$$,
  'a customer has more locations that are not primary'
);
select throws_ok(
  $$update public.customers set status = 'archived'
    where id = '00000000-0000-4000-8000-00000000a002'$$,
  '23514',
  null,
  'an archived customer has archived_at'
);
insert into public.customers (organization_id, name)
values ('00000000-0000-4000-8000-000000000001', 'Mine B.V.');
select is(
  (select created_by from public.customers where name = 'Mine B.V.'),
  '00000000-0000-4000-8000-0000000000a2'::uuid,
  'created_by defaults to the caller'
);

select * from finish();
rollback;
