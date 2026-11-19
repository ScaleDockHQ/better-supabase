-- recompute_invoice_status: derives an issued invoice's status, paid total and
-- credited total from its ledger payments, imported allocations and issued
-- credit notes, so an app never writes the status itself. A paid total an
-- import wrote without a posting stays, a draft keeps its status, and the
-- caller needs invoices.manage (invoices.purchase for a purchase invoice) and
-- a session that may write. Run with `supabase test db`.
begin;
select plan(14);

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

select set_config('test.paid', (better_supabase.issue_invoice((better_supabase.create_invoice(
  '00000000-0000-4000-8000-000000000001', '{"title": "Recompute paid", "currency": "EUR"}'::jsonb,
  '[{"description": "Work", "quantity": 1, "unitAmount": "10000"}]'::jsonb) ->> 'id')::uuid, current_date) ->> 'id'), true);
select set_config('test.total', (select total::text from better_supabase.invoices where id = current_setting('test.paid')::uuid), true);
select better_supabase.record_invoice_payment(current_setting('test.paid')::uuid, current_setting('test.total')::bigint, 'EUR', now(), 'bank', 'recompute-status-1');
update better_supabase.invoices set status = 'issued', paid_total = 0, paid_at = null where id = current_setting('test.paid')::uuid;

select is(
  better_supabase.recompute_invoice_status(current_setting('test.paid')::uuid) ->> 'status',
  'paid',
  'a paid invoice whose status drifted is paid again'
);
select is(
  (select paid_total::text from better_supabase.invoices where id = current_setting('test.paid')::uuid),
  current_setting('test.total'),
  'its paid total comes from the ledger'
);

select set_config('test.credited', (better_supabase.issue_invoice((better_supabase.create_invoice(
  '00000000-0000-4000-8000-000000000001', '{"title": "Recompute credited", "currency": "EUR"}'::jsonb,
  '[{"description": "Work", "quantity": 1, "unitAmount": "10000"}]'::jsonb) ->> 'id')::uuid, current_date) ->> 'id'), true);
select better_supabase.issue_invoice((better_supabase.credit_invoice(current_setting('test.credited')::uuid, null, 'credit') ->> 'id')::uuid, current_date);
update better_supabase.invoices set status = 'issued', credited_total = 0 where id = current_setting('test.credited')::uuid;
select better_supabase.recompute_invoice_status(current_setting('test.credited')::uuid);

select is(
  (select credited_total = total from better_supabase.invoices where id = current_setting('test.credited')::uuid),
  true,
  'the credited total comes from the issued credit notes'
);
select isnt(
  (select status::text from better_supabase.invoices where id = current_setting('test.credited')::uuid),
  'issued',
  'a fully credited invoice is settled again'
);

-- An import's row settlement writes the paid total and status without a posting.
select set_config('test.row', (better_supabase.issue_invoice((better_supabase.create_invoice(
  '00000000-0000-4000-8000-000000000001', '{"title": "Recompute row settlement", "currency": "EUR"}'::jsonb,
  '[{"description": "Work", "quantity": 1, "unitAmount": "10000"}]'::jsonb) ->> 'id')::uuid, current_date) ->> 'id'), true);
update better_supabase.invoices set status = 'paid', paid_total = total, paid_at = now() where id = current_setting('test.row')::uuid;
select better_supabase.recompute_invoice_status(current_setting('test.row')::uuid);
select is(
  (select status::text || ' ' || (paid_total = total)::text from better_supabase.invoices where id = current_setting('test.row')::uuid),
  'paid true',
  'a row-settled import keeps its status and paid total'
);

-- An imported allocation links a receipt without a posting.
select set_config('test.alloc', (better_supabase.issue_invoice((better_supabase.create_invoice(
  '00000000-0000-4000-8000-000000000001', '{"title": "Recompute allocation", "currency": "EUR"}'::jsonb,
  '[{"description": "Work", "quantity": 1, "unitAmount": "10000"}]'::jsonb) ->> 'id')::uuid, current_date) ->> 'id'), true);
select better_supabase.allocate_existing('00000000-0000-4000-8000-000000000001', current_setting('test.alloc')::uuid, 'recompute-import-1',
  (select total from better_supabase.invoices where id = current_setting('test.alloc')::uuid), 'party-1');
select better_supabase.recompute_invoice_status(current_setting('test.alloc')::uuid);
select is(
  (select status::text || ' ' || (paid_total = total)::text from better_supabase.invoices where id = current_setting('test.alloc')::uuid),
  'paid true',
  'an invoice paid by an imported allocation keeps its status and paid total'
);
update better_supabase.invoices set status = 'issued', paid_total = 0 where id = current_setting('test.alloc')::uuid;
select better_supabase.recompute_invoice_status(current_setting('test.alloc')::uuid);
select is(
  (select status::text || ' ' || (paid_total = total)::text from better_supabase.invoices where id = current_setting('test.alloc')::uuid),
  'paid true',
  'the imported allocations count into the derived paid total'
);

select set_config('test.draft', (better_supabase.create_invoice(
  '00000000-0000-4000-8000-000000000001', '{"title": "Recompute draft", "currency": "EUR"}'::jsonb,
  '[{"description": "Work", "quantity": 1, "unitAmount": "10000"}]'::jsonb) ->> 'id'), true);
select is(
  better_supabase.recompute_invoice_status(current_setting('test.draft')::uuid) ->> 'status',
  'draft',
  'a draft keeps its status'
);
select set_config('test.purchase', (better_supabase.create_invoice(
  '00000000-0000-4000-8000-000000000001', '{"title": "Recompute purchase", "currency": "EUR", "direction": "purchase"}'::jsonb,
  '[{"description": "Parts", "quantity": 1, "unitAmount": "10000"}]'::jsonb) ->> 'id'), true);

-- The Acme member (…a2) reads invoices; with invoices.manage they still lack
-- invoices.purchase.
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated"}', true);
set local role authenticated;
select throws_ok(
  format('select better_supabase.recompute_invoice_status(%L::uuid)', current_setting('test.paid')),
  '42501',
  'you may not recompute this invoice',
  'a member who reads invoices without invoices.manage is refused'
);

reset role;
insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p on p.key = 'invoices.manage'
where r.scope = 'tenant' and r.key = 'member'
on conflict do nothing;
set local role authenticated;
select is(
  better_supabase.recompute_invoice_status(current_setting('test.paid')::uuid) ->> 'status',
  'paid',
  'invoices.manage recomputes a sales invoice'
);
select throws_ok(
  format('select better_supabase.recompute_invoice_status(%L::uuid)', current_setting('test.purchase')),
  '42501',
  'you may not recompute this invoice',
  'a purchase invoice needs invoices.purchase'
);

reset role;
insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p on p.key = 'invoices.purchase'
where r.scope = 'tenant' and r.key = 'member'
on conflict do nothing;
set local role authenticated;
select is(
  better_supabase.recompute_invoice_status(current_setting('test.purchase')::uuid) ->> 'status',
  'draft',
  'invoices.purchase recomputes a purchase invoice'
);

reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","act":{"kind":"support","sub":"admin-1","session_id":"s1","read_only":true}}', true);
set local role authenticated;
select throws_ok(
  format('select better_supabase.recompute_invoice_status(%L::uuid)', current_setting('test.paid')),
  '42501',
  'This session is read-only',
  'a read-only session is refused'
);

reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000e9","role":"authenticated"}', true);
set local role authenticated;
select throws_ok(
  format('select better_supabase.recompute_invoice_status(%L::uuid)', current_setting('test.paid')),
  'P0002',
  null,
  'a caller who can''t read the invoice gets not found'
);

select * from finish();
rollback;
