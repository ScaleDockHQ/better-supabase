-- ERP import acceptance 1 (ADR 0141): a second identical import run writes zero
-- rows and zero audit rows. One run brings in the whole ledger of a small
-- company: payment terms, a tax code, accounts, a journal, opening balances,
-- ledger entries, an invoice with payments, a credit note, an open item, a quote
-- and an order. The same input in a second run reports every record as
-- unchanged, changes no row count of any touched table and adds no audit event.
-- Run with `supabase test db`.
begin;
select plan(10);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select better_supabase.setup_accounting('00000000-0000-4000-8000-000000000001', 'EUR');
select better_supabase.open_fiscal_year('00000000-0000-4000-8000-000000000001', 2026);

select set_config(
  'bsb.run1',
  (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'erp-rerun', '{}'::jsonb) ->> 'id'),
  true
);

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select better_supabase.mark_import_running(current_setting('bsb.run1')::uuid);

-- The whole input of one source, as the batches an importer sends. Returns the
-- counts of every batch as one object per entity.
create function pg_temp.erp_input(run uuid) returns jsonb
language plpgsql
as $$
declare
  v_tenant text := '00000000-0000-4000-8000-000000000001';
  v_out jsonb := '{}'::jsonb;
  v_vat uuid;

begin
  v_out := v_out || jsonb_build_object('payment_term', better_supabase.import_upsert_batch(run, 'payment_term',
    '[{"key":"N30","data":{"code":"N30","name":"Net 30","days":30}}]'::jsonb));
  v_out := v_out || jsonb_build_object('tax_code', better_supabase.import_upsert_batch(run, 'tax_code',
    '[{"key":"VAT21","data":{"code":"VAT21","name":"VAT 21%","type":"sales","rateBps":2100,"returnBoxes":["1a"],"validFrom":"2020-01-01"}}]'::jsonb));
  select id into v_vat from better_supabase.tax_codes where tenant_id = v_tenant::uuid and code = 'VAT21';

  v_out := v_out || jsonb_build_object('accounting_account', better_supabase.import_upsert_batch(run, 'accounting_account',
    '[{"key":"1900","data":{"code":"1900","name":"Clearing","type":"asset"}},
      {"key":"4100","data":{"code":"4100","name":"Services","type":"income"}}]'::jsonb));
  v_out := v_out || jsonb_build_object('accounting_journal', better_supabase.import_upsert_batch(run, 'accounting_journal',
    '[{"key":"MEMO","data":{"code":"MEMO","name":"Memorial","type":"general"}}]'::jsonb));
  v_out := v_out || jsonb_build_object('accounting_opening_balance', better_supabase.import_upsert_batch(run, 'accounting_opening_balance',
    '[{"key":"2026-1200","data":{"fiscalYear":2026,"accountCode":"1200","amount":"7000"}},
      {"key":"2026-4000","data":{"fiscalYear":2026,"accountCode":"4000","amount":"-7000"}}]'::jsonb));
  v_out := v_out || jsonb_build_object('accounting_entry', better_supabase.import_upsert_batch(run, 'accounting_entry',
    '[{"key":"2026-01-0001","data":{"journalCode":"MEMO","entryDate":"2026-01-15","lines":[{"accountCode":"1200","debit":"12100"},{"accountCode":"4100","credit":"12100"}]}},
      {"key":"2026-02-0001","data":{"journalCode":"MEMO","entryDate":"2026-02-10","lines":[{"accountCode":"1900","debit":"500"},{"accountCode":"4100","credit":"500"}]}}]'::jsonb));

  v_out := v_out || jsonb_build_object('invoice', better_supabase.import_upsert_batch(run, 'invoice', jsonb_build_array(jsonb_build_object(
    'key', 'inv-1001', 'data', jsonb_build_object(
      'number', 'INV-1001', 'status', 'paid', 'issuedOn', '2025-11-03', 'dueOn', '2025-12-03', 'currency', 'EUR', 'title', 'November',
      'lines', jsonb_build_array(jsonb_build_object('description', 'Consulting', 'quantity', 10, 'unitAmount', 10000, 'taxRateBps', 2100, 'taxCodeId', v_vat)),
      'totals', jsonb_build_object('subtotal', 100000, 'tax', 21000, 'total', 121000),
      'payments', jsonb_build_array(jsonb_build_object('amount', 121000, 'paidAt', '2025-11-20T10:00:00Z')))))));
  v_out := v_out || jsonb_build_object('credit_note', better_supabase.import_upsert_batch(run, 'credit_note',
    '[{"key":"cn-1001","data":{"number":"CN-1001","issuedOn":"2025-12-01","original":"INV-1001","note":"One hour credited",
      "lines":[{"description":"Consulting","quantity":1,"unitAmount":10000,"taxRateBps":2100}]}}]'::jsonb));
  v_out := v_out || jsonb_build_object('open_item', better_supabase.import_upsert_batch(run, 'open_item',
    '[{"key":"open-1002","data":{"number":"INV-1002","issuedOn":"2025-12-15","dueOn":"2026-01-14","currency":"EUR","balance":24200}}]'::jsonb));
  v_out := v_out || jsonb_build_object('quote', better_supabase.import_upsert_batch(run, 'quote',
    '[{"key":"q-77","data":{"number":"Q-77","status":"accepted","title":"Website","currency":"EUR",
      "lines":[{"description":"Design","quantity":1,"unitAmount":50000,"taxRateBps":2100}],
      "totals":{"subtotal":50000,"tax":10500,"total":60500}}}]'::jsonb));
  v_out := v_out || jsonb_build_object('order', better_supabase.import_upsert_batch(run, 'order',
    '[{"key":"ord-5001","data":{"number":"ORD-5001","status":"completed","currency":"EUR","email":"old@example.com",
      "placedAt":"2025-05-01T08:00:00Z","paidAt":"2025-05-01T08:05:00Z","completedAt":"2025-05-03T08:00:00Z",
      "lines":[{"sku":"FREE","title":"Delivery","quantity":1,"unitAmount":"2500"}],
      "totals":{"subtotal":"2500","taxTotal":"0","total":"2500"},
      "payments":[{"amount":"2500","paidAt":"2025-05-01T08:05:00Z"}]}}]'::jsonb));
  return v_out;
end;
$$;

create temporary table first_run (result jsonb) on commit drop;
grant all on first_run to service_role, authenticated;
insert into first_run select pg_temp.erp_input(current_setting('bsb.run1')::uuid);

select is(
  (select (select jsonb_agg(k) from jsonb_object_keys(result) k where (result -> k -> 'errors') <> '[]'::jsonb) from first_run),
  null,
  'the first run has no item errors'
);
select ok(
  (select (result -> 'invoice' ->> 'inserted')::int = 1
      and (result -> 'accounting_entry' ->> 'inserted')::int = 2
      and (result -> 'open_item' ->> 'inserted')::int = 1
      and (result -> 'quote' ->> 'inserted')::int = 1
      and (result -> 'order' ->> 'inserted')::int = 1
   from first_run),
  'the first run inserts every record'
);
select better_supabase.finish_import_run(current_setting('bsb.run1')::uuid);

-- The second run: same source, same input.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;
select set_config(
  'bsb.run2',
  (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'erp-rerun', '{}'::jsonb) ->> 'id'),
  true
);
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select better_supabase.mark_import_running(current_setting('bsb.run2')::uuid);

-- Row counts of every table the import touches, plus the audit log.
create temporary table counts_before as
select
  (select count(*) from better_supabase.payment_terms) as payment_terms,
  (select count(*) from better_supabase.tax_codes) as tax_codes,
  (select count(*) from better_supabase.tax_rates) as tax_rates,
  (select count(*) from better_supabase.accounting_accounts) as accounts,
  (select count(*) from better_supabase.accounting_journals) as journals,
  (select count(*) from better_supabase.accounting_entries) as entries,
  (select count(*) from better_supabase.accounting_entry_lines) as entry_lines,
  (select count(*) from better_supabase.accounting_opening_balances) as openings,
  (select count(*) from better_supabase.invoices) as invoices,
  (select count(*) from better_supabase.invoice_lines) as invoice_lines,
  (select count(*) from better_supabase.invoice_tax_lines) as invoice_tax_lines,
  (select count(*) from better_supabase.quotes) as quotes,
  (select count(*) from better_supabase.orders) as orders,
  (select count(*) from better_supabase.order_lines) as order_lines,
  (select count(*) from better_supabase.ledger_transactions) as ledger_transactions,
  (select count(*) from better_supabase.import_records) as import_records,
  (select count(*) from better_supabase.audit_events) as audit_events,
  (select count(*) from better_supabase.outbox_events) as outbox_events;
grant all on counts_before to service_role, authenticated;

create temporary table second_run (result jsonb) on commit drop;
grant all on second_run to service_role, authenticated;
insert into second_run select pg_temp.erp_input(current_setting('bsb.run2')::uuid);

select is(
  (select (select jsonb_agg(k) from jsonb_object_keys(result) k where (result -> k -> 'errors') <> '[]'::jsonb) from second_run),
  null,
  'the second run has no item errors'
);
select is(
  (select jsonb_agg(k order by k) from second_run, jsonb_object_keys(result) k
   where (result -> k ->> 'inserted')::int <> 0 or (result -> k ->> 'updated')::int <> 0 or (result -> k ->> 'conflicted')::int <> 0),
  null,
  'the second run inserts, updates and conflicts nothing in any entity'
);
select is(
  (select jsonb_agg(k order by k) from second_run, jsonb_object_keys(result) k where (result -> k ->> 'unchanged')::int < 1),
  null,
  'the second run reports every entity as unchanged'
);

select is(
  (select jsonb_build_array(
    (select count(*) from better_supabase.payment_terms) - payment_terms,
    (select count(*) from better_supabase.tax_codes) - tax_codes,
    (select count(*) from better_supabase.tax_rates) - tax_rates,
    (select count(*) from better_supabase.accounting_accounts) - accounts,
    (select count(*) from better_supabase.accounting_journals) - journals,
    (select count(*) from better_supabase.accounting_entries) - entries,
    (select count(*) from better_supabase.accounting_entry_lines) - entry_lines,
    (select count(*) from better_supabase.accounting_opening_balances) - openings,
    (select count(*) from better_supabase.invoices) - invoices,
    (select count(*) from better_supabase.invoice_lines) - invoice_lines,
    (select count(*) from better_supabase.invoice_tax_lines) - invoice_tax_lines,
    (select count(*) from better_supabase.quotes) - quotes,
    (select count(*) from better_supabase.orders) - orders,
    (select count(*) from better_supabase.order_lines) - order_lines,
    (select count(*) from better_supabase.ledger_transactions) - ledger_transactions,
    (select count(*) from better_supabase.import_records) - import_records) from counts_before),
  '[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]'::jsonb,
  'the second run writes no row in any table it touches'
);
select is(
  ((select count(*) from better_supabase.outbox_events) - (select outbox_events from counts_before))::int,
  0,
  'the second run emits no event'
);

select better_supabase.finish_import_run(current_setting('bsb.run2')::uuid);

select is(
  ((select count(*) from better_supabase.audit_events) - (select audit_events from counts_before))::int,
  0,
  'the second run writes zero audit rows, the summary entries included'
);
select is(
  (select count(*)::int from better_supabase.audit_events where correlation_id = 'import:' || current_setting('bsb.run2')),
  0,
  'no audit row carries the second run''s correlation id'
);
select ok(
  (select count(*) from better_supabase.audit_events where correlation_id = 'import:' || current_setting('bsb.run1')) > 0,
  'the first run did write its audit summary, so the zero above is a real comparison'
);

select * from finish();
rollback;
