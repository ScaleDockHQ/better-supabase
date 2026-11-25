-- An import item names records by id as well as by code. Every id must belong
-- to the run's organization, so an item can't post into another organization's
-- journal or book on its accounts. Acme is …0001, Globex is …0002.
begin;
select plan(6);

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select better_supabase.setup_accounting('00000000-0000-4000-8000-000000000001', 'EUR');
select better_supabase.setup_accounting('00000000-0000-4000-8000-000000000002', 'EUR');
select better_supabase.open_fiscal_year('00000000-0000-4000-8000-000000000002', 2026);

create temporary table refs on commit drop as
select
  (select id from better_supabase.accounting_journals where tenant_id = '00000000-0000-4000-8000-000000000002' and code = 'SAL') as globex_journal,
  (select id from better_supabase.accounting_accounts where tenant_id = '00000000-0000-4000-8000-000000000002' and code = '1200') as globex_debit,
  (select id from better_supabase.accounting_accounts where tenant_id = '00000000-0000-4000-8000-000000000002' and code = '4000') as globex_credit;

select throws_ok(
  format($$select better_supabase.import_accounting_entry(gen_random_uuid(), jsonb_build_object(
    'tenant', '00000000-0000-4000-8000-000000000001',
    'data', jsonb_build_object('journalId', %L, 'entryDate', '2026-03-05',
      'lines', jsonb_build_array(jsonb_build_object('accountId', %L, 'debit', '100'), jsonb_build_object('accountId', %L, 'credit', '100')))), null)$$,
    (select globex_journal from refs), (select globex_debit from refs), (select globex_credit from refs)),
  '22023', null, 'an entry can''t name another organization''s journal'
);
select throws_ok(
  format($$select better_supabase.import_accounting_entry(gen_random_uuid(), jsonb_build_object(
    'tenant', '00000000-0000-4000-8000-000000000001',
    'data', jsonb_build_object('journalCode', 'SAL', 'entryDate', '2026-03-05',
      'lines', jsonb_build_array(jsonb_build_object('accountId', %L, 'debit', '100'), jsonb_build_object('accountId', %L, 'credit', '100')))), null)$$,
    (select globex_debit from refs), (select globex_credit from refs)),
  '22023', null, 'an entry can''t book on another organization''s accounts'
);
select is(
  (select count(*)::int from better_supabase.accounting_entries where tenant_id = '00000000-0000-4000-8000-000000000002'),
  0, 'Globex''s ledger stays empty'
);

create temporary table parties on commit drop as
select
  (better_supabase.save_company('00000000-0000-4000-8000-000000000002', null, '{"name": "Globex supplier"}') ->> 'id')::uuid as globex_company,
  (better_supabase.save_person('00000000-0000-4000-8000-000000000002', null, '{"name": "Globex person"}') ->> 'id')::uuid as globex_person,
  (better_supabase.save_person('00000000-0000-4000-8000-000000000001', null, '{"name": "Acme person"}') ->> 'id')::uuid as acme_person;

select throws_ok(
  format($$select better_supabase.import_party_bank_account(gen_random_uuid(), jsonb_build_object(
    'tenant', '00000000-0000-4000-8000-000000000001',
    'data', jsonb_build_object('partyId', %L, 'iban', 'DE89370400440532013000')), null)$$,
    (select globex_company from parties)),
  '22023', null, 'a bank account can''t hang on another organization''s party'
);
select throws_ok(
  format($$select better_supabase.import_party_contact(gen_random_uuid(), jsonb_build_object(
    'tenant', '00000000-0000-4000-8000-000000000001',
    'data', jsonb_build_object('companyId', %L, 'personId', %L, 'isPrimary', true)), null)$$,
    (select globex_company from parties), (select acme_person from parties)),
  '22023', null, 'a contact link can''t name another organization''s company'
);
select is(
  (select count(*)::int from better_supabase.company_people where company_id = (select globex_company from parties)),
  0, 'Globex''s company gets no link from Acme''s import'
);

select * from finish();
rollback;
