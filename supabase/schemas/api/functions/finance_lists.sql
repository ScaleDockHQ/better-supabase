-- Server-side lists and record reads for the Next.js example's finance pages
-- (apps/examples/nextjs, /finance/*). The finance blocks keep their tables in
-- `better_supabase`, which the Data API doesn't expose, and have no list with
-- search, facets, a sort and a keyset cursor. `finance_list_spec` names each
-- entity once (its rows, its search columns, its facets and its sorts) and
-- `finance_list` builds the page from it. Every function is SECURITY INVOKER,
-- so each block's read policies decide what the caller sees.

create or replace function api.finance_list_spec(entity text)
returns jsonb
language plpgsql
immutable
security invoker
set search_path = ''
as $$
begin
  return case entity
    when 'invoices' then jsonb_build_object(
      'from', 'better_supabase.invoices t',
      'item', $i$jsonb_build_object(
        'id', t.id, 'identifier', t.identifier, 'title', t.title,
        'direction', t.direction, 'status', t.status, 'currency', t.currency,
        'total', t.total::text,
        'balance', (t.total - t.credited_total - t.paid_total)::text,
        'issuedOn', t.issued_on, 'dueOn', t.due_on,
        'dunningLevel', t.dunning_level,
        'overdue', t.status in ('issued', 'partially_paid') and t.due_on < current_date)$i$,
      'search', jsonb_build_array('t.title', 't.identifier'),
      'facets', jsonb_build_object('status', 't.status', 'direction', 't.direction'),
      'sorts', jsonb_build_object(
        'default', jsonb_build_object('expr', 't.created_at', 'dir', 'desc', 'cast', 'timestamptz'),
        'due', jsonb_build_object('expr', 'coalesce(t.due_on, date ''9999-12-31'')', 'dir', 'asc', 'cast', 'date'),
        'total', jsonb_build_object('expr', 't.total', 'dir', 'desc', 'cast', 'bigint')))
    when 'expenses' then jsonb_build_object(
      'from', $f$better_supabase.expense_reports t
        left join lateral (
          select coalesce(sum(l.amount), 0) as total, count(*) as lines
          from better_supabase.expense_lines l where l.report_id = t.id) s on true$f$,
      'item', $i$jsonb_build_object(
        'id', t.id, 'title', t.title, 'userId', t.user_id, 'currency', t.currency,
        'status', case
          when t.cancelled_at is not null then 'cancelled'
          when t.reimbursed_at is not null then 'reimbursed'
          when t.approved_at is not null then 'approved'
          when t.submitted_at is not null then 'submitted'
          else 'draft' end,
        'total', s.total::text, 'lines', s.lines,
        'submittedAt', t.submitted_at, 'createdAt', t.created_at)$i$,
      'search', jsonb_build_array('t.title'),
      'facets', jsonb_build_object('status', $e$case
          when t.cancelled_at is not null then 'cancelled'
          when t.reimbursed_at is not null then 'reimbursed'
          when t.approved_at is not null then 'approved'
          when t.submitted_at is not null then 'submitted'
          else 'draft' end$e$),
      'sorts', jsonb_build_object(
        'default', jsonb_build_object('expr', 't.created_at', 'dir', 'desc', 'cast', 'timestamptz'),
        'total', jsonb_build_object('expr', 's.total', 'dir', 'desc', 'cast', 'numeric')))
    when 'ledger' then jsonb_build_object(
      'from', $f$better_supabase.ledger_transactions t
        left join lateral (
          select count(*) as entries from better_supabase.ledger_entries e
          where e.transaction_id = t.id) s on true$f$,
      'item', $i$jsonb_build_object(
        'id', t.id, 'kind', t.kind, 'memo', t.memo,
        'referenceType', t.reference_type, 'referenceId', t.reference_id,
        'entries', s.entries, 'effectiveAt', t.effective_at)$i$,
      'search', jsonb_build_array('t.memo', 't.reference_id'),
      'facets', jsonb_build_object('kind', 't.kind'),
      'sorts', jsonb_build_object(
        'default', jsonb_build_object('expr', 't.effective_at', 'dir', 'desc', 'cast', 'timestamptz'),
        'oldest', jsonb_build_object('expr', 't.effective_at', 'dir', 'asc', 'cast', 'timestamptz')))
    when 'journal' then jsonb_build_object(
      'from', $f$better_supabase.accounting_entries t
        left join lateral (
          select coalesce(sum(l.debit), 0) as total, max(l.currency) as currency
          from better_supabase.accounting_entry_lines l
          where l.entry_id = t.id) s on true$f$,
      'item', $i$jsonb_build_object(
        'id', t.id, 'number', t.number, 'entryDate', t.entry_date, 'status', t.status,
        'memo', t.memo, 'reference', t.reference, 'sourceType', t.source_type,
        'total', s.total::text, 'currency', s.currency)$i$,
      'search', jsonb_build_array('t.memo', 't.number', 't.reference'),
      'facets', jsonb_build_object('status', 't.status', 'sourceType', 't.source_type'),
      'sorts', jsonb_build_object(
        'default', jsonb_build_object('expr', 't.entry_date', 'dir', 'desc', 'cast', 'date'),
        'oldest', jsonb_build_object('expr', 't.entry_date', 'dir', 'asc', 'cast', 'date')))
    when 'billable-time' then jsonb_build_object(
      'from', $f$better_supabase.time_entries t
        left join better_supabase.time_invoice_entries b on b.entry_id = t.id$f$,
      'item', $i$jsonb_build_object(
        'id', t.id, 'userId', t.user_id, 'subjectType', t.subject_type,
        'subjectId', t.subject_id, 'startedAt', t.started_at, 'endedAt', t.ended_at,
        'seconds', t.seconds, 'billable', t.billable, 'rate', t.rate::text,
        'currency', t.rate_currency, 'note', t.note, 'billed', b.entry_id is not null)$i$,
      'search', jsonb_build_array('t.note'),
      'facets', jsonb_build_object(
        'billable', 't.billable', 'billed', '(b.entry_id is not null)'),
      'sorts', jsonb_build_object(
        'default', jsonb_build_object('expr', 't.started_at', 'dir', 'desc', 'cast', 'timestamptz'),
        'longest', jsonb_build_object('expr', 'coalesce(t.seconds, 0)', 'dir', 'desc', 'cast', 'bigint')))
    when 'recurring' then jsonb_build_object(
      'from', $f$better_supabase.accounting_recognition_schedules t
        left join lateral (
          select count(*) as total, count(*) filter (where r.status = 'posted') as posted
          from better_supabase.accounting_recognition_rows r where r.schedule_id = t.id) s on true$f$,
      'item', $i$jsonb_build_object(
        'id', t.id, 'sourceType', t.source_type, 'sourceId', t.source_id,
        'lineRef', t.line_ref, 'amount', t.amount::text, 'currency', t.currency,
        'startsOn', t.starts_on, 'endsOn', t.ends_on,
        'rows', s.total, 'posted', s.posted)$i$,
      'search', jsonb_build_array('t.source_id', 't.line_ref'),
      'facets', jsonb_build_object('sourceType', 't.source_type'),
      'sorts', jsonb_build_object(
        'default', jsonb_build_object('expr', 't.starts_on', 'dir', 'desc', 'cast', 'date'),
        'amount', jsonb_build_object('expr', 't.amount', 'dir', 'desc', 'cast', 'bigint')))
    when 'tax' then jsonb_build_object(
      'from', 'better_supabase.tax_returns t',
      'item', $i$jsonb_build_object(
        'id', t.id, 'period', t.period, 'periodStart', t.period_start,
        'periodEnd', t.period_end, 'status', t.status, 'currency', t.currency,
        'preparedAt', t.prepared_at, 'filedAt', t.filed_at)$i$,
      'search', jsonb_build_array('t.period'),
      'facets', jsonb_build_object('status', 't.status'),
      'sorts', jsonb_build_object(
        'default', jsonb_build_object('expr', 't.period_start', 'dir', 'desc', 'cast', 'date'),
        'oldest', jsonb_build_object('expr', 't.period_start', 'dir', 'asc', 'cast', 'date')))
    when 'periods' then jsonb_build_object(
      'from', 'better_supabase.periods t',
      'item', $i$jsonb_build_object(
        'id', t.id, 'kind', t.kind, 'startsOn', t.starts_on, 'endsOn', t.ends_on,
        'status', t.status, 'closedAt', t.closed_at)$i$,
      'search', jsonb_build_array('t.kind'),
      'facets', jsonb_build_object('status', 't.status', 'kind', 't.kind'),
      'sorts', jsonb_build_object(
        'default', jsonb_build_object('expr', 't.starts_on', 'dir', 'desc', 'cast', 'date'),
        'oldest', jsonb_build_object('expr', 't.starts_on', 'dir', 'asc', 'cast', 'date')))
    when 'payroll' then jsonb_build_object(
      'from', $f$better_supabase.payroll_runs t
        left join lateral (
          select count(*) as lines from better_supabase.payroll_lines l where l.run_id = t.id) s on true$f$,
      'item', $i$jsonb_build_object(
        'id', t.id, 'label', t.label, 'periodFrom', t.period_from, 'periodTo', t.period_to,
        'status', t.status, 'format', t.format, 'exportedAt', t.exported_at,
        'lines', s.lines)$i$,
      'search', jsonb_build_array('t.label'),
      'facets', jsonb_build_object('status', 't.status'),
      'sorts', jsonb_build_object(
        'default', jsonb_build_object('expr', 't.period_from', 'dir', 'desc', 'cast', 'date'),
        'oldest', jsonb_build_object('expr', 't.period_from', 'dir', 'asc', 'cast', 'date')))
    when 'legal-entities' then jsonb_build_object(
      'from', 'better_supabase.legal_entities t',
      'item', $i$jsonb_build_object(
        'id', t.id, 'code', t.code, 'name', t.name, 'vatNumber', t.vat_number,
        'currency', t.default_currency, 'isDefault', t.is_default,
        'archived', t.archived_at is not null)$i$,
      'search', jsonb_build_array('t.name', 't.code'),
      'facets', jsonb_build_object(
        'state', $e$case when t.archived_at is null then 'active' else 'archived' end$e$),
      'sorts', jsonb_build_object(
        'default', jsonb_build_object('expr', 't.code', 'dir', 'asc', 'cast', 'text'),
        'newest', jsonb_build_object('expr', 't.created_at', 'dir', 'desc', 'cast', 'timestamptz')))
    when 'funding' then jsonb_build_object(
      'from', $f$better_supabase.funding_awards t
        left join lateral (
          select coalesce(sum(d.units), 0) as used from better_supabase.funding_deliveries d
          where d.award_id = t.id and d.status <> 'cancelled') s on true$f$,
      'item', $i$jsonb_build_object(
        'id', t.id, 'subjectType', t.subject_type, 'subjectId', t.subject_id,
        'reference', t.reference, 'units', t.units, 'used', s.used, 'period', t.period,
        'startsOn', t.starts_on, 'endsOn', t.ends_on, 'status', t.status)$i$,
      'search', jsonb_build_array('t.reference', 't.subject_id'),
      'facets', jsonb_build_object('status', 't.status', 'period', 't.period'),
      'sorts', jsonb_build_object(
        'default', jsonb_build_object('expr', 't.starts_on', 'dir', 'desc', 'cast', 'date'),
        'units', jsonb_build_object('expr', 't.units', 'dir', 'desc', 'cast', 'numeric')))
    when 'bank-accounts' then jsonb_build_object(
      'from', 'better_supabase.bank_accounts t',
      'item', $i$jsonb_build_object(
        'id', t.id, 'name', t.name, 'iban', t.iban, 'currency', t.currency,
        'holder', t.holder, 'isPrimary', t.is_primary,
        'archived', t.archived_at is not null)$i$,
      'search', jsonb_build_array('t.name', 't.iban'),
      'facets', jsonb_build_object('currency', 't.currency'),
      'sorts', jsonb_build_object(
        'default', jsonb_build_object('expr', 't.name', 'dir', 'asc', 'cast', 'text'),
        'newest', jsonb_build_object('expr', 't.created_at', 'dir', 'desc', 'cast', 'timestamptz')))
    when 'bank-transactions' then jsonb_build_object(
      'from', $f$better_supabase.bank_transactions t
        join better_supabase.bank_accounts a on a.id = t.account_id$f$,
      'item', $i$jsonb_build_object(
        'id', t.id, 'account', a.name, 'bookedOn', t.booked_on, 'amount', t.amount::text,
        'currency', t.currency, 'counterparty', t.counterparty_name,
        'remittance', t.remittance, 'status', t.status)$i$,
      'search', jsonb_build_array('t.counterparty_name', 't.remittance'),
      'facets', jsonb_build_object('status', 't.status', 'account', 'a.name'),
      'sorts', jsonb_build_object(
        'default', jsonb_build_object('expr', 't.booked_on', 'dir', 'desc', 'cast', 'date'),
        'amount', jsonb_build_object('expr', 't.amount', 'dir', 'desc', 'cast', 'bigint')))
    else null
  end;
end;
$$;

-- One page of an entity: `q` searches the entity's columns, `filters` maps a
-- facet to its values (`{"status": ["issued"]}`), `sort` names one of the
-- entity's sorts, and `after` is the cursor of the previous page (`nextCursor`).
create or replace function api.finance_list(
  entity text,
  tenant uuid,
  q text default null,
  filters jsonb default '{}'::jsonb,
  sort text default null,
  after text default null,
  lim integer default 50
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  spec jsonb := api.finance_list_spec(entity);
  chosen jsonb;
  wheres text[] := array['t.tenant_id = $1'];
  base text[];
  facet_wheres jsonb := '{}'::jsonb;
  facet record;
  counts jsonb := '{}'::jsonb;
  counted jsonb;
  capped boolean := false;
  this_capped boolean;
  terms text[];
  cur jsonb := case when after is null or after = '' then null else after::jsonb end;
  op text;
  size integer := least(greatest(coalesce(lim, 50), 1), 200);
  statement text;
  fetched jsonb;
  kept jsonb;
  last_row jsonb;
begin
  if spec is null then
    raise exception 'unknown finance entity %', entity using errcode = '22023';
  end if;

  chosen := coalesce(spec -> 'sorts' -> coalesce(sort, 'default'), spec -> 'sorts' -> 'default');
  op := case when chosen ->> 'dir' = 'desc' then '<' else '>' end;

  for facet in select key, value from jsonb_each(coalesce(filters, '{}'::jsonb)) loop
    if spec -> 'facets' ? facet.key and jsonb_typeof(facet.value) = 'array'
      and jsonb_array_length(facet.value) > 0 then
      facet_wheres := facet_wheres || jsonb_build_object(facet.key, format(
        '(%s)::text = any (%L::text[])',
        spec -> 'facets' ->> facet.key,
        array(select jsonb_array_elements_text(facet.value))));
    end if;
  end loop;

  if q is not null and btrim(q) <> '' then
    select array_agg(format('%s::text ilike $2', term))
      into terms
      from jsonb_array_elements_text(spec -> 'search') as term;

    wheres := wheres || ('(' || array_to_string(terms, ' or ') || ')');
  end if;

  base := wheres;

  wheres := wheres || array(select value #>> '{}' from jsonb_each(facet_wheres));

  if cur is not null then
    wheres := wheres || format(
      '((%s), t.id) %s ($3::%s, $4::uuid)',
      chosen ->> 'expr', op, chosen ->> 'cast');
  end if;

  statement := format(
    $s$select coalesce(jsonb_agg(x order by x.n), '[]'::jsonb) from (
      select row_number() over (order by (%2$s) %5$s, t.id %5$s) as n, (%1$s) as item,
        ((%2$s))::text as k, t.id as id
      from %3$s where %4$s
      order by (%2$s) %5$s, t.id %5$s limit %6$s) x$s$,
    spec ->> 'item', chosen ->> 'expr', spec ->> 'from',
    array_to_string(wheres, ' and '), chosen ->> 'dir', size + 1);

  execute statement into fetched
    using tenant, '%' || coalesce(q, '') || '%',
      cur ->> 'k', (cur ->> 'id')::uuid;

  select coalesce(jsonb_agg(r -> 'item' order by ord), '[]'::jsonb)
    into kept
    from jsonb_array_elements(fetched) with ordinality as e(r, ord)
    where ord <= size;

  last_row := case
    when jsonb_array_length(fetched) > size then fetched -> (size - 1)
    else null end;

  -- Each facet counts its values under every other filter, over at most 1,000
  -- rows (a capped count), on the first page only.
  if cur is null then
    for facet in select key, value from jsonb_each_text(spec -> 'facets') loop
      execute format(
        $c$select coalesce(jsonb_object_agg(v, n), '{}'::jsonb), coalesce(sum(n) >= 1000, false) from (
          select v, count(*) as n from (
            select (%1$s)::text as v from %2$s where %3$s limit 1000) s
          where v is not null group by v) g$c$,
        facet.value, spec ->> 'from',
        array_to_string(base || array(
          select w.value #>> '{}' from jsonb_each(facet_wheres) w where w.key <> facet.key), ' and '))
        into counted, this_capped
        using tenant, '%' || coalesce(q, '') || '%';

      capped := capped or this_capped;
      counts := counts || jsonb_build_object(facet.key, counted);
    end loop;
  end if;

  return jsonb_build_object(
    'items', kept,
    'nextCursor', case when last_row is null then null
      else jsonb_build_object('k', last_row ->> 'k', 'id', last_row ->> 'id')::text end,
    'facetCounts', case when cur is null then counts end,
    'facetCountsCapped', case when cur is null then capped end);
end;
$$;

-- One record with its child rows, as the finance detail pages show it.
create or replace function api.finance_detail(entity text, tenant uuid, id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
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
$$;

-- Keyset sorts and trigram search for the lists above. Each tenant index ends
-- in the id, so a page seeks to its cursor instead of sorting the tenant.
create index if not exists finance_invoices_list_idx
  on better_supabase.invoices (tenant_id, created_at desc, id desc);
create index if not exists finance_invoices_title_trgm_idx
  on better_supabase.invoices using gin (title extensions.gin_trgm_ops);
create index if not exists finance_invoices_identifier_trgm_idx
  on better_supabase.invoices using gin (identifier extensions.gin_trgm_ops);
create index if not exists finance_expense_reports_list_idx
  on better_supabase.expense_reports (tenant_id, created_at desc, id desc);
create index if not exists finance_expense_reports_title_trgm_idx
  on better_supabase.expense_reports using gin (title extensions.gin_trgm_ops);
create index if not exists finance_ledger_transactions_list_idx
  on better_supabase.ledger_transactions (tenant_id, effective_at desc, id desc);
create index if not exists finance_accounting_entries_list_idx
  on better_supabase.accounting_entries (tenant_id, entry_date desc, id desc);
create index if not exists finance_time_entries_list_idx
  on better_supabase.time_entries (tenant_id, started_at desc, id desc);
create index if not exists finance_time_entries_note_trgm_idx
  on better_supabase.time_entries using gin (note extensions.gin_trgm_ops);
create index if not exists finance_recognition_schedules_list_idx
  on better_supabase.accounting_recognition_schedules (tenant_id, starts_on desc, id desc);
create index if not exists finance_tax_returns_list_idx
  on better_supabase.tax_returns (tenant_id, period_start desc, id desc);
create index if not exists finance_periods_list_idx
  on better_supabase.periods (tenant_id, starts_on desc, id desc);
create index if not exists finance_payroll_runs_list_idx
  on better_supabase.payroll_runs (tenant_id, period_from desc, id desc);
create index if not exists finance_legal_entities_list_idx
  on better_supabase.legal_entities (tenant_id, code, id);
create index if not exists finance_funding_awards_list_idx
  on better_supabase.funding_awards (tenant_id, starts_on desc, id desc);
create index if not exists finance_bank_accounts_list_idx
  on better_supabase.bank_accounts (tenant_id, name, id);
create index if not exists finance_bank_transactions_list_idx
  on better_supabase.bank_transactions (tenant_id, booked_on desc, id desc);

revoke all on function api.finance_list_spec(text) from public, anon;
grant execute on function api.finance_list_spec(text) to authenticated;
revoke all on function api.finance_list(text, uuid, text, jsonb, text, text, integer) from public, anon;
grant execute on function api.finance_list(text, uuid, text, jsonb, text, text, integer) to authenticated;
revoke all on function api.finance_detail(text, uuid, uuid) from public, anon;
grant execute on function api.finance_detail(text, uuid, uuid) to authenticated;
