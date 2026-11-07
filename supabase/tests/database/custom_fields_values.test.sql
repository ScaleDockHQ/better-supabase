-- Custom field values: setting a value again replaces it and seals it once,
-- and a value can be changed or removed by its id. The admin (…00a1) owns
-- Acme (…0001); …00a3 belongs to another organization.
begin;
select plan(14);

create temporary table acme_plan (id uuid) on commit drop;
create temporary table acme_visits (id uuid) on commit drop;
create temporary table acme_value (id uuid) on commit drop;
create temporary table acme_visit_value (id uuid) on commit drop;
grant all on acme_plan, acme_visits, acme_value, acme_visit_value to authenticated;

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

insert into acme_plan
select (better_supabase.save_field_definition(
  '00000000-0000-4000-8000-000000000001', 'person', 'plan', 'Plan', 'text', false
) ->> 'id')::uuid;
insert into acme_visits
select (better_supabase.save_field_definition(
  '00000000-0000-4000-8000-000000000001', 'person', 'bsn', 'BSN', 'bsn', false
) ->> 'id')::uuid;

insert into acme_value
select (better_supabase.set_field_value(
  '00000000-0000-4000-8000-000000000001', 'contact', 'c-1', (select id from acme_plan), 'basic'
) ->> 'id')::uuid;

select lives_ok(
  $$select better_supabase.set_field_value(
    '00000000-0000-4000-8000-000000000001', 'contact', 'c-1', (select id from acme_plan), 'pro'
  )$$,
  'setting the same field again does not fail on the key'
);
select is(
  (select e ->> 'text' from jsonb_array_elements(
    better_supabase.read_field_values('00000000-0000-4000-8000-000000000001', 'contact', 'c-1')) e
    where e ->> 'id' = (select id::text from acme_value)),
  'pro',
  'the replaced value reads back under the same row'
);

select is(
  better_supabase.update_field_value((select id from acme_value), 'team') ->> 'id',
  (select id::text from acme_value),
  'update_field_value returns the row id'
);
select is(
  (select e ->> 'text' from jsonb_array_elements(
    better_supabase.read_field_values('00000000-0000-4000-8000-000000000001', 'contact', 'c-1')) e
    where e ->> 'id' = (select id::text from acme_value)),
  'team',
  'the updated value reads back'
);
select throws_ok(
  $$select better_supabase.update_field_value(gen_random_uuid(), 'x')$$,
  'P0002',
  'field value not found',
  'updating an unknown value fails'
);

insert into acme_visit_value
select (better_supabase.set_field_value(
  '00000000-0000-4000-8000-000000000001', 'contact', 'c-1', (select id from acme_visits), '111222333'
) ->> 'id')::uuid;

select throws_ok(
  $$select better_supabase.update_field_value((select id from acme_visit_value), '123456789')$$,
  '22023',
  null,
  'a value the field format refuses is rejected'
);

-- The field's encryption seals an updated value once.
select lives_ok(
  $$select better_supabase.encrypt_field_definition((select id from acme_plan))$$,
  'the admin encrypts the plan field'
);
select lives_ok(
  $$select better_supabase.update_field_value((select id from acme_value), 'enterprise')$$,
  'the admin updates an encrypted value'
);
select is(
  (select e ->> 'text' from jsonb_array_elements(
    better_supabase.read_field_values('00000000-0000-4000-8000-000000000001', 'contact', 'c-1')) e
    where e ->> 'id' = (select id::text from acme_value)),
  'enterprise',
  'the encrypted value reads back as plaintext, so it was sealed once'
);

-- Another organization changes and removes nothing.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);

select throws_ok(
  $$select better_supabase.update_field_value((select id from acme_value), 'stolen')$$,
  '42501',
  null,
  'a stranger cannot update the value'
);
select throws_ok(
  $$select better_supabase.delete_field_value((select id from acme_value))$$,
  '42501',
  null,
  'a stranger cannot delete the value'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);

select is(
  better_supabase.delete_field_value((select id from acme_value)),
  true,
  'the admin deletes the value'
);
select throws_ok(
  $$select better_supabase.delete_field_value((select id from acme_value))$$,
  'P0002',
  'field value not found',
  'deleting it again fails'
);
reset role;

select is(
  (select count(*)::int from better_supabase.field_values where definition_id = (select id from acme_plan)),
  0,
  'no value is left for the field'
);
select * from finish();
rollback;
