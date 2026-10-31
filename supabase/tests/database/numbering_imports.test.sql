-- Numbering for imports (ADR 0155). A fixed historical number is accepted
-- only while an import session runs (`better_supabase.import_run()`), series
-- count per kind and legal entity, a normal issue continues above the highest
-- imported number of its series, and `sync_number_sequences` lists numbers
-- that don't match the current format without rejecting them. Run with
-- `supabase test db`.
begin;
select plan(17);

select has_column('better_supabase', 'number_sequences', 'scope', 'number sequences carry a scope');
select col_is_pk('better_supabase', 'number_sequences', array['tenant_id', 'entity', 'scope', 'period'],
  'the sequence key holds the scope and the period');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

create temporary table ids (name text primary key, id uuid) on commit drop;
grant all on ids to authenticated, service_role;

select set_config(
  'bsb.run',
  (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'numbering', '{}'::jsonb) ->> 'id'),
  true
);
insert into ids values ('de', (better_supabase.create_legal_entity('00000000-0000-4000-8000-000000000001', 'DE01', 'Acme GmbH') ->> 'id')::uuid);
insert into ids values ('be', (better_supabase.create_legal_entity('00000000-0000-4000-8000-000000000001', 'BE01', 'Acme NV') ->> 'id')::uuid);

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

create temporary table inv (name text primary key, id uuid) on commit drop;
grant all on inv to authenticated, service_role;

insert into inv
select n, (better_supabase.create_invoice('00000000-0000-4000-8000-000000000001',
  jsonb_build_object('title', 'Numbering ' || n, 'currency', 'EUR', 'termsDays', 10),
  jsonb_build_array(jsonb_build_object('description', 'Service', 'quantity', 1, 'unitAmount', 1000))) ->> 'id')::uuid
from unnest(array['de_old', 'be_old', 'de_new', 'be_new', 'de_credit']) n;

update better_supabase.invoices set legal_entity_id = (select id from ids where name = 'be')
where id in (select id from inv where name in ('be_old', 'be_new'));

-- Outside an import a fixed number is refused, for every entity.
select throws_ok(
  format($$select better_supabase.issue_invoice(%L, current_date, null, null, 'INV-23000365')$$, (select id from inv where name = 'de_old')),
  '42501', null, 'issue_invoice refuses a fixed number outside an import'
);
select throws_ok(
  $$select better_supabase.credit_invoice('00000000-0000-4000-8000-0000000000ff', null, 'x', 'CN-1')$$,
  '42501', null, 'credit_invoice refuses a fixed number outside an import'
);
select throws_ok(
  $$select better_supabase.set_fixed_number('quote', 'Q-1')$$,
  '42501', null, 'set_fixed_number refuses a number outside an import'
);
select throws_ok(
  $$select better_supabase.register_fixed_number('00000000-0000-4000-8000-000000000001', 'invoice', 'INV-1')$$,
  '42501', null, 'register_fixed_number refuses a number outside an import'
);
select is(
  (select status from better_supabase.invoices where id = (select id from inv where name = 'de_old')),
  'draft',
  'the refused invoice stays a draft'
);

-- During a session the importer's numbers are kept as they are.
select better_supabase.mark_import_running(current_setting('bsb.run')::uuid);
select better_supabase.begin_import_session(current_setting('bsb.run')::uuid);

select is(
  (select better_supabase.issue_invoice(id, current_date, null, null, 'INV-23000365') ->> 'identifier' from inv where name = 'de_old'),
  'INV-23000365',
  'an import keeps the historical invoice number'
);
select is(
  (select number from better_supabase.invoices where id = (select id from inv where name = 'de_old')),
  23000365::bigint,
  'the number holds the digits the historical number ends with'
);
select is(
  (select better_supabase.issue_invoice(id, current_date, null, null, 'INV-100') ->> 'identifier' from inv where name = 'be_old'),
  'INV-100',
  'the second legal entity keeps its own historical number'
);
select is(
  (select better_supabase.credit_invoice((select id from inv where name = 'de_old'), null, 'Imported credit', 'CN-77') ->> 'identifier'),
  'CN-77',
  'an import keeps the historical credit note number'
);
select is(
  (select status from better_supabase.invoices where identifier = 'CN-77'),
  'issued',
  'the imported credit note is issued at once'
);

select set_config('better_supabase.import_run', '', true);
select throws_ok(
  format($$select better_supabase.issue_invoice(%L, current_date, null, null, 'INV-1')$$, (select id from inv where name = 'de_new')),
  '42501', null, 'ending the session ends the fixed numbers'
);

-- A normal issue continues above the highest imported number of its series:
-- per kind, per legal entity.
select is(
  (select better_supabase.issue_invoice(id, current_date) ->> 'identifier' from inv where name = 'de_new'),
  'INV-23000366',
  'the default entity continues above its highest imported invoice'
);
select is(
  (select better_supabase.issue_invoice(id, current_date) ->> 'identifier' from inv where name = 'be_new'),
  'INV-101',
  'the second entity continues in its own series'
);
select is(
  (select better_supabase.issue_invoice(
    (better_supabase.credit_invoice((select id from inv where name = 'de_new'), null, 'Credit') ->> 'id')::uuid,
    current_date) ->> 'identifier'),
  'CN-78',
  'credit notes continue in their own series, apart from the invoices'
);
-- The fixture numbers no invoice entity, so the sync (covered with configured
-- entities in tests/sql/modules/numbering-imports.test.ts) refuses it.
select throws_ok(
  $$select better_supabase.sync_number_sequences('00000000-0000-4000-8000-000000000001', 'invoice')$$,
  '22023', null, 'the sync refuses an entity numbering does not number'
);

select * from finish();
rollback;
