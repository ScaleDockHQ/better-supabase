-- Field encryption (ADR 0087): encrypted custom fields and app table columns
-- are ciphertext at rest under Acme's (…0001) Vault key, decrypt only through
-- the definer paths that check scope, and write one read audit entry per call.
-- The admin (…00a1) owns Acme; …00a3 belongs to another organization.
begin;
select plan(33);

create temporary table acme_field (id uuid) on commit drop;
grant all on acme_field to authenticated;

select ok(
  not has_function_privilege('authenticated', 'better_supabase.field_key(text, boolean)', 'execute'),
  'signed-in users cannot read a data key'
);
select ok(
  not has_function_privilege('authenticated', 'better_supabase.field_open(text, text)', 'execute'),
  'signed-in users cannot decrypt with a key'
);
select ok(
  not has_function_privilege('authenticated', 'better_supabase.field_decrypt(text, text)', 'execute'),
  'signed-in users cannot decrypt for an owner'
);
select ok(
  not has_function_privilege('authenticated', 'better_supabase.drop_field_key(text)', 'execute'),
  'signed-in users cannot drop a data key'
);

-- The admin adds an encrypted custom field and sets a value.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

insert into acme_field
select (better_supabase.save_field_definition(
  '00000000-0000-4000-8000-000000000001', 'person', 'diagnosis', 'Diagnosis', 'text', false
) ->> 'id')::uuid;

select lives_ok(
  $$select better_supabase.encrypt_field_definition((select id from acme_field))$$,
  'the admin encrypts a text field'
);
select lives_ok(
  $$select better_supabase.set_field_value(
    '00000000-0000-4000-8000-000000000001', 'contact', 'c-1', (select id from acme_field), 'flu'
  )$$,
  'the admin sets an encrypted value'
);
select throws_ok(
  $$select better_supabase.encrypt_field_definition((better_supabase.save_field_definition(
    '00000000-0000-4000-8000-000000000001', 'person', 'visits', 'Visits', 'number', false
  ) ->> 'id')::uuid)$$,
  '22023',
  'only text fields can be encrypted',
  'a number field cannot be encrypted'
);
select is(
  better_supabase.read_field_values('00000000-0000-4000-8000-000000000001', 'contact', 'c-1') -> 0 ->> 'text',
  'flu',
  'the admin reads the plaintext'
);

-- The admin adds a client note with an encrypted diagnosis.
insert into public.client_notes (organization_id, client_name, diagnosis, birth_date)
values ('00000000-0000-4000-8000-000000000001', 'Ada', 'asthma', '1990-05-01');

select throws_ok(
  $$select diagnosis from public.client_notes$$,
  '42501',
  null,
  'a member cannot select an encrypted column'
);
select is(
  (select diagnosis from public.client_notes_reveal((select array_agg(id) from public.client_notes))),
  'asthma',
  'a member reveals the diagnosis'
);
select is(
  (select birth_date from public.client_notes_reveal((select array_agg(id) from public.client_notes))),
  '1990-05-01'::date,
  'a reveal returns the configured type'
);

reset role;

select ok(
  (select left(value_text, 5) = 'bsf1:' and value_text <> 'flu'
    from better_supabase.field_values where definition_id = (select id from acme_field)),
  'the custom field value is ciphertext at rest'
);
select ok(
  (select left(diagnosis, 5) = 'bsf1:' and left(birth_date, 5) = 'bsf1:' from public.client_notes),
  'the note columns are ciphertext at rest'
);
select is(
  (select count(*)::int from vault.secrets
    where name = 'bs:field-key:tenant:00000000-0000-4000-8000-000000000001'),
  1,
  'the tenant data key lives in Vault'
);
select is(
  (select count(*)::int from better_supabase.audit_events
    where event_type = 'field_value.viewed' and category = 'read'
      and tenant_id = '00000000-0000-4000-8000-000000000001'),
  1,
  'reading the encrypted field writes one read audit entry'
);
select is(
  (select count(*)::int from better_supabase.audit_events
    where event_type = 'client_notes.viewed' and category = 'read'
      and tenant_id = '00000000-0000-4000-8000-000000000001'
      and actor_id = '00000000-0000-4000-8000-0000000000a1'),
  2,
  'each reveal writes one read audit entry naming the member'
);

-- A member of another organization reveals and reads nothing.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;

select is(
  (select count(*)::int from public.client_notes_reveal(
    (select array_agg(id) from public.client_notes))),
  0,
  'a stranger reveals no note'
);
select is(
  better_supabase.read_field_values('00000000-0000-4000-8000-000000000001', 'contact', 'c-1'),
  '[]'::jsonb,
  'a stranger reads no field value'
);
select throws_ok(
  $$select better_supabase.encrypt_field_definition((select id from acme_field))$$,
  '42501',
  'not allowed to manage custom fields',
  'a stranger cannot encrypt the field'
);
select ok(
  not exists (select 1 from jsonb_array_elements(better_supabase.field_key_status()) e
    where e ->> 'owner' = 'tenant:00000000-0000-4000-8000-000000000001'),
  'a stranger does not see the tenant key status'
);
select throws_ok(
  $$select better_supabase.rotate_field_key('tenant:00000000-0000-4000-8000-000000000001')$$,
  '42501',
  'not allowed to rotate the field key of this owner',
  'a stranger cannot rotate the tenant key'
);

reset role;
select set_config('request.jwt.claims', '', true);
set local role anon;

select throws_ok(
  $$select * from public.client_notes_reveal(array[]::uuid[])$$,
  '42501',
  null,
  'anon cannot reveal'
);
select throws_ok(
  $$select better_supabase.field_key_status()$$,
  '42501',
  null,
  'anon cannot read a key status'
);

reset role;

-- The admin reads the key status and rotates the key; every value reads the same after.
create temporary table acme_before (diagnosis text, value_text text) on commit drop;
insert into acme_before
select n.diagnosis, v.value_text
from public.client_notes n, better_supabase.field_values v
where v.definition_id = (select id from acme_field);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select ok(
  (select e ->> 'key_created_at' is not null and e ->> 'key_rotated_at' is null and (e ->> 'fields')::int = 1
      and e -> 'columns' @> '[{"table":"client_notes","column":"diagnosis"}]'
      and e::text not like '%bsf1:%'
    from jsonb_array_elements(better_supabase.field_key_status()) e
    where e ->> 'owner' = 'tenant:00000000-0000-4000-8000-000000000001'),
  'the admin reads the key dates, the encrypted columns and fields, and no key material'
);
select is(
  (better_supabase.rotate_field_key('tenant:00000000-0000-4000-8000-000000000001') ->> 'values')::int,
  2,
  'the admin rotates the key and both stored rows are encrypted again'
);
select is(
  (select diagnosis from public.client_notes_reveal((select array_agg(id) from public.client_notes))),
  'asthma',
  'the note reveals the same diagnosis after the rotation'
);
select is(
  better_supabase.read_field_values('00000000-0000-4000-8000-000000000001', 'contact', 'c-1') -> 0 ->> 'text',
  'flu',
  'the field value reads the same after the rotation'
);

reset role;

select ok(
  (select n.diagnosis <> b.diagnosis and v.value_text <> b.value_text
    from public.client_notes n, better_supabase.field_values v, acme_before b
    where v.definition_id = (select id from acme_field)),
  'the stored ciphertext changed'
);
select is(
  (select count(*)::int from better_supabase.audit_events
    where event_type = 'field_key.rotated' and category = 'security'),
  1,
  'rotating a key writes a security audit entry'
);
select set_config('request.jwt.claims', '', true);

-- Dropping the key shreds every value sealed under it.
select ok(
  better_supabase.drop_field_key('tenant:00000000-0000-4000-8000-000000000001'),
  'the service role drops the tenant key'
);
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select is(
  (select diagnosis from public.client_notes_reveal((select array_agg(id) from public.client_notes))),
  null,
  'a shredded note reveals null'
);
select is(
  better_supabase.read_field_values('00000000-0000-4000-8000-000000000001', 'contact', 'c-1') -> 0 ->> 'text',
  null,
  'a shredded field value reads null'
);
select is(
  (select count(*)::int from better_supabase.audit_events
    where event_type = 'field_key.dropped' and category = 'security'),
  1,
  'dropping a key writes a security audit entry'
);

select * from finish();
rollback;
