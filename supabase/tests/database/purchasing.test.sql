-- Purchasing on the fixture (ADR 0147). The Acme member (…a2), given the
-- purchase keys but not the override keys, requests stock and writes a bill;
-- the Acme owner (…a1) approves the requisition, receives part of the order,
-- pays the bill that fails its match and issues an invoice over a credit
-- limit. A blocked supplier gets no purchase order, and the Globex owner
-- (…a3) sees none of it. Run with `supabase test db`.
begin;
select plan(15);

select has_table('better_supabase', 'purchase_requisitions', 'requisitions are a table');
select has_table('better_supabase', 'inventory_receipts', 'receipts are a table');
select col_default_is('better_supabase', 'invoices', 'direction', 'sales'::text, 'an invoice is a sales invoice by default');

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p on p.key in ('inventory.purchase', 'invoices.purchase', 'invoices.write')
where r.scope = 'tenant' and r.key = 'member'
on conflict do nothing;

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('t.product', better_supabase.save_product('00000000-0000-4000-8000-000000000001', null, 'Bolts', 'bolts-purchasing', null, 'physical', null) ->> 'id', true);
select set_config('t.v', better_supabase.save_variant(current_setting('t.product')::uuid, null, 'BOLT-PUR', null, 'Bolts', null, null, true, false, null) ->> 'id', true);
select set_config('t.l', better_supabase.save_location('00000000-0000-4000-8000-000000000001', null, 'PUR', 'Purchasing dock', null, null) ->> 'id', true);
select set_config('t.supplier', better_supabase.save_company('00000000-0000-4000-8000-000000000001', null, '{"name": "Purchasing supplier"}') ->> 'id', true);
select set_config('t.customer', better_supabase.save_company('00000000-0000-4000-8000-000000000001', null,
  '{"name": "Purchasing customer", "creditLimit": "1000", "creditCurrency": "EUR"}') ->> 'id', true);
select better_supabase.set_supplier_status(current_setting('t.supplier')::uuid, 'blocked', 'Failed the audit');

select throws_ok(
  format($$select better_supabase.save_purchase_order('00000000-0000-4000-8000-000000000001', null, %L, 'company', %L, 'EUR', null, %L, null)$$,
    current_setting('t.l'), current_setting('t.supplier'), jsonb_build_array(jsonb_build_object('variantId', current_setting('t.v'), 'quantity', 5))),
  '55000',
  'the supplier is blocked and can''t get a purchase order',
  'a blocked supplier gets no purchase order'
);
select better_supabase.set_supplier_status(current_setting('t.supplier')::uuid, 'approved', 'Passed the audit');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);

select set_config('t.req', better_supabase.request_purchase('00000000-0000-4000-8000-000000000001', current_setting('t.l')::uuid,
  jsonb_build_array(jsonb_build_object('variantId', current_setting('t.v'), 'quantity', 5, 'unitCost', '200')),
  'company', current_setting('t.supplier'), 'EUR', 'Restock')::text, true);
select is(
  (select jsonb_build_array(r ->> 'status', r ? 'approvalId') from (select current_setting('t.req')::jsonb r) x),
  '["pending", true]'::jsonb,
  'a requisition starts pending with an approval request'
);
select throws_ok(
  format($$select better_supabase.decide_purchase_requisition(%L, true)$$, current_setting('t.req')::jsonb ->> 'id'),
  '55000',
  'this requisition is decided through its approval request',
  'a requisition with an approval request is decided there'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);

select better_supabase.decide_approval((current_setting('t.req')::jsonb ->> 'approvalId')::uuid, 'approved');
select is(
  (select status from better_supabase.purchase_requisitions where id = (current_setting('t.req')::jsonb ->> 'id')::uuid),
  'approved',
  'approving the request approves the requisition'
);

select set_config('t.po', better_supabase.purchase_order_from_requisitions(array[(current_setting('t.req')::jsonb ->> 'id')::uuid]) ->> 'id', true);
select better_supabase.place_purchase_order(current_setting('t.po')::uuid);
select set_config('t.receipt', better_supabase.receive_purchase_order(current_setting('t.po')::uuid,
  (select jsonb_agg(jsonb_build_object('lineId', x.id, 'quantity', 3)) from better_supabase.purchase_order_lines x where x.purchase_order_id = current_setting('t.po')::uuid)
) ->> 'receiptId', true);
select is(
  (select count(*) from better_supabase.inventory_receipt_lines where receipt_id = current_setting('t.receipt')::uuid),
  1::bigint,
  'receiving writes a receipt with its line'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);

select set_config('t.bill', better_supabase.create_invoice('00000000-0000-4000-8000-000000000001',
  jsonb_build_object('direction', 'purchase', 'title', 'Bolts', 'currency', 'EUR', 'company', jsonb_build_object('id', current_setting('t.supplier')),
    'purchaseOrderId', current_setting('t.po'), 'supplierReference', 'S-100'),
  jsonb_build_array(jsonb_build_object('product', jsonb_build_object('type', 'product_variant', 'id', current_setting('t.v')),
    'description', 'Bolts', 'quantity', 5, 'unitAmount', 200))) ->> 'id', true);
select better_supabase.issue_invoice(current_setting('t.bill')::uuid, current_date);

select is(
  better_supabase.purchase_bill_match(current_setting('t.bill')::uuid) ->> 'status',
  'quantity_variance',
  'a bill for 5 against 3 received is a quantity variance'
);
select throws_ok(
  format($$select better_supabase.record_invoice_payment(%L, 1000, 'EUR', now(), 'bank', null)$$, current_setting('t.bill')),
  '55000',
  'the bill doesn''t match its purchase order and receipts; someone with invoices.override_match can pay it',
  'paying an unmatched bill needs invoices.override_match'
);

select set_config('t.sale', better_supabase.create_invoice('00000000-0000-4000-8000-000000000001',
  jsonb_build_object('title', 'Big order', 'currency', 'EUR', 'company', jsonb_build_object('id', current_setting('t.customer'))),
  jsonb_build_array(jsonb_build_object('description', 'Bolts', 'quantity', 1, 'unitAmount', 1500))) ->> 'id', true);
select throws_ok(
  format($$select better_supabase.issue_invoice(%L, current_date)$$, current_setting('t.sale')),
  '55000',
  'this invoice takes the customer over their credit limit',
  'an invoice over the credit limit needs orders.override_credit'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);

select lives_ok(
  format($$select better_supabase.record_invoice_payment(%L, 1000, 'EUR', now(), 'bank', null)$$, current_setting('t.bill')),
  'the owner pays the unmatched bill with invoices.override_match'
);
select is(
  better_supabase.issue_invoice(current_setting('t.sale')::uuid, current_date) ->> 'status',
  'issued',
  'the owner issues over the credit limit with orders.override_credit'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);

select is(
  (select count(*) from better_supabase.purchase_requisitions where id = (current_setting('t.req')::jsonb ->> 'id')::uuid),
  0::bigint,
  'another organization does not read the requisition'
);
select is(
  (select count(*) from better_supabase.inventory_receipts where id = current_setting('t.receipt')::uuid),
  0::bigint,
  'another organization does not read the receipt'
);

select * from finish();
rollback;
