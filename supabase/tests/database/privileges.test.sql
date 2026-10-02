-- Table and function privileges of the Data API roles, and the composite
-- foreign keys that keep child rows in their parent's tenant. Foreign key
-- checks bypass RLS, so only the tenant column in the key stops a member from
-- attaching a row to another organization's customer.
begin;
select plan(17);

select table_privs_are('public', t, 'anon', '{}'::text[], format('anon has no privileges on public.%s', t))
from unnest(array[
  'organizations', 'contacts', 'customers', 'locations', 'tags', 'customer_tags', 'notes', 'notifications'
]) as t;

select table_privs_are('public', 'organizations', 'authenticated', array['SELECT'],
  'authenticated only reads organizations');
select table_privs_are('public', t, 'authenticated', array['SELECT', 'INSERT', 'UPDATE', 'DELETE'],
  format('authenticated has no TRUNCATE, REFERENCES or TRIGGER on public.%s', t))
from unnest(array['customers', 'notes', 'notifications']) as t;

select function_privs_are('rbac', 'authorize', array['rbac.app_permission'], 'anon', '{}'::text[],
  'anon cannot call rbac.authorize');

-- An Acme member (tenant …0001) aims at Initech (…a003), a Globex customer.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select throws_ok(
  $$insert into public.locations (organization_id, customer_id, label)
    values ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000a003', 'Elsewhere')$$,
  '23503', null, 'a location cannot point at another tenant''s customer'
);
select throws_ok(
  $$insert into public.notes (organization_id, customer_id, body)
    values ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000a003', 'Hello')$$,
  '23503', null, 'a note cannot point at another tenant''s customer'
);
select throws_ok(
  $$insert into public.customer_tags (customer_id, tag_id, organization_id)
    values ('00000000-0000-4000-8000-00000000a003', '00000000-0000-4000-8000-00000000b001', '00000000-0000-4000-8000-000000000001')$$,
  '23503', null, 'a tag cannot be attached to another tenant''s customer'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000b1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;

select throws_ok(
  $$update public.customers set primary_contact_id = '00000000-0000-4000-8000-00000000c001'
    where id = '00000000-0000-4000-8000-00000000a003'$$,
  '23503', null, 'a customer cannot take another tenant''s contact'
);

select * from finish();
rollback;
