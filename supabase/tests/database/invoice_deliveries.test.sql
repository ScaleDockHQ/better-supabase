-- The e-invoices an invoice was sent as (ADR 0174). Ann (…a1) owns Acme (…0001),
-- Carl (…a3) owns Globex (…0002). A delivery keeps the channel's reference once
-- per invoice and channel, and only an issued invoice has one. Run with
-- `supabase test db`.
begin;
select plan(9);

create temp table ids (name text primary key, id uuid) on commit drop;
grant all on ids to authenticated;

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

insert into ids values ('draft', (better_supabase.create_invoice('00000000-0000-4000-8000-000000000001',
  '{"title": "Draft", "currency": "EUR"}',
  '[{"description": "Fence", "quantity": 1, "unitAmount": 10000, "taxRateBps": 2100}]') ->> 'id')::uuid);
insert into ids values ('sent', (better_supabase.create_invoice('00000000-0000-4000-8000-000000000001',
  '{"title": "Sent", "currency": "EUR"}',
  '[{"description": "Fence", "quantity": 1, "unitAmount": 10000, "taxRateBps": 2100}]') ->> 'id')::uuid);
select better_supabase.issue_invoice((select id from ids where name = 'sent'), current_date);

select throws_ok(
  format($$select better_supabase.record_invoice_delivery(%L, 'peppol', 'ubl', 'ref-1', 'INV-1.xml')$$, (select id from ids where name = 'draft')),
  '55000',
  'a draft or void invoice can''t be sent as an e-invoice',
  'a draft invoice has no delivery'
);

select is(
  (select x ->> 'externalRef' from (select better_supabase.record_invoice_delivery((select id from ids where name = 'sent'), 'peppol', 'ubl', 'ref-1', 'INV-1.xml') as x) s),
  'ref-1',
  'an issued invoice keeps the channel''s reference'
);
select is(
  (select x ->> 'filename' from (select better_supabase.record_invoice_delivery((select id from ids where name = 'sent'), 'peppol', 'ubl', 'ref-1', 'other.xml') as x) s),
  'INV-1.xml',
  'the same channel and reference return the first row'
);
select better_supabase.record_invoice_delivery((select id from ids where name = 'sent'), 'peppol', 'ubl', 'ref-2');
select is(
  (select jsonb_array_length(better_supabase.list_invoice_deliveries((select id from ids where name = 'sent')))),
  2,
  'a second reference is a second delivery'
);
select is(
  (select better_supabase.list_invoice_deliveries((select id from ids where name = 'sent')) -> 0 ->> 'externalRef'),
  'ref-2',
  'deliveries list newest first'
);
select throws_ok(
  format($$select better_supabase.record_invoice_delivery(%L, 'peppol', 'ubl', '   ')$$, (select id from ids where name = 'sent')),
  '22023',
  'a delivery has a channel, a format and the channel''s reference',
  'a blank reference is refused'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;
select throws_ok(
  format($$select better_supabase.record_invoice_delivery(%L, 'peppol', 'ubl', 'ref-3')$$, (select id from ids where name = 'sent')),
  'P0002',
  'no such invoice you can send',
  'another organization cannot record a delivery'
);
select is(
  (select count(*) from better_supabase.invoice_deliveries),
  0::bigint,
  'another organization reads none'
);

reset role;
select is(
  (select count(*) from pg_catalog.pg_tables
   where schemaname = 'better_supabase' and tablename = 'invoice_deliveries' and rowsecurity),
  1::bigint,
  'the table has row level security'
);

select * from finish();
rollback;
