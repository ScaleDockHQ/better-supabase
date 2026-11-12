-- Demo rows for the example's finance pages (apps/examples/nextjs, /finance/*)
-- in the Acme organization: invoices with dunning and a delivery, expense
-- reports, ledger and journal postings, billable time, a recognition
-- schedule, a tax return, periods, a payroll run, a legal entity, a funding
-- award and a bank account with transactions. Runs after seed.sql.

do $seed$
declare
  t constant uuid := '00000000-0000-4000-8000-000000000001';
  inv uuid;
  rep uuid;
  acct uuid;
  tx uuid;
  entry uuid;
  sched uuid;
  run uuid;
  award uuid;
  bank uuid;
  g integer;
  cat uuid := '00000000-0000-4000-8000-00000000ec01';
begin
  insert into better_supabase.expense_categories (id, tenant_id, key, name)
  values (cat, t, 'travel', 'Travel')
  on conflict do nothing;

  for g in 1..14 loop
    inv := gen_random_uuid();

    insert into better_supabase.invoices (
      id, tenant_id, kind, number, identifier, title, currency, status, direction,
      issued_on, due_on, subtotal, tax_total, total, list_total, paid_total, dunning_level)
    values (
      inv, t, 'invoice', case when g % 4 = 0 then null else g end,
      case when g % 4 = 0 then null else (case when g % 5 = 0 then 'BILL-' else 'INV-' end) || lpad(g::text, 4, '0') end,
      (array['Website redesign', 'Annual support plan', 'Anvil delivery', 'Consulting sprint', 'Hosting'])[1 + g % 5] || ' ' || g,
      'EUR',
      case when g % 4 = 0 then 'draft' when g % 4 = 1 then 'issued' when g % 4 = 2 then 'paid' else 'partially_paid' end,
      case when g % 5 = 0 then 'purchase' else 'sales' end,
      case when g % 4 = 0 then null else current_date - (g * 6) end,
      case when g % 4 = 0 then null else current_date - (g * 6) + 30 end,
      g * 100000, g * 21000, g * 121000, g * 121000,
      case when g % 4 = 2 then g * 121000 when g % 4 = 3 then g * 40000 else 0 end,
      case when g % 4 = 1 and g > 4 then 1 else 0 end)
    on conflict do nothing;

    insert into better_supabase.invoice_lines (
      tenant_id, parent_id, description, quantity, unit_amount, tax_rate_bps, position)
    values (t, inv, 'Line one of invoice ' || g, 1, g * 100000, 2100, 1);

    if g % 4 = 1 and g > 4 then
      insert into better_supabase.invoice_dunning_history (
        tenant_id, invoice_id, kind, level, template_key, fee, balance, note)
      values (t, inv, 'reminder', 1, 'reminder-1', 0, g * 121000, 'First reminder sent');
    end if;

    if g % 4 = 2 then
      insert into better_supabase.e_invoice_deliveries (
        tenant_id, invoice_id, direction, format, channel, message_id, state)
      values (t, inv, 'outbound', 'ubl', 'peppol', 'msg-' || g, 'delivered');
    end if;
  end loop;

  for g in 1..8 loop
    rep := gen_random_uuid();

    insert into better_supabase.expense_reports (
      id, tenant_id, user_id, title, currency, submitted_at, approved_at, reimbursed_at)
    values (
      rep, t, '00000000-0000-4000-8000-0000000000a1',
      (array['Conference trip', 'Client dinner', 'Office supplies', 'Train tickets'])[1 + g % 4] || ' ' || g,
      'EUR',
      case when g % 4 <> 0 then now() - (g || ' days')::interval end,
      case when g % 4 in (2, 3) then now() - (g || ' days')::interval end,
      case when g % 4 = 3 then now() - (g || ' days')::interval end);

    insert into better_supabase.expense_lines (tenant_id, report_id, category_id, spent_on, description, merchant, amount)
    values
      (t, rep, cat, current_date - g, 'Receipt A', 'Cafe Central', g * 1250),
      (t, rep, cat, current_date - g - 1, 'Receipt B', 'NS', g * 840);
  end loop;

  for g in 1..6 loop
    insert into better_supabase.time_entries (
      tenant_id, user_id, subject_type, subject_id, started_at, ended_at, billable, rate, rate_currency, note)
    values (
      t, '00000000-0000-4000-8000-0000000000a1', 'company', '00000000-0000-4000-8000-00000000a001',
      now() - (g || ' days')::interval, now() - (g || ' days')::interval + interval '90 minutes',
      g % 3 <> 0, 9500, 'EUR', 'Consulting block ' || g);
  end loop;

  insert into better_supabase.periods (tenant_id, kind, starts_on, ends_on, status)
  select t, 'fiscal_month', d::date, (d + interval '1 month - 1 day')::date,
    case when d < date_trunc('month', current_date) - interval '2 month' then 'closed' else 'open' end
  from generate_series(date_trunc('month', current_date) - interval '5 month',
    date_trunc('month', current_date), interval '1 month') d
  on conflict do nothing;

  insert into better_supabase.tax_returns (tenant_id, period, period_start, period_end, status, currency, boxes, filed_at)
  values
    (t, to_char(current_date - interval '3 month', 'YYYY-"Q"Q'),
      date_trunc('quarter', current_date - interval '3 month')::date,
      (date_trunc('quarter', current_date - interval '3 month') + interval '3 month - 1 day')::date,
      'filed', 'EUR', '{"1a": 120000, "5b": 45000}', now() - interval '40 days'),
    (t, to_char(current_date, 'YYYY-"Q"Q'), date_trunc('quarter', current_date)::date,
      (date_trunc('quarter', current_date) + interval '3 month - 1 day')::date,
      'draft', 'EUR', '{"1a": 80000, "5b": 12000}', null)
  on conflict do nothing;

  insert into better_supabase.payroll_runs (tenant_id, period_from, period_to, label, status, format, checksum, exported_at)
  values
    (t, date_trunc('month', current_date - interval '1 month')::date,
      (date_trunc('month', current_date) - interval '1 day')::date, 'Last month', 'exported', 'csv', repeat('a', 64), now() - interval '5 days'),
    (t, date_trunc('month', current_date)::date,
      (date_trunc('month', current_date) + interval '1 month - 1 day')::date, 'This month', 'draft', null, null, null)
  on conflict do nothing;

  insert into better_supabase.legal_entities (tenant_id, code, name, vat_number, default_currency, is_default)
  values
    (t, 'ACME-NL', 'Acme Nederland B.V.', 'NL001234567B01', 'EUR', true),
    (t, 'ACME-DE', 'Acme Deutschland GmbH', 'DE123456789', 'EUR', false)
  on conflict do nothing;

  insert into better_supabase.bank_accounts (id, tenant_id, name, iban, currency, holder, is_primary)
  values ('00000000-0000-4000-8000-00000000ba01', t, 'Operating account', 'NL91ABNA0417164300', 'EUR', 'Acme Nederland B.V.', true)
  on conflict do nothing;

  for g in 1..12 loop
    insert into better_supabase.bank_transactions (
      tenant_id, account_id, booked_on, value_on, amount, currency, counterparty_name, remittance, external_id, status)
    values (
      t, '00000000-0000-4000-8000-00000000ba01', current_date - g * 3, current_date - g * 3,
      case when g % 2 = 0 then g * 25000 else -g * 12000 end, 'EUR',
      (array['Road Runner Inc', 'Anvil Supplies', 'Hosting BV', 'Landlord'])[1 + g % 4],
      'Payment ' || g, 'demo-' || g,
      case when g % 3 = 0 then 'matched' else 'unmatched' end)
    on conflict do nothing;
  end loop;
end
$seed$;

-- Ledger, journal, recognition and funding rows for the finance pages.
do $seed2$
declare
  t constant uuid := '00000000-0000-4000-8000-000000000001';
  cash uuid := gen_random_uuid();
  rev uuid := gen_random_uuid();
  tx uuid;
  g integer;
  jr uuid := gen_random_uuid();
  a_bank uuid := gen_random_uuid();
  a_rev uuid := gen_random_uuid();
  ent uuid;
  per uuid := gen_random_uuid();
  sched uuid;
  prod uuid := gen_random_uuid();
  award uuid;
begin
  insert into better_supabase.ledger_accounts (id, tenant_id, kind, code, name, unit, allow_negative)
  values (cash, t, 'cash', 'demo-cash', 'Demo cash', 'EUR', true),
         (rev, t, 'revenue', 'demo-revenue', 'Demo revenue', 'EUR', true);

  for g in 1..6 loop
    tx := gen_random_uuid();
    insert into better_supabase.ledger_transactions (id, tenant_id, kind, reference_type, reference_id, memo, effective_at)
    values (tx, t, 'payment', 'invoice', 'INV-' || lpad(g::text, 4, '0'), 'Payment received ' || g, now() - (g || ' days')::interval);
    insert into better_supabase.ledger_entries (tenant_id, transaction_id, account_id, amount, unit, effective_at)
    values (t, tx, cash, 100000 * g, 'EUR', now() - (g || ' days')::interval),
           (t, tx, rev, -100000 * g, 'EUR', now() - (g || ' days')::interval);
  end loop;

  insert into better_supabase.accounting_settings (tenant_id, functional_currency)
  values (t, 'EUR')
  on conflict do nothing;
  insert into better_supabase.accounting_accounts (id, tenant_id, code, name, type, normal_side, currency)
  values (a_bank, t, '1100', 'Bank', 'asset', 'debit', 'EUR'),
         (a_rev, t, '8000', 'Revenue', 'income', 'credit', 'EUR');
  insert into better_supabase.accounting_journals (id, tenant_id, code, name, type, currency)
  values (jr, t, 'GEN', 'General journal', 'general', 'EUR');
  insert into better_supabase.accounting_periods (id, tenant_id, fiscal_year, number, starts_on, ends_on)
  values (per, t, extract(year from now())::int, 1, date_trunc('year', now())::date, (date_trunc('year', now()) + interval '1 year - 1 day')::date);

  for g in 1..4 loop
    ent := gen_random_uuid();
    insert into better_supabase.accounting_entries (id, tenant_id, journal_id, fiscal_year, sequence, entry_date, status, reference, memo)
    values (ent, t, jr, extract(year from now())::int, g, current_date - g, 'draft', 'REF-' || g, 'Sales booking ' || g);
    insert into better_supabase.accounting_entry_lines (tenant_id, entry_id, position, account_id, debit, credit, currency, amount_currency)
    values (t, ent, 1, a_bank, 250000 * g, 0, 'EUR', 250000 * g),
           (t, ent, 2, a_rev, 0, 250000 * g, 'EUR', -250000 * g);
    update better_supabase.accounting_entries
    set status = 'posted', number = 'GEN-' || lpad(g::text, 4, '0'), period_id = per, posted_at = now()
    where id = ent;
  end loop;

  sched := gen_random_uuid();
  insert into better_supabase.accounting_recognition_schedules (id, tenant_id, source_type, source_id, line_ref, amount, currency, starts_on, ends_on)
  values (sched, t, 'invoice', 'INV-0001', '1', 1200000, 'EUR', current_date - 60, current_date + 300);
  for g in 0..11 loop
    insert into better_supabase.accounting_recognition_rows (schedule_id, tenant_id, due_on, amount, status)
    values (sched, t, current_date - 60 + g * 30, 100000, case when g < 2 then 'posted' else 'pending' end);
  end loop;

  insert into better_supabase.funding_products (id, tenant_id, code, title, unit, rate, currency)
  values (prod, t, 'CARE-H', 'Care hour', 'hour', 4500, 'EUR');
  for g in 1..3 loop
    award := gen_random_uuid();
    insert into better_supabase.funding_awards (id, tenant_id, subject_type, subject_id, funder_id, product_id, units, period, starts_on, reference, status)
    values (award, t, 'customer', (select id::text from public.customers where organization_id = t order by created_at offset (g - 1) % 2 limit 1), gen_random_uuid(), prod, 20 * g, 'month', current_date - 30, 'AWD-' || g, case when g = 3 then 'requested' else 'active' end);
    insert into better_supabase.funding_deliveries (tenant_id, award_id, delivered_on, units, status)
    values (t, award, current_date - 3, 2 * g, 'approved');
  end loop;
end
$seed2$;
