-- The tax module on the fixture (ADR 0143). The Acme owner (…a1) adds tax codes with
-- dated rates, computes the tax of documents (margin scheme and credit restriction
-- included), issues invoices that write their tax lines, and prepares, files and lists
-- a tax return with its intra-EU sales list. The member (…a2) reads but can't change
-- anything, and the Globex owner (…a3) sees none of it. Run with `supabase test db`.
--
-- Hand-computed expectations, in minor units, rounded once per line:
--   Rate history: VAT21 charges 2100 bps until 2026-12-31 and 2300 bps from 2027-01-01.
--     100000 added on top: 100000 * 2100 / 10000 = 21000, and * 2300 / 10000 = 23000.
--   Margin scheme (type margin, prices include tax): price 121000, cost 80000, 2100 bps.
--     margin = 121000 - 80000 = 41000; tax = round(41000 * 2100 / (10000 + 2100))
--     = round(7115.70) = 7116; net = 121000 - 7116 = 113884; gross = 121000.
--     The document shows no tax amount (showTaxAmount is false).
--   Credit restriction 2500 bps on 100000 at 2100 bps, tax added on top:
--     taxable base = 100000 * (10000 - 2500) / 10000 = 75000; tax = 75000 * 2100 / 10000
--     = 15750; gross = 115750.
begin;
select plan(32);

select is(
  (select count(*) from pg_catalog.pg_tables
   where schemaname = 'better_supabase'
     and tablename in ('tax_codes', 'tax_rates', 'invoice_tax_lines', 'tax_returns', 'eu_sales_list_lines')
     and rowsecurity),
  5::bigint,
  'the tax tables have RLS enabled'
);
select table_privs_are('better_supabase', 'tax_codes', 'anon', '{}'::text[],
  'anon has no privileges on tax codes');
select table_privs_are('better_supabase', 'tax_codes', 'authenticated', array['SELECT'],
  'authenticated only reads tax codes; writes go through the functions');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

create temporary table ids (name text primary key, id uuid) on commit drop;

insert into ids values ('vat21', (better_supabase.save_tax_code('00000000-0000-4000-8000-000000000001',
  '{"code": "VAT21", "name": "VAT 21%", "type": "sales", "rateBps": 2100, "returnBoxes": ["1a"]}') ->> 'id')::uuid);
select is(
  (select jsonb_build_array(code, type, return_boxes) from better_supabase.tax_codes
   where id = (select id from ids where name = 'vat21')),
  '["VAT21", "sales", ["1a"]]'::jsonb,
  'the owner adds a tax code with its return boxes'
);
select throws_ok(
  $$select better_supabase.save_tax_code('00000000-0000-4000-8000-000000000001', '{"code": "VAT21", "name": "Again", "type": "sales", "rateBps": 900}')$$,
  '22023',
  null,
  'a code is unique per organization'
);
select throws_ok(
  $$select better_supabase.save_tax_code('00000000-0000-4000-8000-000000000001', '{"code": "BAD", "name": "Bad", "type": "nonsense"}')$$,
  null,
  null,
  'an unknown type is refused'
);

select better_supabase.save_tax_rate('00000000-0000-4000-8000-000000000001',
  (select id from ids where name = 'vat21'), 2300, date '2027-01-01');
select is(
  (select jsonb_agg(jsonb_build_array(rate_bps, valid_to) order by valid_from) from better_supabase.tax_rates
   where tax_code_id = (select id from ids where name = 'vat21')),
  '[[2100, "2026-12-31"], [2300, null]]'::jsonb,
  'a later rate ends the one before it the day before'
);
select is(better_supabase.tax_rate_on((select id from ids where name = 'vat21'), date '2026-12-31'), 2100,
  'the rate valid on the last day of the old rate is 21%');
select is(better_supabase.tax_rate_on((select id from ids where name = 'vat21'), date '2027-01-01'), 2300,
  'the rate valid on the first day of the new rate is 23%');

select is(
  (better_supabase.compute_document_tax(
    jsonb_build_array(jsonb_build_object('quantity', 1, 'unitAmount', 100000, 'taxCodeId', (select id from ids where name = 'vat21'))),
    date '2026-12-31') ->> 'taxTotal'),
  '21000',
  'a document dated 2026-12-31 is taxed at 21%: 100000 * 2100 / 10000'
);
select is(
  (better_supabase.compute_document_tax(
    jsonb_build_array(jsonb_build_object('quantity', 1, 'unitAmount', 100000, 'taxCodeId', (select id from ids where name = 'vat21'))),
    date '2027-01-01') ->> 'total'),
  '123000',
  'a document dated 2027-01-01 is taxed at 23%: 100000 + 23000'
);

insert into ids values ('margin', (better_supabase.save_tax_code('00000000-0000-4000-8000-000000000001',
  '{"code": "MARGIN", "name": "Margin scheme", "type": "margin", "rateBps": 2100, "returnBoxes": ["1a"]}') ->> 'id')::uuid);
select is(
  (select jsonb_build_array(g ->> 'net', g ->> 'tax', g ->> 'gross')
   from jsonb_array_elements(better_supabase.compute_document_tax(
     jsonb_build_array(jsonb_build_object('quantity', 1, 'unitAmount', 121000, 'unitCost', 80000,
       'taxCodeId', (select id from ids where name = 'margin'))),
     date '2026-06-30', true) -> 'groups') g),
  '["113884", "7116", "121000"]'::jsonb,
  'the margin scheme taxes the margin: net 113884, tax 7116, gross 121000'
);
select is(
  (better_supabase.compute_document_tax(
    jsonb_build_array(jsonb_build_object('quantity', 1, 'unitAmount', 121000, 'unitCost', 80000,
      'taxCodeId', (select id from ids where name = 'margin'))),
    date '2026-06-30', true) ->> 'showTaxAmount')::boolean,
  false,
  'a margin scheme document shows no tax amount'
);
select throws_ok(
  format($$select better_supabase.compute_document_tax(
    '[{"unitAmount": 121000, "taxCodeId": "%s"}]'::jsonb, date '2026-06-30', true)$$,
    (select id from ids where name = 'margin')),
  '22023',
  null,
  'a margin line without a cost is refused'
);

select is(
  (select jsonb_build_array(r ->> 'taxTotal', r ->> 'total')
   from (select better_supabase.compute_document_tax(
     jsonb_build_array(jsonb_build_object('quantity', 1, 'unitAmount', 100000, 'taxCodeId', (select id from ids where name = 'vat21'))),
     date '2026-06-30', false, 2500) as r) x),
  '["15750", "115750"]'::jsonb,
  'a credit restriction of 2500 bps taxes 75000: tax 15750, gross 115750'
);

insert into ids values ('exempt', (better_supabase.save_tax_code('00000000-0000-4000-8000-000000000001',
  '{"code": "EXEMPT", "name": "Exempt", "type": "exempt", "returnBoxes": ["5"]}') ->> 'id')::uuid);
select is(
  (better_supabase.compute_document_tax(
    jsonb_build_array(jsonb_build_object('quantity', 2, 'unitAmount', 5000, 'taxCodeId', (select id from ids where name = 'exempt'))),
    date '2026-06-30') ->> 'taxTotal'),
  '0',
  'an exempt code charges no tax'
);

insert into ids values ('icg', (better_supabase.save_tax_code('00000000-0000-4000-8000-000000000001',
  '{"code": "ICG", "name": "Intra-EU goods", "type": "intra_eu_goods", "returnBoxes": ["3b"]}') ->> 'id')::uuid);

-- Invoices: a domestic sale and an intra-EU sale to a customer with a VAT number.
insert into ids values ('domestic', (better_supabase.save_company('00000000-0000-4000-8000-000000000001', null,
  '{"name": "Domestic customer"}') ->> 'id')::uuid);
insert into ids values ('german', (better_supabase.save_company('00000000-0000-4000-8000-000000000001', null,
  '{"name": "German customer", "vatId": "DE 123456789"}') ->> 'id')::uuid);

insert into ids values ('inv1', (better_supabase.create_invoice('00000000-0000-4000-8000-000000000001',
  jsonb_build_object('title', 'Domestic', 'currency', 'EUR', 'company', jsonb_build_object('id', (select id from ids where name = 'domestic'))),
  jsonb_build_array(jsonb_build_object('description', 'Consulting', 'quantity', 1, 'unitAmount', 100000, 'taxCode', 'VAT21'))) ->> 'id')::uuid);
insert into ids values ('inv2', (better_supabase.create_invoice('00000000-0000-4000-8000-000000000001',
  jsonb_build_object('title', 'Intra-EU', 'currency', 'EUR', 'company', jsonb_build_object('id', (select id from ids where name = 'german'))),
  jsonb_build_array(jsonb_build_object('description', 'Goods', 'quantity', 1, 'unitAmount', 50000, 'taxCode', 'ICG'))) ->> 'id')::uuid);
select better_supabase.issue_invoice((select id from ids where name = 'inv1'), current_date);
select better_supabase.issue_invoice((select id from ids where name = 'inv2'), current_date);

select is(
  (select jsonb_build_array(tax_code_id = (select id from ids where name = 'vat21'), tax_rate_bps, net, tax, gross)
   from better_supabase.invoice_tax_lines where invoice_id = (select id from ids where name = 'inv1')),
  '[true, 2100, 100000, 21000, 121000]'::jsonb,
  'issuing writes the invoice tax line: a code named by text resolves to its rate that day'
);
select is(
  (select tax_rate_bps from better_supabase.invoice_lines
   where parent_id = (select id from ids where name = 'inv1')),
  2100,
  'the issued line carries the resolved rate'
);
select is(
  (select tax_code_id from better_supabase.invoice_lines
   where parent_id = (select id from ids where name = 'inv2')),
  (select id from ids where name = 'icg'),
  'the issued line carries the resolved code id'
);

insert into ids values ('return', (better_supabase.prepare_tax_return('00000000-0000-4000-8000-000000000001',
  date_trunc('month', current_date)::date, current_date, null, 'current') ->> 'id')::uuid);
select is(
  (select boxes -> 'boxes' from better_supabase.tax_returns where id = (select id from ids where name = 'return')),
  '[{"box": "1a", "base": "100000", "tax": "21000"}, {"box": "3b", "base": "50000", "tax": "0"}]'::jsonb,
  'the return totals base and tax per box'
);
select is(
  (select jsonb_build_array(boxes ->> 'salesTax', boxes ->> 'purchaseTax', boxes ->> 'netTax')
   from better_supabase.tax_returns where id = (select id from ids where name = 'return')),
  '["21000", "0", "21000"]'::jsonb,
  'the net tax is the sales tax less the purchase tax'
);
select is(
  (select jsonb_agg(jsonb_build_array(customer_vat_number, country, kind, amount, invoice_count))
   from better_supabase.eu_sales_list_lines where tax_return_id = (select id from ids where name = 'return')),
  '[["DE123456789", "DE", "goods", 50000, 1]]'::jsonb,
  'the EU sales list holds the intra-EU sale per customer VAT number'
);
select is(
  (better_supabase.prepare_tax_return('00000000-0000-4000-8000-000000000001',
    date_trunc('month', current_date)::date, current_date) ->> 'id')::uuid,
  (select id from ids where name = 'return'),
  'preparing the same period again rebuilds the draft return'
);
select is(
  (select count(*) from better_supabase.eu_sales_list_lines where tax_return_id = (select id from ids where name = 'return')),
  1::bigint,
  'a rebuilt return replaces its sales list'
);
select is(
  better_supabase.file_tax_return((select id from ids where name = 'return')) ->> 'status',
  'filed',
  'filing freezes the return'
);
select throws_ok(
  $$select better_supabase.prepare_tax_return('00000000-0000-4000-8000-000000000001',
    date_trunc('month', current_date)::date, current_date)$$,
  '55000',
  null,
  'a filed return can''t be prepared again'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);

select is(
  (select count(*) from better_supabase.tax_codes),
  4::bigint,
  'a member reads the tax codes'
);
select throws_ok(
  $$select better_supabase.save_tax_code('00000000-0000-4000-8000-000000000001', '{"code": "X", "name": "X", "type": "sales"}')$$,
  '42501',
  null,
  'a member can''t change tax codes'
);
select throws_ok(
  $$select better_supabase.prepare_tax_return('00000000-0000-4000-8000-000000000001', date '2026-01-01', date '2026-03-31')$$,
  '42501',
  null,
  'a member can''t prepare a return'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);

select is(
  (select count(*) from better_supabase.tax_codes) + (select count(*) from better_supabase.tax_returns)
    + (select count(*) from better_supabase.invoice_tax_lines),
  0::bigint,
  'another organization''s owner sees no tax rows'
);
select throws_ok(
  $$select better_supabase.list_tax_codes('00000000-0000-4000-8000-000000000001')$$,
  '42501',
  null,
  'another organization''s owner can''t list the codes'
);
select throws_ok(
  $$select better_supabase.list_tax_returns('00000000-0000-4000-8000-000000000001')$$,
  '42501',
  null,
  'another organization''s owner can''t list the returns'
);

select * from finish();
rollback;
