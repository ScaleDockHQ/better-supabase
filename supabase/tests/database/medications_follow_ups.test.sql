-- Medication signatures and guest reads. The Acme owner (…a1) prescribes a
-- medication for the customer Road Runner Inc (…a001), a signature approves
-- the order, and a guest (…e1) of that customer reads the order, its doses and
-- the medication but writes nothing.
-- Run with `supabase test db`.
begin;
select plan(8);

insert into auth.users (id, email, email_confirmed_at, aud, role, instance_id) values
  ('00000000-0000-4000-8000-0000000000e1', 'family@example.test', now(), 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

create temporary table ids (name text primary key, id uuid) on commit drop;
grant all on ids to authenticated;
insert into ids values ('med', (better_supabase.save_medication(
  '00000000-0000-4000-8000-000000000001', 'Paracetamol', 'mg') ->> 'id')::uuid);
insert into ids values ('order', (better_supabase.prescribe_medication(
  '00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001',
  (select id from ids where name = 'med'),
  jsonb_build_object('dose', 500, 'schedule', jsonb_build_object('times', jsonb_build_array('08:00')),
    'startsOn', current_date + 1)) ->> 'id')::uuid);
select better_supabase.plan_medication_administrations('00000000-0000-4000-8000-000000000001', now() + interval '3 days');

select throws_ok(
  $$select better_supabase.approve_medication_order((select id from ids where name = 'order'), null)$$,
  '22023',
  'approving an order needs a signature',
  'approving an order without a signature is refused'
);
select throws_ok(
  $$select better_supabase.approve_medication_order((select id from ids where name = 'order'), gen_random_uuid())$$,
  '22023',
  null,
  'a signature that is not yours and completed on this order is refused'
);

reset role;
insert into better_supabase.versions (id, tenant_id, subject_type, subject_id, number, content, content_hash)
select gen_random_uuid(), '00000000-0000-4000-8000-000000000001', 'medication_order', id::text, 1, '{}', 'h'
from ids where name = 'order';
insert into better_supabase.signature_requests (id, tenant_id, subject_type, subject_id, version_id, content_hash, signers, status)
select gen_random_uuid(), '00000000-0000-4000-8000-000000000001', 'medication_order', v.subject_id, v.id, 'h',
  array['00000000-0000-4000-8000-0000000000a1'::uuid], 'completed'
from better_supabase.versions v where v.subject_type = 'medication_order';
insert into better_supabase.signatures (id, request_id, tenant_id, signer, method, typed_name, signed_hash, signed_at)
select gen_random_uuid(), r.id, r.tenant_id, '00000000-0000-4000-8000-0000000000a1', 'typed', 'Owner', 'h', now()
from better_supabase.signature_requests r;

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select lives_ok(
  $$select better_supabase.approve_medication_order((select id from ids where name = 'order'), (select id from better_supabase.signatures limit 1))$$,
  'the signer approves the order with their completed signature'
);
select isnt(
  (select signature_id from better_supabase.medication_orders where id = (select id from ids where name = 'order')),
  null,
  'the order keeps the signature'
);

select set_config('test.invite', better_supabase.invite_guest(
  '00000000-0000-4000-8000-000000000001', 'family@example.test', 'Family',
  party_type => 'customer', party_id => '00000000-0000-4000-8000-00000000a001'
)::text, true);

reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000e1","role":"authenticated"}', true);
set local role authenticated;
select better_supabase.accept_guest_invite(current_setting('test.invite')::jsonb ->> 'token');

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;
select better_supabase.grant_guest_access(
  (current_setting('test.invite')::jsonb ->> 'id')::uuid, 'customer', '00000000-0000-4000-8000-00000000a001'
);

reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000e1","role":"authenticated"}', true);
set local role authenticated;

select is((select count(*) from better_supabase.medication_orders), 1::bigint,
  'a guest reads the order of the record they were granted');
select ok((select count(*) from better_supabase.medication_administrations) >= 1,
  'a guest reads its doses');
select is((select count(*) from better_supabase.medications), 1::bigint,
  'a guest reads the medication the order names');
select throws_ok(
  $$select better_supabase.pause_medication_order((select id from ids where name = 'order'), true)$$,
  null,
  null,
  'a guest writes nothing'
);

select * from finish();
rollback;
