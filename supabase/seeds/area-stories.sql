-- The area stories: the story data of the ERP, manufacturing and quality and
-- commerce areas that the page seeds cannot hold because they call block functions.
-- It runs last: it books against the chart and the open year that finance-demo.sql
-- creates, and gives each ledger role an account so completed work posts.
select set_config('request.jwt.claims', '{"role": "service_role", "sub": "00000000-0000-4000-8000-0000000000a1"}', false);

do $roles$
declare
  t constant uuid := '00000000-0000-4000-8000-000000000001';
  spec record;
  acc uuid;
begin
  insert into better_supabase.accounting_settings (tenant_id, functional_currency)
  values (t, 'EUR')
  on conflict do nothing;

  insert into better_supabase.accounting_journals (tenant_id, code, name, type, currency)
  values (t, 'SAL', 'Sales journal', 'sales', 'EUR'),
         (t, 'PUR', 'Purchase journal', 'purchase', 'EUR'),
         (t, 'BNK', 'Bank journal', 'bank', 'EUR'),
         (t, 'CSH', 'Cash journal', 'cash', 'EUR')
  on conflict do nothing;

  for spec in
    select * from (values
      ('receivable', '1200', 'Accounts receivable', 'asset', 'debit'),
      ('inventory', '1300', 'Inventory', 'asset', 'debit'),
      ('work_in_progress', '1350', 'Work in progress', 'asset', 'debit'),
      ('tax_receivable', '1400', 'VAT receivable', 'asset', 'debit'),
      ('payable', '2000', 'Accounts payable', 'liability', 'credit'),
      ('tax_payable', '2200', 'VAT payable', 'liability', 'credit'),
      ('deferred_revenue', '2300', 'Deferred revenue', 'liability', 'credit'),
      ('cogs', '7000', 'Cost of goods sold', 'expense', 'debit'),
      ('expense', '4000', 'Operating expenses', 'expense', 'debit'),
      ('suspense', '9999', 'Suspense', 'asset', 'debit')
    ) as x(role, code, name, type, side)
  loop
    insert into better_supabase.accounting_accounts (tenant_id, code, name, type, normal_side, currency)
    values (t, spec.code, spec.name, spec.type, spec.side, 'EUR')
    on conflict do nothing
    returning id into acc;

    if acc is null then
      select id into acc from better_supabase.accounting_accounts where tenant_id = t and code = spec.code;
    end if;

    perform better_supabase.set_accounting_account_role(t, spec.role, acc);
  end loop;

  perform better_supabase.set_accounting_account_role(t, 'bank',
    (select id from better_supabase.accounting_accounts where tenant_id = t and code = '1100'));
  perform better_supabase.set_accounting_account_role(t, 'revenue',
    (select id from better_supabase.accounting_accounts where tenant_id = t and code = '8000'));
end
$roles$;

-- Manufacturing and quality: an assembly bench, the active bill
-- of materials of the burr grinder, a draft, a released and a completed production
-- order, and two inspections: one planned, one running with a finding that
-- already has its case and one that still needs it.
do $seed$
declare
  t constant uuid := '00000000-0000-4000-8000-000000000001';
  grinder constant uuid := '00000000-0000-4000-8000-0000000b1004';
  filter constant uuid := '00000000-0000-4000-8000-0000000b1003';
  bench jsonb;
  bom jsonb;
  mo jsonb;
  insp jsonb;
  found jsonb;
begin
  bench := better_supabase.save_work_center(t,
    jsonb_build_object('name', 'Assembly bench', 'hoursPerDay', 8, 'costRate', '4500', 'currency', 'EUR'), null);

  perform better_supabase.adjust_stock(filter, '00000000-0000-4000-8000-0000000b2001', 20, 'receipt', 'Filters for the grinder build', null);

  bom := better_supabase.save_bom(t, grinder,
    jsonb_build_object('quantity', 1, 'note', 'Grinder with the steel filter in the box',
      'components', jsonb_build_array(
        jsonb_build_object('variantId', filter, 'quantity', 1, 'scrapBps', 0, 'operation', null)),
      'operations', jsonb_build_array(
        jsonb_build_object('sequence', 10, 'workCenterId', bench ->> 'id', 'title', 'Assemble and calibrate',
          'setupMinutes', 10, 'runMinutesPerUnit', 25))),
    null);
  perform better_supabase.activate_bom((bom ->> 'id')::uuid);

  perform better_supabase.create_production_order(t,
    jsonb_build_object('variantId', grinder, 'quantity', 2, 'dueOn', (current_date + 10)::text, 'note', 'Restock for the spring launch'));

  mo := better_supabase.create_production_order(t,
    jsonb_build_object('variantId', grinder, 'quantity', 4, 'dueOn', (current_date + 3)::text, 'note', 'Released to the bench'));
  perform better_supabase.release_production_order((mo ->> 'id')::uuid, false);

  mo := better_supabase.create_production_order(t,
    jsonb_build_object('variantId', grinder, 'quantity', 3, 'dueOn', current_date::text, 'note', 'First batch'));
  perform better_supabase.release_production_order((mo ->> 'id')::uuid, false);
  perform better_supabase.complete_production_order((mo ->> 'id')::uuid, 3, 0, null);

  insp := better_supabase.schedule_inspection(t,
    jsonb_build_object('kind', 'supplier_audit', 'title', 'Supplier audit, Acme Studio',
      'plannedStart', (current_date + 14)::text, 'plannedEnd', (current_date + 14)::text));

  insp := better_supabase.schedule_inspection(t,
    jsonb_build_object('kind', 'internal_audit', 'title', 'Assembly line audit',
      'plannedStart', current_date::text, 'plannedEnd', current_date::text));
  perform better_supabase.start_inspection((insp ->> 'id')::uuid);

  found := better_supabase.add_inspection_finding((insp ->> 'id')::uuid, 'major_nonconformity',
    'Calibration records missing for the torque tool', 'The tool was used after its due date.', 'ISO 9001 7.1.5', null, null);
  perform better_supabase.raise_inspection_finding_case((found ->> 'id')::uuid, 'finding', null);

  perform better_supabase.add_inspection_finding((insp ->> 'id')::uuid, 'minor_nonconformity',
    'Work instruction revision not on the bench', null, 'ISO 9001 7.5.3', null, null);
  perform better_supabase.add_inspection_finding((insp ->> 'id')::uuid, 'positive',
    'Clean and orderly work area', null, null, null, null);
end
$seed$;

select set_config('request.jwt.claims', '', false);

-- Order to cash and procure to pay: two supplier bills that fall due soon, so the
-- "Pay due bills" batch on /finance/payables has something to pay.
select set_config('request.jwt.claims', '{"role": "service_role", "sub": "00000000-0000-4000-8000-0000000000a1"}', false);

do $bills$
declare
  t constant uuid := '00000000-0000-4000-8000-000000000001';
  bill jsonb;
  spec record;
begin
  for spec in
    select * from (values
      ('00000000-0000-4000-8000-0000000c0003', 'Hooli hosting, November', 'HOOLI-2611', 480000),
      ('00000000-0000-4000-8000-0000000c0002', 'Packaging film, pallet wrap', 'PF-88121', 215000)
    ) as x(company, title, reference, amount)
  loop
    bill := better_supabase.create_invoice(t,
      jsonb_build_object('title', spec.title, 'direction', 'purchase', 'currency', 'EUR',
        'company', jsonb_build_object('type', 'company', 'id', spec.company), 'supplierReference', spec.reference, 'termsDays', 7),
      jsonb_build_array(jsonb_build_object('description', spec.title, 'quantity', 1, 'unitAmount', spec.amount::text, 'taxRateBps', 2100)));
    perform better_supabase.issue_invoice((bill ->> 'id')::uuid, null, null, null);
  end loop;
end
$bills$;

select set_config('request.jwt.claims', '', false);

-- Commerce: a collection of the coffee products, shown on /shop/collections.
select set_config('request.jwt.claims', '{"role": "service_role", "sub": "00000000-0000-4000-8000-0000000000a1"}', false);

do $shop$
declare
  t constant uuid := '00000000-0000-4000-8000-000000000001';
  coll jsonb;
  prod uuid;
begin
  coll := better_supabase.save_collection(t, null, 'Brew at home', 'brew-at-home', 'manual', null);

  foreach prod in array array[
    '00000000-0000-4000-8000-0000000b0001'::uuid,
    '00000000-0000-4000-8000-0000000b0002'::uuid,
    '00000000-0000-4000-8000-0000000b0003'::uuid,
    '00000000-0000-4000-8000-0000000b0004'::uuid]
  loop
    perform better_supabase.add_to_collection((coll ->> 'id')::uuid, prod, null);
  end loop;
end
$shop$;

-- Content: a held board meeting with its agenda and decisions, so /meetings/[id]
-- has a seeded row to open.
insert into better_supabase.meetings (id, tenant_id, kind, title, location, starts_at, ends_at, status, held_at, summary, created_by) values
  ('00000000-0000-4000-8000-0000005e0001', '00000000-0000-4000-8000-000000000001', 'board', 'Q3 board meeting', 'Boardroom',
   now() - interval '7 days', now() - interval '7 days' + interval '2 hours', 'held', now() - interval '7 days',
   'The board approved the Q3 budget and asked for a hiring plan.', '00000000-0000-4000-8000-0000000000a1'),
  ('00000000-0000-4000-8000-0000005e0002', '00000000-0000-4000-8000-000000000001', 'meeting', 'Weekly operations sync', null,
   now() + interval '2 days', now() + interval '2 days' + interval '1 hour', 'planned', null, null, '00000000-0000-4000-8000-0000000000a1')
on conflict (id) do nothing;

insert into better_supabase.meeting_agenda_items (id, tenant_id, meeting_id, ordinal, title, status, outcome) values
  ('00000000-0000-4000-8000-0000005e0101', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000005e0001', 1, 'Q3 budget', 'covered', 'Approved'),
  ('00000000-0000-4000-8000-0000005e0102', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000005e0001', 2, 'Hiring plan', 'covered', 'Draft by next meeting'),
  ('00000000-0000-4000-8000-0000005e0103', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000005e0002', 1, 'Open incidents', 'open', null)
on conflict (id) do nothing;

insert into better_supabase.meeting_decisions (id, tenant_id, meeting_id, agenda_item_id, title, status, decided_by, decided_at) values
  ('00000000-0000-4000-8000-0000005e0201', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000005e0001',
   '00000000-0000-4000-8000-0000005e0101', 'Approve the Q3 budget', 'passed', '00000000-0000-4000-8000-0000000000a1', now() - interval '7 days')
on conflict (id) do nothing;

select set_config('request.jwt.claims', '', false);
