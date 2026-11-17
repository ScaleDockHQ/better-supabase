SET local check_function_bodies = off;

DROP FUNCTION "api"."audit_event"(text, text, text, text, text, text, uuid, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text, text, text, uuid, uuid, text);

DROP FUNCTION
  "api"."audit_event_trusted"(text, text, text, text, text, text, uuid, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text, text, text, uuid, uuid, text);

DROP FUNCTION
  "better_supabase"."audit_event"(text, text, text, text, text, text, uuid, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text, text, text, uuid, uuid, text);

DROP FUNCTION
  "better_supabase"."audit_event_trusted"(text, text, text, text, text, text, uuid, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text, text, text, uuid,
  uuid, text);

DROP FUNCTION "better_supabase"."ledger_post"(uuid, text, jsonb, text, text, text, text, timestamp WITH time zone, jsonb, uuid);

ALTER TABLE "better_supabase"."accounting_entries"
  ADD COLUMN "memo_key" text;

ALTER TABLE "better_supabase"."accounting_entries"
  ADD COLUMN "memo_params" jsonb;

ALTER TABLE "better_supabase"."audit_events"
  ADD COLUMN "summary_key" text;

ALTER TABLE "better_supabase"."audit_events"
  ADD COLUMN "summary_params" jsonb;

ALTER TABLE "better_supabase"."ledger_transactions"
  ADD COLUMN "memo_key" text;

ALTER TABLE "better_supabase"."ledger_transactions"
  ADD COLUMN "memo_params" jsonb;

CREATE OR REPLACE FUNCTION api.audit_event (
  event_type           text,
  category             text  DEFAULT NULL::text,
  outcome              text  DEFAULT 'success'::text,
  source               text  DEFAULT NULL::text,
  target_type          text  DEFAULT NULL::text,
  record_id            text  DEFAULT NULL::text,
  tenant               uuid  DEFAULT NULL::uuid,
  metadata             jsonb DEFAULT '{}'::jsonb,
  idempotency_key      text  DEFAULT NULL::text,
  restricted           jsonb DEFAULT NULL::jsonb,
  actor_id             uuid  DEFAULT NULL::uuid,
  summary              text  DEFAULT NULL::text,
  target_label         text  DEFAULT NULL::text,
  correlation_id       text  DEFAULT NULL::text,
  actor_kind           text  DEFAULT NULL::text,
  actor_label          text  DEFAULT NULL::text,
  ip                   inet  DEFAULT NULL::inet,
  user_agent           text  DEFAULT NULL::text,
  session_id           text  DEFAULT NULL::text,
  request_id           text  DEFAULT NULL::text,
  scope                text  DEFAULT NULL::text,
  support_session      uuid  DEFAULT NULL::uuid,
  impersonated_by      uuid  DEFAULT NULL::uuid,
  impersonation_reason text  DEFAULT NULL::text,
  summary_key          text  DEFAULT NULL::text,
  summary_params       jsonb DEFAULT NULL::jsonb
)
  RETURNS text
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."audit_event"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21, $22, $23, $24, $25, $26) $function$;

CREATE OR REPLACE FUNCTION api.audit_event_trusted (
  event_type           text,
  category             text  DEFAULT NULL::text,
  outcome              text  DEFAULT 'success'::text,
  source               text  DEFAULT NULL::text,
  target_type          text  DEFAULT NULL::text,
  record_id            text  DEFAULT NULL::text,
  tenant               uuid  DEFAULT NULL::uuid,
  metadata             jsonb DEFAULT '{}'::jsonb,
  idempotency_key      text  DEFAULT NULL::text,
  restricted           jsonb DEFAULT NULL::jsonb,
  actor_id             uuid  DEFAULT NULL::uuid,
  summary              text  DEFAULT NULL::text,
  target_label         text  DEFAULT NULL::text,
  correlation_id       text  DEFAULT NULL::text,
  actor_kind           text  DEFAULT NULL::text,
  actor_label          text  DEFAULT NULL::text,
  ip                   inet  DEFAULT NULL::inet,
  user_agent           text  DEFAULT NULL::text,
  session_id           text  DEFAULT NULL::text,
  request_id           text  DEFAULT NULL::text,
  scope                text  DEFAULT NULL::text,
  support_session      uuid  DEFAULT NULL::uuid,
  impersonated_by      uuid  DEFAULT NULL::uuid,
  impersonation_reason text  DEFAULT NULL::text,
  summary_key          text  DEFAULT NULL::text,
  summary_params       jsonb DEFAULT NULL::jsonb
)
  RETURNS text
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."audit_event_trusted"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21, $22, $23, $24, $25, $26) $function$;

CREATE OR REPLACE FUNCTION better_supabase.accounting_asset_depreciation_lines (
  source_id text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'organizationId', y."tenant_id",
    'entryDate', (y."period_start" + interval '1 month' - interval '1 day')::date,
    'currency', a."currency",
    'reference', left(coalesce(a."tag" || ' ' || a."name", a."name"), 200),
    'memo', left('Depreciation of ' || a."name" || ' for ' || to_char(y."period_start", 'YYYY-MM'), 500), 'memoKey', 'accounting.asset_depreciation', 'memoParams', jsonb_build_object('asset', a."name", 'periodStart', y."period_start"),
    'lines', jsonb_build_array(
      jsonb_build_object('role', 'depreciation_expense', 'debit', y."amount"::text),
      jsonb_build_object('role', 'accumulated_depreciation', 'credit', y."amount"::text))
  )
  from "better_supabase"."asset_depreciations" y join "better_supabase"."assets" a on a."id" = y."asset_id"
  where y."id"::text = source_id
$function$;

CREATE OR REPLACE FUNCTION better_supabase.accounting_asset_disposal_lines (
  source_id text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'organizationId', a."tenant_id",
    'entryDate', a."disposed_on",
    'currency', a."currency",
    'reference', left(coalesce(a."tag" || ' ' || a."name", a."name"), 200),
    'memo', left('Disposal of ' || a."name", 500), 'memoKey', 'accounting.asset_disposal', 'memoParams', jsonb_build_object('asset', a."name"),
    'lines', jsonb_build_array(
      jsonb_build_object('role', 'bank', 'debit', a."disposal_amount"::text),
      jsonb_build_object('role', 'accumulated_depreciation', 'debit', q.total::text),
      jsonb_build_object('role', 'fixed_asset', 'credit', a."acquisition_cost"::text),
      jsonb_build_object('role', 'disposal_gain', 'credit', greatest(q.result, 0)::text),
      jsonb_build_object('role', 'disposal_loss', 'debit', greatest(-q.result, 0)::text))
  )
  from "better_supabase"."assets" a
  cross join lateral (
    select coalesce(sum(y."amount"), 0) as total,
      a."disposal_amount" + coalesce(sum(y."amount"), 0) - a."acquisition_cost" as result
    from "better_supabase"."asset_depreciations" y where y."asset_id" = a."id"
  ) q
  where a."id"::text = source_id and a."disposed_on" is not null and a."acquisition_cost" is not null
$function$;

CREATE OR REPLACE FUNCTION better_supabase.accounting_expense_reimbursement_lines (
  source_id text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'organizationId', v."tenant_id",
    'entryDate', (v."reimbursed_at" at time zone 'UTC')::date,
    'currency', v."currency",
    'reference', left(v."id"::text, 8),
    'memo', left('Reimbursed: ' || v."title", 500), 'memoKey', 'accounting.expense_reimbursement', 'memoParams', jsonb_build_object('title', v."title"),
    'lines', jsonb_build_array(
      jsonb_build_object('role', 'payable', 'debit', (select coalesce(sum(y."amount"), 0) from "better_supabase"."expense_lines" y where y."report_id" = v."id")::text, 'partyId', v."user_id"::text),
      jsonb_build_object('role', 'bank', 'credit', (select coalesce(sum(y."amount"), 0) from "better_supabase"."expense_lines" y where y."report_id" = v."id")::text))
  )
  from "better_supabase"."expense_reports" v
  where v."id"::text = source_id and v."cancelled_at" is null and v."reimbursed_at" is not null
$function$;

CREATE OR REPLACE FUNCTION better_supabase.accounting_expense_report_lines (
  source_id text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'organizationId', v."tenant_id",
    'entryDate', (v."approved_at" at time zone 'UTC')::date,
    'currency', v."currency",
    'reference', left(v."id"::text, 8),
    'memo', left('Expenses: ' || v."title", 500), 'memoKey', 'accounting.expense_report', 'memoParams', jsonb_build_object('title', v."title"),
    'lines', coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('role', 'expense', 'debit', g.amount::text, 'description', v."title", 'dimensions', nullif(g.dim, '{}'::jsonb))) order by g.dim::text)
        from (select coalesce(y."dimensions", '{}'::jsonb) as dim, sum(y."amount") as amount from "better_supabase"."expense_lines" y where y."report_id" = v."id" group by 1) g),
      jsonb_build_array(jsonb_build_object('role', 'expense', 'debit', (select coalesce(sum(y."amount"), 0) from "better_supabase"."expense_lines" y where y."report_id" = v."id")::text, 'description', v."title")))
      || jsonb_build_array(jsonb_build_object('role', 'payable', 'credit', (select coalesce(sum(y."amount"), 0) from "better_supabase"."expense_lines" y where y."report_id" = v."id")::text, 'partyId', v."user_id"::text))
  )
  from "better_supabase"."expense_reports" v
  where v."id"::text = source_id and v."cancelled_at" is null and v."approved_at" is not null
$function$;

CREATE OR REPLACE FUNCTION better_supabase.accounting_gift_lines (
  source_id text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'organizationId', v."tenant_id",
    'entryDate', v."received_on",
    'currency', v."currency",
    'memo', 'Gift', 'memoKey', 'accounting.gift', 'memoParams', '{}'::jsonb,
    'lines', jsonb_build_array(
      jsonb_build_object('role', 'bank', 'debit', v."amount"::text),
      jsonb_build_object('role', 'revenue', 'credit', v."amount"::text, 'partyId', v."donor_id"))
  )
  from "better_supabase"."donations" v
  where v."id"::text = source_id and v."status" = 'posted' and v."amount" <> 0
$function$;

CREATE OR REPLACE FUNCTION better_supabase.accounting_invoice_charge_lines (
  source_id text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'organizationId', inv."tenant_id",
    'entryDate', (c."created_at" at time zone 'UTC')::date,
    'currency', inv."currency",
    'reference', inv."identifier",
    'memo', 'Charge on ' || coalesce(inv."identifier", inv."title"), 'memoKey', 'accounting.invoice_charge', 'memoParams', jsonb_build_object('invoice', coalesce(inv."identifier", inv."title")),
    'lines', jsonb_build_array(
      jsonb_strip_nulls(jsonb_build_object('role', 'receivable', 'debit', c."amount"::text, 'partyId', inv."company_id"::text)),
      jsonb_strip_nulls(jsonb_build_object('role', 'revenue', 'credit', c."amount"::text, 'description', c."description")))
  )
  from "better_supabase"."invoice_charges" c
  join "better_supabase"."invoices" inv on inv."id" = c."invoice_id"
  where c."id"::text = source_id and c."amount" <> 0 and not (inv."direction" = 'purchase')
$function$;

CREATE OR REPLACE FUNCTION better_supabase.accounting_invoice_discount_lines (
  source_id text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'organizationId', y."tenant_id",
    'entryDate', (y."effective_at" at time zone 'UTC')::date,
    'currency', inv."currency",
    'reference', inv."identifier",
    'memo', 'Early payment discount on ' || coalesce(inv."identifier", inv."title"), 'memoKey', 'accounting.invoice_discount', 'memoParams', jsonb_build_object('invoice', coalesce(inv."identifier", inv."title")),
    'lines', case when inv."direction" = 'purchase' then jsonb_build_array(
        jsonb_strip_nulls(jsonb_build_object('role', 'payable', 'debit', d.amount::text, 'partyId', inv."company_id"::text)),
        jsonb_build_object('role', 'expense', 'credit', d.amount::text, 'description', 'Early payment discount'))
      else jsonb_build_array(
        jsonb_build_object('role', 'revenue', 'debit', d.amount::text, 'description', 'Early payment discount'),
        jsonb_strip_nulls(jsonb_build_object('role', 'receivable', 'credit', d.amount::text, 'partyId', inv."company_id"::text))) end
  )
  from "better_supabase"."ledger_transactions" y
  join "better_supabase"."invoices" inv on inv."id"::text = y."metadata" ->> 'invoiceId'
  cross join lateral (
    select sum(e."amount") as amount from "better_supabase"."ledger_entries" e
    join "better_supabase"."ledger_accounts" a on a."id" = e."account_id"
    where e."transaction_id" = y."id" and a."code" like 'invoices:discount:%'
  ) d
  where y."id"::text = source_id and y."reference_type" = 'invoices'
    and y."kind" = 'invoice.discount' and d.amount > 0
$function$;

CREATE OR REPLACE FUNCTION better_supabase.accounting_invoice_party_payment_lines (
  source_id text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'organizationId', y."tenant_id",
    'entryDate', (y."effective_at" at time zone 'UTC')::date,
    'currency', y."metadata" ->> 'currency',
    'reference', y."metadata" ->> 'reference',
    'memo', 'Payment on account', 'memoKey', 'accounting.invoice_party_payment', 'memoParams', '{}'::jsonb,
    'lines', jsonb_build_array(
      jsonb_build_object('role', 'bank', 'debit', p.amount::text),
      jsonb_build_object('role', 'receivable', 'credit', p.amount::text, 'partyId', y."metadata" ->> 'partyId'))
  )
  from "better_supabase"."ledger_transactions" y
  cross join lateral (
    select sum(e."amount") as amount from "better_supabase"."ledger_entries" e
    join "better_supabase"."ledger_accounts" a on a."id" = e."account_id"
    where e."transaction_id" = y."id" and a."code" = 'invoices:cash:' || (y."metadata" ->> 'currency')
  ) p
  where y."id"::text = source_id and y."reference_type" = 'invoices'
    and y."metadata" ? 'partyId' and not y."metadata" ? 'invoiceId' and p.amount <> 0
$function$;

CREATE OR REPLACE FUNCTION better_supabase.accounting_invoice_payment_lines (
  source_id text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'organizationId', inv."tenant_id",
    'entryDate', (y."effective_at" at time zone 'UTC')::date,
    'currency', inv."currency",
    'reference', coalesce(y."metadata" ->> 'reference', inv."identifier"),
    'memo', 'Payment of ' || coalesce(inv."identifier", inv."title"), 'memoKey', 'accounting.invoice_payment', 'memoParams', jsonb_build_object('invoice', coalesce(inv."identifier", inv."title")),
    'lines', jsonb_build_array(
      jsonb_build_object('role', 'bank', case when inv."direction" = 'purchase' then 'credit' else 'debit' end, p.amount::text),
      jsonb_strip_nulls(jsonb_build_object('role', case when inv."direction" = 'purchase' then 'payable' else 'receivable' end, case when inv."direction" = 'purchase' then 'debit' else 'credit' end, p.amount::text, 'partyId', inv."company_id"::text)))
  )
  from "better_supabase"."ledger_transactions" y
  join "better_supabase"."invoices" inv on inv."id"::text = y."metadata" ->> 'invoiceId'
  cross join lateral (
    select sum(e."amount") as amount from "better_supabase"."ledger_entries" e
    join "better_supabase"."ledger_accounts" a on a."id" = e."account_id"
    where e."transaction_id" = y."id" and a."code" = case when inv."direction" = 'purchase' then 'invoices:paid:' || inv."currency" else 'invoices:cash:' || inv."currency" end
  ) p
  where y."id"::text = source_id and y."reference_type" = 'invoices' and p.amount <> 0
$function$;

CREATE OR REPLACE FUNCTION better_supabase.accounting_invoice_write_off_lines (
  source_id text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'organizationId', inv."tenant_id",
    'currency', inv."currency",
    'reference', inv."identifier",
    'memo', 'Write-off of ' || coalesce(inv."identifier", inv."title"), 'memoKey', 'accounting.invoice_write_off', 'memoParams', jsonb_build_object('invoice', coalesce(inv."identifier", inv."title")),
    'lines', jsonb_build_array(
      jsonb_build_object('role', 'expense', 'debit', b.balance::text),
      jsonb_strip_nulls(jsonb_build_object('role', 'receivable', 'credit', b.balance::text, 'partyId', inv."company_id"::text)))
  )
  from "better_supabase"."invoices" inv
  cross join lateral (select inv."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = inv."id"), 0) - inv."credited_total" - inv."paid_total" as balance) b
  where inv."id"::text = source_id and b.balance > 0 and not (inv."direction" = 'purchase')
$function$;

CREATE OR REPLACE FUNCTION better_supabase.accounting_lease_payment_lines (
  source_id text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'organizationId', v."tenant_id",
    'entryDate', (y."effective_at" at time zone 'UTC')::date,
    'currency', v."currency",
    'reference', y."metadata" ->> 'reference',
    'memo', left('Rent payment: ' || coalesce(v."title", ''), 500), 'memoKey', 'accounting.lease_payment', 'memoParams', jsonb_build_object('lease', coalesce(v."title", '')),
    'lines', jsonb_build_array(
      jsonb_build_object('role', 'bank', 'debit', p.amount::text),
      jsonb_build_object('role', 'receivable', 'credit', p.amount::text, 'partyId', v."party_id"))
  )
  from "better_supabase"."ledger_transactions" y
  join "better_supabase"."leases" v on v."id"::text = y."reference_id"
  cross join lateral (
    select sum(e."amount") as amount from "better_supabase"."ledger_entries" e
    where e."transaction_id" = y."id" and e."amount" > 0
  ) p
  where y."id"::text = source_id and y."reference_type" = 'leases' and y."kind" = 'lease.payment'
    and p.amount <> 0
$function$;

CREATE OR REPLACE FUNCTION better_supabase.accounting_lease_rent_lines (
  source_id text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'organizationId', y."tenant_id",
    'entryDate', y."period_start",
    'currency', y."currency",
    'memo', left('Rent from ' || y."period_start"::text || ': ' || coalesce(v."title", ''), 500), 'memoKey', 'accounting.lease_rent', 'memoParams', jsonb_build_object('periodStart', y."period_start", 'lease', coalesce(v."title", '')),
    'lines', jsonb_build_array(
      jsonb_build_object('role', 'receivable', 'debit', y."amount"::text, 'partyId', v."party_id"),
      jsonb_build_object('role', 'revenue', 'credit', y."amount"::text))
  )
  from "better_supabase"."lease_charges" y join "better_supabase"."leases" v on v."id" = y."lease_id"
  where y."id"::text = source_id and y."amount" <> 0
$function$;

CREATE OR REPLACE FUNCTION better_supabase.accounting_post (
  entry_id uuid,
  closing  boolean DEFAULT false
)
  RETURNS better_supabase.accounting_entries
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."accounting_entries"%rowtype;
  v_settings "better_supabase"."accounting_settings"%rowtype;
  v_period "better_supabase"."accounting_periods"%rowtype;
  v_journal "better_supabase"."accounting_journals"%rowtype;
  v_total numeric;
  v_credits numeric;
  v_count integer;
  v_sequence integer;
begin
  select * into v_row from "better_supabase"."accounting_entries" y where y."id" = accounting_post.entry_id for update;
  if not found then
    raise exception 'entry not found' using errcode = 'P0002', hint = 'ACCOUNTING_ENTRY_NOT_FOUND';
  end if;
  if v_row."status" <> 'draft' then
    raise exception 'a posted entry can''t change; reverse it' using errcode = '55000', hint = 'ACCOUNTING_ENTRY_POSTED';
  end if;
  select * into v_settings from "better_supabase"."accounting_settings" st where st."tenant_id" = v_row."tenant_id";
  if not found then
    raise exception 'accounting isn''t set up for this organization; call setup_accounting first' using errcode = 'P0002', hint = 'ACCOUNTING_SETTING_NOT_FOUND';
  end if;
  select count(*), coalesce(sum(y."debit"), 0), coalesce(sum(y."credit"), 0) into v_count, v_total, v_credits
  from "better_supabase"."accounting_entry_lines" y where y."entry_id" = v_row."id";
  if v_count < 2 then
    raise exception 'an entry needs at least two lines' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
  end if;
  if v_total <> v_credits then
    raise exception 'the debits and credits of the entry differ in the functional currency' using errcode = '23514', hint = 'ACCOUNTING_ENTRY_UNBALANCED';
  end if;
  if exists (
    select 1 from "better_supabase"."accounting_entry_lines" y join "better_supabase"."accounting_accounts" z on z."id" = y."account_id"
    where y."entry_id" = v_row."id" and (z."archived_at" is not null or not z."active")
  ) then
    raise exception 'an account of the entry is archived or inactive' using errcode = '22023', hint = 'ACCOUNTING_ACCOUNT_INVALID';
  end if;
  if exists (
    select 1 from "better_supabase"."accounting_entry_lines" y, jsonb_each(y."dimensions") dim
    where y."entry_id" = v_row."id"
      and (jsonb_typeof(dim.value) <> 'string' or not exists (
        select 1 from "better_supabase"."accounting_dimensions" z join "better_supabase"."accounting_dimension_values" w on w."dimension_id" = z."id"
        where z."tenant_id" = v_row."tenant_id" and z."key" = dim.key
          and w."code" = dim.value #>> '{}' and w."archived_at" is null
      ))
  ) then
    raise exception 'a line names a dimension or value that doesn''t exist or is archived' using errcode = '22023', hint = 'ACCOUNTING_DIMENSION_INVALID';
  end if;
  select * into v_period from "better_supabase"."accounting_periods" y
  where y."tenant_id" = v_row."tenant_id" and v_row."entry_date" >= y."starts_on" and v_row."entry_date" <= y."ends_on";
  if not found then
    raise exception 'no period covers the entry date; open its fiscal year first' using errcode = 'P0002', hint = 'ACCOUNTING_PERIOD_NOT_FOUND';
  end if;
  if v_period."status" = 'locked' then
    raise exception 'the entry date is in a locked period' using errcode = '55000', hint = 'ACCOUNTING_PERIOD_LOCKED';
  end if;
  if not coalesce(accounting_post.closing, false) and (
    (v_period."status" = 'closed' and better_supabase.import_run() is null)
    or (v_settings."lock_date" is not null and v_row."entry_date" <= v_settings."lock_date")
  ) then
    raise exception 'the entry date is in a closed period or on or before the lock date' using errcode = '55000', hint = 'ACCOUNTING_PERIOD_CLOSED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_accounting_entry_post"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  select * into v_journal from "better_supabase"."accounting_journals" y where y."id" = v_row."journal_id";
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_journal."id"::text || ':' || v_period."fiscal_year"::text, 0));
  select coalesce(max(y."sequence"), 0) + 1 into v_sequence from "better_supabase"."accounting_entries" y
  where y."journal_id" = v_journal."id" and y."fiscal_year" = v_period."fiscal_year";
  update "better_supabase"."accounting_entries" y set "status" = 'posted', "fiscal_year" = v_period."fiscal_year", "sequence" = v_sequence,
    "number" = v_journal."code" || '-' || v_period."fiscal_year"::text || '-' || lpad(v_sequence::text, 5, '0'),
    "period_id" = v_period."id", "posted_at" = now(), "posted_by" = auth.uid(), "updated_at" = now()
  where y."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('accounting_entry.posted', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'journalId', v_row."journal_id", 'number', v_row."number", 'entryDate', v_row."entry_date", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'reversesId', v_row."reverses_id", 'total', v_total::text), 'accounting-entries/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/accounting');
  perform better_supabase.audit_event(
    event_type => 'accounting_entry.posted',
    category => 'data',
    target_type => 'accounting_entry',
    record_id => v_row."id"::text,
    target_label => v_row."number",
    summary => 'posted entry ' || v_row."number",
    summary_params => jsonb_build_object('number', v_row."number"),
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'journalId', v_row."journal_id", 'number', v_row."number", 'entryDate', v_row."entry_date", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'reversesId', v_row."reverses_id", 'total', v_total::text)
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_accounting_entry_post"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.accounting_post_source (
  source_type text,
  source_id   text
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_doc jsonb;
  v_kind text;
  v_tenant uuid;
  v_settings "better_supabase"."accounting_settings"%rowtype;
  v_journal "better_supabase"."accounting_journals"%rowtype;
  v_period "better_supabase"."accounting_periods"%rowtype;
  v_row "better_supabase"."accounting_entries"%rowtype;
  v_date date;
  v_line record;
  v_amount bigint;
  v_functional bigint;
  v_rate numeric;
  v_currency text;
  v_account uuid;
  v_tax "better_supabase"."tax_codes"%rowtype;
  v_diff bigint;
  v_largest integer;
  v_accounts uuid[] := '{}';
  v_functionals bigint[] := '{}';
  v_amounts bigint[] := '{}';
  v_currencies text[] := '{}';
  v_rates numeric[] := '{}';
  v_taxes uuid[] := '{}';
  v_parties uuid[] := '{}';
  v_dimensions jsonb[] := '{}';
  v_descriptions text[] := '{}';
begin
  if accounting_post_source.source_type is null or accounting_post_source.source_id is null
    or accounting_post_source.source_type not in ('stock_movement', 'invoice', 'invoice_payment', 'invoice_charge', 'invoice_discount', 'invoice_write_off', 'invoice_party_payment', 'asset_depreciation', 'asset_disposal', 'lease_rent', 'lease_payment', 'expense_report', 'expense_reimbursement', 'gift', 'production_order', 'bank_transaction', 'till_count', 'till_deposit') then
    raise exception 'no installed block books this source type' using errcode = '22023', hint = 'ACCOUNTING_SOURCE_INVALID';
  end if;
  v_doc := case accounting_post_source.source_type
    when 'stock_movement' then "better_supabase"."accounting_stock_movement_lines"(accounting_post_source.source_id)
    when 'invoice' then "better_supabase"."accounting_invoice_lines"(accounting_post_source.source_id)
    when 'invoice_payment' then "better_supabase"."accounting_invoice_payment_lines"(accounting_post_source.source_id)
    when 'invoice_charge' then "better_supabase"."accounting_invoice_charge_lines"(accounting_post_source.source_id)
    when 'invoice_discount' then "better_supabase"."accounting_invoice_discount_lines"(accounting_post_source.source_id)
    when 'invoice_write_off' then "better_supabase"."accounting_invoice_write_off_lines"(accounting_post_source.source_id)
    when 'invoice_party_payment' then "better_supabase"."accounting_invoice_party_payment_lines"(accounting_post_source.source_id)
    when 'asset_depreciation' then "better_supabase"."accounting_asset_depreciation_lines"(accounting_post_source.source_id)
    when 'asset_disposal' then "better_supabase"."accounting_asset_disposal_lines"(accounting_post_source.source_id)
    when 'lease_rent' then "better_supabase"."accounting_lease_rent_lines"(accounting_post_source.source_id)
    when 'lease_payment' then "better_supabase"."accounting_lease_payment_lines"(accounting_post_source.source_id)
    when 'expense_report' then "better_supabase"."accounting_expense_report_lines"(accounting_post_source.source_id)
    when 'expense_reimbursement' then "better_supabase"."accounting_expense_reimbursement_lines"(accounting_post_source.source_id)
    when 'gift' then "better_supabase"."accounting_gift_lines"(accounting_post_source.source_id)
    when 'production_order' then "better_supabase"."accounting_production_order_lines"(accounting_post_source.source_id)
    when 'bank_transaction' then "better_supabase"."accounting_bank_transaction_lines"(accounting_post_source.source_id)
    when 'till_count' then "better_supabase"."accounting_till_count_lines"(accounting_post_source.source_id)
    when 'till_deposit' then "better_supabase"."accounting_till_deposit_lines"(accounting_post_source.source_id)
  end;
  v_kind := case accounting_post_source.source_type
    when 'stock_movement' then 'general'
    when 'invoice' then 'sales'
    when 'invoice_payment' then 'bank'
    when 'invoice_charge' then 'sales'
    when 'invoice_discount' then 'general'
    when 'invoice_write_off' then 'general'
    when 'invoice_party_payment' then 'bank'
    when 'asset_depreciation' then 'general'
    when 'asset_disposal' then 'general'
    when 'lease_rent' then 'sales'
    when 'lease_payment' then 'bank'
    when 'expense_report' then 'purchase'
    when 'expense_reimbursement' then 'bank'
    when 'gift' then 'bank'
    when 'production_order' then 'general'
    when 'bank_transaction' then 'bank'
    when 'till_count' then 'cash'
    when 'till_deposit' then 'bank'
  end;
  if v_doc is null or jsonb_typeof(v_doc -> 'lines') is distinct from 'array' then
    return null;
  end if;
  v_tenant := (v_doc ->> 'organizationId')::uuid;
  select * into v_settings from "better_supabase"."accounting_settings" y where y."tenant_id" = v_tenant;
  if not found then
    return null;
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'accounting-source:' || v_tenant::text || ':' || accounting_post_source.source_type || ':' || accounting_post_source.source_id, 0));
  select * into v_row from "better_supabase"."accounting_entries" y
  where y."tenant_id" = v_tenant and y."source_type" = accounting_post_source.source_type
    and y."source_id" = accounting_post_source.source_id and y."status" <> 'reversed';
  if found then
    return v_row."id";
  end if;
  v_date := coalesce((v_doc ->> 'entryDate')::date, current_date);
  v_kind := coalesce(v_doc ->> 'journal', v_kind);
  if coalesce(v_doc ->> 'journalId', '') ~ '^[0-9a-fA-F-]{36}$' then
    select * into v_journal from "better_supabase"."accounting_journals" y
    where y."tenant_id" = v_tenant and y."id" = (v_doc ->> 'journalId')::uuid;
  end if;
  if v_journal."id" is null then
    select * into v_journal from "better_supabase"."accounting_journals" y
    where y."tenant_id" = v_tenant and y."type" = v_kind order by y."code" limit 1;
  end if;
  if v_journal."id" is null then
    raise exception 'the organization has no journal of the type this document books in' using errcode = 'P0002', hint = 'ACCOUNTING_JOURNAL_NOT_FOUND';
  end if;
  for v_line in select q.value from jsonb_array_elements(v_doc -> 'lines') q loop
    v_amount := coalesce((v_line.value ->> 'debit')::bigint, 0) - coalesce((v_line.value ->> 'credit')::bigint, 0);
    continue when v_amount = 0;
    v_tax := null;
    if v_line.value ->> 'taxCode' is not null then
      select * into v_tax from "better_supabase"."tax_codes" y
      where y."tenant_id" = v_tenant and y."code" = v_line.value ->> 'taxCode' and y."archived_at" is null
      order by y."legal_entity_id" nulls first limit 1;
    end if;
    if v_tax."id" is null and coalesce(v_line.value ->> 'taxRateBps', '') ~ '^[0-9]{1,6}$' then
      select * into v_tax from "better_supabase"."tax_codes" y
      where y."tenant_id" = v_tenant and "better_supabase"."tax_rate_on"(y."id", v_date) = (v_line.value ->> 'taxRateBps')::integer
        and y."type" = case when v_journal."type" = 'purchase' then 'purchase' else 'sales' end
        and y."archived_at" is null
      order by y."legal_entity_id" nulls first, y."code" limit 1;
    end if;
    v_account := null;
    if v_line.value ->> 'role' in ('tax_payable', 'tax_receivable') and v_tax."id" is not null then
      v_account := case when v_tax."type" = 'purchase' then v_tax."purchase_account_id"
        else coalesce(v_tax."sales_account_id", v_tax."purchase_account_id") end;
    elsif coalesce(v_line.value ->> 'accountId', '') ~ '^[0-9a-fA-F-]{36}$' then
      select y."id" into v_account from "better_supabase"."accounting_accounts" y where y."id" = (v_line.value ->> 'accountId')::uuid and y."tenant_id" = v_tenant and y."archived_at" is null;
    elsif v_line.value ->> 'accountCode' is not null then
      select y."id" into v_account from "better_supabase"."accounting_accounts" y where y."code" = v_line.value ->> 'accountCode' and y."tenant_id" = v_tenant and y."archived_at" is null;
    elsif v_line.value ->> 'role' is not null then
      select y."id" into v_account from "better_supabase"."accounting_account_roles" z join "better_supabase"."accounting_accounts" y on y."id" = z."account_id"
      where z."tenant_id" = v_tenant and z."role" = v_line.value ->> 'role' and y."archived_at" is null;
    end if;
    if v_account is null then
      select y."id" into v_account from "better_supabase"."accounting_account_roles" z join "better_supabase"."accounting_accounts" y on y."id" = z."account_id"
      where z."tenant_id" = v_tenant and z."role" = 'suspense' and y."archived_at" is null;
    end if;
    if v_account is null then
      raise exception 'no account plays the role a document line needs, and no account plays suspense' using errcode = 'P0002', hint = 'ACCOUNTING_ROLE_UNMAPPED';
    end if;
    v_currency := upper(coalesce(v_line.value ->> 'currency', v_doc ->> 'currency', v_settings."functional_currency"));
    v_rate := null;
    v_functional := v_amount;
    if v_currency <> v_settings."functional_currency" then
      v_rate := "better_supabase"."accounting_fx_rate"(v_tenant, v_currency, v_settings."functional_currency", v_date);
      v_functional := round(v_amount * v_rate)::bigint;
      continue when v_functional = 0;
    end if;
    v_accounts := v_accounts || v_account;
    v_functionals := v_functionals || v_functional;
    v_amounts := v_amounts || v_amount;
    v_currencies := v_currencies || v_currency;
    v_rates := v_rates || v_rate;
    v_taxes := v_taxes || v_tax."id";
    v_parties := v_parties || case when coalesce(v_line.value ->> 'partyId', '') ~ '^[0-9a-fA-F-]{36}$' then (v_line.value ->> 'partyId')::uuid end;
    v_dimensions := v_dimensions || case when jsonb_typeof(v_line.value -> 'dimensions') = 'object' then v_line.value -> 'dimensions' else '{}'::jsonb end;
    v_descriptions := v_descriptions || left(nullif(trim(v_line.value ->> 'description'), ''), 500);
  end loop;
  if coalesce(array_length(v_accounts, 1), 0) < 2 then
    return null;
  end if;
  -- Converting each line rounds on its own; the difference goes to the
  -- largest line on the side that is short.
  select coalesce(sum(u), 0) into v_diff from unnest(v_functionals) u;
  if v_diff <> 0 then
    select q.n into v_largest from unnest(v_functionals) with ordinality q(amount, n)
    where sign(q.amount) = -sign(v_diff) order by abs(q.amount) desc limit 1;
    if v_largest is null then
      raise exception 'the document''s lines don''t balance' using errcode = '23514', hint = 'ACCOUNTING_ENTRY_UNBALANCED';
    end if;
    v_functionals[v_largest] := v_functionals[v_largest] - v_diff;
  end if;
  insert into "better_supabase"."accounting_entries" ("tenant_id", "journal_id", "entry_date", "reference", "source_type", "source_id", "memo", "memo_key", "memo_params", "created_by", "period_id")
  values (v_tenant, v_journal."id", v_date, left(nullif(trim(v_doc ->> 'reference'), ''), 200),
    accounting_post_source.source_type, accounting_post_source.source_id, left(nullif(trim(v_doc ->> 'memo'), ''), 2000), nullif(v_doc ->> 'memoKey', ''), case when jsonb_typeof(v_doc -> 'memoParams') = 'object' then v_doc -> 'memoParams' end, auth.uid(),
    (select y."id" from "better_supabase"."accounting_periods" y where y."tenant_id" = v_tenant and v_date >= y."starts_on" and v_date <= y."ends_on"))
  returning * into v_row;
  insert into "better_supabase"."accounting_entry_lines" ("tenant_id", "entry_id", "position", "account_id", "debit", "credit", "currency",
    "amount_currency", "fx_rate", "tax_code_id", "party_id", "dimensions", "description")
  select v_tenant, v_row."id", u.n, u.account, greatest(u.functional, 0), greatest(-u.functional, 0), u.currency,
    case when u.rate is null then u.functional else u.amount end, u.rate, u.tax, u.party, u.dimensions, u.description
  from unnest(v_accounts, v_functionals, v_amounts, v_currencies, v_rates, v_taxes, v_parties, v_dimensions, v_descriptions)
    with ordinality u(account, functional, amount, currency, rate, tax, party, dimensions, description, n);
  select * into v_period from "better_supabase"."accounting_periods" y where y."id" = v_row."period_id";
  if found and v_period."status" = 'open'
    and (v_settings."lock_date" is null or v_date > v_settings."lock_date") then
    perform "better_supabase"."accounting_post"(v_row."id");
  end if;
  return v_row."id";
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.accounting_production_order_lines (
  source_id text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'organizationId', x."tenant_id",
    'entryDate', (x."completed_at" at time zone 'UTC')::date,
    'currency', x."currency",
    'reference', x."number",
    'memo', 'Production labor ' || x."number", 'memoKey', 'accounting.production_order', 'memoParams', jsonb_build_object('number', x."number"),
    'lines', jsonb_build_array(
      jsonb_build_object('role', 'work_in_progress', 'debit', x."labor_cost"::text),
      jsonb_build_object('role', 'expense', 'credit', x."labor_cost"::text))
  )
  from "better_supabase"."production_orders" x
  where x."id"::text = source_id and x."status" = 'done' and x."labor_cost" > 0
$function$;

CREATE OR REPLACE FUNCTION better_supabase.accounting_reverse (
  entry_id   uuid,
  entry_date date DEFAULT NULL::date
)
  RETURNS better_supabase.accounting_entries
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."accounting_entries"%rowtype;
  v_reversal "better_supabase"."accounting_entries"%rowtype;
begin
  select * into v_row from "better_supabase"."accounting_entries" y where y."id" = accounting_reverse.entry_id for update;
  if not found then
    raise exception 'entry not found' using errcode = 'P0002', hint = 'ACCOUNTING_ENTRY_NOT_FOUND';
  end if;
  if v_row."status" = 'reversed' then
    raise exception 'the entry is already reversed' using errcode = '55000', hint = 'ACCOUNTING_ENTRY_REVERSED';
  end if;
  if v_row."status" <> 'posted' then
    raise exception 'only a posted entry can be reversed; delete a draft instead' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_accounting_entry_reverse"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  insert into "better_supabase"."accounting_entries" ("tenant_id", "journal_id", "entry_date", "reference", "reverses_id", "memo", "memo_key", "memo_params", "created_by")
  values (v_row."tenant_id", v_row."journal_id", coalesce(accounting_reverse.entry_date, v_row."entry_date"), v_row."number",
    v_row."id", 'Reversal of ' || v_row."number", 'accounting.reversal', jsonb_build_object('number', v_row."number"), auth.uid())
  returning * into v_reversal;
  insert into "better_supabase"."accounting_entry_lines" ("tenant_id", "entry_id", "position", "account_id", "debit", "credit", "currency",
    "amount_currency", "fx_rate", "tax_code_id", "party_id", "dimensions", "description")
  select y."tenant_id", v_reversal."id", y."position", y."account_id", y."credit", y."debit", y."currency",
    -y."amount_currency", y."fx_rate", y."tax_code_id", y."party_id", y."dimensions", y."description"
  from "better_supabase"."accounting_entry_lines" y where y."entry_id" = v_row."id";
  v_reversal := "better_supabase"."accounting_post"(v_reversal."id");
  update "better_supabase"."accounting_entries" y set "status" = 'reversed', "updated_at" = now() where y."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('accounting_entry.reversed', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'journalId', v_row."journal_id", 'number', v_row."number", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'reversalId', v_reversal."id"), 'accounting-entries/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/accounting');
  perform better_supabase.audit_event(
    event_type => 'accounting_entry.reversed',
    category => 'data',
    target_type => 'accounting_entry',
    record_id => v_row."id"::text,
    target_label => v_row."number",
    summary => 'reversed entry ' || v_row."number" || ' with ' || v_reversal."number",
    summary_params => jsonb_build_object('number', v_row."number", 'reversalNumber', v_reversal."number"),
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'journalId', v_row."journal_id", 'number', v_row."number", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'reversalId', v_reversal."id")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_accounting_entry_reverse"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return v_reversal;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.accounting_stock_movement_lines (
  source_id text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'organizationId', y."tenant_id",
    'entryDate', (y."effective_at" at time zone 'UTC')::date,
    'currency', a."unit",
    'reference', y."reference_id",
    'memo', 'Stock ' || (y."metadata" ->> 'reason'), 'memoKey', 'accounting.stock_movement', 'memoParams', jsonb_build_object('reason', y."metadata" ->> 'reason'),
    'lines', jsonb_build_array(
      jsonb_build_object('role', 'inventory', 'debit', e."amount"::text),
      jsonb_build_object('role', case y."metadata" ->> 'reason' when 'receipt' then 'payable' when 'sale' then 'cogs' when 'return' then 'cogs'
        when 'consumption' then 'work_in_progress' when 'production' then 'work_in_progress' else 'expense' end,
        'credit', e."amount"::text))
  )
  from "better_supabase"."ledger_transactions" y
  join "better_supabase"."ledger_entries" e on e."transaction_id" = y."id"
  join "better_supabase"."ledger_accounts" a on a."id" = e."account_id" and a."kind" = 'stock_value'
  where y."id"::text = source_id and e."amount" <> 0
  limit 1
$function$;

CREATE OR REPLACE FUNCTION better_supabase.accounting_till_count_lines (
  source_id text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'organizationId', v."tenant_id",
    'entryDate', (v."counted_at" at time zone 'UTC')::date,
    'currency', x."currency",
    'reference', left(v."session_id"::text, 8),
    'memo', left('Till count: ' || x."name", 500), 'memoKey', 'accounting.till_count', 'memoParams', jsonb_build_object('till', x."name"),
    'lines', case when v."variance_amount" > 0 then jsonb_build_array(
      jsonb_build_object('accountId', x."account_id", 'debit', v."variance_amount"::text),
      jsonb_build_object('role', 'suspense', 'credit', v."variance_amount"::text))
    else jsonb_build_array(
      jsonb_build_object('role', 'suspense', 'debit', (-v."variance_amount")::text),
      jsonb_build_object('accountId', x."account_id", 'credit', (-v."variance_amount")::text))
    end
  )
  from "better_supabase"."till_counts" v
  join "better_supabase"."till_sessions" y on y."id" = v."session_id"
  join "better_supabase"."tills" x on x."id" = y."till_id"
  where v."id"::text = source_id and v."variance_amount" <> 0 and x."account_id" is not null
$function$;

CREATE OR REPLACE FUNCTION better_supabase.accounting_till_deposit_lines (
  source_id text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'organizationId', v."tenant_id",
    'entryDate', v."deposited_on",
    'currency', x."currency",
    'reference', left(coalesce(v."reference", v."id"::text), 100),
    'memo', left('Cash deposit: ' || x."name", 500), 'memoKey', 'accounting.till_deposit', 'memoParams', jsonb_build_object('till', x."name"),
    'lines', jsonb_build_array(
      jsonb_build_object('role', 'bank', 'debit', v."amount"::text),
      jsonb_build_object('accountId', x."account_id", 'credit', v."amount"::text))
  )
  from "better_supabase"."till_deposits" v
  join "better_supabase"."till_sessions" y on y."id" = v."session_id"
  join "better_supabase"."tills" x on x."id" = y."till_id"
  where v."id"::text = source_id and x."account_id" is not null
$function$;

CREATE OR REPLACE FUNCTION better_supabase.activate_lease (
  lease_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."leases"%rowtype;
  v_account uuid;
  v_hold "better_supabase"."ledger_holds"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."leases" x where x."id" = activate_lease.lease_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leases.manage'), false)) then
    raise exception 'no such lease you can read' using errcode = 'P0002', hint = 'LEASE_NOT_FOUND';
  end if;
  if v_row."status" <> 'draft' then
    raise exception 'only a draft lease can be activated' using errcode = '55000', hint = 'LEASE_STATUS_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('leases.unit:' || v_row."unit_id"::text, 0));
  if exists (
    select 1 from "better_supabase"."leases" x
    where x."unit_id" = v_row."unit_id" and x."id" <> v_row."id" and x."status" = 'active'
      and daterange(x."starts_on", x."ends_on") && daterange(v_row."starts_on", v_row."ends_on")
  ) then
    raise exception 'another active lease of this unit overlaps these dates' using errcode = '23P01', hint = 'LEASE_OVERLAP';
  end if;
  if v_row."deposit" > 0 then
    v_account := "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_deposit', 'leases.deposit:' || v_row."id"::text, 'Deposit ' || v_row."title",
      v_row."currency"::text, 0::smallint, 'lease', v_row."id"::text, null, false, 'leases.read', 'leases',
      jsonb_build_object('leaseId', v_row."id"));
    perform "better_supabase"."ledger_post"(v_row."tenant_id", 'lease.deposit',
      jsonb_build_array(
        jsonb_build_object('account', v_account, 'amount', v_row."deposit"),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_cash', 'leases.cash:' || v_row."currency", 'Rent received ' || v_row."currency",
      v_row."currency"::text, 0::smallint, null, null, null, true, 'leases.read', 'leases', null), 'amount', -v_row."deposit")),
      'leases', v_row."id"::text, 'Deposit received', 'leases.deposit:' || v_row."id"::text, null,
      jsonb_build_object('leaseId', v_row."id"),
      memo_key => 'lease.deposit', memo_params => '{}'::jsonb);
    v_hold := "better_supabase"."ledger_hold"(v_account, v_row."deposit", 'leases', v_row."id"::text, null);
  end if;
  update "better_supabase"."leases" x set "status" = 'active', "deposit_hold_id" = v_hold."id", "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  perform "better_supabase".emit_event('lease.activated', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'unitId', v_row."unit_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'status', v_row."status", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'rent', v_row."rent"::text, 'currency', v_row."currency"), 'leases/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/leases');
  perform better_supabase.audit_event(
    event_type => 'lease.activated',
    category => 'billing',
    target_type => 'lease',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'activated a lease',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'unitId', v_row."unit_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'status', v_row."status", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'rent', v_row."rent"::text, 'currency', v_row."currency")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'unitId', v_row."unit_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'title', v_row."title", 'status', v_row."status", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'rent', v_row."rent"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'deposit', v_row."deposit"::text, 'depositHoldId', v_row."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = v_row."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = v_row."tenant_id" and x."code" = 'leases.rent:' || v_row."id"::text), 0)::text, 'renewedAt', v_row."renewed_at", 'terminatedOn', v_row."terminated_on", 'terminationReason', v_row."termination_reason", 'metadata', v_row."metadata", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.adjust_leave_balance (
  tenant  uuid,
  user_id uuid,
  type_id uuid,
  amount  numeric,
  period  integer DEFAULT NULL::integer,
  kind    text    DEFAULT 'adjustment'::text,
  note    text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_period integer := coalesce(adjust_leave_balance.period, extract(year from current_date)::integer);
  v_transaction uuid;
  v_entry uuid;
  v_row jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', adjust_leave_balance.tenant, 'leave.manage'), false)) then
    raise exception 'not allowed to adjust leave balances' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  if coalesce(adjust_leave_balance.kind, 'adjustment') not in ('grant', 'adjustment') then
    raise exception 'kind must be grant or adjustment' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  if adjust_leave_balance.amount is null or adjust_leave_balance.amount = 0 then
    raise exception 'amount must not be zero' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  if not exists (select 1 from "public"."memberships" m where m."organization_id" = adjust_leave_balance.tenant and m."user_id" = adjust_leave_balance.user_id) then
    raise exception 'the user is not a member of this organization' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  if not exists (select 1 from "better_supabase"."leave_types" t where t."id" = adjust_leave_balance.type_id and t."tenant_id" = adjust_leave_balance.tenant) then
    raise exception 'leave type not found' using errcode = 'P0002', hint = 'LEAVE_TYPE_NOT_FOUND';
  end if;
  v_transaction := "better_supabase"."leave_post"(adjust_leave_balance.tenant, adjust_leave_balance.user_id, adjust_leave_balance.type_id,
    coalesce(adjust_leave_balance.kind, 'adjustment'), adjust_leave_balance.amount, v_period, null, adjust_leave_balance.note);
  select y."id", jsonb_build_object('id', y."id", 'organizationId', x."tenant_id", 'userId', x."owner_id",
      'typeId', (x."metadata" ->> 'typeId')::uuid, 'kind', substr(r."kind", 7), 'amount', (y."amount"::numeric / 100)::numeric(10, 2)::text,
      'period', (x."metadata" ->> 'period')::integer,
      'requestId', case when r."reference_type" = 'leave-requests' then r."reference_id"::uuid end,
      'note', r."memo", 'createdAt', y."created_at") into v_entry, v_row
  from "better_supabase"."ledger_entries" y
    join "better_supabase"."ledger_accounts" x on x."id" = y."account_id" and x."managed_by" = 'leave' and x."kind" = 'leave'
    join "better_supabase"."ledger_transactions" r on r."id" = y."transaction_id"
  where y."transaction_id" = v_transaction and x."owner_id" = adjust_leave_balance.user_id;
  perform "better_supabase".emit_event('leave_balance.adjusted', jsonb_build_object('organizationId', adjust_leave_balance.tenant, 'id', v_entry, 'userId', adjust_leave_balance.user_id, 'typeId', adjust_leave_balance.type_id, 'kind', coalesce(adjust_leave_balance.kind, 'adjustment'), 'amount', adjust_leave_balance.amount::numeric(8, 2)::text, 'period', v_period), 'leave-ledger-entries/' || v_entry::text, (adjust_leave_balance.tenant)::text, null, 'better-supabase/leave');
  perform better_supabase.audit_event(
    event_type => 'leave_balance.adjusted',
    category => 'data',
    target_type => 'leave_balance',
    record_id => v_entry::text,
    summary => 'adjusted a leave balance by ' || adjust_leave_balance.amount::numeric(8, 2)::text,
    summary_params => jsonb_build_object('amount', adjust_leave_balance.amount),
    tenant => (adjust_leave_balance.tenant)::uuid,
    metadata => jsonb_build_object('organizationId', adjust_leave_balance.tenant, 'id', v_entry, 'userId', adjust_leave_balance.user_id, 'typeId', adjust_leave_balance.type_id, 'kind', coalesce(adjust_leave_balance.kind, 'adjustment'), 'amount', adjust_leave_balance.amount::numeric(8, 2)::text, 'period', v_period)
  );
  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.approve_expense_report (
  report_id uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_lines jsonb;
  v_tx uuid;
begin
  select * into v_row from "better_supabase"."expense_reports" x
    where x."id" = approve_expense_report.report_id and x."approved_at" is null and x."cancelled_at" is null
    for update;
  if not found then
    return;
  end if;
  select jsonb_agg(jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'expense', 'expenses:category:' || c."key" || ':' || v_row."currency", 'Expenses: ' || c."name", v_row."currency"::text, 0::smallint, null, null, null, true, 'expenses.read', 'expenses', null), 'amount', q.total) order by c."key")
    into v_lines
  from (
    select l."category_id" as category, sum(l."amount") as total
    from "better_supabase"."expense_lines" l where l."report_id" = v_row."id" group by l."category_id"
  ) q join "better_supabase"."expense_categories" c on c."id" = q.category;
  v_lines := v_lines || jsonb_build_array(jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'expense_payable', 'expenses:payable:' || v_row."user_id"::text || ':' || v_row."currency", 'Expenses owed ' || v_row."currency", v_row."currency"::text, 0::smallint, 'users', v_row."user_id"::text, v_row."user_id", true, 'expenses.read', 'expenses', null), 'amount', -coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)));
  v_tx := "better_supabase"."ledger_post"(v_row."tenant_id", 'expense.approved', v_lines,
    'expenses', v_row."id"::text, left('Expenses: ' || v_row."title", 500), 'expense:' || v_row."id"::text || ':approved', null,
    jsonb_build_object('reportId', v_row."id", 'userId', v_row."user_id"),
    memo_key => 'expense.approved', memo_params => jsonb_build_object('title', v_row."title"));
  update "better_supabase"."expense_reports" x set "approved_at" = now(), "approval_transaction_id" = v_tx, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not better_supabase.import_run() is not null then
    perform "better_supabase"."accounting_post_source"('expense_report', v_row."id"::text);
  end if;
  perform "better_supabase".emit_event('expense_report.approved', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'currency', v_row."currency", 'transactionId', v_tx), 'expense-reports/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/expenses');
  perform better_supabase.audit_event(
    event_type => 'expense_report.approved',
    category => 'billing',
    target_type => 'expense_report',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'approved an expense report',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'currency', v_row."currency", 'transactionId', v_tx)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.audit_event (
  event_type           text,
  category             text  DEFAULT NULL::text,
  outcome              text  DEFAULT 'success'::text,
  source               text  DEFAULT NULL::text,
  target_type          text  DEFAULT NULL::text,
  record_id            text  DEFAULT NULL::text,
  tenant               uuid  DEFAULT NULL::uuid,
  metadata             jsonb DEFAULT '{}'::jsonb,
  idempotency_key      text  DEFAULT NULL::text,
  restricted           jsonb DEFAULT NULL::jsonb,
  actor_id             uuid  DEFAULT NULL::uuid,
  summary              text  DEFAULT NULL::text,
  target_label         text  DEFAULT NULL::text,
  correlation_id       text  DEFAULT NULL::text,
  actor_kind           text  DEFAULT NULL::text,
  actor_label          text  DEFAULT NULL::text,
  ip                   inet  DEFAULT NULL::inet,
  user_agent           text  DEFAULT NULL::text,
  session_id           text  DEFAULT NULL::text,
  request_id           text  DEFAULT NULL::text,
  scope                text  DEFAULT NULL::text,
  support_session      uuid  DEFAULT NULL::uuid,
  impersonated_by      uuid  DEFAULT NULL::uuid,
  impersonation_reason text  DEFAULT NULL::text,
  summary_key          text  DEFAULT NULL::text,
  summary_params       jsonb DEFAULT NULL::jsonb
)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  existing text;
  v_integration boolean := better_supabase.import_run() is not null;
  entry_id "better_supabase"."audit_events"."id"%type;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if restricted is not null or ip is not null or user_agent is not null or session_id is not null then
    raise exception 'audit_event got restricted details, and the audit module has no restricted table'
      using errcode = '22023', hint = 'Set blocks.audit.options.restricted to true.';
  end if;
  -- imports.audit 'summary' (ADR 0141): the run audits per entity at its end.
  if v_integration and current_setting('better_supabase.import_audit', true) = 'summary' then
    return null;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    actor_id := auth.uid();
    actor_kind := null;
    actor_label := null;
    ip := null;
    user_agent := null;
    session_id := null;
    request_id := null;
    scope := null;
    if (select auth.jwt()) -> 'act' is not null or impersonated_by is distinct from auth.uid() then
      support_session := null;
      impersonated_by := null;
      impersonation_reason := null;
    end if;
  elsif actor_id is null then
    actor_id := coalesce(auth.uid(), better_supabase.acting_member());
  end if;
  if idempotency_key is not null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('better_supabase.audit_event'), pg_catalog.hashtext(coalesce(tenant::text, '') || ':' || idempotency_key));
    select l."id"::text into existing
    from "better_supabase"."audit_events" l
    where l."idempotency_key" = audit_event.idempotency_key
      and l."tenant_id" is not distinct from audit_event.tenant
    limit 1;
    if existing is not null then
      return existing;
    end if;
  end if;
  insert into "better_supabase"."audit_events" ("table_name", "record_id", "op", "actor_id", "actor_role", "tenant_id", "impersonated_by", "impersonation_reason", "support_session_id", "event_type", "category", "outcome", "source", "target_type", "metadata", "idempotency_key", "actor_kind", "actor_label", "tenant_label", "target_label", "summary", "summary_key", "summary_params", "request_id", "correlation_id", "scope")
  values (
    null,
    record_id,
    'event',
    actor_id,
    coalesce(auth.jwt() ->> 'role', current_user),
    tenant,
    coalesce(audit_event.impersonated_by, case when auth.jwt() -> 'act' ->> 'sub' ~ '^[0-9a-f-]{36}$' then (auth.jwt() -> 'act' ->> 'sub')::uuid end),
    coalesce(audit_event.impersonation_reason, auth.jwt() -> 'act' ->> 'reason'),
    coalesce(audit_event.support_session, case when auth.jwt() -> 'act' ->> 'session_id' ~ '^[0-9a-f-]{36}$' then (auth.jwt() -> 'act' ->> 'session_id')::uuid end),
    event_type,
    coalesce(category, 'system'),
    coalesce(outcome, 'success'),
    coalesce(source, 'app'),
    target_type,
    coalesce(metadata, '{}'),
    idempotency_key,
    coalesce(actor_kind, case
      when v_integration then 'integration'
      when coalesce(auth.jwt() ->> 'role', '') = 'service_role' then 'service'
      when auth.jwt() -> 'act' ->> 'kind' = 'support' then 'support'
      when auth.jwt() -> 'act' is not null then 'impersonation'
      when auth.jwt() ->> 'client_id' is not null then 'oauth-client'
      when auth.uid() is not null then 'user'
      else 'system'
    end),
    coalesce(actor_label, coalesce(auth.jwt() -> 'user_metadata' ->> 'full_name', auth.jwt() ->> 'email')),
    (select o."name"::text from "public"."organizations" o where o."id" = tenant),
    target_label,
    summary,
    coalesce(summary_key, event_type),
    summary_params,
    coalesce(better_supabase.request_id_or_null(request_id), coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.request_id', true)), better_supabase.request_id_or_null(better_supabase.request_header('x-request-id')))),
    coalesce(better_supabase.request_id_or_null(correlation_id), coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.correlation_id', true)), better_supabase.request_id_or_null(better_supabase.request_header('x-correlation-id')))),
    coalesce(audit_event.scope, case when tenant is null then 'platform' else 'tenant' end)
  )
  returning "id" into entry_id;
  if audit_event.target_type is not null and audit_event.record_id is not null then
    perform pg_catalog.set_config('better_supabase.recorded', coalesce(pg_catalog.current_setting('better_supabase.recorded', true), '') || E'\n' || audit_event.target_type || ':' || audit_event.record_id, true);
  end if;
  return entry_id::text;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.audit_event_many (
  events jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  batch_event jsonb;
  results jsonb := '[]';
  batch_result text;
  failed_state text;
  failed_message text;
  failed_hint text;
begin
  if pg_catalog.jsonb_typeof(events) is distinct from 'array' then
    raise exception 'audit_event_many takes a jsonb array of events'
      using errcode = '22023', hint = 'AUDIT_BATCH_NOT_ARRAY';
  end if;
  if pg_catalog.jsonb_array_length(events) > 1000 then
    raise exception 'audit_event_many got % events, more than 1000', pg_catalog.jsonb_array_length(events)
      using errcode = '22023', hint = 'AUDIT_BATCH_TOO_LARGE';
  end if;
  for batch_event in select e from pg_catalog.jsonb_array_elements(events) e loop
    begin
      batch_result := better_supabase.audit_event(
        event_type => batch_event ->> 'event_type',
        category => batch_event ->> 'category',
        outcome => coalesce(batch_event ->> 'outcome', 'success'),
        source => batch_event ->> 'source',
        target_type => batch_event ->> 'target_type',
        record_id => batch_event ->> 'record_id',
        tenant => (batch_event ->> 'tenant')::uuid,
        metadata => coalesce(nullif(batch_event -> 'metadata', 'null'::jsonb), '{}'),
        idempotency_key => batch_event ->> 'idempotency_key',
        restricted => nullif(batch_event -> 'restricted', 'null'::jsonb),
        actor_id => (batch_event ->> 'actor_id')::uuid,
        summary => batch_event ->> 'summary',
        target_label => batch_event ->> 'target_label',
        correlation_id => batch_event ->> 'correlation_id',
        actor_kind => batch_event ->> 'actor_kind',
        actor_label => batch_event ->> 'actor_label',
        ip => (batch_event ->> 'ip')::inet,
        user_agent => batch_event ->> 'user_agent',
        session_id => batch_event ->> 'session_id',
        request_id => batch_event ->> 'request_id',
        scope => batch_event ->> 'scope',
        support_session => (batch_event ->> 'support_session')::uuid,
        impersonated_by => (batch_event ->> 'impersonated_by')::uuid,
        impersonation_reason => batch_event ->> 'impersonation_reason',
        summary_key => batch_event ->> 'summary_key',
        summary_params => nullif(batch_event -> 'summary_params', 'null'::jsonb)
      );
      results := results || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('id', batch_result));
    exception when others then
      get stacked diagnostics
        failed_state = returned_sqlstate,
        failed_message = message_text,
        failed_hint = pg_exception_hint;
      results := results || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object('code', failed_state, 'message', failed_message, 'hint', nullif(failed_hint, ''))
      ));
    end;
  end loop;
  return results;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.audit_event_trusted (
  event_type           text,
  category             text  DEFAULT NULL::text,
  outcome              text  DEFAULT 'success'::text,
  source               text  DEFAULT NULL::text,
  target_type          text  DEFAULT NULL::text,
  record_id            text  DEFAULT NULL::text,
  tenant               uuid  DEFAULT NULL::uuid,
  metadata             jsonb DEFAULT '{}'::jsonb,
  idempotency_key      text  DEFAULT NULL::text,
  restricted           jsonb DEFAULT NULL::jsonb,
  actor_id             uuid  DEFAULT NULL::uuid,
  summary              text  DEFAULT NULL::text,
  target_label         text  DEFAULT NULL::text,
  correlation_id       text  DEFAULT NULL::text,
  actor_kind           text  DEFAULT NULL::text,
  actor_label          text  DEFAULT NULL::text,
  ip                   inet  DEFAULT NULL::inet,
  user_agent           text  DEFAULT NULL::text,
  session_id           text  DEFAULT NULL::text,
  request_id           text  DEFAULT NULL::text,
  scope                text  DEFAULT NULL::text,
  support_session      uuid  DEFAULT NULL::uuid,
  impersonated_by      uuid  DEFAULT NULL::uuid,
  impersonation_reason text  DEFAULT NULL::text,
  summary_key          text  DEFAULT NULL::text,
  summary_params       jsonb DEFAULT NULL::jsonb
)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  existing text;
  v_integration boolean := better_supabase.import_run() is not null;
  entry_id "better_supabase"."audit_events"."id"%type;
begin
  if restricted is not null or ip is not null or user_agent is not null or session_id is not null then
    raise exception 'audit_event got restricted details, and the audit module has no restricted table'
      using errcode = '22023', hint = 'Set blocks.audit.options.restricted to true.';
  end if;
  -- imports.audit 'summary' (ADR 0141): the run audits per entity at its end.
  if v_integration and current_setting('better_supabase.import_audit', true) = 'summary' then
    return null;
  end if;
  actor_id := coalesce(actor_id, auth.uid());
  if idempotency_key is not null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('better_supabase.audit_event'), pg_catalog.hashtext(coalesce(tenant::text, '') || ':' || idempotency_key));
    select l."id"::text into existing
    from "better_supabase"."audit_events" l
    where l."idempotency_key" = audit_event_trusted.idempotency_key
      and l."tenant_id" is not distinct from audit_event_trusted.tenant
    limit 1;
    if existing is not null then
      return existing;
    end if;
  end if;
  insert into "better_supabase"."audit_events" ("table_name", "record_id", "op", "actor_id", "actor_role", "tenant_id", "impersonated_by", "impersonation_reason", "support_session_id", "event_type", "category", "outcome", "source", "target_type", "metadata", "idempotency_key", "actor_kind", "actor_label", "tenant_label", "target_label", "summary", "summary_key", "summary_params", "request_id", "correlation_id", "scope")
  values (
    null,
    record_id,
    'event',
    actor_id,
    coalesce(auth.jwt() ->> 'role', current_user),
    tenant,
    coalesce(audit_event_trusted.impersonated_by, case when auth.jwt() -> 'act' ->> 'sub' ~ '^[0-9a-f-]{36}$' then (auth.jwt() -> 'act' ->> 'sub')::uuid end),
    coalesce(audit_event_trusted.impersonation_reason, auth.jwt() -> 'act' ->> 'reason'),
    coalesce(audit_event_trusted.support_session, case when auth.jwt() -> 'act' ->> 'session_id' ~ '^[0-9a-f-]{36}$' then (auth.jwt() -> 'act' ->> 'session_id')::uuid end),
    event_type,
    coalesce(category, 'system'),
    coalesce(outcome, 'success'),
    coalesce(source, 'app'),
    target_type,
    coalesce(metadata, '{}'),
    idempotency_key,
    coalesce(actor_kind, case
      when v_integration then 'integration'
      when coalesce(auth.jwt() ->> 'role', '') = 'service_role' then 'service'
      when auth.jwt() -> 'act' ->> 'kind' = 'support' then 'support'
      when auth.jwt() -> 'act' is not null then 'impersonation'
      when auth.jwt() ->> 'client_id' is not null then 'oauth-client'
      when auth.uid() is not null then 'user'
      else 'system'
    end),
    coalesce(actor_label, coalesce(auth.jwt() -> 'user_metadata' ->> 'full_name', auth.jwt() ->> 'email')),
    (select o."name"::text from "public"."organizations" o where o."id" = tenant),
    target_label,
    summary,
    coalesce(summary_key, event_type),
    summary_params,
    coalesce(better_supabase.request_id_or_null(request_id), coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.request_id', true)), better_supabase.request_id_or_null(better_supabase.request_header('x-request-id')))),
    coalesce(better_supabase.request_id_or_null(correlation_id), coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.correlation_id', true)), better_supabase.request_id_or_null(better_supabase.request_header('x-correlation-id')))),
    coalesce(audit_event_trusted.scope, case when tenant is null then 'platform' else 'tenant' end)
  )
  returning "id" into entry_id;
  if audit_event_trusted.target_type is not null and audit_event_trusted.record_id is not null then
    perform pg_catalog.set_config('better_supabase.recorded', coalesce(pg_catalog.current_setting('better_supabase.recorded', true), '') || E'\n' || audit_event_trusted.target_type || ':' || audit_event_trusted.record_id, true);
  end if;
  return entry_id::text;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.audit_row_change()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  entry record;
  settings jsonb;
  entry_id "better_supabase"."audit_events"."id"%type;
  old_row jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) end;
  new_row jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) end;
  row_data jsonb := coalesce(new_row, old_row);
  changed_columns text[];
  changed_values jsonb;
  row_tenant uuid;
  v_jwt jsonb := auth.jwt();
  v_headers jsonb := better_supabase.request_headers();
  v_integration boolean := better_supabase.import_run() is not null;
  v_label text;
  path_value text;
  path_step jsonb;
begin
  -- An import run with imports.audit 'summary' audits one entry per entity at
  -- its end instead of one per row (ADR 0141).
  if v_integration and current_setting('better_supabase.import_audit', true) = 'summary' then
    return null;
  end if;
  if tg_nargs > 0 then
    settings := tg_argv[0]::jsonb;
    select array(select jsonb_array_elements_text(coalesce(settings -> 'ignore', '[]'))) as ignore,
      coalesce(
        nullif(array(select jsonb_array_elements_text(coalesce(settings -> 'key_columns', '[]'))), '{}'),
        (select array_agg(c.attname::text order by k.ord)
         from pg_catalog.pg_index i
         cross join lateral unnest(i.indkey) with ordinality k(attnum, ord)
         join pg_catalog.pg_attribute c on c.attrelid = i.indrelid and c.attnum = k.attnum
         where i.indrelid = tg_relid and i.indisprimary),
        '{id}'
      ) as key_columns,
      array(select jsonb_array_elements_text(coalesce(settings -> 'redact', '[]'))) as redact,
      settings ->> 'category' as category, settings ->> 'event_prefix' as event_prefix,
      settings ->> 'target_type' as target_type, settings ->> 'tenant_column' as tenant_column,
      settings ->> 'label_column' as label_column,
      settings -> 'tenant_path' as tenant_path, settings ->> 'tenant_function' as tenant_function,
      settings ->> 'archive_column' as archive_column, settings ->> 'archive_value' as archive_value
    into entry;
  else
    select coalesce(a."ignore", '{}') as ignore, coalesce(a."key_columns", '{id}') as key_columns,
      coalesce(a."redact", '{}') as redact, a."category" as category,
      a."event_prefix" as event_prefix, a."target_type" as target_type,
      a."tenant_column" as tenant_column, a."label_column" as label_column,
      null::jsonb as tenant_path, null::text as tenant_function,
      null::text as archive_column, null::text as archive_value
    into entry
    from (select 1) one
    left join "better_supabase"."audited_tables" a on a."target" = tg_relid::regclass;
  end if;
  if position(E'\n' || coalesce(entry.target_type, tg_table_name) || ':' || coalesce((select string_agg(row_data ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord)), '') || E'\n' in coalesce(current_setting('better_supabase.recorded', true), '') || E'\n') > 0 then
    return null;
  end if;
  row_tenant := case when row_data ->> coalesce(entry.tenant_column, 'organization_id') ~* '^[0-9a-f-]{36}$' then (row_data ->> coalesce(entry.tenant_column, 'organization_id'))::uuid end;
  -- A child row without a tenant column: follow the foreign-key path
  -- registered through tenant_path, then the tenant function.
  if row_tenant is null and entry.tenant_path is not null then
    path_value := row_data ->> (entry.tenant_path ->> 'column');
    for path_step in select * from jsonb_array_elements(entry.tenant_path -> 'steps') loop
      exit when path_value is null;
      execute format('select %I::text from %s where %I::text = $1 limit 1',
        path_step ->> 'read', path_step ->> 'table', path_step ->> 'ref')
        into path_value using path_value;
    end loop;
    row_tenant := case when path_value ~* '^[0-9a-f-]{36}$' then (path_value)::uuid end;
  end if;
  if row_tenant is null and entry.tenant_function is not null then
    execute format('select %s($1)::text', (entry.tenant_function::regprocedure)::oid::regproc) into path_value using row_data;
    row_tenant := case when path_value ~* '^[0-9a-f-]{36}$' then (path_value)::uuid end;
  end if;
  if row_tenant is not null then
    v_label := better_supabase.memo_slot_get('audit.tenant_label.t' || replace(row_tenant::text, '-', ''));
    if v_label is null then
      v_label := (select o."name"::text from "public"."organizations" o where o."id" = row_tenant);
      perform better_supabase.memo_slot_set('audit.tenant_label.t' || replace(row_tenant::text, '-', ''), coalesce(v_label, ''));
    end if;
  end if;
  old_row := old_row - entry.ignore;
  new_row := new_row - entry.ignore;
  if tg_op = 'UPDATE' then
    select array_agg(key order by key) into changed_columns
    from jsonb_each(new_row) n
    where n.value is distinct from old_row -> n.key;
    if changed_columns is null then
      return null;
    end if;
  end if;
  -- Redacted columns stay in changed, with their values masked.
  old_row := old_row || coalesce((select jsonb_object_agg(k, '"[redacted]"'::jsonb) from unnest(entry.redact) k where old_row ? k), '{}');
  new_row := new_row || coalesce((select jsonb_object_agg(k, '"[redacted]"'::jsonb) from unnest(entry.redact) k where new_row ? k), '{}');
  insert into "better_supabase"."audit_events" ("table_name", "record_id", "op", "old_record", "new_record", "changed", "actor_id", "actor_role", "tenant_id", "impersonated_by", "impersonation_reason", "support_session_id", "event_type", "category", "outcome", "source", "target_type", "actor_kind", "actor_label", "tenant_label", "target_label", "summary", "summary_key", "summary_params", "request_id", "correlation_id", "scope")
  values (
    tg_table_schema || '.' || tg_table_name,
    (select string_agg(row_data ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord)),
    lower(tg_op),
    old_row,
    new_row,
    changed_columns,
    coalesce(auth.uid(), better_supabase.acting_member()),
    coalesce(v_jwt ->> 'role', current_user),
    row_tenant,
    case when v_jwt -> 'act' ->> 'sub' ~ '^[0-9a-f-]{36}$' then (v_jwt -> 'act' ->> 'sub')::uuid end,
    v_jwt -> 'act' ->> 'reason',
    case when v_jwt -> 'act' ->> 'session_id' ~ '^[0-9a-f-]{36}$' then (v_jwt -> 'act' ->> 'session_id')::uuid end,
    coalesce(entry.event_prefix, tg_table_name) || '.' || case tg_op when 'INSERT' then 'created' when 'UPDATE' then case when entry.archive_column is null then 'updated' when (case when entry.archive_value is null then coalesce(new_row ->> entry.archive_column, 'false') <> 'false' else new_row ->> entry.archive_column is not distinct from entry.archive_value end) and not (case when entry.archive_value is null then coalesce(old_row ->> entry.archive_column, 'false') <> 'false' else old_row ->> entry.archive_column is not distinct from entry.archive_value end) then 'archived' when (case when entry.archive_value is null then coalesce(old_row ->> entry.archive_column, 'false') <> 'false' else old_row ->> entry.archive_column is not distinct from entry.archive_value end) and not (case when entry.archive_value is null then coalesce(new_row ->> entry.archive_column, 'false') <> 'false' else new_row ->> entry.archive_column is not distinct from entry.archive_value end) then 'restored' else 'updated' end else 'deleted' end,
    coalesce(entry.category, 'data'),
    'success',
    'database',
    coalesce(entry.target_type, tg_table_name),
    case
      when v_integration then 'integration'
      when coalesce(v_jwt ->> 'role', '') = 'service_role' then 'service'
      when v_jwt -> 'act' ->> 'kind' = 'support' then 'support'
      when v_jwt -> 'act' is not null then 'impersonation'
      when v_jwt ->> 'client_id' is not null then 'oauth-client'
      when auth.uid() is not null then 'user'
      else 'system'
    end,
    coalesce(v_jwt -> 'user_metadata' ->> 'full_name', v_jwt ->> 'email'),
    v_label,
    row_data ->> entry.label_column,
    null,
    null,
    null,
    coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.request_id', true)), better_supabase.request_id_or_null((v_headers ->> 'x-request-id'))),
    coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.correlation_id', true)), better_supabase.request_id_or_null((v_headers ->> 'x-correlation-id'))),
    case when row_tenant is null then 'platform' else 'tenant' end
  )
  returning "id" into entry_id;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.audit_statement_change()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  entry record;
  settings jsonb;
  v_jwt jsonb := auth.jwt();
  v_headers jsonb := better_supabase.request_headers();
  v_integration boolean := better_supabase.import_run() is not null;
begin
  if v_integration and current_setting('better_supabase.import_audit', true) = 'summary' then
    return null;
  end if;
  if tg_nargs > 0 then
    settings := tg_argv[0]::jsonb;
    select array(select jsonb_array_elements_text(coalesce(settings -> 'ignore', '[]'))) as ignore,
      coalesce(
        nullif(array(select jsonb_array_elements_text(coalesce(settings -> 'key_columns', '[]'))), '{}'),
        (select array_agg(c.attname::text order by k.ord)
         from pg_catalog.pg_index i
         cross join lateral unnest(i.indkey) with ordinality k(attnum, ord)
         join pg_catalog.pg_attribute c on c.attrelid = i.indrelid and c.attnum = k.attnum
         where i.indrelid = tg_relid and i.indisprimary),
        '{id}'
      ) as key_columns,
      array(select jsonb_array_elements_text(coalesce(settings -> 'redact', '[]'))) as redact,
      settings ->> 'category' as category, settings ->> 'event_prefix' as event_prefix,
      settings ->> 'target_type' as target_type, settings ->> 'tenant_column' as tenant_column,
      settings ->> 'label_column' as label_column,
      settings -> 'tenant_path' as tenant_path, settings ->> 'tenant_function' as tenant_function,
      settings ->> 'archive_column' as archive_column, settings ->> 'archive_value' as archive_value
    into entry;
  else
    select coalesce(a."ignore", '{}') as ignore, coalesce(a."key_columns", '{id}') as key_columns,
      coalesce(a."redact", '{}') as redact, a."category" as category,
      a."event_prefix" as event_prefix, a."target_type" as target_type,
      a."tenant_column" as tenant_column, a."label_column" as label_column,
      null::jsonb as tenant_path, null::text as tenant_function,
      null::text as archive_column, null::text as archive_value
    into entry
    from (select 1) one
    left join "better_supabase"."audited_tables" a on a."target" = tg_relid::regclass;
  end if;
  if tg_op = 'INSERT' then
    with src as (
      select null::jsonb as old_row, to_jsonb(n) as new_row from new_rows n
    ), paired as (
      select case when s.old_row is null then 'insert' when s.new_row is null then 'delete' else 'update' end as op,
        coalesce(s.new_row, s.old_row) as row_data,
        s.old_row - entry.ignore as old_row, s.new_row - entry.ignore as new_row
      from src s
    ), changed as (
      select p.*, case when p.op = 'update' then (
          select array_agg(e.key order by e.key) from jsonb_each(p.new_row) e
          where e.value is distinct from p.old_row -> e.key
        ) end as changed_columns
      from paired p
    ), kept as (
      select c.*, case when c.row_data ->> coalesce(entry.tenant_column, 'organization_id') ~* '^[0-9a-f-]{36}$' then (c.row_data ->> coalesce(entry.tenant_column, 'organization_id'))::uuid end as row_tenant
      from changed c
      where (c.op <> 'update' or c.changed_columns is not null)
        and not (position(E'\n' || coalesce(entry.target_type, tg_table_name) || ':' || coalesce((select string_agg(row_data ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord)), '') || E'\n' in coalesce(current_setting('better_supabase.recorded', true), '') || E'\n') > 0)
    ), final as (
      select k.op, k.row_data, k.changed_columns, k.row_tenant,
        k.old_row || coalesce((select jsonb_object_agg(r, '"[redacted]"'::jsonb) from unnest(entry.redact) r where k.old_row ? r), '{}') as old_row,
        k.new_row || coalesce((select jsonb_object_agg(r, '"[redacted]"'::jsonb) from unnest(entry.redact) r where k.new_row ? r), '{}') as new_row
      from kept k
    ), labels as (
      select t.row_tenant as tenant_key, (select o."name"::text from "public"."organizations" o where o."id" = t.row_tenant) as label
      from (select distinct row_tenant from kept) t
    )
    insert into "better_supabase"."audit_events" ("table_name", "record_id", "op", "old_record", "new_record", "changed", "actor_id", "actor_role", "tenant_id", "impersonated_by", "impersonation_reason", "support_session_id", "event_type", "category", "outcome", "source", "target_type", "actor_kind", "actor_label", "tenant_label", "target_label", "summary", "summary_key", "summary_params", "request_id", "correlation_id", "scope")
    select tg_table_schema || '.' || tg_table_name,
    (select string_agg(row_data ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord)),
    op,
    old_row,
    new_row,
    changed_columns,
    coalesce(auth.uid(), better_supabase.acting_member()),
    coalesce(v_jwt ->> 'role', current_user),
    row_tenant,
    case when v_jwt -> 'act' ->> 'sub' ~ '^[0-9a-f-]{36}$' then (v_jwt -> 'act' ->> 'sub')::uuid end,
    v_jwt -> 'act' ->> 'reason',
    case when v_jwt -> 'act' ->> 'session_id' ~ '^[0-9a-f-]{36}$' then (v_jwt -> 'act' ->> 'session_id')::uuid end,
    coalesce(entry.event_prefix, tg_table_name) || '.' || case op when 'insert' then 'created' when 'update' then case when entry.archive_column is null then 'updated' when (case when entry.archive_value is null then coalesce(new_row ->> entry.archive_column, 'false') <> 'false' else new_row ->> entry.archive_column is not distinct from entry.archive_value end) and not (case when entry.archive_value is null then coalesce(old_row ->> entry.archive_column, 'false') <> 'false' else old_row ->> entry.archive_column is not distinct from entry.archive_value end) then 'archived' when (case when entry.archive_value is null then coalesce(old_row ->> entry.archive_column, 'false') <> 'false' else old_row ->> entry.archive_column is not distinct from entry.archive_value end) and not (case when entry.archive_value is null then coalesce(new_row ->> entry.archive_column, 'false') <> 'false' else new_row ->> entry.archive_column is not distinct from entry.archive_value end) then 'restored' else 'updated' end else 'deleted' end,
    coalesce(entry.category, 'data'),
    'success',
    'database',
    coalesce(entry.target_type, tg_table_name),
    case
      when v_integration then 'integration'
      when coalesce(v_jwt ->> 'role', '') = 'service_role' then 'service'
      when v_jwt -> 'act' ->> 'kind' = 'support' then 'support'
      when v_jwt -> 'act' is not null then 'impersonation'
      when v_jwt ->> 'client_id' is not null then 'oauth-client'
      when auth.uid() is not null then 'user'
      else 'system'
    end,
    coalesce(v_jwt -> 'user_metadata' ->> 'full_name', v_jwt ->> 'email'),
    l.label,
    row_data ->> entry.label_column,
    null,
    null,
    null,
    coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.request_id', true)), better_supabase.request_id_or_null((v_headers ->> 'x-request-id'))),
    coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.correlation_id', true)), better_supabase.request_id_or_null((v_headers ->> 'x-correlation-id'))),
    case when row_tenant is null then 'platform' else 'tenant' end
    from final
    left join labels l on l.tenant_key is not distinct from final.row_tenant;
  elsif tg_op = 'DELETE' then
    with src as (
      select to_jsonb(o) as old_row, null::jsonb as new_row from old_rows o
    ), paired as (
      select case when s.old_row is null then 'insert' when s.new_row is null then 'delete' else 'update' end as op,
        coalesce(s.new_row, s.old_row) as row_data,
        s.old_row - entry.ignore as old_row, s.new_row - entry.ignore as new_row
      from src s
    ), changed as (
      select p.*, case when p.op = 'update' then (
          select array_agg(e.key order by e.key) from jsonb_each(p.new_row) e
          where e.value is distinct from p.old_row -> e.key
        ) end as changed_columns
      from paired p
    ), kept as (
      select c.*, case when c.row_data ->> coalesce(entry.tenant_column, 'organization_id') ~* '^[0-9a-f-]{36}$' then (c.row_data ->> coalesce(entry.tenant_column, 'organization_id'))::uuid end as row_tenant
      from changed c
      where (c.op <> 'update' or c.changed_columns is not null)
        and not (position(E'\n' || coalesce(entry.target_type, tg_table_name) || ':' || coalesce((select string_agg(row_data ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord)), '') || E'\n' in coalesce(current_setting('better_supabase.recorded', true), '') || E'\n') > 0)
    ), final as (
      select k.op, k.row_data, k.changed_columns, k.row_tenant,
        k.old_row || coalesce((select jsonb_object_agg(r, '"[redacted]"'::jsonb) from unnest(entry.redact) r where k.old_row ? r), '{}') as old_row,
        k.new_row || coalesce((select jsonb_object_agg(r, '"[redacted]"'::jsonb) from unnest(entry.redact) r where k.new_row ? r), '{}') as new_row
      from kept k
    ), labels as (
      select t.row_tenant as tenant_key, (select o."name"::text from "public"."organizations" o where o."id" = t.row_tenant) as label
      from (select distinct row_tenant from kept) t
    )
    insert into "better_supabase"."audit_events" ("table_name", "record_id", "op", "old_record", "new_record", "changed", "actor_id", "actor_role", "tenant_id", "impersonated_by", "impersonation_reason", "support_session_id", "event_type", "category", "outcome", "source", "target_type", "actor_kind", "actor_label", "tenant_label", "target_label", "summary", "summary_key", "summary_params", "request_id", "correlation_id", "scope")
    select tg_table_schema || '.' || tg_table_name,
    (select string_agg(row_data ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord)),
    op,
    old_row,
    new_row,
    changed_columns,
    coalesce(auth.uid(), better_supabase.acting_member()),
    coalesce(v_jwt ->> 'role', current_user),
    row_tenant,
    case when v_jwt -> 'act' ->> 'sub' ~ '^[0-9a-f-]{36}$' then (v_jwt -> 'act' ->> 'sub')::uuid end,
    v_jwt -> 'act' ->> 'reason',
    case when v_jwt -> 'act' ->> 'session_id' ~ '^[0-9a-f-]{36}$' then (v_jwt -> 'act' ->> 'session_id')::uuid end,
    coalesce(entry.event_prefix, tg_table_name) || '.' || case op when 'insert' then 'created' when 'update' then case when entry.archive_column is null then 'updated' when (case when entry.archive_value is null then coalesce(new_row ->> entry.archive_column, 'false') <> 'false' else new_row ->> entry.archive_column is not distinct from entry.archive_value end) and not (case when entry.archive_value is null then coalesce(old_row ->> entry.archive_column, 'false') <> 'false' else old_row ->> entry.archive_column is not distinct from entry.archive_value end) then 'archived' when (case when entry.archive_value is null then coalesce(old_row ->> entry.archive_column, 'false') <> 'false' else old_row ->> entry.archive_column is not distinct from entry.archive_value end) and not (case when entry.archive_value is null then coalesce(new_row ->> entry.archive_column, 'false') <> 'false' else new_row ->> entry.archive_column is not distinct from entry.archive_value end) then 'restored' else 'updated' end else 'deleted' end,
    coalesce(entry.category, 'data'),
    'success',
    'database',
    coalesce(entry.target_type, tg_table_name),
    case
      when v_integration then 'integration'
      when coalesce(v_jwt ->> 'role', '') = 'service_role' then 'service'
      when v_jwt -> 'act' ->> 'kind' = 'support' then 'support'
      when v_jwt -> 'act' is not null then 'impersonation'
      when v_jwt ->> 'client_id' is not null then 'oauth-client'
      when auth.uid() is not null then 'user'
      else 'system'
    end,
    coalesce(v_jwt -> 'user_metadata' ->> 'full_name', v_jwt ->> 'email'),
    l.label,
    row_data ->> entry.label_column,
    null,
    null,
    null,
    coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.request_id', true)), better_supabase.request_id_or_null((v_headers ->> 'x-request-id'))),
    coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.correlation_id', true)), better_supabase.request_id_or_null((v_headers ->> 'x-correlation-id'))),
    case when row_tenant is null then 'platform' else 'tenant' end
    from final
    left join labels l on l.tenant_key is not distinct from final.row_tenant;
  else
    with src as (
      select o.j as old_row, n.j as new_row
      from (select to_jsonb(r) as j, (select string_agg(to_jsonb(r) ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord)) as k from old_rows r) o
      full join (select to_jsonb(r) as j, (select string_agg(to_jsonb(r) ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord)) as k from new_rows r) n on o.k = n.k
    ), paired as (
      select case when s.old_row is null then 'insert' when s.new_row is null then 'delete' else 'update' end as op,
        coalesce(s.new_row, s.old_row) as row_data,
        s.old_row - entry.ignore as old_row, s.new_row - entry.ignore as new_row
      from src s
    ), changed as (
      select p.*, case when p.op = 'update' then (
          select array_agg(e.key order by e.key) from jsonb_each(p.new_row) e
          where e.value is distinct from p.old_row -> e.key
        ) end as changed_columns
      from paired p
    ), kept as (
      select c.*, case when c.row_data ->> coalesce(entry.tenant_column, 'organization_id') ~* '^[0-9a-f-]{36}$' then (c.row_data ->> coalesce(entry.tenant_column, 'organization_id'))::uuid end as row_tenant
      from changed c
      where (c.op <> 'update' or c.changed_columns is not null)
        and not (position(E'\n' || coalesce(entry.target_type, tg_table_name) || ':' || coalesce((select string_agg(row_data ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord)), '') || E'\n' in coalesce(current_setting('better_supabase.recorded', true), '') || E'\n') > 0)
    ), final as (
      select k.op, k.row_data, k.changed_columns, k.row_tenant,
        k.old_row || coalesce((select jsonb_object_agg(r, '"[redacted]"'::jsonb) from unnest(entry.redact) r where k.old_row ? r), '{}') as old_row,
        k.new_row || coalesce((select jsonb_object_agg(r, '"[redacted]"'::jsonb) from unnest(entry.redact) r where k.new_row ? r), '{}') as new_row
      from kept k
    ), labels as (
      select t.row_tenant as tenant_key, (select o."name"::text from "public"."organizations" o where o."id" = t.row_tenant) as label
      from (select distinct row_tenant from kept) t
    )
    insert into "better_supabase"."audit_events" ("table_name", "record_id", "op", "old_record", "new_record", "changed", "actor_id", "actor_role", "tenant_id", "impersonated_by", "impersonation_reason", "support_session_id", "event_type", "category", "outcome", "source", "target_type", "actor_kind", "actor_label", "tenant_label", "target_label", "summary", "summary_key", "summary_params", "request_id", "correlation_id", "scope")
    select tg_table_schema || '.' || tg_table_name,
    (select string_agg(row_data ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord)),
    op,
    old_row,
    new_row,
    changed_columns,
    coalesce(auth.uid(), better_supabase.acting_member()),
    coalesce(v_jwt ->> 'role', current_user),
    row_tenant,
    case when v_jwt -> 'act' ->> 'sub' ~ '^[0-9a-f-]{36}$' then (v_jwt -> 'act' ->> 'sub')::uuid end,
    v_jwt -> 'act' ->> 'reason',
    case when v_jwt -> 'act' ->> 'session_id' ~ '^[0-9a-f-]{36}$' then (v_jwt -> 'act' ->> 'session_id')::uuid end,
    coalesce(entry.event_prefix, tg_table_name) || '.' || case op when 'insert' then 'created' when 'update' then case when entry.archive_column is null then 'updated' when (case when entry.archive_value is null then coalesce(new_row ->> entry.archive_column, 'false') <> 'false' else new_row ->> entry.archive_column is not distinct from entry.archive_value end) and not (case when entry.archive_value is null then coalesce(old_row ->> entry.archive_column, 'false') <> 'false' else old_row ->> entry.archive_column is not distinct from entry.archive_value end) then 'archived' when (case when entry.archive_value is null then coalesce(old_row ->> entry.archive_column, 'false') <> 'false' else old_row ->> entry.archive_column is not distinct from entry.archive_value end) and not (case when entry.archive_value is null then coalesce(new_row ->> entry.archive_column, 'false') <> 'false' else new_row ->> entry.archive_column is not distinct from entry.archive_value end) then 'restored' else 'updated' end else 'deleted' end,
    coalesce(entry.category, 'data'),
    'success',
    'database',
    coalesce(entry.target_type, tg_table_name),
    case
      when v_integration then 'integration'
      when coalesce(v_jwt ->> 'role', '') = 'service_role' then 'service'
      when v_jwt -> 'act' ->> 'kind' = 'support' then 'support'
      when v_jwt -> 'act' is not null then 'impersonation'
      when v_jwt ->> 'client_id' is not null then 'oauth-client'
      when auth.uid() is not null then 'user'
      else 'system'
    end,
    coalesce(v_jwt -> 'user_metadata' ->> 'full_name', v_jwt ->> 'email'),
    l.label,
    row_data ->> entry.label_column,
    null,
    null,
    null,
    coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.request_id', true)), better_supabase.request_id_or_null((v_headers ->> 'x-request-id'))),
    coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.correlation_id', true)), better_supabase.request_id_or_null((v_headers ->> 'x-correlation-id'))),
    case when row_tenant is null then 'platform' else 'tenant' end
    from final
    left join labels l on l.tenant_key is not distinct from final.row_tenant;
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.close_accounting_period (
  period_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_period "better_supabase"."accounting_periods"%rowtype;
  v_blockers text[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_period from "better_supabase"."accounting_periods" y where y."id" = close_accounting_period.period_id for update;
  if not found then
    raise exception 'period not found' using errcode = 'P0002', hint = 'ACCOUNTING_PERIOD_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_period."tenant_id", 'accounting.close'), false)) then
    raise exception 'not allowed to close accounting periods' using errcode = '42501', hint = 'ACCOUNTING_PERIOD_FORBIDDEN';
  end if;
  if v_period."status" in ('closed', 'locked') then
    return jsonb_build_object('id', v_period."id", 'organizationId', v_period."tenant_id", 'fiscalYear', v_period."fiscal_year", 'number', v_period."number", 'startsOn', v_period."starts_on", 'endsOn', v_period."ends_on", 'status', v_period."status", 'closedAt', v_period."closed_at", 'closedBy', v_period."closed_by", 'lockedAt', v_period."locked_at", 'lockedBy', v_period."locked_by");
  end if;
  v_blockers := "better_supabase"."accounting_period_close_blockers"(v_period."id");
  if cardinality(v_blockers) > 0 then
    raise exception 'the period can''t close yet: %', array_to_string(v_blockers, ', ') using errcode = '55000', hint = 'ACCOUNTING_PERIOD_CLOSE_BLOCKED';
  end if;
  update "better_supabase"."accounting_periods" y set "status" = 'closed', "closed_at" = now(), "closed_by" = auth.uid()
    where y."id" = v_period."id"
    returning * into v_period;
    perform "better_supabase".emit_event('accounting_period.closed', jsonb_build_object('organizationId', v_period."tenant_id", 'id', v_period."id", 'fiscalYear', v_period."fiscal_year", 'number', v_period."number", 'startsOn', v_period."starts_on", 'endsOn', v_period."ends_on"), 'accounting-periods/' || v_period."id"::text, (v_period."tenant_id")::text, null, 'better-supabase/accounting');
  perform better_supabase.audit_event(
    event_type => 'accounting_period.closed',
    category => 'data',
    target_type => 'accounting_period',
    record_id => v_period."id"::text,
    target_label => v_period."fiscal_year"::text || '-' || lpad(v_period."number"::text, 2, '0'),
    summary => 'closed period ' || v_period."fiscal_year"::text || '-' || lpad(v_period."number"::text, 2, '0'),
    summary_params => jsonb_build_object('fiscalYear', v_period."fiscal_year", 'number', v_period."number"),
    tenant => (v_period."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_period."tenant_id", 'id', v_period."id", 'fiscalYear', v_period."fiscal_year", 'number', v_period."number", 'startsOn', v_period."starts_on", 'endsOn', v_period."ends_on")
  );
  return jsonb_build_object('id', v_period."id", 'organizationId', v_period."tenant_id", 'fiscalYear', v_period."fiscal_year", 'number', v_period."number", 'startsOn', v_period."starts_on", 'endsOn', v_period."ends_on", 'status', v_period."status", 'closedAt', v_period."closed_at", 'closedBy', v_period."closed_by", 'lockedAt', v_period."locked_at", 'lockedBy', v_period."locked_by");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.close_fiscal_year (
  tenant      uuid,
  fiscal_year integer
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_settings "better_supabase"."accounting_settings"%rowtype;
  v_period "better_supabase"."accounting_periods"%rowtype;
  v_starts date;
  v_ends date;
  v_open integer;
  v_retained uuid;
  v_journal uuid;
  v_entry "better_supabase"."accounting_entries"%rowtype;
  v_net numeric;
  v_count integer;
  v_closing uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', close_fiscal_year.tenant, 'accounting.close'), false)) then
    raise exception 'not allowed to close fiscal years' using errcode = '42501', hint = 'ACCOUNTING_PERIOD_FORBIDDEN';
  end if;
  select * into v_settings from "better_supabase"."accounting_settings" st where st."tenant_id" = close_fiscal_year.tenant;
  if not found then
    raise exception 'accounting isn''t set up for this organization; call setup_accounting first' using errcode = 'P0002', hint = 'ACCOUNTING_SETTING_NOT_FOUND';
  end if;
  select min(y."starts_on"), max(y."ends_on"), count(*) filter (where y."status" = 'open')
  into v_starts, v_ends, v_open
  from "better_supabase"."accounting_periods" y where y."tenant_id" = close_fiscal_year.tenant and y."fiscal_year" = close_fiscal_year.fiscal_year;
  if v_starts is null then
    raise exception 'the fiscal year has no periods; open it first' using errcode = 'P0002', hint = 'ACCOUNTING_PERIOD_NOT_FOUND';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(close_fiscal_year.tenant::text || ':fiscal_year:' || close_fiscal_year.fiscal_year::text, 0));
  if exists (
    select 1 from "better_supabase"."accounting_entries" y
    where y."tenant_id" = close_fiscal_year.tenant and y."source_type" = 'fiscal_year'
      and y."source_id" = close_fiscal_year.fiscal_year::text and y."status" <> 'reversed'
  ) then
    raise exception 'the fiscal year is already closed; reverse its closing entry to close it again' using errcode = '55000', hint = 'PERIOD_CLOSED';
  end if;
  if exists (
    select 1 from "better_supabase"."accounting_entries" y
    where y."tenant_id" = close_fiscal_year.tenant and y."status" = 'draft'
      and y."entry_date" >= v_starts and y."entry_date" <= v_ends
  ) then
    raise exception 'the fiscal year can''t close yet: draft_entries' using errcode = '55000', hint = 'ACCOUNTING_PERIOD_CLOSE_BLOCKED';
  end if;
  select y."account_id" into v_retained from "better_supabase"."accounting_account_roles" y
  where y."tenant_id" = close_fiscal_year.tenant and y."role" = 'retained_earnings';
  if v_retained is null then
    raise exception 'no account has the retained_earnings role' using errcode = 'P0002', hint = 'ACCOUNTING_ACCOUNT_ROLE_MISSING';
  end if;
  select y."id" into v_journal from "better_supabase"."accounting_journals" y
  where y."tenant_id" = close_fiscal_year.tenant and y."type" = 'general'
  order by y."code" limit 1;
  if v_journal is null then
    raise exception 'the year-end close needs a general journal' using errcode = 'P0002', hint = 'ACCOUNTING_JOURNAL_NOT_FOUND';
  end if;
  select count(*), coalesce(sum(c.net), 0) into v_count, v_net from (select y."account_id" as account, sum(y."debit") - sum(y."credit") as net
    from "better_supabase"."accounting_entry_lines" y
    join "better_supabase"."accounting_entries" z on z."id" = y."entry_id"
    join "better_supabase"."accounting_accounts" w on w."id" = y."account_id"
    where z."tenant_id" = close_fiscal_year.tenant and z."fiscal_year" = close_fiscal_year.fiscal_year
      and z."status" in ('posted', 'reversed') and w."type" in ('income', 'expense')
    group by y."account_id"
    having sum(y."debit") <> sum(y."credit")) c;
  if v_count > 0 then
    insert into "better_supabase"."accounting_entries" ("tenant_id", "journal_id", "entry_date", "source_type", "source_id", "memo", "created_by")
    values (close_fiscal_year.tenant, v_journal, v_ends, 'fiscal_year', close_fiscal_year.fiscal_year::text,
      'Closing of fiscal year ' || close_fiscal_year.fiscal_year::text, auth.uid())
    returning * into v_entry;
    insert into "better_supabase"."accounting_entry_lines" ("tenant_id", "entry_id", "position", "account_id", "debit", "credit", "currency", "amount_currency")
    select close_fiscal_year.tenant, v_entry."id", (row_number() over (order by w."code"))::smallint, c.account,
      greatest(-c.net, 0)::bigint, greatest(c.net, 0)::bigint, v_settings."functional_currency", (-c.net)::bigint
    from (select y."account_id" as account, sum(y."debit") - sum(y."credit") as net
    from "better_supabase"."accounting_entry_lines" y
    join "better_supabase"."accounting_entries" z on z."id" = y."entry_id"
    join "better_supabase"."accounting_accounts" w on w."id" = y."account_id"
    where z."tenant_id" = close_fiscal_year.tenant and z."fiscal_year" = close_fiscal_year.fiscal_year
      and z."status" in ('posted', 'reversed') and w."type" in ('income', 'expense')
    group by y."account_id"
    having sum(y."debit") <> sum(y."credit")) c join "better_supabase"."accounting_accounts" w on w."id" = c.account;
    if v_net <> 0 then
      insert into "better_supabase"."accounting_entry_lines" ("tenant_id", "entry_id", "position", "account_id", "debit", "credit", "currency", "amount_currency")
      values (close_fiscal_year.tenant, v_entry."id", 32767, v_retained,
        greatest(v_net, 0)::bigint, greatest(-v_net, 0)::bigint, v_settings."functional_currency", v_net::bigint);
    end if;
    v_entry := "better_supabase"."accounting_post"(v_entry."id", true);
    v_closing := v_entry."id";
  elsif v_open = 0 then
    raise exception 'the fiscal year is already closed' using errcode = '55000', hint = 'PERIOD_CLOSED';
  end if;
  delete from "better_supabase"."accounting_opening_balances" y
  where y."tenant_id" = close_fiscal_year.tenant and y."fiscal_year" = close_fiscal_year.fiscal_year + 1 and y."source" = 'carried';
  insert into "better_supabase"."accounting_opening_balances" ("tenant_id", "fiscal_year", "account_id", "party_id", "amount", "source")
  select close_fiscal_year.tenant, close_fiscal_year.fiscal_year + 1, c.account, c.party, c.net, 'carried'
  from (
    select y."account_id" as account, case when w."reconcilable" then y."party_id" end as party,
      sum(y."debit") - sum(y."credit") as net
    from "better_supabase"."accounting_entry_lines" y
    join "better_supabase"."accounting_entries" z on z."id" = y."entry_id"
    join "better_supabase"."accounting_accounts" w on w."id" = y."account_id"
    where z."tenant_id" = close_fiscal_year.tenant and z."status" in ('posted', 'reversed')
      and z."entry_date" <= v_ends and w."type" in ('asset', 'liability', 'equity')
    group by y."account_id", case when w."reconcilable" then y."party_id" end
    having sum(y."debit") <> sum(y."credit")
  ) c
  on conflict do nothing;
  for v_period in
    select * from "better_supabase"."accounting_periods" y
    where y."tenant_id" = close_fiscal_year.tenant and y."fiscal_year" = close_fiscal_year.fiscal_year and y."status" = 'open'
    order by y."number"
    for update
  loop
    update "better_supabase"."accounting_periods" y set "status" = 'closed', "closed_at" = now(), "closed_by" = auth.uid()
    where y."id" = v_period."id"
    returning * into v_period;
    perform "better_supabase".emit_event('accounting_period.closed', jsonb_build_object('organizationId', v_period."tenant_id", 'id', v_period."id", 'fiscalYear', v_period."fiscal_year", 'number', v_period."number", 'startsOn', v_period."starts_on", 'endsOn', v_period."ends_on"), 'accounting-periods/' || v_period."id"::text, (v_period."tenant_id")::text, null, 'better-supabase/accounting');
  perform better_supabase.audit_event(
    event_type => 'accounting_period.closed',
    category => 'data',
    target_type => 'accounting_period',
    record_id => v_period."id"::text,
    target_label => v_period."fiscal_year"::text || '-' || lpad(v_period."number"::text, 2, '0'),
    summary => 'closed period ' || v_period."fiscal_year"::text || '-' || lpad(v_period."number"::text, 2, '0'),
    summary_params => jsonb_build_object('fiscalYear', v_period."fiscal_year", 'number', v_period."number"),
    tenant => (v_period."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_period."tenant_id", 'id', v_period."id", 'fiscalYear', v_period."fiscal_year", 'number', v_period."number", 'startsOn', v_period."starts_on", 'endsOn', v_period."ends_on")
  );
  end loop;
  perform "better_supabase".emit_event('fiscal_year.closed', jsonb_build_object('organizationId', close_fiscal_year.tenant, 'fiscalYear', close_fiscal_year.fiscal_year, 'closingEntryId', v_closing), 'fiscal-years/' || close_fiscal_year.tenant::text || '/' || close_fiscal_year.fiscal_year::text, (close_fiscal_year.tenant)::text, null, 'better-supabase/accounting');
  perform better_supabase.audit_event(
    event_type => 'fiscal_year.closed',
    category => 'data',
    target_type => 'fiscal_year',
    record_id => close_fiscal_year.fiscal_year::text,
    target_label => close_fiscal_year.fiscal_year::text,
    summary => 'closed fiscal year ' || close_fiscal_year.fiscal_year::text,
    summary_params => jsonb_build_object('fiscalYear', close_fiscal_year.fiscal_year),
    tenant => (close_fiscal_year.tenant)::uuid,
    metadata => jsonb_build_object('organizationId', close_fiscal_year.tenant, 'fiscalYear', close_fiscal_year.fiscal_year, 'closingEntryId', v_closing)
  );
  return jsonb_build_object('organizationId', close_fiscal_year.tenant, 'fiscalYear', close_fiscal_year.fiscal_year, 'closingEntryId', v_closing);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.close_ledger_account (
  account_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."ledger_accounts"%rowtype;
  v_balance "better_supabase"."ledger_balances"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."ledger_accounts" x where x."id" = close_ledger_account.account_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'ledger.read'), false) or coalesce(v_row."owner_id" = auth.uid(), false) or (v_row."read_permission" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", v_row."read_permission"), false))) then
    raise exception 'ledger account not found' using errcode = 'P0002', hint = 'LEDGER_ACCOUNT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'ledger.manage'), false)) then
    raise exception 'not allowed to manage ledger accounts' using errcode = '42501', hint = 'LEDGER_FORBIDDEN';
  end if;
  if v_row."managed_by" is not null and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'this account belongs to another block' using errcode = '55000', hint = 'LEDGER_ACCOUNT_MANAGED';
  end if;
  select * into v_balance from "better_supabase"."ledger_balances" x where x."account_id" = v_row."id" for update;
  if coalesce(v_balance."balance", 0) <> 0 or coalesce(v_balance."held", 0) <> 0 then
    raise exception 'only an account with a zero balance and no holds can be closed' using errcode = '55000', hint = 'LEDGER_ACCOUNT_NOT_EMPTY';
  end if;
  if v_row."closed_at" is null then
    update "better_supabase"."ledger_accounts" x set "closed_at" = now(), "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    perform "better_supabase".emit_event('ledger_account.closed', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'code', v_row."code", 'unit', v_row."unit", 'holderType', v_row."holder_type", 'holderId', v_row."holder_id"), 'ledger-accounts/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/ledger');
  perform better_supabase.audit_event(
    event_type => 'ledger_account.closed',
    category => 'billing',
    target_type => 'ledger_account',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'closed ledger account ' || v_row."code",
    summary_params => jsonb_build_object('code', v_row."code"),
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'code', v_row."code", 'unit', v_row."unit", 'holderType', v_row."holder_type", 'holderId', v_row."holder_id")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'code', v_row."code", 'name', v_row."name", 'unit', v_row."unit", 'scale', v_row."scale", 'holderType', v_row."holder_type", 'holderId', v_row."holder_id", 'ownerId', v_row."owner_id", 'allowNegative', v_row."allow_negative", 'readPermission', v_row."read_permission", 'managedBy', v_row."managed_by", 'metadata', v_row."metadata", 'closedAt', v_row."closed_at", 'createdAt', v_row."created_at", 'balance', coalesce(v_balance."balance", 0)::text, 'held', coalesce(v_balance."held", 0)::text, 'available', coalesce(v_balance."balance" - v_balance."held", 0)::text);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_accounting_entry (
  entry_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."accounting_entries"%rowtype;
  v_json jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."accounting_entries" y where y."id" = delete_accounting_entry.entry_id for update;
  if not found then
    raise exception 'entry not found' using errcode = 'P0002', hint = 'ACCOUNTING_ENTRY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'accounting.write'), false)) then
    raise exception 'not allowed to write accounting entries' using errcode = '42501', hint = 'ACCOUNTING_ENTRY_FORBIDDEN';
  end if;
  if v_row."status" <> 'draft' then
    raise exception 'a posted entry can''t change; reverse it' using errcode = '55000', hint = 'ACCOUNTING_ENTRY_POSTED';
  end if;
  v_json := jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'journalId', v_row."journal_id", 'number', v_row."number", 'fiscalYear', v_row."fiscal_year", 'entryDate', v_row."entry_date", 'periodId', v_row."period_id", 'status', v_row."status", 'reference', v_row."reference", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'reversesId', v_row."reverses_id", 'memo', v_row."memo", 'memoKey', v_row."memo_key", 'memoParams', v_row."memo_params", 'total', coalesce((select sum(et."debit") from "better_supabase"."accounting_entry_lines" et where et."entry_id" = v_row."id"), 0)::text, 'postedAt', v_row."posted_at", 'postedBy', v_row."posted_by", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'lines', coalesce((select jsonb_agg(jsonb_build_object('id', el."id", 'accountId', el."account_id", 'accountCode', ea."code", 'accountName', ea."name", 'debit', el."debit"::text, 'credit', el."credit"::text, 'currency', el."currency", 'amountCurrency', el."amount_currency"::text, 'fxRate', el."fx_rate"::text, 'taxCodeId', el."tax_code_id", 'taxAmount', el."tax_amount"::text, 'partyId', el."party_id", 'dimensions', el."dimensions", 'description', el."description") order by el."position", el."id") from "better_supabase"."accounting_entry_lines" el join "better_supabase"."accounting_accounts" ea on ea."id" = el."account_id" where el."entry_id" = v_row."id"), '[]'::jsonb));
  delete from "better_supabase"."accounting_entries" y where y."id" = v_row."id";
  return v_json;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.donation_settle (
  gift_id    uuid,
  status     text,
  provider   text DEFAULT NULL::text,
  payment_id text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."donations"%rowtype;
  v_fund "better_supabase"."donation_funds"%rowtype;
  v_tx uuid;
begin
  select * into v_row from "better_supabase"."donations" x where x."id" = donation_settle.gift_id for update;
  if not found then
    raise exception 'no such gift you can read' using errcode = 'P0002', hint = 'DONATION_NOT_FOUND';
  end if;
  if donation_settle.status not in ('pending', 'succeeded', 'failed', 'refunded') then
    raise exception 'status is pending, succeeded, failed or refunded' using errcode = '22023', hint = 'DONATION_STATUS_INVALID';
  end if;
  if donation_settle.payment_id is not null and v_row."payment_reference" is null then
    update "better_supabase"."donations" x set "provider" = coalesce(donation_settle.provider, x."provider"),
        "payment_reference" = donation_settle.payment_id, "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
  end if;
  select * into v_fund from "better_supabase"."donation_funds" y where y."id" = v_row."fund_id";
  if donation_settle.status = 'succeeded' and v_row."status" in ('pending', 'failed') then
    v_tx := "better_supabase"."ledger_post"(v_row."tenant_id", 'donation.gift',
      jsonb_build_array(
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'gift_cash', 'donations.cash:' || v_row."currency",
      'Donations received ' || v_row."currency", v_row."currency"::text, 0::smallint, null, null, null, true, 'donations.read', 'donations', null), 'amount', v_row."amount"),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'gift_income',
      'donations.fund:' || coalesce(v_fund."key", 'general') || ':' || v_row."currency",
      'Donations: ' || coalesce(v_fund."name", 'General'), v_row."currency"::text, 0::smallint,
      case when v_fund."id" is null then null else 'donation_fund' end, v_fund."id"::text, null, true, 'donations.read', 'donations', null), 'amount', -v_row."amount")),
      'donations', v_row."id"::text, 'Gift', 'donation:' || v_row."id"::text || ':posted', v_row."received_on"::timestamptz,
      jsonb_strip_nulls(jsonb_build_object('donationId', v_row."id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id")),
      memo_key => 'donation.gift', memo_params => '{}'::jsonb);
    update "better_supabase"."donations" x set "status" = 'posted', "transaction_id" = v_tx, "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    if not better_supabase.import_run() is not null then
    perform "better_supabase"."accounting_post_source"('gift', v_row."id"::text);
  end if;
    perform "better_supabase".emit_event('donation.received', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'pledgeId', v_row."pledge_id", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'status', v_row."status"), 'donations/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/donations');
  perform better_supabase.audit_event(
    event_type => 'donation.received',
    category => 'billing',
    target_type => 'donation',
    record_id => v_row."id"::text,
    summary => 'received a gift',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'pledgeId', v_row."pledge_id", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'status', v_row."status")
  );
  elsif donation_settle.status = 'failed' and v_row."status" = 'pending' then
    update "better_supabase"."donations" x set "status" = 'failed', "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    perform "better_supabase".emit_event('donation.failed', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'pledgeId', v_row."pledge_id", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'status', v_row."status"), 'donations/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/donations');
  perform better_supabase.audit_event(
    event_type => 'donation.failed',
    category => 'billing',
    target_type => 'donation',
    record_id => v_row."id"::text,
    summary => 'a gift payment failed',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'pledgeId', v_row."pledge_id", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'status', v_row."status")
  );
  elsif donation_settle.status = 'refunded' and v_row."status" = 'posted' then
    v_tx := "better_supabase"."ledger_post"(v_row."tenant_id", 'donation.refund',
      jsonb_build_array(
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'gift_cash', 'donations.cash:' || v_row."currency",
      'Donations received ' || v_row."currency", v_row."currency"::text, 0::smallint, null, null, null, true, 'donations.read', 'donations', null), 'amount', -v_row."amount"),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'gift_income',
      'donations.fund:' || coalesce(v_fund."key", 'general') || ':' || v_row."currency",
      'Donations: ' || coalesce(v_fund."name", 'General'), v_row."currency"::text, 0::smallint,
      case when v_fund."id" is null then null else 'donation_fund' end, v_fund."id"::text, null, true, 'donations.read', 'donations', null), 'amount', v_row."amount")),
      'donations', v_row."id"::text, 'Gift refunded', 'donation:' || v_row."id"::text || ':refunded', null,
      jsonb_build_object('donationId', v_row."id"),
      memo_key => 'donation.refund', memo_params => '{}'::jsonb);
    update "better_supabase"."donation_receipts" x set "voided_at" = now(), "void_reason" = 'the gift was refunded'
      where x."id" = v_row."receipt_id" and x."kind" = 'gift' and x."voided_at" is null;
    update "better_supabase"."donations" x set "status" = 'refunded', "refund_transaction_id" = v_tx, "receipt_id" = null, "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    perform "better_supabase"."accounting_reverse_source"(v_row."tenant_id", 'gift', v_row."id"::text);
    perform "better_supabase".emit_event('donation.refunded', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'pledgeId', v_row."pledge_id", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'status', v_row."status"), 'donations/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/donations');
  perform better_supabase.audit_event(
    event_type => 'donation.refunded',
    category => 'billing',
    target_type => 'donation',
    record_id => v_row."id"::text,
    summary => 'refunded a gift',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'pledgeId', v_row."pledge_id", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'status', v_row."status")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'pledgeId', v_row."pledge_id", 'periodStart', v_row."period_start", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'receivedOn', v_row."received_on", 'method', v_row."method", 'status', v_row."status", 'provider', v_row."provider", 'paymentReference', v_row."payment_reference", 'transactionId', v_row."transaction_id", 'refundTransactionId', v_row."refund_transaction_id", 'receiptId', v_row."receipt_id", 'note', v_row."note", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_accounting_entry (
  entry_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'journalId', x."journal_id", 'number', x."number", 'fiscalYear', x."fiscal_year", 'entryDate', x."entry_date", 'periodId', x."period_id", 'status', x."status", 'reference', x."reference", 'sourceType', x."source_type", 'sourceId', x."source_id", 'reversesId', x."reverses_id", 'memo', x."memo", 'memoKey', x."memo_key", 'memoParams', x."memo_params", 'total', coalesce((select sum(et."debit") from "better_supabase"."accounting_entry_lines" et where et."entry_id" = x."id"), 0)::text, 'postedAt', x."posted_at", 'postedBy', x."posted_by", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'lines', coalesce((select jsonb_agg(jsonb_build_object('id', el."id", 'accountId', el."account_id", 'accountCode', ea."code", 'accountName', ea."name", 'debit', el."debit"::text, 'credit', el."credit"::text, 'currency', el."currency", 'amountCurrency', el."amount_currency"::text, 'fxRate', el."fx_rate"::text, 'taxCodeId', el."tax_code_id", 'taxAmount', el."tax_amount"::text, 'partyId', el."party_id", 'dimensions', el."dimensions", 'description', el."description") order by el."position", el."id") from "better_supabase"."accounting_entry_lines" el join "better_supabase"."accounting_accounts" ea on ea."id" = el."account_id" where el."entry_id" = x."id"), '[]'::jsonb)) from "better_supabase"."accounting_entries" x where x."id" = get_accounting_entry.entry_id
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_audit_event (
  entry_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  result jsonb;
begin
  execute $q$select $q$ || $e$jsonb_build_object('id', l."id", 'table', l."table_name", 'record', l."record_id", 'op', l."op", 'old', l."old_record", 'new', l."new_record", 'changed', l."changed", 'actorId', l."actor_id", 'actorRole', l."actor_role", 'actorKind', l."actor_kind", 'actorLabel', l."actor_label", 'tenant', l."tenant_id", 'tenantLabel', l."tenant_label", 'occurredAt', l."occurred_at", 'impersonatedBy', l."impersonated_by", 'impersonationReason', l."impersonation_reason", 'supportSession', l."support_session_id", 'eventType', l."event_type", 'category', l."category", 'outcome', l."outcome") || jsonb_build_object('source', l."source", 'targetType', l."target_type", 'targetLabel', l."target_label", 'summary', l."summary", 'summaryKey', l."summary_key", 'summaryParams', l."summary_params", 'requestId', l."request_id", 'correlationId', l."correlation_id", 'scope', l."scope", 'metadata', l."metadata")$e$ || $q$ from "better_supabase"."audit_events" l where l."id" = $1$q$
  into result
  using entry_id::bigint;
  return result;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_ledger_transaction (
  transaction_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."ledger_transactions"%rowtype;
begin
  select * into v_row from "better_supabase"."ledger_transactions" x where x."id" = get_ledger_transaction.transaction_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'ledger.read'), false) or exists (
    select 1 from "better_supabase"."ledger_entries" y join "better_supabase"."ledger_accounts" x on x."id" = y."account_id"
    where y."transaction_id" = v_row."id" and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', x."tenant_id", 'ledger.read'), false) or coalesce(x."owner_id" = auth.uid(), false) or (x."read_permission" is not null and coalesce(better_supabase.can('tenant', x."tenant_id", x."read_permission"), false)))
  )) then
    raise exception 'ledger transaction not found' using errcode = 'P0002', hint = 'LEDGER_TRANSACTION_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'referenceType', v_row."reference_type", 'referenceId', v_row."reference_id", 'memo', v_row."memo", 'memoKey', v_row."memo_key", 'memoParams', v_row."memo_params", 'idempotencyKey', v_row."idempotency_key", 'reverses', v_row."reverses", 'metadata', v_row."metadata", 'effectiveAt', v_row."effective_at", 'actorId', v_row."actor_id", 'createdAt', v_row."created_at", 'entries', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'accountId', y."account_id", 'amount', y."amount"::text, 'unit', y."unit") order by y."created_at", y."id") from "better_supabase"."ledger_entries" y where y."transaction_id" = v_row."id"), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.ledger_account_entries (
  account_id uuid,
  before     timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  page_size  integer                  DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_account "better_supabase"."ledger_accounts"%rowtype;
  v_rows jsonb;
begin
  select * into v_account from "better_supabase"."ledger_accounts" x where x."id" = ledger_account_entries.account_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_account."tenant_id", 'ledger.read'), false) or coalesce(v_account."owner_id" = auth.uid(), false) or (v_account."read_permission" is not null and coalesce(better_supabase.can('tenant', v_account."tenant_id", v_account."read_permission"), false))) then
    raise exception 'ledger account not found' using errcode = 'P0002', hint = 'LEDGER_ACCOUNT_NOT_FOUND';
  end if;
  select coalesce(jsonb_agg(z.item order by z.created desc, z.id desc), '[]'::jsonb) into v_rows
  from (
    select jsonb_build_object('id', y."id", 'accountId', y."account_id", 'amount', y."amount"::text, 'unit', y."unit",
        'transactionId', r."id", 'kind', r."kind", 'referenceType', r."reference_type", 'referenceId', r."reference_id",
        'memo', r."memo", 'memoKey', r."memo_key", 'memoParams', r."memo_params", 'reverses', r."reverses", 'metadata', r."metadata", 'effectiveAt', r."effective_at", 'actorId', r."actor_id", 'createdAt', y."created_at") as item,
      y."created_at" as created, y."id" as id
    from "better_supabase"."ledger_entries" y
    join "better_supabase"."ledger_transactions" r on r."id" = y."transaction_id"
    where y."account_id" = v_account."id"
      and (ledger_account_entries.before is null or y."created_at" < ledger_account_entries.before)
    order by y."created_at" desc, y."id" desc
    limit least(greatest(coalesce(ledger_account_entries.page_size, 50), 1), 500)
  ) z;
  return v_rows;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.ledger_post (
  tenant          uuid,
  kind            text,
  lines           jsonb,
  reference_type  text                     DEFAULT NULL::text,
  reference_id    text                     DEFAULT NULL::text,
  memo            text                     DEFAULT NULL::text,
  idempotency_key text                     DEFAULT NULL::text,
  effective_at    timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  metadata        jsonb                    DEFAULT NULL::jsonb,
  reverses        uuid                     DEFAULT NULL::uuid,
  memo_key        text                     DEFAULT NULL::text,
  memo_params     jsonb                    DEFAULT NULL::jsonb
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_id uuid;
  v_row "better_supabase"."ledger_transactions"%rowtype;
begin
  if ledger_post.idempotency_key is not null then
    select x."id" into v_id from "better_supabase"."ledger_transactions" x
      where x."tenant_id" = ledger_post.tenant and x."idempotency_key" = ledger_post.idempotency_key;
    if found then
      return v_id;
    end if;
  end if;
  if ledger_post.kind is null or ledger_post.kind !~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)*$' then
    raise exception 'kind must be lowercase words joined by dots, such as credit.grant' using errcode = '22023', hint = 'LEDGER_KIND_INVALID';
  end if;
  if jsonb_typeof(ledger_post.lines) is distinct from 'array' or jsonb_array_length(ledger_post.lines) < 2 then
    raise exception 'a transaction needs at least two lines' using errcode = '22023', hint = 'LEDGER_LINES_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(ledger_post.lines) l
    where jsonb_typeof(l.value) is distinct from 'object'
      or coalesce(l.value ->> 'account', '') !~ '^[0-9a-fA-F-]{36}$'
      or coalesce(l.value ->> 'amount', '') !~ '^-?[0-9]{1,18}$'
      or (l.value ->> 'amount')::bigint = 0
  ) then
    raise exception 'every line needs an account id and a non-zero integer amount' using errcode = '22023', hint = 'LEDGER_LINES_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(ledger_post.lines) l
    left join "better_supabase"."ledger_accounts" x on x."id" = (l.value ->> 'account')::uuid
      and x."tenant_id" = ledger_post.tenant and x."closed_at" is null
    where x."id" is null
  ) then
    raise exception 'an account of the transaction doesn''t exist here or is closed' using errcode = 'P0002', hint = 'LEDGER_ACCOUNT_NOT_FOUND';
  end if;
  if exists (
    select 1 from jsonb_array_elements(ledger_post.lines) l
    join "better_supabase"."ledger_accounts" x on x."id" = (l.value ->> 'account')::uuid
    group by x."unit" having sum((l.value ->> 'amount')::bigint) <> 0
  ) then
    raise exception 'the lines of a ledger transaction must sum to zero per unit' using errcode = '23514', hint = 'LEDGER_UNBALANCED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_ledger_transaction_post"(uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::jsonb)', v_hook::oid::regproc)
        using ledger_post.tenant, ledger_post.kind, ledger_post.lines;
    end if;
  end;
  insert into "better_supabase"."ledger_transactions" ("tenant_id", "kind", "reference_type", "reference_id", "memo", "memo_key", "memo_params", "idempotency_key", "reverses", "metadata", "effective_at", "actor_id")
  values (ledger_post.tenant, ledger_post.kind, ledger_post.reference_type, ledger_post.reference_id, nullif(trim(ledger_post.memo), ''), ledger_post.memo_key, ledger_post.memo_params,
    ledger_post.idempotency_key, ledger_post.reverses, coalesce(ledger_post.metadata, '{}'::jsonb), coalesce(ledger_post.effective_at, now()), auth.uid())
  returning * into v_row;
  insert into "better_supabase"."ledger_entries" ("tenant_id", "transaction_id", "account_id", "amount", "unit", "effective_at")
  select ledger_post.tenant, v_row."id", x."id", (l.value ->> 'amount')::bigint, x."unit", v_row."effective_at"
  from jsonb_array_elements(ledger_post.lines) with ordinality as l(value, n)
  join "better_supabase"."ledger_accounts" x on x."id" = (l.value ->> 'account')::uuid
  order by l.n;
  perform "better_supabase".emit_event('ledger_transaction.posted', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'referenceType', v_row."reference_type", 'referenceId', v_row."reference_id", 'reverses', v_row."reverses", 'entries', (select count(*)::integer from "better_supabase"."ledger_entries" y where y."transaction_id" = v_row."id")), 'ledger-transactions/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/ledger');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_ledger_transaction_post"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return v_row."id";
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_accounting_entries (
  tenant     uuid,
  journal_id uuid    DEFAULT NULL::uuid,
  status     text    DEFAULT NULL::text,
  since      date    DEFAULT NULL::date,
  until      date    DEFAULT NULL::date,
  page_size  integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(z.entry order by z.entry_date desc, z.created_at desc), '[]'::jsonb)
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'journalId', x."journal_id", 'number', x."number", 'fiscalYear', x."fiscal_year", 'entryDate', x."entry_date", 'periodId', x."period_id", 'status', x."status", 'reference', x."reference", 'sourceType', x."source_type", 'sourceId', x."source_id", 'reversesId', x."reverses_id", 'memo', x."memo", 'memoKey', x."memo_key", 'memoParams', x."memo_params", 'total', coalesce((select sum(et."debit") from "better_supabase"."accounting_entry_lines" et where et."entry_id" = x."id"), 0)::text, 'postedAt', x."posted_at", 'postedBy', x."posted_by", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as entry, x."entry_date" as entry_date, x."created_at" as created_at
    from "better_supabase"."accounting_entries" x
    where x."tenant_id" = list_accounting_entries.tenant
      and (list_accounting_entries.journal_id is null or x."journal_id" = list_accounting_entries.journal_id)
      and (list_accounting_entries.status is null or x."status" = list_accounting_entries.status)
      and (list_accounting_entries.since is null or x."entry_date" >= list_accounting_entries.since)
      and (list_accounting_entries.until is null or x."entry_date" <= list_accounting_entries.until)
    order by x."entry_date" desc, x."created_at" desc
    limit least(greatest(coalesce(list_accounting_entries.page_size, 50), 1), 500)
  ) z
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_audit_events (
  for_tenants         uuid[]                   DEFAULT NULL::uuid[],
  for_event_types     text[]                   DEFAULT NULL::text[],
  for_actors          uuid[]                   DEFAULT NULL::uuid[],
  for_target_types    text[]                   DEFAULT NULL::text[],
  for_records         text[]                   DEFAULT NULL::text[],
  for_categories      text[]                   DEFAULT NULL::text[],
  for_outcomes        text[]                   DEFAULT NULL::text[],
  search              text                     DEFAULT NULL::text,
  for_sources         text[]                   DEFAULT NULL::text[],
  for_actor_kinds     text[]                   DEFAULT NULL::text[],
  for_correlation_ids text[]                   DEFAULT NULL::text[],
  since               timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  until               timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  cursor_at           timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  cursor_id           text                     DEFAULT NULL::text,
  max_items           integer                  DEFAULT 50,
  ascending           boolean                  DEFAULT false,
  skip                integer                  DEFAULT 0,
  entry_fields        text                     DEFAULT 'full'::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_where text := 'true';
  v_order text := case when ascending then 'asc' else 'desc' end;
  v_skip text := '';
  v_entry text;
  result jsonb;
begin
  -- 'summary' leaves out the old and new record, the changed columns and the
  -- metadata, so a page of a busy log stays small. get_audit_event returns the
  -- full entry.
  v_entry := case when entry_fields = 'summary'
    then $e$jsonb_build_object('id', l."id", 'table', l."table_name", 'record', l."record_id", 'op', l."op", 'actorId', l."actor_id", 'actorRole', l."actor_role", 'actorKind', l."actor_kind", 'actorLabel', l."actor_label", 'tenant', l."tenant_id", 'tenantLabel', l."tenant_label", 'occurredAt', l."occurred_at", 'impersonatedBy', l."impersonated_by", 'impersonationReason', l."impersonation_reason", 'supportSession', l."support_session_id", 'eventType', l."event_type", 'category', l."category", 'outcome', l."outcome", 'source', l."source", 'targetType', l."target_type", 'targetLabel', l."target_label") || jsonb_build_object('summary', l."summary", 'summaryKey', l."summary_key", 'summaryParams', l."summary_params", 'requestId', l."request_id", 'correlationId', l."correlation_id", 'scope', l."scope")$e$
    else $e$jsonb_build_object('id', l."id", 'table', l."table_name", 'record', l."record_id", 'op', l."op", 'old', l."old_record", 'new', l."new_record", 'changed', l."changed", 'actorId', l."actor_id", 'actorRole', l."actor_role", 'actorKind', l."actor_kind", 'actorLabel', l."actor_label", 'tenant', l."tenant_id", 'tenantLabel', l."tenant_label", 'occurredAt', l."occurred_at", 'impersonatedBy', l."impersonated_by", 'impersonationReason', l."impersonation_reason", 'supportSession', l."support_session_id", 'eventType', l."event_type", 'category', l."category", 'outcome', l."outcome") || jsonb_build_object('source', l."source", 'targetType', l."target_type", 'targetLabel', l."target_label", 'summary', l."summary", 'summaryKey', l."summary_key", 'summaryParams', l."summary_params", 'requestId', l."request_id", 'correlationId', l."correlation_id", 'scope', l."scope", 'metadata', l."metadata")$e$
  end;
  if cardinality(for_tenants) > 0 then
    v_where := v_where || $q$ and l."tenant_id" = any ($1)$q$;
  end if;
  if cardinality(for_event_types) > 0 then
    v_where := v_where || $q$ and l."event_type" = any ($2)$q$;
  end if;
  if cardinality(for_actors) > 0 then
    v_where := v_where || $q$ and l."actor_id" = any ($3)$q$;
  end if;
  if cardinality(for_target_types) > 0 then
    v_where := v_where || $q$ and l."target_type" = any ($4)$q$;
  end if;
  if cardinality(for_records) > 0 then
    v_where := v_where || $q$ and l."record_id" = any ($5)$q$;
  end if;
  if cardinality(for_categories) > 0 then
    v_where := v_where || $q$ and l."category" = any ($6)$q$;
  end if;
  if cardinality(for_outcomes) > 0 then
    v_where := v_where || $q$ and l."outcome" = any ($7)$q$;
  end if;
  if cardinality(for_sources) > 0 then
    v_where := v_where || $q$ and l."source" = any ($9)$q$;
  end if;
  if cardinality(for_actor_kinds) > 0 then
    v_where := v_where || $q$ and l."actor_kind" = any ($10)$q$;
  end if;
  if cardinality(for_correlation_ids) > 0 then
    v_where := v_where || $q$ and l."correlation_id" = any ($11)$q$;
  end if;
  if search <> '' then
    v_where := v_where || $q$ and concat_ws(' ', l."event_type", l."summary", l."target_label", l."actor_label", l."tenant_label", l."record_id", l."table_name") ilike '%' || replace(replace(replace($8, '\', '\\'), '%', '\%'), '_', '\_') || '%'$q$;
  end if;
  if since is not null then
    v_where := v_where || $q$ and l."occurred_at" >= $12$q$;
  end if;
  if until is not null then
    v_where := v_where || $q$ and l."occurred_at" < $13$q$;
  end if;
  if cursor_at is not null then
    v_where := v_where || case when ascending
      then $q$ and (l."occurred_at", l."id") > ($14, $15::bigint)$q$
      else $q$ and (l."occurred_at", l."id") < ($14, $15::bigint)$q$
    end;
  elsif coalesce(skip, 0) > 0 then
    v_skip := ' offset $17';
  end if;
  -- Only the filters passed reach the query, so the planner sees no
  -- "is null or" branches and can use the (tenant, occurred_at) index.
  execute $q$select coalesce(jsonb_agg(x.entry order by x.occurred_at $q$ || v_order || $q$, x.id $q$ || v_order || $q$), '[]')
  from (
    select $q$ || v_entry || $q$ as entry, l."occurred_at" as occurred_at, l."id" as id
    from "better_supabase"."audit_events" l
    where $q$ || v_where || $q$
    order by l."occurred_at" $q$ || v_order || $q$, l."id" $q$ || v_order || $q$
    limit $16$q$ || v_skip || $q$
  ) x$q$
  into result
  using for_tenants, for_event_types, for_actors, for_target_types, for_records, for_categories, for_outcomes, search, for_sources, for_actor_kinds, for_correlation_ids, since, until, cursor_at, cursor_id, least(greatest(coalesce(max_items, 50), 1), 1000), greatest(coalesce(skip, 0), 0);
  return result;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.lock_accounting_period (
  period_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_period "better_supabase"."accounting_periods"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_period from "better_supabase"."accounting_periods" y where y."id" = lock_accounting_period.period_id for update;
  if not found then
    raise exception 'period not found' using errcode = 'P0002', hint = 'ACCOUNTING_PERIOD_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_period."tenant_id", 'accounting.close'), false)) then
    raise exception 'not allowed to lock accounting periods' using errcode = '42501', hint = 'ACCOUNTING_PERIOD_FORBIDDEN';
  end if;
  if v_period."status" = 'locked' then
    return jsonb_build_object('id', v_period."id", 'organizationId', v_period."tenant_id", 'fiscalYear', v_period."fiscal_year", 'number', v_period."number", 'startsOn', v_period."starts_on", 'endsOn', v_period."ends_on", 'status', v_period."status", 'closedAt', v_period."closed_at", 'closedBy', v_period."closed_by", 'lockedAt', v_period."locked_at", 'lockedBy', v_period."locked_by");
  end if;
  if v_period."status" <> 'closed' then
    raise exception 'close the period before you lock it' using errcode = '55000', hint = 'ACCOUNTING_PERIOD_CLOSE_BLOCKED';
  end if;
  update "better_supabase"."accounting_periods" y set "status" = 'locked', "locked_at" = now(), "locked_by" = auth.uid()
  where y."id" = v_period."id"
  returning * into v_period;
  perform "better_supabase".emit_event('accounting_period.locked', jsonb_build_object('organizationId', v_period."tenant_id", 'id', v_period."id", 'fiscalYear', v_period."fiscal_year", 'number', v_period."number", 'startsOn', v_period."starts_on", 'endsOn', v_period."ends_on"), 'accounting-periods/' || v_period."id"::text, (v_period."tenant_id")::text, null, 'better-supabase/accounting');
  perform better_supabase.audit_event(
    event_type => 'accounting_period.locked',
    category => 'data',
    target_type => 'accounting_period',
    record_id => v_period."id"::text,
    target_label => v_period."fiscal_year"::text || '-' || lpad(v_period."number"::text, 2, '0'),
    summary => 'locked period ' || v_period."fiscal_year"::text || '-' || lpad(v_period."number"::text, 2, '0'),
    summary_params => jsonb_build_object('fiscalYear', v_period."fiscal_year", 'number', v_period."number"),
    tenant => (v_period."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_period."tenant_id", 'id', v_period."id", 'fiscalYear', v_period."fiscal_year", 'number', v_period."number", 'startsOn', v_period."starts_on", 'endsOn', v_period."ends_on")
  );
  return jsonb_build_object('id', v_period."id", 'organizationId', v_period."tenant_id", 'fiscalYear', v_period."fiscal_year", 'number', v_period."number", 'startsOn', v_period."starts_on", 'endsOn', v_period."ends_on", 'status', v_period."status", 'closedAt', v_period."closed_at", 'closedBy', v_period."closed_by", 'lockedAt', v_period."locked_at", 'lockedBy', v_period."locked_by");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.open_ledger_account (
  tenant          uuid,
  kind            text,
  code            text,
  name            text,
  unit            text,
  scale           smallint DEFAULT 0,
  holder_type     text     DEFAULT NULL::text,
  holder_id       text     DEFAULT NULL::text,
  owner_id        uuid     DEFAULT NULL::uuid,
  allow_negative  boolean  DEFAULT false,
  read_permission text     DEFAULT NULL::text,
  metadata        jsonb    DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."ledger_accounts"%rowtype;
  v_balance "better_supabase"."ledger_balances"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', open_ledger_account.tenant, 'ledger.manage'), false)) then
    raise exception 'not allowed to manage ledger accounts' using errcode = '42501', hint = 'LEDGER_FORBIDDEN';
  end if;
  if exists (select 1 from "better_supabase"."ledger_accounts" x where x."tenant_id" = open_ledger_account.tenant and x."code" = open_ledger_account.code) then
    raise exception 'an account with this code already exists' using errcode = '23505', hint = 'LEDGER_ACCOUNT_CODE_TAKEN';
  end if;
  insert into "better_supabase"."ledger_accounts" ("tenant_id", "kind", "code", "name", "unit", "scale", "holder_type", "holder_id", "owner_id", "allow_negative", "read_permission", "metadata")
  values (open_ledger_account.tenant, open_ledger_account.kind, open_ledger_account.code, open_ledger_account.name, open_ledger_account.unit,
    coalesce(open_ledger_account.scale, 0), open_ledger_account.holder_type, open_ledger_account.holder_id, open_ledger_account.owner_id,
    coalesce(open_ledger_account.allow_negative, false), open_ledger_account.read_permission, coalesce(open_ledger_account.metadata, '{}'::jsonb))
  returning * into v_row;
  perform "better_supabase".emit_event('ledger_account.opened', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'code', v_row."code", 'unit', v_row."unit", 'holderType', v_row."holder_type", 'holderId', v_row."holder_id"), 'ledger-accounts/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/ledger');
  perform better_supabase.audit_event(
    event_type => 'ledger_account.opened',
    category => 'billing',
    target_type => 'ledger_account',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'opened ledger account ' || v_row."code",
    summary_params => jsonb_build_object('code', v_row."code"),
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'code', v_row."code", 'unit', v_row."unit", 'holderType', v_row."holder_type", 'holderId', v_row."holder_id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'code', v_row."code", 'name', v_row."name", 'unit', v_row."unit", 'scale', v_row."scale", 'holderType', v_row."holder_type", 'holderId', v_row."holder_id", 'ownerId', v_row."owner_id", 'allowNegative', v_row."allow_negative", 'readPermission', v_row."read_permission", 'managedBy', v_row."managed_by", 'metadata', v_row."metadata", 'closedAt', v_row."closed_at", 'createdAt', v_row."created_at", 'balance', coalesce(v_balance."balance", 0)::text, 'held', coalesce(v_balance."held", 0)::text, 'available', coalesce(v_balance."balance" - v_balance."held", 0)::text);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_accounting_entries (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_accounting_entries.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 500);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status') then
      raise exception 'facet is one of status' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text end) as v
      from "better_supabase"."accounting_entries" x
      where x."tenant_id" = page_accounting_entries.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'journalId' is not null and jsonb_typeof(v_filters -> 'journalId') <> 'null' and not (jsonb_typeof(v_filters -> 'journalId') = 'array' and jsonb_array_length(v_filters -> 'journalId') = 0)) or x."journal_id"::text = any((case when jsonb_typeof(v_filters -> 'journalId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'journalId')) else array[v_filters ->> 'journalId'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{since,0}', v_filters ->> 'since'), '') is null or x."entry_date" >= (nullif(coalesce(v_filters #>> '{since,0}', v_filters ->> 'since'), ''))::date)
        and (nullif(coalesce(v_filters #>> '{until,0}', v_filters ->> 'until'), '') is null or x."entry_date" <= (nullif(coalesce(v_filters #>> '{until,0}', v_filters ->> 'until'), ''))::date)
        and (v_search is null or x."reference" ilike v_search or x."memo" ilike v_search or x."number" ilike v_search)
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "better_supabase"."accounting_entries" x
      where x."tenant_id" = page_accounting_entries.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'journalId' is not null and jsonb_typeof(v_filters -> 'journalId') <> 'null' and not (jsonb_typeof(v_filters -> 'journalId') = 'array' and jsonb_array_length(v_filters -> 'journalId') = 0)) or x."journal_id"::text = any((case when jsonb_typeof(v_filters -> 'journalId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'journalId')) else array[v_filters ->> 'journalId'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{since,0}', v_filters ->> 'since'), '') is null or x."entry_date" >= (nullif(coalesce(v_filters #>> '{since,0}', v_filters ->> 'since'), ''))::date)
        and (nullif(coalesce(v_filters #>> '{until,0}', v_filters ->> 'until'), '') is null or x."entry_date" <= (nullif(coalesce(v_filters #>> '{until,0}', v_filters ->> 'until'), ''))::date)
        and (v_search is null or x."reference" ilike v_search or x."memo" ilike v_search or x."number" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('entryDate', 'createdAt') then
    raise exception 'sort is one of entryDate, createdAt' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'journalId', x."journal_id", 'number', x."number", 'fiscalYear', x."fiscal_year", 'entryDate', x."entry_date", 'periodId', x."period_id", 'status', x."status", 'reference', x."reference", 'sourceType', x."source_type", 'sourceId', x."source_id", 'reversesId', x."reverses_id", 'memo', x."memo", 'memoKey', x."memo_key", 'memoParams', x."memo_params", 'total', coalesce((select sum(et."debit") from "better_supabase"."accounting_entry_lines" et where et."entry_id" = x."id"), 0)::text, 'postedAt', x."posted_at", 'postedBy', x."posted_by", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."entry_date")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."accounting_entries" x
      where x."tenant_id" = page_accounting_entries.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'journalId' is not null and jsonb_typeof(v_filters -> 'journalId') <> 'null' and not (jsonb_typeof(v_filters -> 'journalId') = 'array' and jsonb_array_length(v_filters -> 'journalId') = 0)) or x."journal_id"::text = any((case when jsonb_typeof(v_filters -> 'journalId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'journalId')) else array[v_filters ->> 'journalId'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{since,0}', v_filters ->> 'since'), '') is null or x."entry_date" >= (nullif(coalesce(v_filters #>> '{since,0}', v_filters ->> 'since'), ''))::date)
        and (nullif(coalesce(v_filters #>> '{until,0}', v_filters ->> 'until'), '') is null or x."entry_date" <= (nullif(coalesce(v_filters #>> '{until,0}', v_filters ->> 'until'), ''))::date)
        and (v_search is null or x."reference" ilike v_search or x."memo" ilike v_search or x."number" ilike v_search)
        and (v_after is null or (x."entry_date" >= (v_after ->> 0)::date and ((x."entry_date" > (v_after ->> 0)::date) or (x."entry_date" = (v_after ->> 0)::date and x."created_at" < (v_after ->> 1)::timestamptz) or (x."entry_date" = (v_after ->> 0)::date and x."created_at" = (v_after ->> 1)::timestamptz and x."id" < (v_after ->> 2)::uuid))))
      order by x."entry_date" asc, x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'journalId', x."journal_id", 'number', x."number", 'fiscalYear', x."fiscal_year", 'entryDate', x."entry_date", 'periodId', x."period_id", 'status', x."status", 'reference', x."reference", 'sourceType', x."source_type", 'sourceId', x."source_id", 'reversesId', x."reverses_id", 'memo', x."memo", 'memoKey', x."memo_key", 'memoParams', x."memo_params", 'total', coalesce((select sum(et."debit") from "better_supabase"."accounting_entry_lines" et where et."entry_id" = x."id"), 0)::text, 'postedAt', x."posted_at", 'postedBy', x."posted_by", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."entry_date")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."accounting_entries" x
      where x."tenant_id" = page_accounting_entries.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'journalId' is not null and jsonb_typeof(v_filters -> 'journalId') <> 'null' and not (jsonb_typeof(v_filters -> 'journalId') = 'array' and jsonb_array_length(v_filters -> 'journalId') = 0)) or x."journal_id"::text = any((case when jsonb_typeof(v_filters -> 'journalId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'journalId')) else array[v_filters ->> 'journalId'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{since,0}', v_filters ->> 'since'), '') is null or x."entry_date" >= (nullif(coalesce(v_filters #>> '{since,0}', v_filters ->> 'since'), ''))::date)
        and (nullif(coalesce(v_filters #>> '{until,0}', v_filters ->> 'until'), '') is null or x."entry_date" <= (nullif(coalesce(v_filters #>> '{until,0}', v_filters ->> 'until'), ''))::date)
        and (v_search is null or x."reference" ilike v_search or x."memo" ilike v_search or x."number" ilike v_search)
        and (v_after is null or (x."entry_date", x."created_at", x."id") < ((v_after ->> 0)::date, (v_after ->> 1)::timestamptz, (v_after ->> 2)::uuid))
      order by x."entry_date" desc, x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'entryDate' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'journalId', x."journal_id", 'number', x."number", 'fiscalYear', x."fiscal_year", 'entryDate', x."entry_date", 'periodId', x."period_id", 'status', x."status", 'reference', x."reference", 'sourceType', x."source_type", 'sourceId', x."source_id", 'reversesId', x."reverses_id", 'memo', x."memo", 'memoKey', x."memo_key", 'memoParams', x."memo_params", 'total', coalesce((select sum(et."debit") from "better_supabase"."accounting_entry_lines" et where et."entry_id" = x."id"), 0)::text, 'postedAt', x."posted_at", 'postedBy', x."posted_by", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."entry_date")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."accounting_entries" x
      where x."tenant_id" = page_accounting_entries.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'journalId' is not null and jsonb_typeof(v_filters -> 'journalId') <> 'null' and not (jsonb_typeof(v_filters -> 'journalId') = 'array' and jsonb_array_length(v_filters -> 'journalId') = 0)) or x."journal_id"::text = any((case when jsonb_typeof(v_filters -> 'journalId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'journalId')) else array[v_filters ->> 'journalId'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{since,0}', v_filters ->> 'since'), '') is null or x."entry_date" >= (nullif(coalesce(v_filters #>> '{since,0}', v_filters ->> 'since'), ''))::date)
        and (nullif(coalesce(v_filters #>> '{until,0}', v_filters ->> 'until'), '') is null or x."entry_date" <= (nullif(coalesce(v_filters #>> '{until,0}', v_filters ->> 'until'), ''))::date)
        and (v_search is null or x."reference" ilike v_search or x."memo" ilike v_search or x."number" ilike v_search)
        and (v_after is null or (x."entry_date" >= (v_after ->> 0)::date and ((x."entry_date" > (v_after ->> 0)::date) or (x."entry_date" = (v_after ->> 0)::date and x."created_at" < (v_after ->> 1)::timestamptz) or (x."entry_date" = (v_after ->> 0)::date and x."created_at" = (v_after ->> 1)::timestamptz and x."id" < (v_after ->> 2)::uuid))))
      order by x."entry_date" asc, x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'entryDate' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'journalId', x."journal_id", 'number', x."number", 'fiscalYear', x."fiscal_year", 'entryDate', x."entry_date", 'periodId', x."period_id", 'status', x."status", 'reference', x."reference", 'sourceType', x."source_type", 'sourceId', x."source_id", 'reversesId', x."reverses_id", 'memo', x."memo", 'memoKey', x."memo_key", 'memoParams', x."memo_params", 'total', coalesce((select sum(et."debit") from "better_supabase"."accounting_entry_lines" et where et."entry_id" = x."id"), 0)::text, 'postedAt', x."posted_at", 'postedBy', x."posted_by", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."entry_date")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."accounting_entries" x
      where x."tenant_id" = page_accounting_entries.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'journalId' is not null and jsonb_typeof(v_filters -> 'journalId') <> 'null' and not (jsonb_typeof(v_filters -> 'journalId') = 'array' and jsonb_array_length(v_filters -> 'journalId') = 0)) or x."journal_id"::text = any((case when jsonb_typeof(v_filters -> 'journalId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'journalId')) else array[v_filters ->> 'journalId'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{since,0}', v_filters ->> 'since'), '') is null or x."entry_date" >= (nullif(coalesce(v_filters #>> '{since,0}', v_filters ->> 'since'), ''))::date)
        and (nullif(coalesce(v_filters #>> '{until,0}', v_filters ->> 'until'), '') is null or x."entry_date" <= (nullif(coalesce(v_filters #>> '{until,0}', v_filters ->> 'until'), ''))::date)
        and (v_search is null or x."reference" ilike v_search or x."memo" ilike v_search or x."number" ilike v_search)
        and (v_after is null or (x."entry_date", x."created_at", x."id") < ((v_after ->> 0)::date, (v_after ->> 1)::timestamptz, (v_after ->> 2)::uuid))
      order by x."entry_date" desc, x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'journalId', x."journal_id", 'number', x."number", 'fiscalYear', x."fiscal_year", 'entryDate', x."entry_date", 'periodId', x."period_id", 'status', x."status", 'reference', x."reference", 'sourceType', x."source_type", 'sourceId', x."source_id", 'reversesId', x."reverses_id", 'memo', x."memo", 'memoKey', x."memo_key", 'memoParams', x."memo_params", 'total', coalesce((select sum(et."debit") from "better_supabase"."accounting_entry_lines" et where et."entry_id" = x."id"), 0)::text, 'postedAt', x."posted_at", 'postedBy', x."posted_by", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."accounting_entries" x
      where x."tenant_id" = page_accounting_entries.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'journalId' is not null and jsonb_typeof(v_filters -> 'journalId') <> 'null' and not (jsonb_typeof(v_filters -> 'journalId') = 'array' and jsonb_array_length(v_filters -> 'journalId') = 0)) or x."journal_id"::text = any((case when jsonb_typeof(v_filters -> 'journalId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'journalId')) else array[v_filters ->> 'journalId'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{since,0}', v_filters ->> 'since'), '') is null or x."entry_date" >= (nullif(coalesce(v_filters #>> '{since,0}', v_filters ->> 'since'), ''))::date)
        and (nullif(coalesce(v_filters #>> '{until,0}', v_filters ->> 'until'), '') is null or x."entry_date" <= (nullif(coalesce(v_filters #>> '{until,0}', v_filters ->> 'until'), ''))::date)
        and (v_search is null or x."reference" ilike v_search or x."memo" ilike v_search or x."number" ilike v_search)
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'journalId', x."journal_id", 'number', x."number", 'fiscalYear', x."fiscal_year", 'entryDate', x."entry_date", 'periodId', x."period_id", 'status', x."status", 'reference', x."reference", 'sourceType', x."source_type", 'sourceId', x."source_id", 'reversesId', x."reverses_id", 'memo', x."memo", 'memoKey', x."memo_key", 'memoParams', x."memo_params", 'total', coalesce((select sum(et."debit") from "better_supabase"."accounting_entry_lines" et where et."entry_id" = x."id"), 0)::text, 'postedAt', x."posted_at", 'postedBy', x."posted_by", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."accounting_entries" x
      where x."tenant_id" = page_accounting_entries.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'journalId' is not null and jsonb_typeof(v_filters -> 'journalId') <> 'null' and not (jsonb_typeof(v_filters -> 'journalId') = 'array' and jsonb_array_length(v_filters -> 'journalId') = 0)) or x."journal_id"::text = any((case when jsonb_typeof(v_filters -> 'journalId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'journalId')) else array[v_filters ->> 'journalId'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{since,0}', v_filters ->> 'since'), '') is null or x."entry_date" >= (nullif(coalesce(v_filters #>> '{since,0}', v_filters ->> 'since'), ''))::date)
        and (nullif(coalesce(v_filters #>> '{until,0}', v_filters ->> 'until'), '') is null or x."entry_date" <= (nullif(coalesce(v_filters #>> '{until,0}', v_filters ->> 'until'), ''))::date)
        and (v_search is null or x."reference" ilike v_search or x."memo" ilike v_search or x."number" ilike v_search)
        and (v_after is null or (x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."accounting_entries" x
      where x."tenant_id" = page_accounting_entries.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'journalId' is not null and jsonb_typeof(v_filters -> 'journalId') <> 'null' and not (jsonb_typeof(v_filters -> 'journalId') = 'array' and jsonb_array_length(v_filters -> 'journalId') = 0)) or x."journal_id"::text = any((case when jsonb_typeof(v_filters -> 'journalId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'journalId')) else array[v_filters ->> 'journalId'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{since,0}', v_filters ->> 'since'), '') is null or x."entry_date" >= (nullif(coalesce(v_filters #>> '{since,0}', v_filters ->> 'since'), ''))::date)
        and (nullif(coalesce(v_filters #>> '{until,0}', v_filters ->> 'until'), '') is null or x."entry_date" <= (nullif(coalesce(v_filters #>> '{until,0}', v_filters ->> 'until'), ''))::date)
        and (v_search is null or x."reference" ilike v_search or x."memo" ilike v_search or x."number" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.post_accounting_entry (
  entry_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."accounting_entries"%rowtype;
begin
  select * into v_row from "better_supabase"."accounting_entries" y where y."id" = post_accounting_entry.entry_id;
  if not found then
    raise exception 'entry not found' using errcode = 'P0002', hint = 'ACCOUNTING_ENTRY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'accounting.post'), false)) then
    raise exception 'not allowed to post accounting entries' using errcode = '42501', hint = 'ACCOUNTING_ENTRY_FORBIDDEN';
  end if;
  v_row := "better_supabase"."accounting_post"(v_row."id");
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'journalId', v_row."journal_id", 'number', v_row."number", 'fiscalYear', v_row."fiscal_year", 'entryDate', v_row."entry_date", 'periodId', v_row."period_id", 'status', v_row."status", 'reference', v_row."reference", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'reversesId', v_row."reverses_id", 'memo', v_row."memo", 'memoKey', v_row."memo_key", 'memoParams', v_row."memo_params", 'total', coalesce((select sum(et."debit") from "better_supabase"."accounting_entry_lines" et where et."entry_id" = v_row."id"), 0)::text, 'postedAt', v_row."posted_at", 'postedBy', v_row."posted_by", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'lines', coalesce((select jsonb_agg(jsonb_build_object('id', el."id", 'accountId', el."account_id", 'accountCode', ea."code", 'accountName', ea."name", 'debit', el."debit"::text, 'credit', el."credit"::text, 'currency', el."currency", 'amountCurrency', el."amount_currency"::text, 'fxRate', el."fx_rate"::text, 'taxCodeId', el."tax_code_id", 'taxAmount', el."tax_amount"::text, 'partyId', el."party_id", 'dimensions', el."dimensions", 'description', el."description") order by el."position", el."id") from "better_supabase"."accounting_entry_lines" el join "better_supabase"."accounting_accounts" ea on ea."id" = el."account_id" where el."entry_id" = v_row."id"), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.post_accounting_opening_balances (
  tenant      uuid,
  fiscal_year integer,
  journal_id  uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_settings "better_supabase"."accounting_settings"%rowtype;
  v_row "better_supabase"."accounting_entries"%rowtype;
  v_journal uuid := post_accounting_opening_balances.journal_id;
  v_starts date;
  v_net numeric;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', post_accounting_opening_balances.tenant, 'accounting.post'), false)) then
    raise exception 'not allowed to post accounting entries' using errcode = '42501', hint = 'ACCOUNTING_OPENING_FORBIDDEN';
  end if;
  select * into v_settings from "better_supabase"."accounting_settings" st where st."tenant_id" = post_accounting_opening_balances.tenant;
  if not found then
    raise exception 'accounting isn''t set up for this organization; call setup_accounting first' using errcode = 'P0002', hint = 'ACCOUNTING_SETTING_NOT_FOUND';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(post_accounting_opening_balances.tenant::text || ':opening:' || post_accounting_opening_balances.fiscal_year::text, 0));
  select * into v_row from "better_supabase"."accounting_entries" y
  where y."tenant_id" = post_accounting_opening_balances.tenant and y."source_type" = 'opening_balance'
    and y."source_id" = post_accounting_opening_balances.fiscal_year::text and y."status" <> 'reversed';
  if found then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'journalId', v_row."journal_id", 'number', v_row."number", 'fiscalYear', v_row."fiscal_year", 'entryDate', v_row."entry_date", 'periodId', v_row."period_id", 'status', v_row."status", 'reference', v_row."reference", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'reversesId', v_row."reverses_id", 'memo', v_row."memo", 'memoKey', v_row."memo_key", 'memoParams', v_row."memo_params", 'total', coalesce((select sum(et."debit") from "better_supabase"."accounting_entry_lines" et where et."entry_id" = v_row."id"), 0)::text, 'postedAt', v_row."posted_at", 'postedBy', v_row."posted_by", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'lines', coalesce((select jsonb_agg(jsonb_build_object('id', el."id", 'accountId', el."account_id", 'accountCode', ea."code", 'accountName', ea."name", 'debit', el."debit"::text, 'credit', el."credit"::text, 'currency', el."currency", 'amountCurrency', el."amount_currency"::text, 'fxRate', el."fx_rate"::text, 'taxCodeId', el."tax_code_id", 'taxAmount', el."tax_amount"::text, 'partyId', el."party_id", 'dimensions', el."dimensions", 'description', el."description") order by el."position", el."id") from "better_supabase"."accounting_entry_lines" el join "better_supabase"."accounting_accounts" ea on ea."id" = el."account_id" where el."entry_id" = v_row."id"), '[]'::jsonb));
  end if;
  select count(*), coalesce(sum(y."amount"), 0) into v_count, v_net from "better_supabase"."accounting_opening_balances" y
  where y."tenant_id" = post_accounting_opening_balances.tenant and y."fiscal_year" = post_accounting_opening_balances.fiscal_year and y."source" = 'imported';
  if v_count = 0 then
    raise exception 'the fiscal year has no imported opening balances' using errcode = 'P0002', hint = 'ACCOUNTING_OPENING_NOT_FOUND';
  end if;
  if v_net <> 0 then
    raise exception 'the opening balances don''t add up to zero' using errcode = '23514', hint = 'ACCOUNTING_ENTRY_UNBALANCED';
  end if;
  select min(y."starts_on") into v_starts from "better_supabase"."accounting_periods" y
  where y."tenant_id" = post_accounting_opening_balances.tenant and y."fiscal_year" = post_accounting_opening_balances.fiscal_year;
  if v_starts is null then
    raise exception 'the fiscal year has no periods; open it first' using errcode = 'P0002', hint = 'ACCOUNTING_PERIOD_NOT_FOUND';
  end if;
  if v_journal is null then
    select y."id" into v_journal from "better_supabase"."accounting_journals" y
    where y."tenant_id" = post_accounting_opening_balances.tenant and y."type" = 'general'
    order by y."code" limit 1;
  elsif not exists (select 1 from "better_supabase"."accounting_journals" y where y."id" = v_journal and y."tenant_id" = post_accounting_opening_balances.tenant) then
    raise exception 'journal not found' using errcode = 'P0002', hint = 'ACCOUNTING_JOURNAL_NOT_FOUND';
  end if;
  if v_journal is null then
    raise exception 'the opening entry needs a general journal' using errcode = 'P0002', hint = 'ACCOUNTING_JOURNAL_NOT_FOUND';
  end if;
  insert into "better_supabase"."accounting_entries" ("tenant_id", "journal_id", "entry_date", "source_type", "source_id", "memo", "memo_key", "memo_params", "created_by")
  values (post_accounting_opening_balances.tenant, v_journal, v_starts, 'opening_balance', post_accounting_opening_balances.fiscal_year::text,
    'Opening balances of fiscal year ' || post_accounting_opening_balances.fiscal_year::text, 'accounting.opening_balances', jsonb_build_object('fiscalYear', post_accounting_opening_balances.fiscal_year), auth.uid())
  returning * into v_row;
  insert into "better_supabase"."accounting_entry_lines" ("tenant_id", "entry_id", "position", "account_id", "debit", "credit", "currency", "amount_currency", "party_id")
  select post_accounting_opening_balances.tenant, v_row."id", (row_number() over (order by w."code", y."party_id"))::smallint, y."account_id",
    greatest(y."amount", 0)::bigint, greatest(-y."amount", 0)::bigint, v_settings."functional_currency", y."amount", y."party_id"
  from "better_supabase"."accounting_opening_balances" y join "better_supabase"."accounting_accounts" w on w."id" = y."account_id"
  where y."tenant_id" = post_accounting_opening_balances.tenant and y."fiscal_year" = post_accounting_opening_balances.fiscal_year and y."source" = 'imported';
  v_row := "better_supabase"."accounting_post"(v_row."id", true);
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'journalId', v_row."journal_id", 'number', v_row."number", 'fiscalYear', v_row."fiscal_year", 'entryDate', v_row."entry_date", 'periodId', v_row."period_id", 'status', v_row."status", 'reference', v_row."reference", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'reversesId', v_row."reverses_id", 'memo', v_row."memo", 'memoKey', v_row."memo_key", 'memoParams', v_row."memo_params", 'total', coalesce((select sum(et."debit") from "better_supabase"."accounting_entry_lines" et where et."entry_id" = v_row."id"), 0)::text, 'postedAt', v_row."posted_at", 'postedBy', v_row."posted_by", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'lines', coalesce((select jsonb_agg(jsonb_build_object('id', el."id", 'accountId', el."account_id", 'accountCode', ea."code", 'accountName', ea."name", 'debit', el."debit"::text, 'credit', el."credit"::text, 'currency', el."currency", 'amountCurrency', el."amount_currency"::text, 'fxRate', el."fx_rate"::text, 'taxCodeId', el."tax_code_id", 'taxAmount', el."tax_amount"::text, 'partyId', el."party_id", 'dimensions', el."dimensions", 'description', el."description") order by el."position", el."id") from "better_supabase"."accounting_entry_lines" el join "better_supabase"."accounting_accounts" ea on ea."id" = el."account_id" where el."entry_id" = v_row."id"), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.post_accounting_source (
  source_type text,
  source_id   text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_id uuid;
  v_row "better_supabase"."accounting_entries"%rowtype;
begin
  v_id := "better_supabase"."accounting_post_source"(post_accounting_source.source_type, post_accounting_source.source_id);
  if v_id is null then
    return null;
  end if;
  select * into v_row from "better_supabase"."accounting_entries" y where y."id" = v_id;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'accounting.post'), false)) then
    raise exception 'not allowed to post accounting entries' using errcode = '42501', hint = 'ACCOUNTING_ENTRY_FORBIDDEN';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'journalId', v_row."journal_id", 'number', v_row."number", 'fiscalYear', v_row."fiscal_year", 'entryDate', v_row."entry_date", 'periodId', v_row."period_id", 'status', v_row."status", 'reference', v_row."reference", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'reversesId', v_row."reverses_id", 'memo', v_row."memo", 'memoKey', v_row."memo_key", 'memoParams', v_row."memo_params", 'total', coalesce((select sum(et."debit") from "better_supabase"."accounting_entry_lines" et where et."entry_id" = v_row."id"), 0)::text, 'postedAt', v_row."posted_at", 'postedBy', v_row."posted_by", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'lines', coalesce((select jsonb_agg(jsonb_build_object('id', el."id", 'accountId', el."account_id", 'accountCode', ea."code", 'accountName', ea."name", 'debit', el."debit"::text, 'credit', el."credit"::text, 'currency', el."currency", 'amountCurrency', el."amount_currency"::text, 'fxRate', el."fx_rate"::text, 'taxCodeId', el."tax_code_id", 'taxAmount', el."tax_amount"::text, 'partyId', el."party_id", 'dimensions', el."dimensions", 'description', el."description") order by el."position", el."id") from "better_supabase"."accounting_entry_lines" el join "better_supabase"."accounting_accounts" ea on ea."id" = el."account_id" where el."entry_id" = v_row."id"), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.post_due_rent (
  tenant   uuid    DEFAULT NULL::uuid,
  through  date    DEFAULT NULL::date,
  max_rows integer DEFAULT 500
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_through date := coalesce(post_due_rent.through, current_date);
  v_max integer := least(greatest(coalesce(post_due_rent.max_rows, 500), 1), 5000);
  v_count integer := 0;
  v_row "better_supabase"."leases"%rowtype;
  v_charge "better_supabase"."lease_charges"%rowtype;
  v_n integer;
  v_start date;
  v_end date;
  v_tx uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if post_due_rent.tenant is null then
    if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
      raise exception 'posting rent for every organization needs the service role' using errcode = '42501', hint = 'LEASES_FORBIDDEN';
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', post_due_rent.tenant, 'leases.manage'), false)) then
    raise exception 'not allowed to manage leases' using errcode = '42501', hint = 'LEASES_FORBIDDEN';
  end if;
  <<periods>>
  for v_row in
    select * from "better_supabase"."leases" x
    where x."status" = 'active' and x."starts_on" <= v_through
      and (post_due_rent.tenant is null or x."tenant_id" = post_due_rent.tenant)
    order by x."id"
    for update skip locked
  loop
    v_n := 0;
    loop
      v_start := (v_row."starts_on" + v_n * (case v_row."frequency" when 'weekly' then interval '1 week' when 'monthly' then interval '1 month' when 'quarterly' then interval '3 months' else interval '1 year' end))::date;
      exit when v_start > v_through or (v_row."ends_on" is not null and v_start >= v_row."ends_on");
      if not exists (select 1 from "better_supabase"."lease_charges" y where y."lease_id" = v_row."id" and y."period_start" = v_start) then
        exit periods when v_count >= v_max;
        v_end := least((v_row."starts_on" + (v_n + 1) * (case v_row."frequency" when 'weekly' then interval '1 week' when 'monthly' then interval '1 month' when 'quarterly' then interval '3 months' else interval '1 year' end))::date, coalesce(v_row."ends_on", 'infinity'::date));
        v_tx := "better_supabase"."ledger_post"(v_row."tenant_id", 'lease.rent',
          jsonb_build_array(
            jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_receivable', 'leases.rent:' || v_row."id"::text, 'Rent ' || v_row."title",
      v_row."currency"::text, 0::smallint, 'lease', v_row."id"::text, null, true, 'leases.read', 'leases',
      jsonb_build_object('leaseId', v_row."id")), 'amount', v_row."rent"),
            jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_income', 'leases.income:' || v_row."currency", 'Rent income ' || v_row."currency",
      v_row."currency"::text, 0::smallint, null, null, null, true, 'leases.read', 'leases', null), 'amount', -v_row."rent")),
          'leases', v_row."id"::text, 'Rent from ' || v_start::text,
          'leases.rent:' || v_row."id"::text || ':' || v_start::text, v_start::timestamptz,
          jsonb_build_object('leaseId', v_row."id", 'periodStart', v_start, 'periodEnd', v_end),
          memo_key => 'lease.rent', memo_params => jsonb_build_object('periodStart', v_start));
        insert into "better_supabase"."lease_charges" ("tenant_id", "lease_id", "period_start", "period_end", "amount", "currency", "transaction_id")
        values (v_row."tenant_id", v_row."id", v_start, v_end, v_row."rent", v_row."currency", v_tx)
        returning * into v_charge;
        if not better_supabase.import_run() is not null then
    perform "better_supabase"."accounting_post_source"('lease_rent', v_charge."id"::text);
  end if;
        perform "better_supabase".emit_event('lease.charged', jsonb_build_object('organizationId', v_charge."tenant_id", 'id', v_charge."id", 'leaseId', v_charge."lease_id", 'periodStart', v_charge."period_start", 'periodEnd', v_charge."period_end", 'amount', v_charge."amount"::text, 'currency', v_charge."currency", 'transactionId', v_charge."transaction_id"), 'lease-charges/' || v_charge."id"::text, (v_charge."tenant_id")::text, null, 'better-supabase/leases');
  perform better_supabase.audit_event(
    event_type => 'lease.charged',
    category => 'billing',
    target_type => 'lease_charge',
    record_id => v_charge."id"::text,
    summary => 'posted rent from ' || v_charge."period_start"::text,
    summary_params => jsonb_build_object('periodStart', v_charge."period_start"),
    tenant => (v_charge."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_charge."tenant_id", 'id', v_charge."id", 'leaseId', v_charge."lease_id", 'periodStart', v_charge."period_start", 'periodEnd', v_charge."period_end", 'amount', v_charge."amount"::text, 'currency', v_charge."currency", 'transactionId', v_charge."transaction_id")
  );
        v_count := v_count + 1;
      end if;
      v_n := v_n + 1;
    end loop;
  end loop;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.post_ledger_transaction (
  tenant          uuid,
  kind            text,
  lines           jsonb,
  reference_type  text                     DEFAULT NULL::text,
  reference_id    text                     DEFAULT NULL::text,
  memo            text                     DEFAULT NULL::text,
  idempotency_key text                     DEFAULT NULL::text,
  effective_at    timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  metadata        jsonb                    DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_id uuid;
  v_row "better_supabase"."ledger_transactions"%rowtype;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', post_ledger_transaction.tenant, 'ledger.post'), false)) then
    raise exception 'not allowed to post ledger transactions' using errcode = '42501', hint = 'LEDGER_FORBIDDEN';
  end if;
  if jsonb_typeof(post_ledger_transaction.lines) = 'array' and exists (
    select 1 from jsonb_array_elements(post_ledger_transaction.lines) l
    join "better_supabase"."ledger_accounts" x on x."id"::text = l.value ->> 'account'
    where x."managed_by" is not null
  ) then
    raise exception 'an account of the transaction belongs to another block' using errcode = '55000', hint = 'LEDGER_ACCOUNT_MANAGED';
  end if;
  v_id := "better_supabase"."ledger_post"(post_ledger_transaction.tenant, post_ledger_transaction.kind, post_ledger_transaction.lines,
    post_ledger_transaction.reference_type, post_ledger_transaction.reference_id, post_ledger_transaction.memo,
    post_ledger_transaction.idempotency_key, post_ledger_transaction.effective_at, post_ledger_transaction.metadata);
  select * into v_row from "better_supabase"."ledger_transactions" x where x."id" = v_id;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'referenceType', v_row."reference_type", 'referenceId', v_row."reference_id", 'memo', v_row."memo", 'memoKey', v_row."memo_key", 'memoParams', v_row."memo_params", 'idempotencyKey', v_row."idempotency_key", 'reverses', v_row."reverses", 'metadata', v_row."metadata", 'effectiveAt', v_row."effective_at", 'actorId', v_row."actor_id", 'createdAt', v_row."created_at", 'entries', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'accountId', y."account_id", 'amount', y."amount"::text, 'unit', y."unit") order by y."created_at", y."id") from "better_supabase"."ledger_entries" y where y."transaction_id" = v_row."id"), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.prorate_change (
  subscription_id uuid,
  unit_amount     bigint                   DEFAULT NULL::bigint,
  quantity        integer                  DEFAULT NULL::integer,
  at              timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."billing_native_subscriptions"%rowtype;
  v_at timestamptz := coalesce(prorate_change.at, now());
  v_fraction numeric;
  v_credit bigint;
  v_charge bigint;
  v_net bigint;
  v_new_amount bigint;
  v_new_quantity integer;
  v_tx uuid;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the service role prorates subscription changes' using errcode = '42501', hint = 'BILLING_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."billing_native_subscriptions" x where x."id" = prorate_change.subscription_id for update;
  if not found or v_row."status" <> 'active' then
    raise exception 'The subscription does not exist or is canceled' using errcode = 'P0002', hint = 'BILLING_SUBSCRIPTION_NOT_FOUND';
  end if;
  v_new_amount := coalesce(prorate_change.unit_amount, v_row."unit_amount");
  v_new_quantity := coalesce(prorate_change.quantity, v_row."quantity");
  if v_new_amount < 0 or v_new_quantity < 0 then
    raise exception 'The new price or quantity is negative' using errcode = '22023', hint = 'BILLING_SUBSCRIPTION_INVALID';
  end if;
  v_fraction := greatest(0, least(1,
    extract(epoch from v_row."period_ends_at" - v_at) / extract(epoch from v_row."period_ends_at" - v_row."period_starts_at")));
  v_credit := round(v_row."unit_amount" * v_row."quantity" * v_fraction);
  v_charge := round(v_new_amount * v_new_quantity * v_fraction);
  v_net := v_charge - v_credit;

  if v_net <> 0 then
    v_tx := "better_supabase"."ledger_post"(v_row."tenant_id", 'billing.proration',
      jsonb_build_array(
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'receivable', 'billing:receivable:' || v_row."currency", 'Subscription receivable ' || v_row."currency", v_row."currency", 0::smallint, null, null, null, true, null, 'billing', null), 'amount', v_net),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'revenue', 'billing:proration:' || v_row."currency", 'Subscription proration ' || v_row."currency", v_row."currency", 0::smallint, null, null, null, true, null, 'billing', null), 'amount', -v_net)),
      'billing-native-subscriptions', v_row."id"::text,
      'Proration for ' || v_row."plan",
      'billing.proration:' || v_row."id"::text || ':' || extract(epoch from v_at)::text,
      v_at,
      jsonb_build_object('plan', v_row."plan", 'credit', v_credit, 'charge', v_charge),
      memo_key => 'billing.proration', memo_params => jsonb_build_object('plan', v_row."plan"));
  end if;
  update "better_supabase"."billing_native_subscriptions" set "unit_amount" = v_new_amount, "quantity" = v_new_quantity
    where "id" = v_row."id";
  return jsonb_build_object('subscription_id', v_row."id", 'credit', v_credit::text, 'charge', v_charge::text, 'net', v_net::text,
    'currency', v_row."currency", 'transaction_id', v_tx);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_rent_payment (
  lease_id  uuid,
  amount    bigint,
  paid_at   timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  reference text                     DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."leases"%rowtype;
  v_key text;
  v_tx uuid;
begin
  select * into v_row from "better_supabase"."leases" x where x."id" = record_rent_payment.lease_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leases.manage'), false)) then
    raise exception 'no such lease you can read' using errcode = 'P0002', hint = 'LEASE_NOT_FOUND';
  end if;
  if v_row."status" = 'draft' then
    raise exception 'a draft lease takes no payments' using errcode = '55000', hint = 'LEASE_STATUS_INVALID';
  end if;
  if record_rent_payment.amount is null or record_rent_payment.amount <= 0 then
    raise exception 'a payment is more than zero minor units' using errcode = '22023', hint = 'LEASE_PAYMENT_INVALID';
  end if;
  v_key := case when nullif(trim(record_rent_payment.reference), '') is not null
    then 'leases.payment:' || v_row."id"::text || ':' || trim(record_rent_payment.reference) end;
  select x."id" into v_tx from "better_supabase"."ledger_transactions" x
    where x."tenant_id" = v_row."tenant_id" and x."idempotency_key" = v_key;
  if v_tx is null then
    v_tx := "better_supabase"."ledger_post"(v_row."tenant_id", 'lease.payment',
      jsonb_build_array(
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_receivable', 'leases.rent:' || v_row."id"::text, 'Rent ' || v_row."title",
      v_row."currency"::text, 0::smallint, 'lease', v_row."id"::text, null, true, 'leases.read', 'leases',
      jsonb_build_object('leaseId', v_row."id")), 'amount', -record_rent_payment.amount),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_cash', 'leases.cash:' || v_row."currency", 'Rent received ' || v_row."currency",
      v_row."currency"::text, 0::smallint, null, null, null, true, 'leases.read', 'leases', null), 'amount', record_rent_payment.amount)),
      'leases', v_row."id"::text, 'Rent payment', v_key, record_rent_payment.paid_at,
      jsonb_strip_nulls(jsonb_build_object('leaseId', v_row."id", 'reference', nullif(trim(record_rent_payment.reference), ''))),
      memo_key => 'lease.payment', memo_params => '{}'::jsonb);
    if not better_supabase.import_run() is not null then
    perform "better_supabase"."accounting_post_source"('lease_payment', v_tx::text);
  end if;
    perform "better_supabase".emit_event('lease.paid', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'transactionId', v_tx, 'amount', record_rent_payment.amount::text, 'currency', v_row."currency"), 'leases/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/leases');
  perform better_supabase.audit_event(
    event_type => 'lease.paid',
    category => 'billing',
    target_type => 'lease',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'recorded a rent payment',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'transactionId', v_tx, 'amount', record_rent_payment.amount::text, 'currency', v_row."currency")
  );
  end if;
  return jsonb_build_object('transactionId', v_tx, 'leaseId', v_row."id", 'amount', record_rent_payment.amount::text,
    'currency', v_row."currency", 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = v_row."tenant_id" and x."code" = 'leases.rent:' || v_row."id"::text), 0)::text);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.reimburse_expense_report (
  report_id uuid,
  paid_at   timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  reference text                     DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_tx uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."expense_reports" x where x."id" = reimburse_expense_report.report_id for update;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.manage'), false)) then
    raise exception 'not allowed to reimburse expenses' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) <> 'approved' then
    raise exception 'only an approved report can be reimbursed' using errcode = '55000', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  v_tx := "better_supabase"."ledger_post"(v_row."tenant_id", 'expense.reimbursed',
    jsonb_build_array(
      jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'expense_payable', 'expenses:payable:' || v_row."user_id"::text || ':' || v_row."currency", 'Expenses owed ' || v_row."currency", v_row."currency"::text, 0::smallint, 'users', v_row."user_id"::text, v_row."user_id", true, 'expenses.read', 'expenses', null), 'amount', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)),
      jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'expense_cash', 'expenses:cash:' || v_row."currency", 'Expenses paid ' || v_row."currency", v_row."currency"::text, 0::smallint, null, null, null, true, 'expenses.read', 'expenses', null), 'amount', -coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0))),
    'expenses', v_row."id"::text, left('Reimbursed: ' || v_row."title", 500), 'expense:' || v_row."id"::text || ':reimbursed',
    reimburse_expense_report.paid_at,
    jsonb_strip_nulls(jsonb_build_object('reportId', v_row."id", 'reference', nullif(trim(reimburse_expense_report.reference), ''))),
    memo_key => 'expense.reimbursed', memo_params => jsonb_build_object('title', v_row."title"));
  update "better_supabase"."expense_reports" x set "reimbursed_at" = coalesce(reimburse_expense_report.paid_at, now()), "reimbursement_transaction_id" = v_tx, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  if not better_supabase.import_run() is not null then
    perform "better_supabase"."accounting_post_source"('expense_reimbursement', v_row."id"::text);
  end if;
  perform "better_supabase".emit_event('expense_report.reimbursed', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'currency', v_row."currency", 'transactionId', v_tx), 'expense-reports/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/expenses');
  perform better_supabase.audit_event(
    event_type => 'expense_report.reimbursed',
    category => 'billing',
    target_type => 'expense_report',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'reimbursed an expense report',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'currency', v_row."currency", 'transactionId', v_tx)
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'title', v_row."title", 'currency', v_row."currency", 'note', v_row."note", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'approvalId', v_row."approval_id", 'submittedAt', v_row."submitted_at", 'approvedAt', v_row."approved_at", 'approvalTransactionId', v_row."approval_transaction_id", 'reimbursedAt', v_row."reimbursed_at", 'reimbursementTransactionId', v_row."reimbursement_transaction_id", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'dimensions', l."dimensions", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', (select count(*) from "better_supabase"."attachments" t where t."subject_type" = 'expense_line' and t."subject_id" = l."id"::text and t."uploaded_at" is not null and t."status" <> 'infected'), 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = v_row."id"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.reopen_accounting_period (
  period_id uuid,
  reason    text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_period "better_supabase"."accounting_periods"%rowtype;
  v_settings "better_supabase"."accounting_settings"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_period from "better_supabase"."accounting_periods" y where y."id" = reopen_accounting_period.period_id for update;
  if not found then
    raise exception 'period not found' using errcode = 'P0002', hint = 'ACCOUNTING_PERIOD_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_period."tenant_id", 'accounting.close'), false)) then
    raise exception 'not allowed to reopen accounting periods' using errcode = '42501', hint = 'ACCOUNTING_PERIOD_FORBIDDEN';
  end if;
  if nullif(trim(reopen_accounting_period.reason), '') is null then
    raise exception 'reopening a period needs a reason' using errcode = '22023', hint = 'ACCOUNTING_PERIOD_INVALID';
  end if;
  if v_period."status" = 'open' then
    return jsonb_build_object('id', v_period."id", 'organizationId', v_period."tenant_id", 'fiscalYear', v_period."fiscal_year", 'number', v_period."number", 'startsOn', v_period."starts_on", 'endsOn', v_period."ends_on", 'status', v_period."status", 'closedAt', v_period."closed_at", 'closedBy', v_period."closed_by", 'lockedAt', v_period."locked_at", 'lockedBy', v_period."locked_by");
  end if;
  if v_period."status" = 'locked' then
    raise exception 'the period is locked; unlock it first' using errcode = '55000', hint = 'ACCOUNTING_PERIOD_LOCKED';
  end if;
  select * into v_settings from "better_supabase"."accounting_settings" st where st."tenant_id" = v_period."tenant_id";
  if not found then
    raise exception 'accounting isn''t set up for this organization; call setup_accounting first' using errcode = 'P0002', hint = 'ACCOUNTING_SETTING_NOT_FOUND';
  end if;
  if v_settings."lock_date" is not null and v_period."starts_on" <= v_settings."lock_date" then
    raise exception 'the period is on or before the lock date' using errcode = '55000', hint = 'ACCOUNTING_PERIOD_CLOSED';
  end if;
  update "better_supabase"."accounting_periods" y set "status" = 'open', "closed_at" = null, "closed_by" = null
  where y."id" = v_period."id"
  returning * into v_period;
  perform "better_supabase".emit_event('accounting_period.reopened', jsonb_build_object('organizationId', v_period."tenant_id", 'id', v_period."id", 'fiscalYear', v_period."fiscal_year", 'number', v_period."number", 'startsOn', v_period."starts_on", 'endsOn', v_period."ends_on", 'reason', trim(reopen_accounting_period.reason)), 'accounting-periods/' || v_period."id"::text, (v_period."tenant_id")::text, null, 'better-supabase/accounting');
  perform better_supabase.audit_event(
    event_type => 'accounting_period.reopened',
    category => 'data',
    target_type => 'accounting_period',
    record_id => v_period."id"::text,
    target_label => v_period."fiscal_year"::text || '-' || lpad(v_period."number"::text, 2, '0'),
    summary => 'reopened period ' || v_period."fiscal_year"::text || '-' || lpad(v_period."number"::text, 2, '0'),
    summary_params => jsonb_build_object('fiscalYear', v_period."fiscal_year", 'number', v_period."number"),
    tenant => (v_period."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_period."tenant_id", 'id', v_period."id", 'fiscalYear', v_period."fiscal_year", 'number', v_period."number", 'startsOn', v_period."starts_on", 'endsOn', v_period."ends_on", 'reason', trim(reopen_accounting_period.reason))
  );
  return jsonb_build_object('id', v_period."id", 'organizationId', v_period."tenant_id", 'fiscalYear', v_period."fiscal_year", 'number', v_period."number", 'startsOn', v_period."starts_on", 'endsOn', v_period."ends_on", 'status', v_period."status", 'closedAt', v_period."closed_at", 'closedBy', v_period."closed_by", 'lockedAt', v_period."locked_at", 'lockedBy', v_period."locked_by");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.reverse_accounting_entry (
  entry_id   uuid,
  entry_date date DEFAULT NULL::date
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."accounting_entries"%rowtype;
begin
  select * into v_row from "better_supabase"."accounting_entries" y where y."id" = reverse_accounting_entry.entry_id;
  if not found then
    raise exception 'entry not found' using errcode = 'P0002', hint = 'ACCOUNTING_ENTRY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'accounting.post'), false)) then
    raise exception 'not allowed to post accounting entries' using errcode = '42501', hint = 'ACCOUNTING_ENTRY_FORBIDDEN';
  end if;
  v_row := "better_supabase"."accounting_reverse"(v_row."id", reverse_accounting_entry.entry_date);
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'journalId', v_row."journal_id", 'number', v_row."number", 'fiscalYear', v_row."fiscal_year", 'entryDate', v_row."entry_date", 'periodId', v_row."period_id", 'status', v_row."status", 'reference', v_row."reference", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'reversesId', v_row."reverses_id", 'memo', v_row."memo", 'memoKey', v_row."memo_key", 'memoParams', v_row."memo_params", 'total', coalesce((select sum(et."debit") from "better_supabase"."accounting_entry_lines" et where et."entry_id" = v_row."id"), 0)::text, 'postedAt', v_row."posted_at", 'postedBy', v_row."posted_by", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'lines', coalesce((select jsonb_agg(jsonb_build_object('id', el."id", 'accountId', el."account_id", 'accountCode', ea."code", 'accountName', ea."name", 'debit', el."debit"::text, 'credit', el."credit"::text, 'currency', el."currency", 'amountCurrency', el."amount_currency"::text, 'fxRate', el."fx_rate"::text, 'taxCodeId', el."tax_code_id", 'taxAmount', el."tax_amount"::text, 'partyId', el."party_id", 'dimensions', el."dimensions", 'description', el."description") order by el."position", el."id") from "better_supabase"."accounting_entry_lines" el join "better_supabase"."accounting_accounts" ea on ea."id" = el."account_id" where el."entry_id" = v_row."id"), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.reverse_ledger_transaction (
  transaction_id uuid,
  memo           text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_old "better_supabase"."ledger_transactions"%rowtype;
  v_row "better_supabase"."ledger_transactions"%rowtype;
  v_id uuid;
begin
  select * into v_old from "better_supabase"."ledger_transactions" x where x."id" = reverse_ledger_transaction.transaction_id;
  if not found then
    raise exception 'ledger transaction not found' using errcode = 'P0002', hint = 'LEDGER_TRANSACTION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_old."tenant_id", 'ledger.post'), false)) then
    raise exception 'not allowed to post ledger transactions' using errcode = '42501', hint = 'LEDGER_FORBIDDEN';
  end if;
  if exists (
    select 1 from "better_supabase"."ledger_entries" y join "better_supabase"."ledger_accounts" x on x."id" = y."account_id"
    where y."transaction_id" = v_old."id" and x."managed_by" is not null
  ) then
    raise exception 'an account of the transaction belongs to another block' using errcode = '55000', hint = 'LEDGER_ACCOUNT_MANAGED';
  end if;
  if v_old."reverses" is not null
    or exists (select 1 from "better_supabase"."ledger_transactions" x where x."reverses" = v_old."id") then
    raise exception 'this transaction is a reversal or is already reversed' using errcode = '55000', hint = 'LEDGER_ALREADY_REVERSED';
  end if;
  v_id := "better_supabase"."ledger_post"(v_old."tenant_id", v_old."kind",
    (select jsonb_agg(jsonb_build_object('account', y."account_id", 'amount', (-y."amount")::text) order by y."created_at", y."id")
      from "better_supabase"."ledger_entries" y where y."transaction_id" = v_old."id"),
    v_old."reference_type", v_old."reference_id", coalesce(reverse_ledger_transaction.memo, v_old."memo"),
    null, null, v_old."metadata", v_old."id",
    case when reverse_ledger_transaction.memo is null then v_old."memo_key" end,
    case when reverse_ledger_transaction.memo is null then v_old."memo_params" end);
  select * into v_row from "better_supabase"."ledger_transactions" x where x."id" = v_id;
  perform "better_supabase".emit_event('ledger_transaction.reversed', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'referenceType', v_row."reference_type", 'referenceId', v_row."reference_id", 'reverses', v_row."reverses", 'entries', (select count(*)::integer from "better_supabase"."ledger_entries" y where y."transaction_id" = v_row."id")), 'ledger-transactions/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/ledger');
  perform better_supabase.audit_event(
    event_type => 'ledger_transaction.reversed',
    category => 'billing',
    target_type => 'ledger_transaction',
    record_id => v_old."id"::text,
    summary => 'reversed a ' || v_old."kind" || ' transaction',
    summary_params => jsonb_build_object('kind', v_old."kind"),
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'referenceType', v_row."reference_type", 'referenceId', v_row."reference_id", 'reverses', v_row."reverses", 'entries', (select count(*)::integer from "better_supabase"."ledger_entries" y where y."transaction_id" = v_row."id"))
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'referenceType', v_row."reference_type", 'referenceId', v_row."reference_id", 'memo', v_row."memo", 'memoKey', v_row."memo_key", 'memoParams', v_row."memo_params", 'idempotencyKey', v_row."idempotency_key", 'reverses', v_row."reverses", 'metadata', v_row."metadata", 'effectiveAt', v_row."effective_at", 'actorId', v_row."actor_id", 'createdAt', v_row."created_at", 'entries', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'accountId', y."account_id", 'amount', y."amount"::text, 'unit', y."unit") order by y."created_at", y."id") from "better_supabase"."ledger_entries" y where y."transaction_id" = v_row."id"), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_accounting_entry (
  journal_id  uuid,
  entry_date  date,
  lines       jsonb,
  memo        text  DEFAULT NULL::text,
  reference   text  DEFAULT NULL::text,
  source_type text  DEFAULT NULL::text,
  source_id   text  DEFAULT NULL::text,
  entry_id    uuid  DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_journal "better_supabase"."accounting_journals"%rowtype;
  v_settings "better_supabase"."accounting_settings"%rowtype;
  v_row "better_supabase"."accounting_entries"%rowtype;
  v_line record;
  v_account "better_supabase"."accounting_accounts"%rowtype;
  v_currency text;
  v_debit bigint;
  v_credit bigint;
  v_amount bigint;
  v_rate numeric;
  v_functional bigint;
  v_tax uuid;
  v_party uuid;
  v_dimensions jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_journal from "better_supabase"."accounting_journals" y where y."id" = save_accounting_entry.journal_id;
  if not found then
    raise exception 'journal not found' using errcode = 'P0002', hint = 'ACCOUNTING_JOURNAL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_journal."tenant_id", 'accounting.write'), false)) then
    raise exception 'not allowed to write accounting entries' using errcode = '42501', hint = 'ACCOUNTING_ENTRY_FORBIDDEN';
  end if;
  select * into v_settings from "better_supabase"."accounting_settings" st where st."tenant_id" = v_journal."tenant_id";
  if not found then
    raise exception 'accounting isn''t set up for this organization; call setup_accounting first' using errcode = 'P0002', hint = 'ACCOUNTING_SETTING_NOT_FOUND';
  end if;
  if save_accounting_entry.entry_date is null then
    raise exception 'an entry needs a date' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
  end if;
  if jsonb_typeof(save_accounting_entry.lines) is distinct from 'array' or jsonb_array_length(save_accounting_entry.lines) < 2 then
    raise exception 'an entry needs at least two lines' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
  end if;
  if (save_accounting_entry.source_type is null) <> (save_accounting_entry.source_id is null)
    or coalesce(save_accounting_entry.source_type, 'x') !~ '^[a-z][a-z0-9_]{0,62}$' then
    raise exception 'source_type (lower-case) and source_id go together' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
  end if;
  if save_accounting_entry.source_type is not null and exists (
    select 1 from "better_supabase"."accounting_entries" y
    where y."tenant_id" = v_journal."tenant_id" and y."source_type" = save_accounting_entry.source_type
      and y."source_id" = save_accounting_entry.source_id and y."status" <> 'reversed'
      and y."id" is distinct from save_accounting_entry.entry_id
  ) then
    raise exception 'the source already has an entry; reverse it first' using errcode = '23505', hint = 'ACCOUNTING_ENTRY_DUPLICATE';
  end if;
  if save_accounting_entry.entry_id is null then
    insert into "better_supabase"."accounting_entries" ("tenant_id", "journal_id", "entry_date", "reference", "source_type", "source_id", "memo", "created_by", "period_id")
    values (v_journal."tenant_id", v_journal."id", save_accounting_entry.entry_date, nullif(trim(save_accounting_entry.reference), ''),
      save_accounting_entry.source_type, save_accounting_entry.source_id, nullif(trim(save_accounting_entry.memo), ''), auth.uid(),
      (select y."id" from "better_supabase"."accounting_periods" y where y."tenant_id" = v_journal."tenant_id" and save_accounting_entry.entry_date >= y."starts_on" and save_accounting_entry.entry_date <= y."ends_on"))
    returning * into v_row;
  else
    select * into v_row from "better_supabase"."accounting_entries" y where y."id" = save_accounting_entry.entry_id and y."tenant_id" = v_journal."tenant_id" for update;
    if not found then
      raise exception 'entry not found' using errcode = 'P0002', hint = 'ACCOUNTING_ENTRY_NOT_FOUND';
    end if;
    if v_row."status" <> 'draft' then
      raise exception 'a posted entry can''t change; reverse it' using errcode = '55000', hint = 'ACCOUNTING_ENTRY_POSTED';
    end if;
    delete from "better_supabase"."accounting_entry_lines" y where y."entry_id" = v_row."id";
    update "better_supabase"."accounting_entries" y set "journal_id" = v_journal."id", "entry_date" = save_accounting_entry.entry_date,
      "reference" = nullif(trim(save_accounting_entry.reference), ''), "source_type" = save_accounting_entry.source_type,
      "source_id" = save_accounting_entry.source_id, "memo" = nullif(trim(save_accounting_entry.memo), ''), "memo_key" = case when y."memo" is not distinct from nullif(trim(save_accounting_entry.memo), '') then y."memo_key" end, "memo_params" = case when y."memo" is not distinct from nullif(trim(save_accounting_entry.memo), '') then y."memo_params" end,
      "period_id" = (select z."id" from "better_supabase"."accounting_periods" z where z."tenant_id" = v_journal."tenant_id" and save_accounting_entry.entry_date >= z."starts_on" and save_accounting_entry.entry_date <= z."ends_on"),
      "updated_at" = now()
    where y."id" = v_row."id"
    returning * into v_row;
  end if;
  for v_line in select q.value, q.ordinality from jsonb_array_elements(save_accounting_entry.lines) with ordinality q loop
    if jsonb_typeof(v_line.value) is distinct from 'object' then
      raise exception 'every line is an object' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
    end if;
    if coalesce(v_line.value ->> 'accountId', '') ~ '^[0-9a-fA-F-]{36}$' then
      select * into v_account from "better_supabase"."accounting_accounts" y where y."id" = (v_line.value ->> 'accountId')::uuid and y."tenant_id" = v_journal."tenant_id";
    else
      select * into v_account from "better_supabase"."accounting_accounts" y where y."code" = v_line.value ->> 'accountCode' and y."tenant_id" = v_journal."tenant_id";
    end if;
    if v_account."id" is null or v_account."archived_at" is not null then
      raise exception 'a line''s account doesn''t exist here or is archived' using errcode = 'P0002', hint = 'ACCOUNTING_ACCOUNT_NOT_FOUND';
    end if;
    if not v_account."active" then
      raise exception 'a line''s account is inactive' using errcode = '22023', hint = 'ACCOUNTING_ACCOUNT_INVALID';
    end if;
    if coalesce(v_line.value ->> 'debit', '0') !~ '^[0-9]{1,18}$' or coalesce(v_line.value ->> 'credit', '0') !~ '^[0-9]{1,18}$'
      or coalesce(v_line.value ->> 'amountCurrency', '0') !~ '^-?[0-9]{1,18}$'
      or coalesce(v_line.value ->> 'taxAmount', '0') !~ '^[0-9]{1,18}$'
      or coalesce(v_line.value ->> 'fxRate', '1') !~ '^[0-9]+(\.[0-9]+)?$' then
      raise exception 'debit and credit are non-negative integers, amountCurrency an integer and fxRate a positive decimal' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
    end if;
    v_debit := coalesce((v_line.value ->> 'debit')::bigint, 0);
    v_credit := coalesce((v_line.value ->> 'credit')::bigint, 0);
    v_currency := upper(coalesce(nullif(v_line.value ->> 'currency', ''), v_settings."functional_currency"));
    if v_currency !~ '^[A-Z]{3}$' then
      raise exception 'a line''s currency must be an ISO 4217 code such as EUR' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
    end if;
    if v_account."currency" is not null and v_account."currency" <> v_currency then
      raise exception 'the account takes lines in its own currency only' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
    end if;
    v_rate := null;
    if v_currency = v_settings."functional_currency" then
      v_amount := v_debit - v_credit;
    else
      v_amount := (v_line.value ->> 'amountCurrency')::bigint;
      if v_amount is null or v_amount = 0 then
        raise exception 'a line in another currency needs a non-zero amountCurrency' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
      end if;
      v_rate := coalesce((v_line.value ->> 'fxRate')::numeric,
        "better_supabase"."accounting_fx_rate"(v_journal."tenant_id", v_currency, v_settings."functional_currency", save_accounting_entry.entry_date));
      if v_rate <= 0 then
        raise exception 'fxRate must be positive' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
      end if;
      if v_debit = 0 and v_credit = 0 then
        v_functional := round(abs(v_amount) * v_rate)::bigint;
        if v_amount > 0 then
          v_debit := v_functional;
        else
          v_credit := v_functional;
        end if;
      elsif (v_amount > 0) <> (v_debit > 0) then
        raise exception 'amountCurrency and the functional amount must be on the same side' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
      end if;
    end if;
    if (v_debit = 0) = (v_credit = 0) then
      raise exception 'every line has either a debit or a credit' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
    end if;
    v_tax := case when v_line.value ? 'taxCodeId' then null else v_account."default_tax_code_id" end;
    if v_line.value ->> 'taxCodeId' is not null then
      select y."id" into v_tax from "better_supabase"."tax_codes" y
      where y."id"::text = v_line.value ->> 'taxCodeId' and y."tenant_id" = v_journal."tenant_id";
      if v_tax is null then
        raise exception 'tax code not found' using errcode = 'P0002', hint = 'ACCOUNTING_TAX_CODE_NOT_FOUND';
      end if;
    end if;
    if coalesce(v_line.value ->> 'partyId', '00000000-0000-0000-0000-000000000000') !~ '^[0-9a-fA-F-]{36}$' then
      raise exception 'partyId must be a uuid' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
    end if;
    v_party := (v_line.value ->> 'partyId')::uuid;
    if coalesce((v_line.value ->> 'taxAmount')::bigint, 0) > v_debit + v_credit then
      raise exception 'a line''s taxAmount can''t exceed its amount' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
    end if;
    v_dimensions := coalesce(v_line.value -> 'dimensions', '{}'::jsonb);
    if jsonb_typeof(v_dimensions) = 'null' then
      v_dimensions := '{}'::jsonb;
    end if;
    if jsonb_typeof(v_dimensions) <> 'object' then
      raise exception 'a line''s dimensions are an object of dimension keys to value codes' using errcode = '22023', hint = 'ACCOUNTING_DIMENSION_INVALID';
    end if;
    insert into "better_supabase"."accounting_entry_lines" ("tenant_id", "entry_id", "position", "account_id", "debit", "credit", "currency",
      "amount_currency", "fx_rate", "tax_code_id", "tax_amount", "party_id", "dimensions", "description")
    values (v_journal."tenant_id", v_row."id", v_line.ordinality, v_account."id", v_debit, v_credit, v_currency,
      v_amount, v_rate, v_tax, coalesce((v_line.value ->> 'taxAmount')::bigint, 0), v_party, v_dimensions, nullif(trim(v_line.value ->> 'description'), ''));
  end loop;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'journalId', v_row."journal_id", 'number', v_row."number", 'fiscalYear', v_row."fiscal_year", 'entryDate', v_row."entry_date", 'periodId', v_row."period_id", 'status', v_row."status", 'reference', v_row."reference", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'reversesId', v_row."reverses_id", 'memo', v_row."memo", 'memoKey', v_row."memo_key", 'memoParams', v_row."memo_params", 'total', coalesce((select sum(et."debit") from "better_supabase"."accounting_entry_lines" et where et."entry_id" = v_row."id"), 0)::text, 'postedAt', v_row."posted_at", 'postedBy', v_row."posted_by", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'lines', coalesce((select jsonb_agg(jsonb_build_object('id', el."id", 'accountId', el."account_id", 'accountCode', ea."code", 'accountName', ea."name", 'debit', el."debit"::text, 'credit', el."credit"::text, 'currency', el."currency", 'amountCurrency', el."amount_currency"::text, 'fxRate', el."fx_rate"::text, 'taxCodeId', el."tax_code_id", 'taxAmount', el."tax_amount"::text, 'partyId', el."party_id", 'dimensions', el."dimensions", 'description', el."description") order by el."position", el."id") from "better_supabase"."accounting_entry_lines" el join "better_supabase"."accounting_accounts" ea on ea."id" = el."account_id" where el."entry_id" = v_row."id"), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.terminate_lease (
  lease_id          uuid,
  terminates_on     date   DEFAULT NULL::date,
  reason            text   DEFAULT NULL::text,
  deposit_deduction bigint DEFAULT 0
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."leases"%rowtype;
  v_on date := coalesce(terminate_lease.terminates_on, current_date);
  v_deduction bigint := coalesce(terminate_lease.deposit_deduction, 0);
  v_held bigint;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."leases" x where x."id" = terminate_lease.lease_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leases.manage'), false)) then
    raise exception 'no such lease you can read' using errcode = 'P0002', hint = 'LEASE_NOT_FOUND';
  end if;
  if v_row."status" not in ('draft', 'active') then
    raise exception 'this lease has already ended' using errcode = '55000', hint = 'LEASE_STATUS_INVALID';
  end if;
  if v_on < v_row."starts_on" and v_row."status" = 'active' then
    raise exception 'a lease can''t end before it starts' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."lease_charges" y where y."lease_id" = v_row."id" and y."period_start" >= v_on) then
    raise exception 'rent is already posted for a period from this date; pick a later date' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  v_held := coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = v_row."deposit_hold_id" and h."status" = 'active'), 0);
  if v_deduction < 0 or v_deduction > v_held then
    raise exception 'a deduction is zero or more and at most the deposit held' using errcode = '22023', hint = 'LEASE_DEPOSIT_INVALID';
  end if;
  if v_held > 0 then
    if v_deduction > 0 then
      perform "better_supabase"."ledger_capture"(v_row."deposit_hold_id", "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_income', 'leases.income:' || v_row."currency", 'Rent income ' || v_row."currency",
      v_row."currency"::text, 0::smallint, null, null, null, true, 'leases.read', 'leases', null), v_deduction, 'lease.deposit_deduction', 'Deposit deduction');
    else
      perform "better_supabase"."ledger_release"(v_row."deposit_hold_id");
    end if;
    if v_held - v_deduction > 0 then
      perform "better_supabase"."ledger_post"(v_row."tenant_id", 'lease.deposit_refund',
        jsonb_build_array(
          jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_deposit', 'leases.deposit:' || v_row."id"::text, 'Deposit ' || v_row."title",
      v_row."currency"::text, 0::smallint, 'lease', v_row."id"::text, null, false, 'leases.read', 'leases',
      jsonb_build_object('leaseId', v_row."id")), 'amount', -(v_held - v_deduction)),
          jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_cash', 'leases.cash:' || v_row."currency", 'Rent received ' || v_row."currency",
      v_row."currency"::text, 0::smallint, null, null, null, true, 'leases.read', 'leases', null), 'amount', v_held - v_deduction)),
        'leases', v_row."id"::text, 'Deposit refunded', 'leases.deposit_refund:' || v_row."id"::text, null,
        jsonb_build_object('leaseId', v_row."id"),
        memo_key => 'lease.deposit_refund', memo_params => '{}'::jsonb);
    end if;
  end if;
  update "better_supabase"."leases" x set
      "status" = case when x."status" = 'active' and x."ends_on" is not null and v_on >= x."ends_on" then 'ended' else 'terminated' end,
      "terminated_on" = v_on, "termination_reason" = nullif(trim(terminate_lease.reason), ''), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  perform "better_supabase".emit_event('lease.terminated', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'unitId', v_row."unit_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'status', v_row."status", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'rent', v_row."rent"::text, 'currency', v_row."currency"), 'leases/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/leases');
  perform better_supabase.audit_event(
    event_type => 'lease.terminated',
    category => 'billing',
    target_type => 'lease',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'ended a lease',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'unitId', v_row."unit_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'status', v_row."status", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'rent', v_row."rent"::text, 'currency', v_row."currency")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'unitId', v_row."unit_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'title', v_row."title", 'status', v_row."status", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'rent', v_row."rent"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'deposit', v_row."deposit"::text, 'depositHoldId', v_row."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = v_row."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = v_row."tenant_id" and x."code" = 'leases.rent:' || v_row."id"::text), 0)::text, 'renewedAt', v_row."renewed_at", 'terminatedOn', v_row."terminated_on", 'terminationReason', v_row."termination_reason", 'metadata', v_row."metadata", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.unlock_accounting_period (
  period_id uuid,
  reason    text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_period "better_supabase"."accounting_periods"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_period from "better_supabase"."accounting_periods" y where y."id" = unlock_accounting_period.period_id for update;
  if not found then
    raise exception 'period not found' using errcode = 'P0002', hint = 'ACCOUNTING_PERIOD_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_period."tenant_id", 'accounting.close'), false)) then
    raise exception 'not allowed to unlock accounting periods' using errcode = '42501', hint = 'ACCOUNTING_PERIOD_FORBIDDEN';
  end if;
  if nullif(trim(unlock_accounting_period.reason), '') is null then
    raise exception 'unlocking a period needs a reason' using errcode = '22023', hint = 'ACCOUNTING_PERIOD_INVALID';
  end if;
  if v_period."status" <> 'locked' then
    return jsonb_build_object('id', v_period."id", 'organizationId', v_period."tenant_id", 'fiscalYear', v_period."fiscal_year", 'number', v_period."number", 'startsOn', v_period."starts_on", 'endsOn', v_period."ends_on", 'status', v_period."status", 'closedAt', v_period."closed_at", 'closedBy', v_period."closed_by", 'lockedAt', v_period."locked_at", 'lockedBy', v_period."locked_by");
  end if;
  update "better_supabase"."accounting_periods" y set "status" = 'closed', "locked_at" = null, "locked_by" = null
  where y."id" = v_period."id"
  returning * into v_period;
  perform "better_supabase".emit_event('accounting_period.unlocked', jsonb_build_object('organizationId', v_period."tenant_id", 'id', v_period."id", 'fiscalYear', v_period."fiscal_year", 'number', v_period."number", 'startsOn', v_period."starts_on", 'endsOn', v_period."ends_on", 'reason', trim(unlock_accounting_period.reason)), 'accounting-periods/' || v_period."id"::text, (v_period."tenant_id")::text, null, 'better-supabase/accounting');
  perform better_supabase.audit_event(
    event_type => 'accounting_period.unlocked',
    category => 'data',
    target_type => 'accounting_period',
    record_id => v_period."id"::text,
    target_label => v_period."fiscal_year"::text || '-' || lpad(v_period."number"::text, 2, '0'),
    summary => 'unlocked period ' || v_period."fiscal_year"::text || '-' || lpad(v_period."number"::text, 2, '0'),
    summary_params => jsonb_build_object('fiscalYear', v_period."fiscal_year", 'number', v_period."number"),
    tenant => (v_period."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_period."tenant_id", 'id', v_period."id", 'fiscalYear', v_period."fiscal_year", 'number', v_period."number", 'startsOn', v_period."starts_on", 'endsOn', v_period."ends_on", 'reason', trim(unlock_accounting_period.reason))
  );
  return jsonb_build_object('id', v_period."id", 'organizationId', v_period."tenant_id", 'fiscalYear', v_period."fiscal_year", 'number', v_period."number", 'startsOn', v_period."starts_on", 'endsOn', v_period."ends_on", 'status', v_period."status", 'closedAt', v_period."closed_at", 'closedBy', v_period."closed_by", 'lockedAt', v_period."locked_at", 'lockedBy', v_period."locked_by");
end;
$function$;

REVOKE ALL
  ON FUNCTION
    "api"."audit_event"(text, text, text, text, text, text, uuid, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text, text, text, uuid, uuid, text, text,
    jsonb)
  FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION
    "api"."audit_event"(text, text, text, text, text, text, uuid, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text, text, text, uuid, uuid, text, text,
    jsonb)
  TO "authenticated", "service_role";

REVOKE ALL
  ON FUNCTION
    "api"."audit_event_trusted"(text, text, text, text, text, text, uuid, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text, text, text, uuid, uuid, text,
    text, jsonb)
  FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION
    "api"."audit_event_trusted"(text, text, text, text, text, text, uuid, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text, text, text, uuid, uuid, text,
    text, jsonb)
  TO "service_role";

REVOKE ALL
  ON FUNCTION
    "better_supabase"."audit_event"(text, text, text, text, text, text, uuid, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text, text, text, uuid, uuid,
    text, text, jsonb)
  FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION
    "better_supabase"."audit_event"(text, text, text, text, text, text, uuid, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text, text, text, uuid, uuid,
    text, text, jsonb)
  TO "authenticated", "service_role";

REVOKE ALL
  ON FUNCTION
    "better_supabase"."audit_event_trusted"(text, text, text, text, text, text, uuid, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text, text, text, uuid,
    uuid, text, text, jsonb)
  FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION
    "better_supabase"."audit_event_trusted"(text, text, text, text, text, text, uuid, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text, text, text, uuid,
    uuid, text, text, jsonb)
  TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."ledger_post"(uuid, text, jsonb, text, text, text, text, timestamp WITH time zone, jsonb, uuid, text, jsonb) FROM PUBLIC;

