-- ERP import acceptance 7 (ADR 0143, 0148): margin-scheme and credit-restriction
-- invoices import with totals that match the source. The margin invoice sells
-- for 121000 with a cost of 80000 at 21%, so the tax is on the margin: net
-- 113884, tax 7116, gross 121000 in its tax line, while the document itself
-- shows 121000 and no tax amount. The credit-restricted invoice is 100000 on a
-- payment term that restricts 2500 bps of the credit: tax 15750, gross 115750.
-- Both come with the source's totals; the import computes the same figures and
-- reports no mismatch. Run with `supabase test db`.
begin;
select plan(10);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;
select set_config(
  'bsb.run',
  (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'erp-tax', '{}'::jsonb) ->> 'id'),
  true
);
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select better_supabase.mark_import_running(current_setting('bsb.run')::uuid);

create temporary table batches (name text primary key, result jsonb) on commit drop;
grant all on batches to authenticated, service_role;

insert into batches values ('tax', better_supabase.import_upsert_batch(current_setting('bsb.run')::uuid, 'tax_code',
  '[{"key":"VAT21","data":{"code":"VAT21","name":"VAT 21%","type":"sales","rateBps":2100,"returnBoxes":["1a"],"validFrom":"2020-01-01"}},
    {"key":"MARGIN","data":{"code":"MARGIN","name":"Margin scheme","type":"margin","rateBps":2100,"returnBoxes":["1a"],"validFrom":"2020-01-01"}}]'::jsonb));
insert into batches values ('terms', better_supabase.import_upsert_batch(current_setting('bsb.run')::uuid, 'payment_term',
  '[{"key":"CR25","data":{"code":"CR25","name":"Net 30, 25% restricted","days":30,"creditRestrictionBps":2500}}]'::jsonb));

select is(
  (select jsonb_build_array(
    (result ->> 'inserted')::int, result -> 'errors') from batches where name = 'tax'),
  '[2, []]'::jsonb,
  'the VAT and margin tax codes import'
);
select is(
  (select jsonb_build_array((result ->> 'inserted')::int, result -> 'errors') from batches where name = 'terms'),
  '[1, []]'::jsonb,
  'the restricted payment term imports'
);

insert into batches values ('margin', better_supabase.import_upsert_batch(current_setting('bsb.run')::uuid, 'invoice', jsonb_build_array(jsonb_build_object(
  'key', 'inv-margin', 'data', jsonb_build_object(
    'number', 'INV-2601', 'status', 'issued', 'issuedOn', '2026-03-10', 'dueOn', '2026-04-09', 'currency', 'EUR',
    'pricesIncludeTax', true,
    'lines', jsonb_build_array(jsonb_build_object('description', 'Used machine', 'quantity', 1, 'unitAmount', 121000, 'unitCost', 80000,
      'taxCodeId', (select id from better_supabase.tax_codes where code = 'MARGIN'))),
    'taxLines', jsonb_build_array(jsonb_build_object('taxCode', 'MARGIN', 'taxRateBps', 2100, 'net', 113884, 'tax', 7116, 'gross', 121000, 'showTax', false)),
    'totals', jsonb_build_object('subtotal', 121000, 'tax', 0, 'total', 121000))))));

insert into batches values ('restricted', better_supabase.import_upsert_batch(current_setting('bsb.run')::uuid, 'invoice', jsonb_build_array(jsonb_build_object(
  'key', 'inv-restricted', 'data', jsonb_build_object(
    'number', 'INV-2602', 'status', 'issued', 'issuedOn', '2026-03-12', 'dueOn', '2026-04-11', 'currency', 'EUR',
    'attrs', jsonb_build_object('paymentTermsId', (select id from better_supabase.payment_terms where code = 'CR25')),
    'lines', jsonb_build_array(jsonb_build_object('description', 'Equipment', 'quantity', 1, 'unitAmount', 100000, 'taxRateBps', 2100,
      'taxCodeId', (select id from better_supabase.tax_codes where code = 'VAT21'))),
    'totals', jsonb_build_object('subtotal', 100000, 'tax', 15750, 'total', 115750))))));

select is(
  (select jsonb_build_array((result ->> 'inserted')::int, result -> 'errors', coalesce(result -> 'warnings', '[]'::jsonb)) from batches where name = 'margin'),
  '[1, [], []]'::jsonb,
  'the margin invoice imports with no totals or tax mismatch warning'
);
select is(
  (select jsonb_build_array(subtotal::text, tax_total::text, total::text) from better_supabase.invoices where identifier = 'INV-2601'),
  '["121000", "0", "121000"]'::jsonb,
  'the margin invoice shows the source totals: 121000 gross and no tax amount'
);
select is(
  (select jsonb_build_array(sum(net)::text, sum(tax)::text, sum(gross)::text)
   from better_supabase.invoice_tax_lines where invoice_id = (select id from better_supabase.invoices where identifier = 'INV-2601')),
  '["113884", "7116", "121000"]'::jsonb,
  'the margin invoice tax line holds the source margin tax: net 113884, tax 7116'
);
select is(
  (select jsonb_build_array((result ->> 'inserted')::int, result -> 'errors') from batches where name = 'restricted'),
  '[1, []]'::jsonb,
  'the credit-restricted invoice imports'
);
-- The header total follows the credit restriction as the tax lines do, so the
-- source's 115750 matches the computed total and nothing is reported.
select is(
  (select coalesce(result -> 'warnings', '[]'::jsonb) from batches where name = 'restricted'),
  '[]'::jsonb,
  'the credit-restricted invoice reports no totals mismatch'
);
select is(
  (select jsonb_build_array(sum(net)::text, sum(tax)::text, sum(gross)::text)
   from better_supabase.invoice_tax_lines where invoice_id = (select id from better_supabase.invoices where identifier = 'INV-2602')),
  '["100000", "15750", "115750"]'::jsonb,
  'the credit-restricted tax line follows the restriction: net 100000, tax 15750, gross 115750'
);
select is(
  (select jsonb_build_array(subtotal::text, tax_total::text, total::text) from better_supabase.invoices where identifier = 'INV-2602'),
  '["100000", "15750", "115750"]'::jsonb,
  'the credit-restricted invoice totals match the source: tax 15750, gross 115750'
);
-- A source that disagrees is reported, and the source's figures are kept.
insert into batches values ('wrong', better_supabase.import_upsert_batch(current_setting('bsb.run')::uuid, 'invoice', jsonb_build_array(jsonb_build_object(
  'key', 'inv-wrong', 'data', jsonb_build_object(
    'number', 'INV-2603', 'status', 'issued', 'issuedOn', '2026-03-14', 'dueOn', '2026-04-13', 'currency', 'EUR',
    'lines', jsonb_build_array(jsonb_build_object('description', 'Equipment', 'quantity', 1, 'unitAmount', 100000, 'taxRateBps', 2100)),
    'totals', jsonb_build_object('subtotal', 100000, 'tax', 21000, 'total', 120000))))));
select is(
  (select result -> 'warnings' -> 0 ->> 'code' from batches where name = 'wrong'),
  'IMPORT_TOTALS_MISMATCH',
  'a source total that differs from the computed one is reported'
);

select * from finish();
rollback;
