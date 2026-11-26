-- The maintained open items match the fold (ADR 1214). The Acme owner (…a1)
-- issues invoices, records a partial party payment that leaves credit, adds a
-- charge, credits an invoice in full and issues one with a future date. After
-- each step open_items_drift is empty; a lost row shows as drift until
-- rebuild_open_items writes it back. Run with `supabase test db`.
begin;
select plan(14);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('t.party', better_supabase.upsert_company('00000000-0000-4000-8000-000000000001', null, '{"name": "Parity customer"}') ->> 'id', true);
select set_config('t.other', better_supabase.upsert_company('00000000-0000-4000-8000-000000000001', null, '{"name": "Parity other"}') ->> 'id', true);

create temporary table t_invoices (n int primary key, id uuid) on commit drop;
grant all on t_invoices to authenticated, service_role;

insert into t_invoices
select n, (better_supabase.create_invoice('00000000-0000-4000-8000-000000000001',
  jsonb_build_object('title', 'Parity ' || n, 'currency', 'EUR', 'termsDays', 10,
    'company', jsonb_build_object('id', current_setting('t.party'))),
  jsonb_build_array(jsonb_build_object('description', 'Service', 'quantity', 1, 'unitAmount', 1000))) ->> 'id')::uuid
from generate_series(1, 5) n;

select better_supabase.issue_invoice(id, current_date - 40) from t_invoices where n <= 4 order by n;

create function pg_temp.drift() returns jsonb language sql stable as $$
  select better_supabase.open_items_drift('00000000-0000-4000-8000-000000000001')
$$;
create function pg_temp.today() returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_array(i ->> 'documentType', coalesce(i ->> 'title', i ->> 'identifier', 'credit'), i ->> 'balance')
    order by i ->> 'documentType', i ->> 'balance'), '[]'::jsonb)
  from jsonb_array_elements(better_supabase.open_items_for_party('00000000-0000-4000-8000-000000000001',
    current_setting('t.party'))) i
$$;

select is(pg_temp.drift(), '[]'::jsonb, 'issued invoices leave no drift');

select better_supabase.record_party_payment('00000000-0000-4000-8000-000000000001', current_setting('t.party'), 1500, 'EUR',
  jsonb_build_array(
    jsonb_build_object('invoiceId', (select id from t_invoices where n = 1), 'amount', (select total from better_supabase.invoices x join t_invoices t using (id) where t.n = 1)),
    jsonb_build_object('invoiceId', (select id from t_invoices where n = 2), 'amount', 300)),
  current_date, 'parity-0001');

select is(pg_temp.drift(), '[]'::jsonb, 'a partial payment with credit leaves no drift');
select is(
  (select count(*)::int from better_supabase.invoice_open_items
   where document_type = 'unallocated_payment' and party_id = current_setting('t.party') and balance < 0),
  1,
  'the unallocated payment has its own stored row'
);
select is(
  (select count(*)::int from jsonb_array_elements(better_supabase.open_items_for_party('00000000-0000-4000-8000-000000000001',
    current_setting('t.party'))) i where i ->> 'bucket' = 'unallocated'),
  1,
  'today''s read returns the unallocated payment from the table'
);
select is(
  (select count(*)::int from better_supabase.invoice_open_items e join t_invoices t on t.id = e.document_id where t.n = 1),
  0,
  'the paid invoice has no stored row'
);

select better_supabase.create_invoice_charge((select id from t_invoices where n = 3), 50, 'EUR', 'Late fee');
select is(pg_temp.drift(), '[]'::jsonb, 'a charge refreshes the stored balance');
select is(
  (select e.balance - x.total from better_supabase.invoice_open_items e join better_supabase.invoices x on x.id = e.document_id
   join t_invoices t on t.id = x.id where t.n = 3),
  50::bigint,
  'the stored balance counts the charge'
);

select better_supabase.issue_invoice((better_supabase.credit_invoice((select id from t_invoices where n = 4), null, 'credit') ->> 'id')::uuid, current_date);
select is(pg_temp.drift(), '[]'::jsonb, 'a credit note leaves no drift');
select is(
  (select count(*)::int from better_supabase.invoice_open_items e join t_invoices t on t.id = e.document_id where t.n = 4),
  0,
  'the fully credited invoice has no stored row'
);

select better_supabase.issue_invoice((select id from t_invoices where n = 5), current_date + 5);
select is(
  (select count(*)::int from better_supabase.invoice_open_items e join t_invoices t on t.id = e.document_id where t.n = 5),
  1,
  'a future-dated invoice is stored'
);
select is(
  (select count(*)::int from jsonb_array_elements(better_supabase.open_items_for_party('00000000-0000-4000-8000-000000000001',
    current_setting('t.party'))) i where i ->> 'documentId' = (select id::text from t_invoices where n = 5))
  + (select count(*)::int from jsonb_array_elements(better_supabase.open_items_page('00000000-0000-4000-8000-000000000001') -> 'rows') i
    where i ->> 'documentId' = (select id::text from t_invoices where n = 5)),
  0,
  'today''s read and the page leave it out until its issue date'
);

reset role;
update better_supabase.invoices set company_id = current_setting('t.other')::uuid where id = (select id from t_invoices where n = 3);
select is(
  (select e.party_id from better_supabase.invoice_open_items e join t_invoices t on t.id = e.document_id where t.n = 3),
  current_setting('t.other'),
  'moving an invoice to another party moves its stored row'
);

delete from better_supabase.invoice_open_items e using t_invoices t where t.id = e.document_id and t.n = 2;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select is(
  (select jsonb_array_length(pg_temp.drift())),
  1,
  'a lost row shows as drift'
);
select better_supabase.rebuild_open_items('00000000-0000-4000-8000-000000000001');
select is(pg_temp.drift(), '[]'::jsonb, 'rebuild_open_items writes it back');

select * from finish();
rollback;
