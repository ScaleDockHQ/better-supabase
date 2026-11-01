-- ERP known gaps 3 (ADR 0143): invoices issued before the totals followed the
-- credit restriction keep stored totals that ignore it. recompute_invoice_totals
-- reports the difference in a dry run, writes it only when asked, leaves the
-- number, issue date and status alone, changes nothing on a second run, writes
-- an audit entry and no outbox event, and does not touch a posted accounting
-- entry: it reports that the entry needs a correcting entry, also when the
-- period is closed. Run with `supabase test db`.
begin;
select plan(22);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;
select better_supabase.setup_accounting('00000000-0000-4000-8000-000000000001', 'EUR');
select better_supabase.open_fiscal_year('00000000-0000-4000-8000-000000000001', 2026);
select set_config(
  'bsb.run',
  (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'gap-repair', '{}'::jsonb) ->> 'id'),
  true
);
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select better_supabase.mark_import_running(current_setting('bsb.run')::uuid);

select better_supabase.import_upsert_batch(current_setting('bsb.run')::uuid, 'tax_code',
  '[{"key":"VAT21","data":{"code":"VAT21","name":"VAT 21%","type":"sales","rateBps":2100,"returnBoxes":["1a"],"validFrom":"2020-01-01"}}]'::jsonb);
select better_supabase.import_upsert_batch(current_setting('bsb.run')::uuid, 'payment_term',
  '[{"key":"CR25","data":{"code":"CR25","name":"Net 30, 25% restricted","days":30,"creditRestrictionBps":2500}}]'::jsonb);

-- Two restricted invoices, one in March and one in April, and a plain one.
select better_supabase.import_upsert_batch(current_setting('bsb.run')::uuid, 'invoice', jsonb_build_array(
  jsonb_build_object('key', 'r-1', 'data', jsonb_build_object(
    'number', 'INV-3001', 'status', 'issued', 'issuedOn', '2026-03-10', 'dueOn', '2026-04-09', 'currency', 'EUR',
    'attrs', jsonb_build_object('paymentTermsId', (select id from better_supabase.payment_terms where code = 'CR25')),
    'lines', jsonb_build_array(jsonb_build_object('description', 'Equipment', 'quantity', 1, 'unitAmount', 100000, 'taxRateBps', 2100,
      'taxCodeId', (select id from better_supabase.tax_codes where code = 'VAT21'))),
    'totals', jsonb_build_object('subtotal', 100000, 'tax', 15750, 'total', 115750))),
  jsonb_build_object('key', 'r-2', 'data', jsonb_build_object(
    'number', 'INV-3002', 'status', 'issued', 'issuedOn', '2026-04-10', 'dueOn', '2026-05-09', 'currency', 'EUR',
    'attrs', jsonb_build_object('paymentTermsId', (select id from better_supabase.payment_terms where code = 'CR25')),
    'lines', jsonb_build_array(jsonb_build_object('description', 'Equipment', 'quantity', 1, 'unitAmount', 100000, 'taxRateBps', 2100,
      'taxCodeId', (select id from better_supabase.tax_codes where code = 'VAT21'))),
    'totals', jsonb_build_object('subtotal', 100000, 'tax', 15750, 'total', 115750))),
  jsonb_build_object('key', 'p-1', 'data', jsonb_build_object(
    'number', 'INV-3003', 'status', 'issued', 'issuedOn', '2026-03-11', 'dueOn', '2026-04-10', 'currency', 'EUR',
    'lines', jsonb_build_array(jsonb_build_object('description', 'Service', 'quantity', 1, 'unitAmount', 50000, 'taxRateBps', 2100,
      'taxCodeId', (select id from better_supabase.tax_codes where code = 'VAT21'))),
    'totals', jsonb_build_object('subtotal', 50000, 'tax', 10500, 'total', 60500)))));

-- The import run ends here: the repair runs as a plain system correction.
select set_config('better_supabase.import_run', '', true);

-- The stored totals as an older release wrote them: the restriction ignored.
update better_supabase.invoices set tax_total = 21000, total = 121000 where identifier in ('INV-3001', 'INV-3002');

select is(
  (select jsonb_agg(total::text order by identifier) from better_supabase.invoices where identifier like 'INV-300%'),
  '["121000", "121000", "60500"]'::jsonb,
  'two invoices carry the totals of before the restriction'
);

-- INV-3002 is booked at its old amount, in a period that is then closed.
select better_supabase.post_accounting_source('invoice', (select id::text from better_supabase.invoices where identifier = 'INV-3002'));
create temporary table booked on commit drop as
select y.id as entry_id, y.number as entry_number, y.period_id,
  (select sum(l.debit) from better_supabase.accounting_entry_lines l where l.entry_id = y.id) as debit
from better_supabase.accounting_entries y
where y.source_type = 'invoice' and y.source_id = (select id::text from better_supabase.invoices where identifier = 'INV-3002') and y.status = 'posted';
grant all on booked to authenticated, service_role;

select is((select count(*) from booked), 1::bigint, 'INV-3002 is booked in the ledger');
select is(
  (select debit from booked), 121000::numeric,
  'the booking holds the old total'
);
select better_supabase.close_accounting_period((select period_id from booked));

create temporary table before_state on commit drop as
select identifier, number, issued_on, status from better_supabase.invoices where identifier like 'INV-300%';
grant all on before_state to authenticated, service_role;

-- A dry run reports and writes nothing.
create temporary table runs (name text primary key, result jsonb) on commit drop;
grant all on runs to authenticated, service_role;
insert into runs values ('dry', better_supabase.recompute_invoice_totals('00000000-0000-4000-8000-000000000001'));

select is(
  (select jsonb_build_array(result ->> 'dryRun', result ->> 'checked', result ->> 'changed', result ->> 'applied') from runs where name = 'dry'),
  '["true", "3", "2", "0"]'::jsonb,
  'the dry run is the default: it checks three invoices, finds two and applies none'
);
select is(
  (select jsonb_build_array(i -> 'old' ->> 'total', i -> 'new' ->> 'total', i -> 'old' ->> 'taxTotal', i -> 'new' ->> 'taxTotal')
   from runs, jsonb_array_elements(result -> 'invoices') i where name = 'dry' and i ->> 'identifier' = 'INV-3001'),
  '["121000", "115750", "21000", "15750"]'::jsonb,
  'the report lists the old and the new totals'
);
select is(
  (select jsonb_agg(total::text order by identifier) from better_supabase.invoices where identifier like 'INV-300%'),
  '["121000", "121000", "60500"]'::jsonb,
  'the dry run wrote nothing'
);
select is(
  (select count(*) from better_supabase.audit_events where op = 'event' and event_type = 'invoice.totals_corrected'),
  0::bigint,
  'a dry run leaves no audit entry'
);

-- The ledger probe: INV-3001 has no booking, INV-3002 has one in a closed period.
select is(
  (select i -> 'ledger' ->> 'posted' from runs, jsonb_array_elements(result -> 'invoices') i where name = 'dry' and i ->> 'identifier' = 'INV-3001'),
  'false',
  'an invoice that is not booked needs no correcting entry'
);
select is(
  (select jsonb_build_array(i -> 'ledger' ->> 'posted', i -> 'ledger' ->> 'periodStatus', i -> 'ledger' ->> 'needsCorrectingEntry', i -> 'ledger' ->> 'entryNumber')
   from runs, jsonb_array_elements(result -> 'invoices') i where name = 'dry' and i ->> 'identifier' = 'INV-3002'),
  (select jsonb_build_array('true', 'closed', 'true', entry_number) from booked),
  'a booked invoice in a closed period is reported as needing a correcting entry'
);

-- Applying one invoice by id.
insert into runs values ('apply', better_supabase.recompute_invoice_totals(
  '00000000-0000-4000-8000-000000000001',
  array[(select id from better_supabase.invoices where identifier = 'INV-3001')], false));
select is(
  (select jsonb_build_array(result ->> 'dryRun', result ->> 'checked', result ->> 'changed', result ->> 'applied') from runs where name = 'apply'),
  '["false", "1", "1", "1"]'::jsonb,
  'applying one invoice by id writes that invoice'
);
select is(
  (select jsonb_build_array(subtotal::text, tax_total::text, total::text) from better_supabase.invoices where identifier = 'INV-3001'),
  '["100000", "15750", "115750"]'::jsonb,
  'the header totals follow the credit restriction'
);
select is(
  (select jsonb_build_array(sum(net)::text, sum(tax)::text, sum(gross)::text)
   from better_supabase.invoice_tax_lines where invoice_id = (select id from better_supabase.invoices where identifier = 'INV-3001')),
  '["100000", "15750", "115750"]'::jsonb,
  'the tax lines agree with the header'
);
select is(
  (select total::text from better_supabase.invoices where identifier = 'INV-3002'),
  '121000',
  'an invoice that was not named is left alone'
);
select is(
  (select count(*) from before_state b join better_supabase.invoices x using (identifier)
   where b.number is distinct from x.number or b.issued_on is distinct from x.issued_on or b.status is distinct from x.status),
  0::bigint,
  'no number, issue date or status changed'
);
select is(
  (select count(*) from better_supabase.audit_events where op = 'event' and event_type = 'invoice.totals_corrected'),
  1::bigint,
  'the correction is audit logged once'
);
select is(
  (select count(*) from better_supabase.outbox_events where type = 'invoice.totals_corrected'),
  0::bigint,
  'no event is sent unless options.correctionEvents is on'
);

-- A second run changes nothing for the repaired invoice.
insert into runs values ('again', better_supabase.recompute_invoice_totals(
  '00000000-0000-4000-8000-000000000001',
  array[(select id from better_supabase.invoices where identifier = 'INV-3001')], false));
select is(
  (select result ->> 'changed' from runs where name = 'again'),
  '0',
  'a second run is idempotent'
);

-- Everything: the booked invoice is corrected on the invoice, never in the ledger.
insert into runs values ('all', better_supabase.recompute_invoice_totals('00000000-0000-4000-8000-000000000001', null, false));
select is(
  (select jsonb_build_array(result ->> 'checked', result ->> 'changed', result ->> 'applied') from runs where name = 'all'),
  '["3", "1", "1"]'::jsonb,
  'a run over every issued invoice finds the one that is left'
);
select is(
  (select total::text from better_supabase.invoices where identifier = 'INV-3002'),
  '115750',
  'the booked invoice follows the restriction too'
);
select is(
  (select sum(l.debit) from better_supabase.accounting_entry_lines l where l.entry_id = (select entry_id from booked)),
  (select debit from booked),
  'the posted entry is not changed'
);
select is(
  (select count(*) from better_supabase.accounting_entries where source_type = 'invoice' and source_id = (select id::text from better_supabase.invoices where identifier = 'INV-3002')),
  1::bigint,
  'no entry was added or reversed'
);

-- Permissions: a member without invoices.manage can't repair.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;
select throws_ok(
  $$select better_supabase.recompute_invoice_totals('00000000-0000-4000-8000-000000000001')$$,
  '42501', null, 'a member can not repair totals'
);

select * from finish();
rollback;
