-- Party roles and supplier status against the seed: the Acme member (…a2)
-- adds a company and sets its roles but can't approve it as a supplier, the
-- Acme owner (…a1) can, and the Globex owner (…a3) sees neither. Run with
-- `supabase test db`.
begin;
select plan(9);

select has_column('better_supabase', 'companies', 'roles', 'companies have roles');
select col_default_is('better_supabase', 'companies', 'roles', '{}'::text[], 'a company starts without roles');
select has_index('better_supabase', 'companies', 'companies_roles_idx', 'the role filter has an index');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

create temporary table ids (name text primary key, id uuid) on commit drop;
insert into ids values ('acme', (better_supabase.save_company(
  '00000000-0000-4000-8000-000000000001', null, '{"name": "Party roles supplier"}') ->> 'id')::uuid);

select is(
  better_supabase.set_party_roles((select id from ids where name = 'acme'), array['supplier', 'customer']) -> 'party' -> 'roles',
  '["customer", "supplier"]'::jsonb,
  'a member sets the roles, sorted'
);
select throws_ok(
  $$select better_supabase.set_party_roles((select id from ids where name = 'acme'), array['vendor'])$$,
  '22023',
  'unknown party role',
  'a role outside options.roles is refused'
);
select throws_ok(
  $$select better_supabase.set_supplier_status((select id from ids where name = 'acme'), 'approved')$$,
  '42501',
  'not allowed to approve suppliers',
  'a member without contacts.approve_supplier can''t approve a supplier'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);

select is(
  better_supabase.set_supplier_status((select id from ids where name = 'acme'), 'approved', 'Audited') -> 'party' ->> 'supplier_status',
  'approved',
  'the owner approves the supplier'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);

select is(
  (select count(*) from better_supabase.companies where id = (select id from ids where name = 'acme')),
  0::bigint,
  'another organization does not read the company'
);
select throws_ok(
  $$select better_supabase.set_supplier_status((select id from ids where name = 'acme'), 'blocked')$$,
  '42501',
  'not allowed to approve suppliers',
  'another organization''s owner can''t change the status'
);

select * from finish();
rollback;
