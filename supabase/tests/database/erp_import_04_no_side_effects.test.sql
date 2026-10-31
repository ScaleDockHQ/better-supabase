-- ERP import acceptance 4 (ADR 0141): an import runs no workflow, webhook,
-- notification or stock side effect unless the config lists the event. The
-- run brings in a paid invoice, a quote, a completed order that sells a stocked
-- variant and a stock count. Outbox events, notification events, webhook
-- deliveries, workflow runs, ledger transactions and stock levels stay as they
-- were. The fixture lists `customer.imported` (tag) and `customer.synced`
-- (emit), which an import still raises. Run with `supabase test db`.
begin;
select plan(9);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('t.p', better_supabase.save_product('00000000-0000-4000-8000-000000000001', null, 'Pump', 'pump', null, 'physical', null) ->> 'id', true);
select set_config('t.v', better_supabase.save_variant(current_setting('t.p')::uuid, null, 'PUMP-1', null, 'Pump', null, 500, true, false, null) ->> 'id', true);
select set_config('t.loc', better_supabase.save_location('00000000-0000-4000-8000-000000000001', null, 'WH1', 'Warehouse', null, null) ->> 'id', true);
select better_supabase.adjust_stock(current_setting('t.v')::uuid, current_setting('t.loc')::uuid, 10, 'receipt', 'in');

select set_config(
  'bsb.run',
  (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'erp-quiet', '{}'::jsonb) ->> 'id'),
  true
);

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select better_supabase.mark_import_running(current_setting('bsb.run')::uuid);

create temporary table before_import as
select
  (select count(*) from better_supabase.outbox_events) as outbox,
  (select count(*) from better_supabase.notification_events) as notifications,
  (select count(*) from better_supabase.webhook_deliveries) as deliveries,
  (select count(*) from better_supabase.workflow_runs) as workflows,
  (select count(*) from better_supabase.ledger_transactions where kind like 'stock.%') as ledger,
  (select coalesce(sum(on_hand), 0) from better_supabase.stock_levels) as on_hand,
  (select coalesce(sum(reserved), 0) from better_supabase.stock_levels) as reserved;
grant select on before_import to authenticated, service_role;

create temporary table batches (result jsonb) on commit drop;
grant all on batches to authenticated, service_role;

insert into batches values (better_supabase.import_upsert_batch(current_setting('bsb.run')::uuid, 'invoice', jsonb_build_array(jsonb_build_object(
  'key', 'inv-1', 'data', jsonb_build_object(
    'number', 'INV-1', 'status', 'paid', 'issuedOn', '2025-11-03', 'dueOn', '2025-12-03', 'currency', 'EUR',
    'lines', jsonb_build_array(jsonb_build_object('description', 'Consulting', 'quantity', 1, 'unitAmount', 10000, 'taxRateBps', 2100)),
    'payments', jsonb_build_array(jsonb_build_object('amount', 12100, 'paidAt', '2025-11-20T10:00:00Z')))))));
insert into batches values (better_supabase.import_upsert_batch(current_setting('bsb.run')::uuid, 'quote',
  '[{"key":"q-1","data":{"number":"Q-1","status":"accepted","title":"Website","currency":"EUR",
    "lines":[{"description":"Design","quantity":1,"unitAmount":50000,"taxRateBps":2100}]}}]'::jsonb));
insert into batches values (better_supabase.import_upsert_batch(current_setting('bsb.run')::uuid, 'order',
  '[{"key":"ord-1","data":{"number":"ORD-1","status":"completed","currency":"EUR","email":"old@example.com",
    "placedAt":"2025-05-01T08:00:00Z","paidAt":"2025-05-01T08:05:00Z","completedAt":"2025-05-03T08:00:00Z",
    "lines":[{"sku":"PUMP-1","title":"Pump","quantity":3,"unitAmount":"500"}],
    "totals":{"subtotal":"1500","taxTotal":"0","total":"1500"},
    "payments":[{"amount":"1500","paidAt":"2025-05-01T08:05:00Z"}]}}]'::jsonb));
insert into batches values (better_supabase.import_upsert_batch(current_setting('bsb.run')::uuid, 'stock_count',
  '[{"key":"count-1","data":{"location":"WH1","note":"Year end","lines":[{"sku":"PUMP-1","counted":7}]}}]'::jsonb));

select is(
  (select jsonb_agg(r -> 'errors') filter (where r -> 'errors' <> '[]'::jsonb) from batches r(r) ) , null,
  'every batch imported without item errors'
);
select is(
  (select sum((result ->> 'inserted')::int)::int from batches),
  4,
  'the invoice, quote, order and stock count are inserted'
);
select is(
  (select count(*)::int from better_supabase.outbox_events) - (select outbox from before_import)::int,
  0,
  'no outbox event is written for the imported documents'
);
select is(
  (select count(*)::int from better_supabase.notification_events) - (select notifications from before_import)::int,
  0,
  'no notification event is written'
);
select is(
  (select count(*)::int from better_supabase.webhook_deliveries) - (select deliveries from before_import)::int,
  0,
  'no webhook delivery is queued'
);
select is(
  (select count(*)::int from better_supabase.workflow_runs) - (select workflows from before_import)::int,
  0,
  'no workflow run starts'
);
select is(
  (select jsonb_build_array(
     (select count(*) from better_supabase.ledger_transactions where kind like 'stock.%') - (select ledger from before_import),
     (select coalesce(sum(on_hand), 0) from better_supabase.stock_levels) - (select on_hand from before_import),
     (select coalesce(sum(reserved), 0) from better_supabase.stock_levels) - (select reserved from before_import))),
  '[0, 0, 0]'::jsonb,
  'the completed order moves no stock: no stock ledger transaction, on-hand or reservation changes'
);

-- A listed event still goes out; an unlisted one stays quiet.
select better_supabase.begin_import_session(current_setting('bsb.run')::uuid);
select isnt(
  better_supabase.emit_event('customer.synced', '{"a":1}'::jsonb), null,
  'an event the config lists as emit is raised during an import'
);
select is(
  better_supabase.emit_event('invoice.issued', '{"a":1}'::jsonb), null,
  'an event the config does not list is skipped during an import'
);

select * from finish();
rollback;
