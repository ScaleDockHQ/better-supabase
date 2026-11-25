SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.finance_detail (
  entity text,
  tenant uuid,
  id     uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  return case entity
    when 'invoices' then (
      select to_jsonb(t) - 'tenant_id' - 'buyer' - 'dimensions'
        || jsonb_build_object(
          'lines', coalesce((select jsonb_agg(to_jsonb(l) order by l.position)
            from better_supabase.invoice_lines l where l.parent_id = t.id), '[]'),
          'dunning', coalesce((select jsonb_agg(to_jsonb(d) order by d.created_at desc)
            from better_supabase.invoice_dunning_history d where d.invoice_id = t.id), '[]'),
          'deliveries', coalesce((select jsonb_agg(to_jsonb(e) order by e.created_at desc)
            from better_supabase.e_invoice_deliveries e where e.invoice_id = t.id), '[]'),
          'matches', coalesce((select jsonb_agg(jsonb_build_object(
              'id', m.id, 'amount', m.amount, 'createdAt', m.created_at,
              'bookedOn', x.booked_on, 'counterparty', x.counterparty_name) order by m.created_at desc)
            from better_supabase.bank_matches m
            join better_supabase.bank_transactions x on x.id = m.transaction_id
            where m.target_type = 'invoice' and m.target_id = t.id), '[]'))
      from better_supabase.invoices t where t.id = finance_detail.id and t.tenant_id = tenant)
    when 'expenses' then (
      select to_jsonb(t) - 'tenant_id'
        || jsonb_build_object('lines', coalesce((
          select jsonb_agg(to_jsonb(l) || jsonb_build_object('category', c.name) order by l.spent_on)
          from better_supabase.expense_lines l
          left join better_supabase.expense_categories c on c.id = l.category_id
          where l.report_id = t.id), '[]'))
      from better_supabase.expense_reports t where t.id = finance_detail.id and t.tenant_id = tenant)
    when 'ledger' then (
      select to_jsonb(t) - 'tenant_id'
        || jsonb_build_object('entries', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', e.id, 'amount', e.amount, 'unit', e.unit,
            'account', a.name, 'code', a.code) order by e.created_at)
          from better_supabase.ledger_entries e
          left join better_supabase.ledger_accounts a on a.id = e.account_id
          where e.transaction_id = t.id), '[]'))
      from better_supabase.ledger_transactions t where t.id = finance_detail.id and t.tenant_id = tenant)
    when 'journal' then (
      select to_jsonb(t) - 'tenant_id'
        || jsonb_build_object('lines', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', l.id, 'position', l.position, 'code', a.code, 'account', a.name,
            'debit', l.debit, 'credit', l.credit, 'currency', l.currency,
            'description', l.description) order by l.position)
          from better_supabase.accounting_entry_lines l
          left join better_supabase.accounting_accounts a on a.id = l.account_id
          where l.entry_id = t.id), '[]'))
      from better_supabase.accounting_entries t where t.id = finance_detail.id and t.tenant_id = tenant)
    when 'billable-time' then (
      select to_jsonb(t) - 'tenant_id'
        || jsonb_build_object('invoices', coalesce((
          select jsonb_agg(jsonb_build_object(
            'invoiceId', b.invoice_id, 'rate', b.rate, 'currency', b.currency,
            'seconds', b.seconds, 'createdAt', b.created_at))
          from better_supabase.time_invoice_entries b where b.entry_id = t.id), '[]'))
      from better_supabase.time_entries t where t.id = finance_detail.id and t.tenant_id = tenant)
    when 'recurring' then (
      select to_jsonb(t) - 'tenant_id'
        || jsonb_build_object('rows', coalesce((
          select jsonb_agg(to_jsonb(r) - 'tenant_id' - 'schedule_id' order by r.due_on)
          from better_supabase.accounting_recognition_rows r where r.schedule_id = t.id), '[]'))
      from better_supabase.accounting_recognition_schedules t
      where t.id = finance_detail.id and t.tenant_id = tenant)
    when 'tax' then (
      select to_jsonb(t) - 'tenant_id'
      from better_supabase.tax_returns t where t.id = finance_detail.id and t.tenant_id = tenant)
    when 'periods' then (
      select to_jsonb(t) - 'tenant_id'
        || jsonb_build_object('blockers', case when t.status = 'closed' then '[]'::jsonb
          else to_jsonb(better_supabase.period_close_blockers(t.id)) end)
      from better_supabase.periods t where t.id = finance_detail.id and t.tenant_id = tenant)
    when 'payroll' then (
      select to_jsonb(t) - 'tenant_id'
        || jsonb_build_object('lines', coalesce((
          select jsonb_agg(to_jsonb(l) - 'tenant_id' - 'run_id' order by l.employee_name, l.code)
          from better_supabase.payroll_lines l where l.run_id = t.id), '[]'))
      from better_supabase.payroll_runs t where t.id = finance_detail.id and t.tenant_id = tenant)
    when 'legal-entities' then (
      select to_jsonb(t) - 'tenant_id'
      from better_supabase.legal_entities t where t.id = finance_detail.id and t.tenant_id = tenant)
    when 'funding' then (
      select to_jsonb(t) - 'tenant_id'
        || jsonb_build_object('deliveries', coalesce((
          select jsonb_agg(to_jsonb(d) - 'tenant_id' - 'award_id' order by d.delivered_on desc)
          from better_supabase.funding_deliveries d where d.award_id = t.id), '[]'))
      from better_supabase.funding_awards t where t.id = finance_detail.id and t.tenant_id = tenant)
    when 'bank-accounts' then (
      select to_jsonb(t) - 'tenant_id'
        || jsonb_build_object('transactions', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', x.id, 'bookedOn', x.booked_on, 'amount', x.amount, 'currency', x.currency,
            'counterparty', x.counterparty_name, 'remittance', x.remittance,
            'status', x.status) order by x.booked_on desc, x.id)
          from (select * from better_supabase.bank_transactions b
                where b.account_id = t.id order by b.booked_on desc, b.id limit 25) x), '[]'))
      from better_supabase.bank_accounts t where t.id = finance_detail.id and t.tenant_id = tenant)
    when 'bank-transactions' then (
      select to_jsonb(t) - 'tenant_id'
        || jsonb_build_object(
          'account', (select a.name from better_supabase.bank_accounts a where a.id = t.account_id),
          'matches', coalesce((
            select jsonb_agg(to_jsonb(m) - 'tenant_id' - 'transaction_id' order by m.created_at)
            from better_supabase.bank_matches m where m.transaction_id = t.id), '[]'))
      from better_supabase.bank_transactions t where t.id = finance_detail.id and t.tenant_id = tenant)
    else null
  end;
end;
$function$;
