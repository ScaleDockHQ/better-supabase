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
