-- Quote and order variants and collective invoicing on the fixture's access
-- contract. The admin (…00a1) of Acme (…0001) keeps two variants of a quote and
-- selects one, which forwards to an order and unselects its sibling. Delivered
-- orders then become one invoice per billing party and currency, in part by
-- quantity, once: a repeat call writes nothing. A voided invoice releases its
-- sources. Globex (…00b1) sees nothing. Run with `supabase test db`.
begin;
select plan(28);

insert into better_supabase.time_entries (id, tenant_id, user_id, subject_type, subject_id, started_at, ended_at, billable, rate, rate_currency, note) values
  ('00000000-0000-4000-8000-00000000d101', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a1', 'customer', '00000000-0000-4000-8000-00000000a001',
    '2026-10-05 09:00+00', '2026-10-05 11:00+00', true, 15000, 'EUR', 'Workshop');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

-- Quote variants.
select set_config('t.qa', better_supabase.create_quote(
  '00000000-0000-4000-8000-000000000001',
  '{"title": "Kitchen", "currency": "EUR"}',
  '[{"description": "Standard cabinets", "quantity": 1, "unitAmount": "10000"}]'
) ->> 'id', true);
select set_config('t.qb', better_supabase.create_quote_variant(
  current_setting('t.qa')::uuid, 'Premium'
) ->> 'id', true);
select is(
  (select jsonb_agg(v ->> 'variantLabel' order by v ->> 'variantLabel')
   from jsonb_array_elements(better_supabase.list_quote_variants(current_setting('t.qa')::uuid)) v),
  '["Original", "Premium"]'::jsonb,
  'a variant copies the quote and the first quote is labelled Original'
);
select is(
  (select jsonb_agg(v ->> 'isSelected' order by v ->> 'variantLabel')
   from jsonb_array_elements(better_supabase.list_quote_variants(current_setting('t.qa')::uuid)) v),
  '["false", "false"]'::jsonb,
  'no variant is selected until one is chosen'
);
select throws_ok(
  format($$select better_supabase.create_quote_variant(%L, 'Premium')$$, current_setting('t.qa')),
  '23505',
  'another variant of this quote has that label',
  'a label is used once per group'
);
select is(
  (select count(*)::int from better_supabase.quote_lines l where l.parent_id = current_setting('t.qb')::uuid),
  1,
  'the variant has the lines of the original'
);
select better_supabase.set_quote_lines(current_setting('t.qb')::uuid,
  '[{"description": "Premium cabinets", "quantity": 1, "unitAmount": "16000"}]');
select better_supabase.send_quote(current_setting('t.qa')::uuid);
select better_supabase.send_quote(current_setting('t.qb')::uuid);
select better_supabase.decide_quote(current_setting('t.qa')::uuid, 'accepted', null, null, null);
select better_supabase.decide_quote(current_setting('t.qb')::uuid, 'accepted', null, null, null);
select throws_ok(
  format($$select better_supabase.order_from_quote(%L)$$, current_setting('t.qb')),
  '55000',
  'this quote is one of several variants; select a variant first',
  'a variant that is not selected does not order'
);
select set_config('t.sel', better_supabase.select_quote_variant(
  current_setting('t.qb')::uuid, '{"forward": "order"}'
)::text, true);
select is(
  (select jsonb_build_array(s -> 'order' ->> 'status', s -> 'order' ->> 'total') from (select current_setting('t.sel')::jsonb s) x),
  '["confirmed", "16000"]'::jsonb,
  'selecting a variant orders it at its own total'
);
select is(
  (select jsonb_agg(v ->> 'isSelected' order by v ->> 'variantLabel')
   from jsonb_array_elements(better_supabase.list_quote_variants(current_setting('t.qa')::uuid)) v),
  '["false", "true"]'::jsonb,
  'the siblings are no longer selected'
);
select throws_ok(
  format($$select better_supabase.order_from_quote(%L)$$, current_setting('t.qa')),
  '55000',
  'this quote is one of several variants; select a variant first',
  'the sibling of the selected variant does not order'
);

-- Order variants.
create temporary table ids (name text primary key, id uuid) on commit drop;
grant all on ids to authenticated, service_role;
insert into ids values
  ('buyer', (better_supabase.save_company('00000000-0000-4000-8000-000000000001', null, '{"name": "Collective buyer"}') ->> 'id')::uuid),
  ('other', (better_supabase.save_company('00000000-0000-4000-8000-000000000001', null, '{"name": "Another buyer"}') ->> 'id')::uuid);

select set_config('t.product', better_supabase.save_product('00000000-0000-4000-8000-000000000001', null, 'Consulting', 'consulting', null, 'service', null) ->> 'id', true);
select set_config('t.v', better_supabase.save_variant(current_setting('t.product')::uuid, null, 'CONSULT', null, 'Consulting', null, null, false, false, null) ->> 'id', true);

select set_config('t.o1', better_supabase.order_from_lines('00000000-0000-4000-8000-000000000001',
  jsonb_build_array(jsonb_build_object('variantId', current_setting('t.v'), 'quantity', 4, 'unitAmount', '500')),
  jsonb_build_object('currency', 'EUR', 'origin', jsonb_build_object('type', 'phone', 'id', 'c1')))::text, true);
select set_config('t.o2', better_supabase.order_from_lines('00000000-0000-4000-8000-000000000001',
  jsonb_build_array(jsonb_build_object('variantId', current_setting('t.v'), 'quantity', 2, 'unitAmount', '700')),
  jsonb_build_object('currency', 'EUR', 'origin', jsonb_build_object('type', 'phone', 'id', 'c2')))::text, true);
select set_config('t.o3', better_supabase.order_from_lines('00000000-0000-4000-8000-000000000001',
  jsonb_build_array(jsonb_build_object('variantId', current_setting('t.v'), 'quantity', 1, 'unitAmount', '900')),
  jsonb_build_object('currency', 'USD', 'origin', jsonb_build_object('type', 'phone', 'id', 'c3')))::text, true);
select set_config('t.o4', better_supabase.order_from_lines('00000000-0000-4000-8000-000000000001',
  jsonb_build_array(jsonb_build_object('variantId', current_setting('t.v'), 'quantity', 1, 'unitAmount', '300')),
  jsonb_build_object('currency', 'EUR', 'origin', jsonb_build_object('type', 'phone', 'id', 'c4')))::text, true);

select is(
  better_supabase.set_order_variant((current_setting('t.o4')::jsonb ->> 'id')::uuid, (current_setting('t.o2')::jsonb ->> 'id')::uuid, 'Smaller') ->> 'isSelected',
  'false',
  'an order joins the variant group of another order'
);
select throws_ok(
  format($$select better_supabase.set_order_variant(%L, %L, 'x')$$, current_setting('t.o3')::jsonb ->> 'id', current_setting('t.o2')::jsonb ->> 'id'),
  '22023',
  'variants share one currency',
  'variants of an order share one currency'
);
select is(
  (better_supabase.select_order_variant((current_setting('t.o4')::jsonb ->> 'id')::uuid) -> 'order' ->> 'isSelected'),
  'true',
  'an order variant can be selected'
);
select better_supabase.select_order_variant((current_setting('t.o2')::jsonb ->> 'id')::uuid);

-- Collective invoicing.
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
update better_supabase.orders set buyer = jsonb_build_object('type', 'company', 'id', (select id from ids where name = 'buyer'))
  where id in ((current_setting('t.o1')::jsonb ->> 'id')::uuid, (current_setting('t.o2')::jsonb ->> 'id')::uuid, (current_setting('t.o3')::jsonb ->> 'id')::uuid, (current_setting('t.o4')::jsonb ->> 'id')::uuid);
update better_supabase.order_lines set quantity_fulfilled = quantity
  where order_id in ((current_setting('t.o1')::jsonb ->> 'id')::uuid, (current_setting('t.o2')::jsonb ->> 'id')::uuid, (current_setting('t.o3')::jsonb ->> 'id')::uuid, (current_setting('t.o4')::jsonb ->> 'id')::uuid);
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  (select jsonb_agg(s ->> 'id' order by s ->> 'id') from jsonb_array_elements(better_supabase.sources_ready_to_invoice(
    '00000000-0000-4000-8000-000000000001', jsonb_build_object('type', 'company', 'id', (select id from ids where name = 'buyer')))) s),
  (select jsonb_agg(x order by x) from unnest(array[current_setting('t.o1')::jsonb ->> 'id', current_setting('t.o2')::jsonb ->> 'id', current_setting('t.o3')::jsonb ->> 'id']) x),
  'the ready sources are the delivered orders, not the variant that was not selected'
);
select is(
  jsonb_array_length(better_supabase.sources_ready_to_invoice(
    '00000000-0000-4000-8000-000000000001', jsonb_build_object('type', 'company', 'id', (select id from ids where name = 'other')))),
  0,
  'another party has nothing ready'
);
select throws_ok(
  format($$select better_supabase.invoice_from_sources('00000000-0000-4000-8000-000000000001', %L, %L)$$,
    jsonb_build_object('type', 'company', 'id', (select id from ids where name = 'other')),
    jsonb_build_array(jsonb_build_object('type', 'order', 'id', current_setting('t.o1')::jsonb ->> 'id'))::text),
  '22023',
  'an order was placed by another buyer than the party',
  'an order of another buyer is not invoiced to the party'
);
select throws_ok(
  format($$select better_supabase.invoice_from_sources('00000000-0000-4000-8000-000000000001', %L, %L)$$,
    jsonb_build_object('type', 'company', 'id', (select id from ids where name = 'buyer')),
    jsonb_build_array(jsonb_build_object('type', 'order', 'id', current_setting('t.o4')::jsonb ->> 'id'))::text),
  '55000',
  'an order is invoiced once it is confirmed or paid and wasn''t invoiced at checkout',
  'the variant that was not selected is not invoiced'
);
select throws_ok(
  format($$select better_supabase.invoice_from_sources('00000000-0000-4000-8000-000000000001', %L, %L)$$,
    jsonb_build_object('type', 'company', 'id', (select id from ids where name = 'buyer')),
    jsonb_build_array(jsonb_build_object('type', 'order', 'id', current_setting('t.o1')::jsonb ->> 'id',
      'lines', jsonb_build_array(jsonb_build_object('id', (select id from better_supabase.order_lines where order_id = (current_setting('t.o1')::jsonb ->> 'id')::uuid), 'quantity', 5))))::text),
  '22023',
  'a line is invoiced for more than is delivered and not yet invoiced',
  'a partial quantity can not exceed what is delivered'
);

-- Part of the first order and the whole second order, plus a USD order: two invoices.
select set_config('t.r1', better_supabase.invoice_from_sources('00000000-0000-4000-8000-000000000001',
  jsonb_build_object('type', 'company', 'id', (select id from ids where name = 'buyer')),
  jsonb_build_array(
    jsonb_build_object('type', 'order', 'id', current_setting('t.o1')::jsonb ->> 'id',
      'lines', jsonb_build_array(jsonb_build_object('id', (select id from better_supabase.order_lines where order_id = (current_setting('t.o1')::jsonb ->> 'id')::uuid), 'quantity', 1))),
    jsonb_build_object('type', 'order', 'id', current_setting('t.o2')::jsonb ->> 'id'),
    jsonb_build_object('type', 'order', 'id', current_setting('t.o3')::jsonb ->> 'id')),
  '{"title": "Delivered orders"}')::text, true);
select is(
  (select jsonb_agg(i ->> 'currency' order by i ->> 'currency') from jsonb_array_elements(current_setting('t.r1')::jsonb -> 'invoices') i),
  '["EUR", "USD"]'::jsonb,
  'the sources split into one invoice per currency'
);
select is(
  (select jsonb_agg(i ->> 'total' order by i ->> 'currency') from jsonb_array_elements(current_setting('t.r1')::jsonb -> 'invoices') i),
  '["1900", "900"]'::jsonb,
  'the euro invoice bills one of four hours and the whole second order'
);
select is(
  (select sum(i.total)::text from better_supabase.invoices i
    where i.id in (select (x ->> 'id')::uuid from jsonb_array_elements(current_setting('t.r1')::jsonb -> 'invoices') x)),
  '2800',
  'the totals of the invoices are the sum of what they bill'
);
select is(
  (select count(*)::int from better_supabase.invoice_line_sources s
    where s.invoice_id in (select (x ->> 'id')::uuid from jsonb_array_elements(current_setting('t.r1')::jsonb -> 'invoices') x)),
  3,
  'each invoice line keeps its source'
);

select is(
  (select jsonb_array_length(better_supabase.invoice_from_sources('00000000-0000-4000-8000-000000000001',
    jsonb_build_object('type', 'company', 'id', (select id from ids where name = 'buyer')),
    jsonb_build_array(jsonb_build_object('type', 'order', 'id', current_setting('t.o2')::jsonb ->> 'id'),
      jsonb_build_object('type', 'order', 'id', current_setting('t.o3')::jsonb ->> 'id'))) -> 'invoices')),
  0,
  'invoicing the same sources again writes nothing'
);

-- The rest of the first order, three of four hours.
select set_config('t.r2', better_supabase.invoice_from_sources('00000000-0000-4000-8000-000000000001',
  jsonb_build_object('type', 'company', 'id', (select id from ids where name = 'buyer')),
  jsonb_build_array(jsonb_build_object('type', 'order', 'id', current_setting('t.o1')::jsonb ->> 'id')))::text, true);
select is(
  current_setting('t.r2')::jsonb -> 'invoices' -> 0 ->> 'total',
  '1500',
  'the next call invoices the quantity left of a partly invoiced order'
);
select is(
  (select count(*)::int from jsonb_array_elements(better_supabase.sources_ready_to_invoice('00000000-0000-4000-8000-000000000001', null)) s
    where s ->> 'id' in (current_setting('t.o1')::jsonb ->> 'id', current_setting('t.o2')::jsonb ->> 'id', current_setting('t.o3')::jsonb ->> 'id')),
  0,
  'nothing is ready once every delivered line is invoiced'
);

-- A voided invoice releases its sources.
select better_supabase.issue_invoice((current_setting('t.r2')::jsonb -> 'invoices' -> 0 ->> 'id')::uuid, current_date);
select better_supabase.void_invoice((current_setting('t.r2')::jsonb -> 'invoices' -> 0 ->> 'id')::uuid, 'wrong party');
select is(
  (select s ->> 'quantity' from jsonb_array_elements(better_supabase.sources_ready_to_invoice('00000000-0000-4000-8000-000000000001', null)) s
    where s ->> 'id' = current_setting('t.o1')::jsonb ->> 'id'),
  '3.0000',
  'voiding an invoice makes its quantity ready again'
);

-- Billable time joins the same call and is claimed once.
select is(
  (select s ->> 'quantity' from jsonb_array_elements(better_supabase.sources_ready_to_invoice('00000000-0000-4000-8000-000000000001',
    '{"type": "customer", "id": "00000000-0000-4000-8000-00000000a001"}')) s where s ->> 'type' = 'time'),
  '2.0000',
  'unbilled time of the party is ready to invoice'
);
select set_config('t.r3', better_supabase.invoice_from_sources('00000000-0000-4000-8000-000000000001',
  '{"type": "customer", "id": "00000000-0000-4000-8000-00000000a001"}',
  '[{"type": "time", "scope": {"subject": {"type": "customer", "id": "00000000-0000-4000-8000-00000000a001"}}}]')::text, true);
select is(
  current_setting('t.r3')::jsonb -> 'invoices' -> 0 ->> 'total',
  '30000',
  'two hours at the entry rate become one invoice line'
);
select is(
  (select count(*)::int from better_supabase.invoice_line_sources s
    where s.source = 'time' and s.invoice_id = (current_setting('t.r3')::jsonb -> 'invoices' -> 0 ->> 'id')::uuid)
  + (select count(*)::int from better_supabase.time_invoice_entries b where b.entry_id = '00000000-0000-4000-8000-00000000d101'),
  2,
  'the entry is marked billed and the line keeps its source'
);

-- Another organization sees nothing.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000b1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
select throws_ok(
  $$select better_supabase.sources_ready_to_invoice('00000000-0000-4000-8000-000000000001')$$,
  'not allowed to read invoices',
  'another organization cannot list the sources'
);

select * from finish();
rollback;
