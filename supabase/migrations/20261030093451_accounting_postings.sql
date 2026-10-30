SET local check_function_bodies = off;

ALTER TABLE "better_supabase"."accounting_account_roles"
  DROP CONSTRAINT "accounting_account_roles_role_check";

CREATE TABLE "better_supabase"."accounting_budget_lines" (
  "id"            uuid     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"     uuid     NOT NULL,
  "budget_id"     uuid     NOT NULL,
  "account_id"    uuid     NOT NULL,
  "period_number" smallint NOT NULL,
  "dimensions"    jsonb    NOT NULL DEFAULT '{}'::jsonb,
  "amount"        bigint   NOT NULL,
  CONSTRAINT "accounting_budget_lines_budget_id_account_id_period_number__key" UNIQUE (budget_id, account_id, period_number, dimensions),
  CONSTRAINT "accounting_budget_lines_dimensions_check" CHECK ((jsonb_typeof(dimensions) = 'object'::text)),
  CONSTRAINT "accounting_budget_lines_period_number_check" CHECK (((period_number >= 1) AND (period_number <= 12))),
  CONSTRAINT "accounting_budget_lines_pkey" PRIMARY KEY (id)
);

ALTER TABLE "better_supabase"."accounting_budget_lines"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."accounting_budgets" (
  "id"          uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"   uuid                     NOT NULL,
  "name"        text                     NOT NULL,
  "fiscal_year" integer                  NOT NULL,
  "status"      text                     NOT NULL DEFAULT 'draft'::text,
  "created_by"  uuid,
  "created_at"  timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"  timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "accounting_budgets_fiscal_year_check" CHECK (((fiscal_year >= 1900) AND (fiscal_year <= 9999))),
  CONSTRAINT "accounting_budgets_name_check" CHECK (((length(name) >= 1) AND (length(name) <= 200))),
  CONSTRAINT "accounting_budgets_pkey" PRIMARY KEY (id),
  CONSTRAINT "accounting_budgets_status_check" CHECK ((status = ANY (ARRAY['draft'::text, 'approved'::text, 'archived'::text]))),
  CONSTRAINT "accounting_budgets_tenant_id_fiscal_year_name_key" UNIQUE (tenant_id, fiscal_year, name)
);

ALTER TABLE "better_supabase"."accounting_budgets"
  ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION api.accounting_budget_vs_actual (
  budget_id     uuid,
  period_number integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."accounting_budget_vs_actual"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.accounting_tax_report (
  tenant uuid,
  since  date,
  until  date
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."accounting_tax_report"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.get_accounting_budget (
  budget_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_accounting_budget"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_accounting_budgets (
  tenant      uuid,
  fiscal_year integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_accounting_budgets"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.post_accounting_source (
  source_type text,
  source_id   text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."post_accounting_source"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.save_accounting_budget (
  tenant      uuid,
  name        text,
  fiscal_year integer,
  status      text    DEFAULT NULL::text,
  lines       jsonb   DEFAULT NULL::jsonb,
  budget_id   uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_accounting_budget"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION better_supabase.accounting_budget_vs_actual (
  budget_id     uuid,
  period_number integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  with budget as (
    select x.* from "better_supabase"."accounting_budgets" x where x."id" = accounting_budget_vs_actual.budget_id
  ),
  planned as (
    select y."account_id" as account, y."dimensions" as dimensions, sum(y."amount") as amount
    from "better_supabase"."accounting_budget_lines" y
    where y."budget_id" = accounting_budget_vs_actual.budget_id
      and (accounting_budget_vs_actual.period_number is null or y."period_number" = accounting_budget_vs_actual.period_number)
    group by y."account_id", y."dimensions"
  ),
  compared as (
    select q.account, q.dimensions, q.amount as budget, ac."code" as code, ac."name" as name, ac."type" as type,
      coalesce((
        select sum(case when ac."type" in ('liability', 'equity', 'income') then z."credit" - z."debit" else z."debit" - z."credit" end)
        from "better_supabase"."accounting_entry_lines" z
        join "better_supabase"."accounting_entries" w on w."id" = z."entry_id"
        join "better_supabase"."accounting_periods" v on v."id" = w."period_id"
        cross join budget g
        where z."account_id" = q.account and z."dimensions" @> q.dimensions
          and w."status" in ('posted', 'reversed') and w."source_type" is distinct from 'fiscal_year'
          and v."tenant_id" = g."tenant_id" and v."fiscal_year" = g."fiscal_year"
          and (accounting_budget_vs_actual.period_number is null or v."number" = accounting_budget_vs_actual.period_number)
      ), 0) as actual
    from planned q join "better_supabase"."accounting_accounts" ac on ac."id" = q.account
  )
  select jsonb_build_object(
    'budgetId', g."id",
    'name', g."name",
    'fiscalYear', g."fiscal_year",
    'periodNumber', accounting_budget_vs_actual.period_number,
    'lines', coalesce((select jsonb_agg(jsonb_build_object('accountId', c.account, 'code', c.code, 'name', c.name, 'type', c.type,
      'dimensions', c.dimensions, 'budget', c.budget::text, 'actual', c.actual::text, 'variance', (c.actual - c.budget)::text)
      order by c.code, c.dimensions::text) from compared c), '[]'::jsonb),
    'budget', coalesce((select sum(c.budget) from compared c), 0)::text,
    'actual', coalesce((select sum(c.actual) from compared c), 0)::text
  )
  from budget g
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
    'memo', left('Reimbursed: ' || v."title", 500),
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
    'memo', left('Expenses: ' || v."title", 500),
    'lines', jsonb_build_array(
      jsonb_build_object('role', 'expense', 'debit', (select coalesce(sum(y."amount"), 0) from "better_supabase"."expense_lines" y where y."report_id" = v."id")::text, 'description', v."title"),
      jsonb_build_object('role', 'payable', 'credit', (select coalesce(sum(y."amount"), 0) from "better_supabase"."expense_lines" y where y."report_id" = v."id")::text, 'partyId', v."user_id"::text))
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
    'memo', 'Gift',
    'lines', jsonb_build_array(
      jsonb_build_object('role', 'bank', 'debit', v."amount"::text),
      jsonb_build_object('role', 'revenue', 'credit', v."amount"::text, 'partyId', v."donor_id"))
  )
  from "better_supabase"."donations" v
  where v."id"::text = source_id and v."status" = 'posted' and v."amount" <> 0
$function$;

CREATE OR REPLACE FUNCTION better_supabase.accounting_invoice_lines (
  source_id text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  with inv as (
    select x."id" as id, x."tenant_id" as tenant, x."issued_on" as issued_on, x."currency" as currency,
      x."identifier" as identifier, x."title" as title, x."subtotal" as subtotal, x."tax_total" as tax_total,
      x."total" as total, x."company_id"::text as party, x."prices_include_tax" as inclusive,
      case when x."kind" = 'credit_note' then -1 else 1 end as sign
    from "better_supabase"."invoices" x
    where x."id"::text = source_id and x."status" not in ('draft', 'void')
  ),
  groups as (
    select l."tax_rate_bps" as rate, l."tax_code" as code, sum(round(l."quantity" * l."unit_amount") - round(round(l."quantity" * l."unit_amount") * l."discount_bps" / 10000.0)) as net,
      sum((round(l."quantity" * l."unit_amount") - round(round(l."quantity" * l."unit_amount") * l."discount_bps" / 10000.0)) * l."tax_rate_bps" / case when inv.inclusive then 10000.0 + l."tax_rate_bps" else 10000.0 end) as tax
    from "better_supabase"."invoice_lines" l cross join inv
    where l."parent_id" = inv.id and true
    group by 1, 2
  ),
  shares as (
    select g.rate, g.code,
      case when sum(g.net) over () = 0
        then case when row_number() over w = count(*) over () then inv.subtotal else 0 end
        else round(inv.subtotal * sum(g.net) over w / sum(g.net) over ()) - round(inv.subtotal * (sum(g.net) over w - g.net) / sum(g.net) over ())
      end as net,
      case when sum(g.tax) over () = 0
        then case when row_number() over w = count(*) over () then inv.tax_total else 0 end
        else round(inv.tax_total * sum(g.tax) over w / sum(g.tax) over ()) - round(inv.tax_total * (sum(g.tax) over w - g.tax) / sum(g.tax) over ())
      end as tax
    from groups g cross join inv
    window w as (order by g.rate, g.code nulls first rows between unbounded preceding and current row)
  )
  select jsonb_build_object(
    'organizationId', inv.tenant,
    'entryDate', inv.issued_on,
    'currency', inv.currency,
    'reference', inv.identifier,
    'memo', inv.title,
    'lines', jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('role', 'receivable', 'debit', (inv.sign * inv.total)::text, 'partyId', inv.party)))
      || coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('role', 'revenue', 'credit', (inv.sign * s.net)::text, 'taxCode', s.code, 'taxRateBps', s.rate, 'partyId', inv.party))) from shares s where s.net <> 0), '[]'::jsonb)
      || coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('role', 'tax_payable', 'credit', (inv.sign * s.tax)::text, 'taxCode', s.code, 'taxRateBps', s.rate, 'partyId', inv.party))) from shares s where s.tax <> 0), '[]'::jsonb)
  )
  from inv
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
    'memo', 'Payment of ' || coalesce(inv."identifier", inv."title"),
    'lines', jsonb_build_array(
      jsonb_build_object('role', 'bank', 'debit', p.amount::text),
      jsonb_strip_nulls(jsonb_build_object('role', 'receivable', 'credit', p.amount::text, 'partyId', inv."company_id"::text)))
  )
  from "better_supabase"."ledger_transactions" y
  join "better_supabase"."invoices" inv on inv."id"::text = y."metadata" ->> 'invoiceId'
  cross join lateral (
    select sum(e."amount") as amount from "better_supabase"."ledger_entries" e
    join "better_supabase"."ledger_accounts" a on a."id" = e."account_id"
    where e."transaction_id" = y."id" and a."code" = 'invoices:cash:' || inv."currency"
  ) p
  where y."id"::text = source_id and y."reference_type" = 'invoices' and p.amount <> 0
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
    'memo', left('Rent payment: ' || coalesce(v."title", ''), 500),
    'lines', jsonb_build_array(
      jsonb_build_object('role', 'bank', 'debit', p.amount::text),
      jsonb_build_object('role', 'receivable', 'credit', p.amount::text, 'partyId', v."party_id"))
  )
  from "better_supabase"."ledger_transactions" y
  join "better_supabase"."lease_agreements" v on v."id"::text = y."reference_id"
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
    'memo', left('Rent from ' || y."period_start"::text || ': ' || coalesce(v."title", ''), 500),
    'lines', jsonb_build_array(
      jsonb_build_object('role', 'receivable', 'debit', y."amount"::text, 'partyId', v."party_id"),
      jsonb_build_object('role', 'revenue', 'credit', y."amount"::text))
  )
  from "better_supabase"."lease_charges" y join "better_supabase"."lease_agreements" v on v."id" = y."lease_id"
  where y."id"::text = source_id and y."amount" <> 0
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
  v_tax "better_supabase"."accounting_tax_codes"%rowtype;
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
    or accounting_post_source.source_type not in ('stock_movement', 'invoice', 'invoice_payment', 'lease_rent', 'lease_payment', 'expense_report', 'expense_reimbursement', 'gift') then
    raise exception 'no installed block books this source type' using errcode = '22023', hint = 'ACCOUNTING_SOURCE_INVALID';
  end if;
  v_doc := case accounting_post_source.source_type
    when 'stock_movement' then "better_supabase"."accounting_stock_movement_lines"(accounting_post_source.source_id)
    when 'invoice' then "better_supabase"."accounting_invoice_lines"(accounting_post_source.source_id)
    when 'invoice_payment' then "better_supabase"."accounting_invoice_payment_lines"(accounting_post_source.source_id)
    when 'lease_rent' then "better_supabase"."accounting_lease_rent_lines"(accounting_post_source.source_id)
    when 'lease_payment' then "better_supabase"."accounting_lease_payment_lines"(accounting_post_source.source_id)
    when 'expense_report' then "better_supabase"."accounting_expense_report_lines"(accounting_post_source.source_id)
    when 'expense_reimbursement' then "better_supabase"."accounting_expense_reimbursement_lines"(accounting_post_source.source_id)
    when 'gift' then "better_supabase"."accounting_gift_lines"(accounting_post_source.source_id)
  end;
  v_kind := case accounting_post_source.source_type
    when 'stock_movement' then 'general'
    when 'invoice' then 'sales'
    when 'invoice_payment' then 'bank'
    when 'lease_rent' then 'sales'
    when 'lease_payment' then 'bank'
    when 'expense_report' then 'purchase'
    when 'expense_reimbursement' then 'bank'
    when 'gift' then 'bank'
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
  select * into v_journal from "better_supabase"."accounting_journals" y
  where y."tenant_id" = v_tenant and y."type" = v_kind order by y."code" limit 1;
  if not found then
    raise exception 'the organization has no journal of the type this document books in' using errcode = 'P0002', hint = 'ACCOUNTING_JOURNAL_NOT_FOUND';
  end if;
  for v_line in select q.value from jsonb_array_elements(v_doc -> 'lines') q loop
    v_amount := coalesce((v_line.value ->> 'debit')::bigint, 0) - coalesce((v_line.value ->> 'credit')::bigint, 0);
    continue when v_amount = 0;
    v_tax := null;
    if v_line.value ->> 'taxCode' is not null then
      select * into v_tax from "better_supabase"."accounting_tax_codes" y
      where y."tenant_id" = v_tenant and y."code" = v_line.value ->> 'taxCode' and y."archived_at" is null;
    end if;
    if v_tax."id" is null and coalesce(v_line.value ->> 'taxRateBps', '') ~ '^[0-9]{1,6}$' then
      select * into v_tax from "better_supabase"."accounting_tax_codes" y
      where y."tenant_id" = v_tenant and y."rate_bps" = (v_line.value ->> 'taxRateBps')::integer
        and y."kind" = case when v_journal."type" = 'purchase' then 'purchase' else 'sales' end
        and y."archived_at" is null
      order by y."code" limit 1;
    end if;
    v_account := null;
    if v_line.value ->> 'role' in ('tax_payable', 'tax_receivable') and v_tax."id" is not null then
      v_account := v_tax."account_id";
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
  insert into "better_supabase"."accounting_entries" ("tenant_id", "journal_id", "entry_date", "reference", "source_type", "source_id", "memo", "created_by", "period_id")
  values (v_tenant, v_journal."id", v_date, left(nullif(trim(v_doc ->> 'reference'), ''), 200),
    accounting_post_source.source_type, accounting_post_source.source_id, left(nullif(trim(v_doc ->> 'memo'), ''), 2000), auth.uid(),
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
  insert into "better_supabase"."accounting_entries" ("tenant_id", "journal_id", "entry_date", "reference", "reverses_id", "memo", "created_by")
  values (v_row."tenant_id", v_row."journal_id", coalesce(accounting_reverse.entry_date, v_row."entry_date"), v_row."number",
    v_row."id", 'Reversal of ' || v_row."number", auth.uid())
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

CREATE OR REPLACE FUNCTION better_supabase.accounting_reverse_source (
  tenant      uuid,
  source_type text,
  source_id   text,
  entry_date  date DEFAULT NULL::date
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."accounting_entries"%rowtype;
begin
  select * into v_row from "better_supabase"."accounting_entries" y
  where y."tenant_id" = accounting_reverse_source.tenant and y."source_type" = accounting_reverse_source.source_type
    and y."source_id" = accounting_reverse_source.source_id and y."status" <> 'reversed'
  for update;
  if not found then
    return null;
  end if;
  if v_row."status" = 'draft' then
    delete from "better_supabase"."accounting_entries" y where y."id" = v_row."id";
    return null;
  end if;
  return ("better_supabase"."accounting_reverse"(v_row."id", coalesce(accounting_reverse_source.entry_date, current_date)))."id";
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
    'memo', 'Stock ' || (y."metadata" ->> 'reason'),
    'lines', jsonb_build_array(
      jsonb_build_object('role', 'inventory', 'debit', e."amount"::text),
      jsonb_build_object('role', case y."metadata" ->> 'reason' when 'receipt' then 'payable' when 'sale' then 'cogs' when 'return' then 'cogs' else 'expense' end,
        'credit', e."amount"::text))
  )
  from "better_supabase"."ledger_transactions" y
  join "better_supabase"."ledger_entries" e on e."transaction_id" = y."id"
  join "better_supabase"."ledger_accounts" a on a."id" = e."account_id" and a."kind" = 'stock_value'
  where y."id"::text = source_id and e."amount" <> 0
  limit 1
$function$;

CREATE OR REPLACE FUNCTION better_supabase.accounting_tax_report (
  tenant uuid,
  since  date,
  until  date
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  with booked as (
    select y."tax_code_id" as tax_code, y."account_id" as account, y."credit" - y."debit" as net
    from "better_supabase"."accounting_entry_lines" y join "better_supabase"."accounting_entries" z on z."id" = y."entry_id"
    where z."tenant_id" = accounting_tax_report.tenant and z."status" in ('posted', 'reversed')
      and y."tax_code_id" is not null
      and z."entry_date" >= accounting_tax_report.since and z."entry_date" <= accounting_tax_report.until
  ),
  codes as (
    select w."id" as id, w."code" as code, w."name" as name, w."kind" as kind,
      w."rate_bps" as rate_bps, w."report_boxes" as boxes,
      (case when w."kind" = 'sales' then 1 else -1 end) * coalesce(sum(b.net) filter (where b.account <> w."account_id"), 0) as base,
      (case when w."kind" = 'sales' then 1 else -1 end) * coalesce(sum(b.net) filter (where b.account = w."account_id"), 0) as tax
    from booked b join "better_supabase"."accounting_tax_codes" w on w."id" = b.tax_code
    group by w."id"
  )
  select jsonb_build_object(
    'organizationId', accounting_tax_report.tenant,
    'since', accounting_tax_report.since,
    'until', accounting_tax_report.until,
    'currency', (select st."functional_currency" from "better_supabase"."accounting_settings" st where st."tenant_id" = accounting_tax_report.tenant),
    'codes', coalesce((select jsonb_agg(jsonb_build_object('taxCodeId', c.id, 'code', c.code, 'name', c.name, 'kind', c.kind,
      'rateBps', c.rate_bps, 'reportBoxes', to_jsonb(c.boxes), 'base', c.base::text, 'tax', c.tax::text) order by c.code) from codes c), '[]'::jsonb),
    'boxes', coalesce((select jsonb_agg(jsonb_build_object('box', x.box, 'base', x.base::text, 'tax', x.tax::text) order by x.box)
      from (select q.box, sum(c.base) as base, sum(c.tax) as tax from codes c cross join unnest(c.boxes) q(box) group by q.box) x), '[]'::jsonb),
    'salesTax', coalesce((select sum(c.tax) from codes c where c.kind = 'sales'), 0)::text,
    'purchaseTax', coalesce((select sum(c.tax) from codes c where c.kind = 'purchase'), 0)::text,
    'netTax', coalesce((select sum(case when c.kind = 'sales' then c.tax else -c.tax end) from codes c), 0)::text
  )
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
    jsonb_build_object('reportId', v_row."id", 'userId', v_row."user_id"));
  update "better_supabase"."expense_reports" x set "approved_at" = now(), "approval_transaction_id" = v_tx, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  perform "better_supabase"."accounting_post_source"('expense_report', v_row."id"::text);
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

CREATE OR REPLACE FUNCTION better_supabase.data_lifecycle_tables()
  RETURNS TABLE (
    subject  text,
    name     text,
    tbl      text,
    col      text,
    purge    boolean,
    omit     text[],
    exported boolean
  )
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select t.subject, t.name, t.tbl, t.col, t.purge,
    t.omit || array(
      select a.attname::text
      from pg_catalog.pg_attribute a
      where a.attrelid = to_regclass(t.tbl)
        and a.attnum > 0
        and not a.attisdropped
        and a.attname ~* 'token|secret|_hash|password|api_key|license_key'
        and a.attname <> t.col
        and not a.attname = any(t.omit)
      order by a.attnum
    ) as omit,
    t.exported
  from (
  select * from (values
    ('user', 'better_supabase.audit_events', '"better_supabase"."audit_events"', 'actor_id', false, array['old_record', 'new_record', 'impersonated_by', 'impersonation_reason', 'support_session_id']::text[], true),
    ('user', 'public.memberships', '"public"."memberships"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.platform_roles', '"better_supabase"."platform_roles"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.profiles', '"better_supabase"."profiles"', 'id', true, '{}'::text[], true),
    ('user', 'better_supabase.notification_recipients', '"better_supabase"."notification_recipients"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.notification_subscriptions', '"better_supabase"."notification_subscriptions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.notification_preferences', '"better_supabase"."notification_preferences"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.notification_suppressions', '"better_supabase"."notification_suppressions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.user_settings', '"better_supabase"."user_settings"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.usage_history', '"better_supabase"."usage_history"', 'actor_id', true, '{}'::text[], true),
    ('user', 'better_supabase.flag_overrides', '"better_supabase"."flag_overrides"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.drive_nodes', '"better_supabase"."drive_nodes"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.drive_drives', '"better_supabase"."drive_drives"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.drive_connections', '"better_supabase"."drive_connections"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.guests', '"better_supabase"."guests"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.attachments', '"better_supabase"."attachments"', 'uploaded_by', true, '{}'::text[], true),
    ('user', 'better_supabase.attachment_versions', '"better_supabase"."attachment_versions"', 'uploaded_by', true, '{}'::text[], true),
    ('user', 'better_supabase.scim_users', '"better_supabase"."scim_users"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.enrollment_programs', '"better_supabase"."enrollment_programs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.enrollments', '"better_supabase"."enrollments"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.waitlist_entries', '"better_supabase"."waitlist_entries"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.invite_code_redemptions', '"better_supabase"."invite_code_redemptions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.announcement_dismissals', '"better_supabase"."announcement_dismissals"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.streams', '"better_supabase"."streams"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_runs', '"better_supabase"."workflow_runs"', 'actor_id', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_schedules', '"better_supabase"."workflow_schedules"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_start_requests', '"better_supabase"."workflow_start_requests"', 'actor_id', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_definitions', '"better_supabase"."workflow_definitions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_opt_outs', '"better_supabase"."workflow_opt_outs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_definition_grants', '"better_supabase"."workflow_definition_grants"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.inbox_members', '"better_supabase"."inbox_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.inbox_team_members', '"better_supabase"."inbox_team_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.contacts', '"better_supabase"."contacts"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.scheduled_inbox_messages', '"better_supabase"."scheduled_inbox_messages"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.inbox_drafts', '"better_supabase"."inbox_drafts"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_projects', '"better_supabase"."ai_projects"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_chats', '"better_supabase"."ai_chats"', 'owner_id', true, array['search_tsv']::text[], true),
    ('user', 'better_supabase.ai_chat_participants', '"better_supabase"."ai_chat_participants"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_messages', '"better_supabase"."ai_messages"', 'owner_id', true, array['search_tsv']::text[], true),
    ('user', 'better_supabase.ai_runs', '"better_supabase"."ai_runs"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_tool_approvals', '"better_supabase"."ai_tool_approvals"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_pending_inputs', '"better_supabase"."ai_pending_inputs"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_message_feedback', '"better_supabase"."ai_message_feedback"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_chat_shares', '"better_supabase"."ai_chat_shares"', 'created_by', true, array['token_hash']::text[], true),
    ('user', 'better_supabase.ai_moderation_events', '"better_supabase"."ai_moderation_events"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_run_steps', '"better_supabase"."ai_run_steps"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_sandboxes', '"better_supabase"."ai_sandboxes"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_harness_sessions', '"better_supabase"."ai_harness_sessions"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_files', '"better_supabase"."ai_files"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_documents', '"better_supabase"."ai_documents"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_document_versions', '"better_supabase"."ai_document_versions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_suggestions', '"better_supabase"."ai_suggestions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.knowledge_documents', '"better_supabase"."knowledge_documents"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.knowledge_collection_grants', '"better_supabase"."knowledge_collection_grants"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.memories', '"better_supabase"."memories"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_message_embeddings', '"better_supabase"."ai_message_embeddings"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.agents', '"better_supabase"."agents"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.agent_installs', '"better_supabase"."agent_installs"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.agent_ratings', '"better_supabase"."agent_ratings"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.connector_grants', '"better_supabase"."connector_grants"', 'user_id', true, array['credential_ref']::text[], true),
    ('user', 'better_supabase.connector_sessions', '"better_supabase"."connector_sessions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_scheduled_tasks', '"better_supabase"."ai_scheduled_tasks"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_task_runs', '"better_supabase"."ai_task_runs"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.push_devices', '"better_supabase"."push_devices"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_batches', '"better_supabase"."ai_batches"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.teams', '"better_supabase"."teams"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.team_members', '"better_supabase"."team_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.status_history', '"better_supabase"."status_history"', 'actor_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.share_links', '"better_supabase"."share_links"', 'created_by', true, array['token_hash', 'password_hash']::text[], true),
    ('user', 'better_supabase.reminders', '"better_supabase"."reminders"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.import_runs', '"better_supabase"."import_runs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.subject_members', '"better_supabase"."subject_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.saved_view_preferences', '"better_supabase"."saved_view_preferences"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.bulk_runs', '"better_supabase"."bulk_runs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.calendar_events', '"better_supabase"."calendar_events"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.calendar_attendees', '"better_supabase"."calendar_attendees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.calendar_working_hours', '"better_supabase"."calendar_working_hours"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.bookings', '"better_supabase"."bookings"', 'customer_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.versions', '"better_supabase"."versions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.trash_items', '"better_supabase"."trash_items"', 'trashed_by', true, '{}'::text[], true),
    ('user', 'better_supabase.reactions', '"better_supabase"."reactions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.custom_emoji', '"better_supabase"."custom_emoji"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.approval_requests', '"better_supabase"."approval_requests"', 'requested_by', true, '{}'::text[], true),
    ('user', 'better_supabase.approval_decisions', '"better_supabase"."approval_decisions"', 'approver', true, '{}'::text[], true),
    ('user', 'better_supabase.approval_policies', '"better_supabase"."approval_policies"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.access_requests', '"better_supabase"."access_requests"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.documents', '"better_supabase"."documents"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.document_updates', '"better_supabase"."document_updates"', 'actor', true, '{}'::text[], true),
    ('user', 'better_supabase.document_suggestions', '"better_supabase"."document_suggestions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.ledger_accounts', '"better_supabase"."ledger_accounts"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.carts', '"better_supabase"."carts"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.forms', '"better_supabase"."forms"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.form_versions', '"better_supabase"."form_versions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.form_submissions', '"better_supabase"."form_submissions"', 'respondent_id', true, '{}'::text[], true),
    ('user', 'better_supabase.signature_requests', '"better_supabase"."signature_requests"', 'requested_by', true, '{}'::text[], true),
    ('user', 'better_supabase.signatures', '"better_supabase"."signatures"', 'signer', true, '{}'::text[], true),
    ('user', 'better_supabase.time_entries', '"better_supabase"."time_entries"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.timesheets', '"better_supabase"."timesheets"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.template_schedules', '"better_supabase"."template_schedules"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.deals', '"better_supabase"."deals"', 'owner_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.deal_members', '"better_supabase"."deal_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.application_scorecards', '"better_supabase"."application_scorecards"', 'reviewer_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.work_items', '"better_supabase"."work_items"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_item_checklist_items', '"better_supabase"."work_item_checklist_items"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_item_assignees', '"better_supabase"."work_item_assignees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.pipeline_stage_history', '"better_supabase"."pipeline_stage_history"', 'actor_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.engagements', '"better_supabase"."engagements"', 'owner_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.quotes', '"better_supabase"."quotes"', 'owner_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.employees', '"better_supabase"."employees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.employee_private_details', '"better_supabase"."employee_private_details"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_reports', '"better_supabase"."moderation_reports"', 'reporter_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_bans', '"better_supabase"."moderation_bans"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.assets', '"better_supabase"."assets"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.score_models', '"better_supabase"."score_models"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.score_model_versions', '"better_supabase"."score_model_versions"', 'saved_by', true, '{}'::text[], true),
    ('user', 'better_supabase.passes', '"better_supabase"."passes"', 'holder_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.lease_agreements', '"better_supabase"."lease_agreements"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.expense_reports', '"better_supabase"."expense_reports"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.pledges', '"better_supabase"."pledges"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.donations', '"better_supabase"."donations"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_orders', '"better_supabase"."work_orders"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.dispatch_routes', '"better_supabase"."dispatch_routes"', 'technician_id', true, '{}'::text[], true),
    ('user', 'better_supabase.work_order_parts', '"better_supabase"."work_order_parts"', 'recorded_by', true, '{}'::text[], true),
    ('user', 'better_supabase.shipments', '"better_supabase"."shipments"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.contracts', '"better_supabase"."contracts"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.control_evidence', '"better_supabase"."control_evidence"', 'collected_by', true, '{}'::text[], true),
    ('user', 'better_supabase.policy_acknowledgements', '"better_supabase"."policy_acknowledgements"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.incident_updates', '"better_supabase"."incident_updates"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.courses', '"better_supabase"."courses"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.course_lesson_progress', '"better_supabase"."course_lesson_progress"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.course_certificates', '"better_supabase"."course_certificates"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.conversations', '"better_supabase"."conversations"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.conversation_members', '"better_supabase"."conversation_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.messages', '"better_supabase"."messages"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.message_edits', '"better_supabase"."message_edits"', 'edited_by', true, '{}'::text[], true),
    ('user', 'better_supabase.thread_reads', '"better_supabase"."thread_reads"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.channels', '"better_supabase"."channels"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.mail_accounts', '"better_supabase"."mail_accounts"', 'user_id', true, array['credential_ref']::text[], true),
    ('user', 'better_supabase.assignment_queue_members', '"better_supabase"."assignment_queue_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.sequences', '"better_supabase"."sequences"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.sequence_enrollments', '"better_supabase"."sequence_enrollments"', 'enrolled_by', true, '{}'::text[], true),
    ('user', 'better_supabase.post_boards', '"better_supabase"."post_boards"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.posts', '"better_supabase"."posts"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.content_entries', '"better_supabase"."content_entries"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.risk_assessments', '"better_supabase"."risk_assessments"', 'assessed_by', true, '{}'::text[], true),
    ('user', 'better_supabase.shift_assignments', '"better_supabase"."shift_assignments"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.shift_swaps', '"better_supabase"."shift_swaps"', 'from_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.shift_availability', '"better_supabase"."shift_availability"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.acknowledgements', '"better_supabase"."acknowledgements"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.acknowledgement_notices', '"better_supabase"."acknowledgement_notices"', 'user_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.audit_events', '"better_supabase"."audit_events"', 'organization_id', false, array['old_record', 'new_record', 'impersonated_by', 'impersonation_reason', 'support_session_id']::text[], true),
    ('organization', 'public.memberships', '"public"."memberships"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invitations', '"better_supabase"."invitations"', 'organization_id', true, array['token_hash']::text[], true),
    ('organization', 'better_supabase.permission_overrides', '"better_supabase"."permission_overrides"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.outbox_events', '"better_supabase"."outbox_events"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_events', '"better_supabase"."notification_events"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_recipients', '"better_supabase"."notification_recipients"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_deliveries', '"better_supabase"."notification_deliveries"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_delivery_events', '"better_supabase"."notification_delivery_events"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_subscriptions', '"better_supabase"."notification_subscriptions"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_preferences', '"better_supabase"."notification_preferences"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.webhook_endpoints', '"better_supabase"."webhook_endpoints"', 'organization_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.webhook_endpoint_secrets', '"better_supabase"."webhook_endpoint_secrets"', 'organization_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.webhook_deliveries', '"better_supabase"."webhook_deliveries"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.api_keys', '"better_supabase"."api_keys"', 'organization_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.organization_settings', '"better_supabase"."organization_settings"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_counters', '"better_supabase"."usage_counters"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_events', '"better_supabase"."usage_events"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_history', '"better_supabase"."usage_history"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_distinct', '"better_supabase"."usage_distinct"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_quotas', '"better_supabase"."usage_quotas"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.flag_overrides', '"better_supabase"."flag_overrides"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_nodes', '"better_supabase"."drive_nodes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_grants', '"better_supabase"."drive_grants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_drives', '"better_supabase"."drive_drives"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_drive_grants', '"better_supabase"."drive_drive_grants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_connections', '"better_supabase"."drive_connections"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_node_texts', '"better_supabase"."drive_node_texts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.guests', '"better_supabase"."guests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.guest_grants', '"better_supabase"."guest_grants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.comment_tasks', '"better_supabase"."comment_tasks"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.attachments', '"better_supabase"."attachments"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.attachment_versions', '"better_supabase"."attachment_versions"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.retention_policies', '"better_supabase"."retention_policies"', 'organization_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.organization_domains', '"better_supabase"."organization_domains"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.organization_sso_providers', '"better_supabase"."organization_sso_providers"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scim_users', '"better_supabase"."scim_users"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scim_groups', '"better_supabase"."scim_groups"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.enrollment_programs', '"better_supabase"."enrollment_programs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.enrollments', '"better_supabase"."enrollments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.enrollment_steps', '"better_supabase"."enrollment_steps"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invite_codes', '"better_supabase"."invite_codes"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.streams', '"better_supabase"."streams"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_runs', '"better_supabase"."workflow_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_schedules', '"better_supabase"."workflow_schedules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_start_requests', '"better_supabase"."workflow_start_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_definitions', '"better_supabase"."workflow_definitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_opt_outs', '"better_supabase"."workflow_opt_outs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_credentials', '"better_supabase"."workflow_credentials"', 'tenant_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.chat_installations', '"better_supabase"."chat_installations"', 'tenant_id', false, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.inboxes', '"better_supabase"."inboxes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_teams', '"better_supabase"."inbox_teams"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.contacts', '"better_supabase"."contacts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.contact_identities', '"better_supabase"."contact_identities"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_conversations', '"better_supabase"."inbox_conversations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.conversation_events', '"better_supabase"."conversation_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_message_details', '"better_supabase"."inbox_message_details"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.message_deliveries', '"better_supabase"."message_deliveries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbound_events', '"better_supabase"."inbound_events"', 'tenant_id', true, array['headers']::text[], true),
    ('organization', 'better_supabase.message_templates', '"better_supabase"."message_templates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scheduled_inbox_messages', '"better_supabase"."scheduled_inbox_messages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_drafts', '"better_supabase"."inbox_drafts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_projects', '"better_supabase"."ai_projects"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_chats', '"better_supabase"."ai_chats"', 'organization_id', true, array['search_tsv']::text[], true),
    ('organization', 'better_supabase.ai_tool_policies', '"better_supabase"."ai_tool_policies"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_moderation_events', '"better_supabase"."ai_moderation_events"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_sandboxes', '"better_supabase"."ai_sandboxes"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_files', '"better_supabase"."ai_files"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_documents', '"better_supabase"."ai_documents"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.knowledge_documents', '"better_supabase"."knowledge_documents"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.knowledge_collections', '"better_supabase"."knowledge_collections"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.memories', '"better_supabase"."memories"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_message_embeddings', '"better_supabase"."ai_message_embeddings"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.agents', '"better_supabase"."agents"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.agent_installs', '"better_supabase"."agent_installs"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.connector_servers', '"better_supabase"."connector_servers"', 'organization_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.connector_grants', '"better_supabase"."connector_grants"', 'organization_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.ai_scheduled_tasks', '"better_supabase"."ai_scheduled_tasks"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_task_runs', '"better_supabase"."ai_task_runs"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_cache_entries', '"better_supabase"."ai_cache_entries"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_provider_keys', '"better_supabase"."ai_provider_keys"', 'organization_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.ai_batches', '"better_supabase"."ai_batches"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_batch_items', '"better_supabase"."ai_batch_items"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.number_sequences', '"better_supabase"."number_sequences"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.teams', '"better_supabase"."teams"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.team_members', '"better_supabase"."team_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.tags', '"better_supabase"."tags"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.taggings', '"better_supabase"."taggings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_history', '"better_supabase"."status_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_stages', '"better_supabase"."status_stages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.subject_lifecycles', '"better_supabase"."subject_lifecycles"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.field_definitions', '"better_supabase"."field_definitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.field_values', '"better_supabase"."field_values"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.share_links', '"better_supabase"."share_links"', 'tenant_id', true, array['token_hash', 'password_hash']::text[], true),
    ('organization', 'better_supabase.recurrence_rules', '"better_supabase"."recurrence_rules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.reminders', '"better_supabase"."reminders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.import_runs', '"better_supabase"."import_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.subject_members', '"better_supabase"."subject_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shared_views', '"better_supabase"."shared_views"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.saved_view_preferences', '"better_supabase"."saved_view_preferences"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.relations', '"better_supabase"."relations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bulk_runs', '"better_supabase"."bulk_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.products', '"better_supabase"."products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_options', '"better_supabase"."product_options"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_option_values', '"better_supabase"."product_option_values"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_variants', '"better_supabase"."product_variants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_variant_values', '"better_supabase"."product_variant_values"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.price_lists', '"better_supabase"."price_lists"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_prices', '"better_supabase"."product_prices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.categories', '"better_supabase"."categories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_categories', '"better_supabase"."product_categories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_collections', '"better_supabase"."product_collections"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.collection_products', '"better_supabase"."collection_products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.storefronts', '"better_supabase"."storefronts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.catalog_channels', '"better_supabase"."catalog_channels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.catalog_channel_products', '"better_supabase"."catalog_channel_products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_translations', '"better_supabase"."product_translations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_variant_translations', '"better_supabase"."product_variant_translations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_media', '"better_supabase"."product_media"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.search_documents', '"better_supabase"."search_documents"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.metric_points', '"better_supabase"."metric_points"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.calendars', '"better_supabase"."calendars"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.calendar_events', '"better_supabase"."calendar_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.calendar_attendees', '"better_supabase"."calendar_attendees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.calendar_event_alarms', '"better_supabase"."calendar_event_alarms"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.calendar_working_hours', '"better_supabase"."calendar_working_hours"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_resources', '"better_supabase"."booking_resources"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_availability', '"better_supabase"."booking_availability"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_exceptions', '"better_supabase"."booking_exceptions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_services', '"better_supabase"."booking_services"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bookings', '"better_supabase"."bookings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.versions', '"better_supabase"."versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.trash_items', '"better_supabase"."trash_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.reactions', '"better_supabase"."reactions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.reaction_scores', '"better_supabase"."reaction_scores"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.custom_emoji', '"better_supabase"."custom_emoji"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.approval_requests', '"better_supabase"."approval_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.approval_decisions', '"better_supabase"."approval_decisions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.approval_policies', '"better_supabase"."approval_policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.access_requests', '"better_supabase"."access_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.documents', '"better_supabase"."documents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_updates', '"better_supabase"."document_updates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_snapshots', '"better_supabase"."document_snapshots"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_suggestions', '"better_supabase"."document_suggestions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ledger_accounts', '"better_supabase"."ledger_accounts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ledger_transactions', '"better_supabase"."ledger_transactions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ledger_entries', '"better_supabase"."ledger_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ledger_balances', '"better_supabase"."ledger_balances"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ledger_holds', '"better_supabase"."ledger_holds"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inventory_locations', '"better_supabase"."inventory_locations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_levels', '"better_supabase"."stock_levels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_reservations', '"better_supabase"."stock_reservations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_transfers', '"better_supabase"."stock_transfers"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_transfer_lines', '"better_supabase"."stock_transfer_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.purchase_orders', '"better_supabase"."purchase_orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.purchase_order_lines', '"better_supabase"."purchase_order_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_items', '"better_supabase"."stock_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_bins', '"better_supabase"."stock_bins"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_lots', '"better_supabase"."stock_lots"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_serials', '"better_supabase"."stock_serials"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_buckets', '"better_supabase"."stock_buckets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_allocations', '"better_supabase"."stock_allocations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.carts', '"better_supabase"."carts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.cart_lines', '"better_supabase"."cart_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shipping_rates', '"better_supabase"."shipping_rates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.orders', '"better_supabase"."orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_lines', '"better_supabase"."order_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_payments', '"better_supabase"."order_payments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.fulfillments', '"better_supabase"."fulfillments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.fulfillment_lines', '"better_supabase"."fulfillment_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_returns', '"better_supabase"."order_returns"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_return_lines', '"better_supabase"."order_return_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_refunds', '"better_supabase"."order_refunds"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.promotions', '"better_supabase"."promotions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.promotion_codes', '"better_supabase"."promotion_codes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.cart_promotion_codes', '"better_supabase"."cart_promotion_codes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.promotion_redemptions', '"better_supabase"."promotion_redemptions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.forms', '"better_supabase"."forms"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.form_versions', '"better_supabase"."form_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.form_submissions', '"better_supabase"."form_submissions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.form_answer_keys', '"better_supabase"."form_answer_keys"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.signature_requests', '"better_supabase"."signature_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.signatures', '"better_supabase"."signatures"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.time_entries', '"better_supabase"."time_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.timesheets', '"better_supabase"."timesheets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.service_principals', '"better_supabase"."service_principals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.templates', '"better_supabase"."templates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.template_applications', '"better_supabase"."template_applications"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.template_schedules', '"better_supabase"."template_schedules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.template_schedule_runs', '"better_supabase"."template_schedule_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deals', '"better_supabase"."deals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deal_contacts', '"better_supabase"."deal_contacts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deal_members', '"better_supabase"."deal_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deal_lines', '"better_supabase"."deal_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.job_openings', '"better_supabase"."job_openings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.applications', '"better_supabase"."applications"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.application_scorecards', '"better_supabase"."application_scorecards"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.interviews', '"better_supabase"."interviews"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_items', '"better_supabase"."work_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_item_checklist_items', '"better_supabase"."work_item_checklist_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_item_assignees', '"better_supabase"."work_item_assignees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_projects', '"better_supabase"."work_projects"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.iterations', '"better_supabase"."iterations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pipelines', '"better_supabase"."pipelines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pipeline_stages', '"better_supabase"."pipeline_stages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pipeline_transitions', '"better_supabase"."pipeline_transitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pipeline_stage_history', '"better_supabase"."pipeline_stage_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.companies', '"better_supabase"."companies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.people', '"better_supabase"."people"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.company_people', '"better_supabase"."company_people"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.person_inbox_contacts', '"better_supabase"."person_inbox_contacts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.engagements', '"better_supabase"."engagements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.engagement_subjects', '"better_supabase"."engagement_subjects"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quotes', '"better_supabase"."quotes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_lines', '"better_supabase"."quote_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_versions', '"better_supabase"."quote_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_version_lines', '"better_supabase"."quote_version_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_tax_lines', '"better_supabase"."quote_tax_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoices', '"better_supabase"."invoices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_lines', '"better_supabase"."invoice_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_charges', '"better_supabase"."invoice_charges"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sla_policies', '"better_supabase"."sla_policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sla_clocks', '"better_supabase"."sla_clocks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.targets', '"better_supabase"."targets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employees', '"better_supabase"."employees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employee_private_details', '"better_supabase"."employee_private_details"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employee_contracts', '"better_supabase"."employee_contracts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_items', '"better_supabase"."moderation_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_reports', '"better_supabase"."moderation_reports"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_actions', '"better_supabase"."moderation_actions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_bans', '"better_supabase"."moderation_bans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rules', '"better_supabase"."rules"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rule_versions', '"better_supabase"."rule_versions"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rule_evaluations', '"better_supabase"."rule_evaluations"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.asset_locations', '"better_supabase"."asset_locations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.assets', '"better_supabase"."assets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.asset_assignments', '"better_supabase"."asset_assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.score_models', '"better_supabase"."score_models"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.score_model_versions', '"better_supabase"."score_model_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scores', '"better_supabase"."scores"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.passes', '"better_supabase"."passes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pass_check_ins', '"better_supabase"."pass_check_ins"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.time_rates', '"better_supabase"."time_rates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.time_invoice_entries', '"better_supabase"."time_invoice_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.lease_agreements', '"better_supabase"."lease_agreements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.lease_charges', '"better_supabase"."lease_charges"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.expense_categories', '"better_supabase"."expense_categories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.expense_reports', '"better_supabase"."expense_reports"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.expense_lines', '"better_supabase"."expense_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.donation_funds', '"better_supabase"."donation_funds"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pledges', '"better_supabase"."pledges"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.donation_receipts', '"better_supabase"."donation_receipts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.donations', '"better_supabase"."donations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_orders', '"better_supabase"."work_orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.dispatch_routes', '"better_supabase"."dispatch_routes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.dispatch_route_stops', '"better_supabase"."dispatch_route_stops"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_order_parts', '"better_supabase"."work_order_parts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shipments', '"better_supabase"."shipments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shipment_packages', '"better_supabase"."shipment_packages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shipment_tracking_events', '"better_supabase"."shipment_tracking_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shipment_lines', '"better_supabase"."shipment_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.contracts', '"better_supabase"."contracts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.contract_obligations', '"better_supabase"."contract_obligations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.control_frameworks', '"better_supabase"."control_frameworks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.controls', '"better_supabase"."controls"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.control_evidence', '"better_supabase"."control_evidence"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.evidence_tasks', '"better_supabase"."evidence_tasks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.policies', '"better_supabase"."policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.policy_acknowledgements', '"better_supabase"."policy_acknowledgements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_components', '"better_supabase"."status_components"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_component_history', '"better_supabase"."status_component_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incidents', '"better_supabase"."incidents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_updates', '"better_supabase"."incident_updates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_impacts', '"better_supabase"."incident_impacts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_postmortems', '"better_supabase"."incident_postmortems"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_pages', '"better_supabase"."status_pages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.courses', '"better_supabase"."courses"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.course_modules', '"better_supabase"."course_modules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.course_lessons', '"better_supabase"."course_lessons"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.course_lesson_progress', '"better_supabase"."course_lesson_progress"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.course_certificates', '"better_supabase"."course_certificates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.conversations', '"better_supabase"."conversations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.conversation_members', '"better_supabase"."conversation_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.messages', '"better_supabase"."messages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.message_edits', '"better_supabase"."message_edits"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.thread_reads', '"better_supabase"."thread_reads"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.message_record_mentions', '"better_supabase"."message_record_mentions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.thread_summaries', '"better_supabase"."thread_summaries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.channels', '"better_supabase"."channels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.activity_entries', '"better_supabase"."activity_entries"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.mail_accounts', '"better_supabase"."mail_accounts"', 'tenant_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.mail_threads', '"better_supabase"."mail_threads"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.mail_messages', '"better_supabase"."mail_messages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.mail_tracked_links', '"better_supabase"."mail_tracked_links"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.mail_tracking_events', '"better_supabase"."mail_tracking_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.mail_thread_subjects', '"better_supabase"."mail_thread_subjects"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.segments', '"better_supabase"."segments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.segment_members', '"better_supabase"."segment_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.assignment_queues', '"better_supabase"."assignment_queues"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.assignment_queue_members', '"better_supabase"."assignment_queue_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.assignments', '"better_supabase"."assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.enrichments', '"better_supabase"."enrichments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.forecast_snapshots', '"better_supabase"."forecast_snapshots"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.forecast_snapshot_deals', '"better_supabase"."forecast_snapshot_deals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.field_changes', '"better_supabase"."field_changes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sequences', '"better_supabase"."sequences"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sequence_enrollments', '"better_supabase"."sequence_enrollments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.lead_score_checks', '"better_supabase"."lead_score_checks"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.post_boards', '"better_supabase"."post_boards"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.posts', '"better_supabase"."posts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.content_entries', '"better_supabase"."content_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.qualification_types', '"better_supabase"."qualification_types"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.qualification_requirements', '"better_supabase"."qualification_requirements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.qualifications', '"better_supabase"."qualifications"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.risk_matrices', '"better_supabase"."risk_matrices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.risks', '"better_supabase"."risks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.risk_assessments', '"better_supabase"."risk_assessments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shift_templates', '"better_supabase"."shift_templates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shifts', '"better_supabase"."shifts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shift_assignments', '"better_supabase"."shift_assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shift_swaps', '"better_supabase"."shift_swaps"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shift_availability', '"better_supabase"."shift_availability"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_settings', '"better_supabase"."accounting_settings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_accounts', '"better_supabase"."accounting_accounts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_account_roles', '"better_supabase"."accounting_account_roles"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_journals', '"better_supabase"."accounting_journals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_periods', '"better_supabase"."accounting_periods"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_entries', '"better_supabase"."accounting_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_entry_lines', '"better_supabase"."accounting_entry_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_dimensions', '"better_supabase"."accounting_dimensions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_dimension_values', '"better_supabase"."accounting_dimension_values"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_fx_rates', '"better_supabase"."accounting_fx_rates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_tax_codes', '"better_supabase"."accounting_tax_codes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_budgets', '"better_supabase"."accounting_budgets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_budget_lines', '"better_supabase"."accounting_budget_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.acknowledgement_assignments', '"better_supabase"."acknowledgement_assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.acknowledgements', '"better_supabase"."acknowledgements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.acknowledgement_notices', '"better_supabase"."acknowledgement_notices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.consent_purposes', '"better_supabase"."consent_purposes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.consents', '"better_supabase"."consents"', 'tenant_id', true, '{}'::text[], true)
  ) as t(subject, name, tbl, col, purge, omit, exported)
  ) as t(subject, name, tbl, col, purge, omit, exported)
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
      jsonb_strip_nulls(jsonb_build_object('donationId', v_row."id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id")));
    update "better_supabase"."donations" x set "status" = 'posted', "transaction_id" = v_tx, "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    perform "better_supabase"."accounting_post_source"('gift', v_row."id"::text);
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
      jsonb_build_object('donationId', v_row."id"));
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

CREATE OR REPLACE FUNCTION better_supabase.get_accounting_budget (
  budget_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'fiscalYear', x."fiscal_year", 'status', x."status", 'total', coalesce((select sum(bt."amount") from "better_supabase"."accounting_budget_lines" bt where bt."budget_id" = x."id"), 0)::text, 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'lines', coalesce((select jsonb_agg(jsonb_build_object('id', bx."id", 'accountId', bx."account_id", 'accountCode', ba."code", 'periodNumber', bx."period_number", 'dimensions', bx."dimensions", 'amount', bx."amount"::text) order by ba."code", bx."period_number", bx."id") from "better_supabase"."accounting_budget_lines" bx join "better_supabase"."accounting_accounts" ba on ba."id" = bx."account_id" where bx."budget_id" = x."id"), '[]'::jsonb)) from "better_supabase"."accounting_budgets" x where x."id" = get_accounting_budget.budget_id
$function$;

CREATE OR REPLACE FUNCTION better_supabase.issue_invoice (
  invoice   uuid,
  issued_on date,
  due_on    date  DEFAULT NULL::date,
  actor     jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."invoices";
  v_original "better_supabase"."invoices";
  v_seq bigint;
  v_identifier text;
  v_issued_on date := coalesce(issue_invoice.issued_on, current_date);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."invoices" x where x."id" = issue_invoice.invoice and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.write'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such invoice you can edit' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  if v_row."status" <> 'draft' then
    raise exception 'the invoice was already issued' using errcode = '55000', hint = 'INVOICE_NOT_DRAFT';
  end if;
  if not exists (select 1 from "better_supabase"."invoice_lines" x where x."parent_id" = v_row."id") then
    raise exception 'an invoice needs a line before it is issued' using errcode = '23514', hint = 'INVOICE_EMPTY';
  end if;
  if issue_invoice.due_on < v_issued_on then
    raise exception 'an invoice falls due on or after its issue date' using errcode = '22023', hint = 'INVOICE_DUE_INVALID';
  end if;
  if issue_invoice.actor is not null then
    if jsonb_typeof(issue_invoice.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(issue_invoice.actor ->> 'ip', '')::inet, nullif(issue_invoice.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(issue_invoice.actor::text, ''), true);
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_invoice_issue"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  if v_row."kind" = 'credit_note' then
    select * into v_original from "better_supabase"."invoices" x where x."id" = v_row."original_id" for update;
    if v_row."total" > v_original."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_original."id"), 0) - v_original."credited_total" then
      raise exception 'a credit note can''t exceed the invoice''s total less its earlier credits' using errcode = '23514', hint = 'INVOICE_CREDIT_TOO_LARGE';
    end if;
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_row."tenant_id"::text || ':credit_note', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from (select * from "better_supabase"."invoices" k where k."kind" = 'credit_note') x where x."tenant_id" = v_row."tenant_id";
  v_identifier := 'CN-' || v_seq::text;
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_row."tenant_id"::text || ':invoice', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from (select * from "better_supabase"."invoices" k where k."kind" = 'invoice') x where x."tenant_id" = v_row."tenant_id";
  v_identifier := 'INV-' || v_seq::text;
  end if;
  update "better_supabase"."invoices" x set "status" = 'issued', "number" = v_seq, "identifier" = v_identifier,
    "issued_on" = v_issued_on,
    "due_on" = coalesce(issue_invoice.due_on, v_issued_on + x."terms_days"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('invoice.issued', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'total', v_row."total"::text, 'currency', v_row."currency", 'dueOn', v_row."due_on"), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  if v_row."kind" = 'credit_note' then
    update "better_supabase"."invoices" x set "credited_total" = x."credited_total" + v_row."total", "updated_at" = now()
    where x."id" = v_original."id"
    returning * into v_original;
  update "better_supabase"."invoices" x set
    "paid_total" = coalesce(-(select sum(e."amount") from "better_supabase"."ledger_entries" e where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text)), 0),
    "updated_at" = now()
  where x."id" = v_original."id"
  returning * into v_original;
  update "better_supabase"."invoices" x set
    "status" = case
      when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then 'paid'
      when x."paid_total" > 0 or x."credited_total" > 0 then 'partially_paid'
      else 'issued' end,
    "paid_at" = case when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then coalesce(x."paid_at", now()) end
  where x."id" = v_original."id" and x."status" in ('issued', 'partially_paid', 'paid')
  returning * into v_original;
    perform "better_supabase".emit_event('invoice.credited', jsonb_build_object('organizationId', v_original."tenant_id", 'invoiceId', v_original."id", 'subjectType', 'invoice', 'subjectId', v_original."id"::text, 'identifier', v_original."identifier", 'creditNoteId', v_row."id", 'amount', v_row."total"::text), 'invoices/' || v_original."id"::text, (v_original."tenant_id"::text)::text, null, 'better-supabase/invoices');
    if v_original."status" = 'paid' then
      perform "better_supabase".emit_event('invoice.paid', jsonb_build_object('organizationId', v_original."tenant_id", 'invoiceId', v_original."id", 'subjectType', 'invoice', 'subjectId', v_original."id"::text, 'identifier', v_original."identifier", 'total', v_original."total"::text), 'invoices/' || v_original."id"::text, (v_original."tenant_id"::text)::text, null, 'better-supabase/invoices');
    end if;
  end if;
  perform "better_supabase"."accounting_post_source"('invoice', v_row."id"::text);
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_invoice_issue"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'deposit_amount', v_row."deposit_amount"::text, 'discount_amount', v_row."discount_amount"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_accounting_budgets (
  tenant      uuid,
  fiscal_year integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'fiscalYear', x."fiscal_year", 'status', x."status", 'total', coalesce((select sum(bt."amount") from "better_supabase"."accounting_budget_lines" bt where bt."budget_id" = x."id"), 0)::text, 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."fiscal_year" desc, x."name"), '[]'::jsonb)
  from "better_supabase"."accounting_budgets" x
  where x."tenant_id" = list_accounting_budgets.tenant
    and (list_accounting_budgets.fiscal_year is null or x."fiscal_year" = list_accounting_budgets.fiscal_year)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.move_stock (
  tenant         uuid,
  variant        uuid,
  location       uuid,
  quantity       numeric,
  reason         text,
  reference_type text    DEFAULT NULL::text,
  reference_id   text    DEFAULT NULL::text,
  note           text    DEFAULT NULL::text,
  detail         jsonb   DEFAULT NULL::jsonb
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_unit text;
  v_scale smallint;
  v_tracking text;
  v_expiry boolean;
  v_costing text;
  v_currency text;
  v_average numeric;
  v_factor numeric;
  v_bin uuid;
  v_lot uuid;
  v_serials text[];
  v_parts jsonb := '[]'::jsonb;
  v_part record;
  v_rest numeric;
  v_take numeric;
  v_lines jsonb := '[]'::jsonb;
  v_held numeric := 0;
  v_bucket numeric;
  v_strict boolean;
  v_id uuid;
  v_on_hand numeric;
  v_after numeric;
  v_point numeric;
  v_unbinned numeric;
  v_total numeric;
  v_value bigint := 0;
  v_balance bigint;
  v_value_account uuid;
  v_suffix text;
begin
  if move_stock.quantity is null or move_stock.quantity = 0 then
    raise exception 'the quantity must not be zero' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  if move_stock.reason is null or move_stock.reason not in ('adjustment', 'damage', 'loss', 'count', 'expired', 'scrap', 'receipt', 'sale', 'return', 'transfer_out', 'transfer_in') then
    raise exception 'unknown stock movement reason' using errcode = '22023', hint = 'INVENTORY_REASON_INVALID';
  end if;
  if move_stock.detail is not null and jsonb_typeof(move_stock.detail) <> 'object' then
    raise exception 'detail must be an object' using errcode = '22023', hint = 'INVENTORY_DETAIL_INVALID';
  end if;
  select x."unit", x."scale", x."tracking", x."tracks_expiry", x."costing", x."currency", x."average_cost"
  into v_unit, v_scale, v_tracking, v_expiry, v_costing, v_currency, v_average
  from "better_supabase"."stock_items" x where x."variant_id" = move_stock.variant for update;
  v_unit := coalesce(v_unit, 'item');
  v_scale := coalesce(v_scale, 0);
  v_tracking := coalesce(v_tracking, 'none');
  v_costing := coalesce(v_costing, 'none');
  v_factor := power(10::numeric, v_scale);
  if move_stock.quantity * v_factor <> trunc(move_stock.quantity * v_factor) then
    raise exception 'the quantity has more decimals than the variant''s scale' using errcode = '22023', hint = 'INVENTORY_QUANTITY_PRECISION';
  end if;
  v_strict := exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = move_stock.variant and cv."track_inventory" and not cv."allow_backorder");
  v_bin := nullif(move_stock.detail ->> 'binId', '')::uuid;
  v_lot := nullif(move_stock.detail ->> 'lotId', '')::uuid;
  if v_lot is null and jsonb_typeof(move_stock.detail -> 'lot') = 'object' then
    v_lot := "better_supabase"."stock_lot_for"(move_stock.tenant, move_stock.variant, move_stock.detail -> 'lot' ->> 'code',
      nullif(move_stock.detail -> 'lot' ->> 'expiresOn', '')::date);
  end if;
  if v_lot is not null and not exists (select 1 from "better_supabase"."stock_lots" x where x."id" = v_lot and x."variant_id" = move_stock.variant) then
    raise exception 'the lot isn''t a lot of this variant' using errcode = 'P0002', hint = 'INVENTORY_LOT_NOT_FOUND';
  end if;
  if v_bin is not null and not exists (select 1 from "better_supabase"."stock_bins" x where x."id" = v_bin and x."location_id" = move_stock.location) then
    raise exception 'the bin isn''t at this location' using errcode = 'P0002', hint = 'INVENTORY_BIN_NOT_FOUND';
  end if;
  if jsonb_typeof(move_stock.detail -> 'serials') = 'array' then
    v_serials := array(select jsonb_array_elements_text(move_stock.detail -> 'serials'));
  end if;
  if v_tracking = 'serial' then
    if v_serials is null or cardinality(v_serials) <> abs(move_stock.quantity)
      or (select count(distinct e) from unnest(v_serials) e where length(e) between 1 and 100) <> cardinality(v_serials) then
      raise exception 'a serial-tracked variant needs one distinct serial number per unit' using errcode = '22023', hint = 'INVENTORY_SERIALS_REQUIRED';
    end if;
  elsif coalesce(cardinality(v_serials), 0) > 0 then
    raise exception 'the variant doesn''t track serial numbers' using errcode = '22023', hint = 'INVENTORY_SERIALS_UNTRACKED';
  end if;

  if move_stock.quantity > 0 then
    if v_tracking = 'lot' and v_lot is null and move_stock.reason = 'receipt' then
      raise exception 'a lot-tracked variant receives stock into a lot' using errcode = '22023', hint = 'INVENTORY_LOT_REQUIRED';
    end if;
    if v_expiry and v_lot is not null and move_stock.reason = 'receipt'
      and (select x."expires_on" from "better_supabase"."stock_lots" x where x."id" = v_lot) is null then
      raise exception 'the variant tracks expiry, so its lots need an expiry date' using errcode = '22023', hint = 'INVENTORY_EXPIRY_REQUIRED';
    end if;
    if v_tracking = 'serial' then
      if exists (select 1 from "better_supabase"."stock_serials" x where x."variant_id" = move_stock.variant and x."serial" = any (v_serials) and x."status" = 'in_stock') then
        raise exception 'a serial number is already in stock' using errcode = '23505', hint = 'INVENTORY_SERIAL_IN_STOCK';
      end if;
      insert into "better_supabase"."stock_serials" as x ("tenant_id", "variant_id", "serial", "lot_id", "location_id", "bin_id", "status")
      select move_stock.tenant, move_stock.variant, e, v_lot, move_stock.location, v_bin, 'in_stock' from unnest(v_serials) e
      on conflict ("variant_id", "serial") do update
        set "lot_id" = coalesce(excluded."lot_id", x."lot_id"), "location_id" = excluded."location_id",
          "bin_id" = excluded."bin_id", "status" = 'in_stock', "updated_at" = now();
      select jsonb_agg(jsonb_build_object('bin', v_bin, 'lot', g.lot, 'quantity', g.n)) into v_parts
      from (select x."lot_id" as lot, count(*) as n from "better_supabase"."stock_serials" x
        where x."variant_id" = move_stock.variant and x."serial" = any (v_serials) group by x."lot_id") g;
    else
      v_parts := jsonb_build_array(jsonb_build_object('bin', v_bin, 'lot', v_lot, 'quantity', move_stock.quantity));
    end if;
  elsif v_tracking = 'serial' then
    if (select count(*) from "better_supabase"."stock_serials" x where x."variant_id" = move_stock.variant and x."serial" = any (v_serials)
        and x."status" = 'in_stock' and x."location_id" = move_stock.location and (v_bin is null or x."bin_id" = v_bin)) <> cardinality(v_serials) then
      raise exception 'a serial number isn''t in stock at this location' using errcode = 'P0002', hint = 'INVENTORY_SERIAL_NOT_IN_STOCK';
    end if;
    select jsonb_agg(jsonb_build_object('bin', g.bin, 'lot', g.lot, 'quantity', -g.n)) into v_parts
    from (select x."bin_id" as bin, x."lot_id" as lot, count(*) as n from "better_supabase"."stock_serials" x
      where x."variant_id" = move_stock.variant and x."serial" = any (v_serials) group by x."bin_id", x."lot_id") g;
    update "better_supabase"."stock_serials" x set "status" = case when move_stock.reason = 'scrap' then 'scrapped' else 'out' end,
      "location_id" = null, "bin_id" = null, "updated_at" = now()
    where x."variant_id" = move_stock.variant and x."serial" = any (v_serials);
  elsif v_bin is not null or v_lot is not null then
    if v_lot is not null and move_stock.reason in ('sale', 'transfer_out')
      and (select x."expires_on" from "better_supabase"."stock_lots" x where x."id" = v_lot) < current_date then
      raise exception 'the lot has expired' using errcode = '55000', hint = 'INVENTORY_LOT_EXPIRED';
    end if;
    v_parts := jsonb_build_array(jsonb_build_object('bin', v_bin, 'lot', v_lot, 'quantity', move_stock.quantity));
  else
    v_rest := -move_stock.quantity;
    for v_part in
      select y."bin_id" as bin, y."lot_id" as lot, y."on_hand" as on_hand
      from "better_supabase"."stock_buckets" y
      left join "better_supabase"."stock_bins" bn on bn."id" = y."bin_id"
      left join "better_supabase"."stock_lots" lo on lo."id" = y."lot_id"
      where y."variant_id" = move_stock.variant and y."location_id" = move_stock.location and y."on_hand" > 0
        and (move_stock.reason not in ('sale', 'transfer_out')
          or (not coalesce(bn."hold", false) and (lo."expires_on" is null or lo."expires_on" >= current_date)))
      order by coalesce(bn."hold", false), lo."expires_on" nulls last, lo."code" nulls last, bn."code"
      for update of y
    loop
      exit when v_rest <= 0;
      v_take := least(v_rest, v_part.on_hand);
      v_parts := v_parts || jsonb_build_array(jsonb_build_object('bin', v_part.bin, 'lot', v_part.lot, 'quantity', -v_take));
      v_rest := v_rest - v_take;
    end loop;
    if v_rest > 0 then
      v_parts := v_parts || jsonb_build_array(jsonb_build_object('bin', null, 'lot', null, 'quantity', -v_rest));
    end if;
  end if;

  for v_part in
    select nullif(p ->> 'bin', '')::uuid as bin, nullif(p ->> 'lot', '')::uuid as lot, (p ->> 'quantity')::numeric as quantity
    from jsonb_array_elements(v_parts) p
  loop
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('account', "better_supabase"."ledger_account_for"(move_stock.tenant, 'stock',
      'stock:' || move_stock.variant::text || ':' || move_stock.location::text
        || case when v_part.bin is null and v_part.lot is null then '' else ':' || coalesce(v_part.bin::text, '-') || ':' || coalesce(v_part.lot::text, '-') end,
      'Stock', v_unit, v_scale, 'product-variants', move_stock.variant::text, null, true, 'inventory.read', 'inventory',
      jsonb_strip_nulls(jsonb_build_object('variantId', move_stock.variant, 'locationId', move_stock.location, 'binId', v_part.bin, 'lotId', v_part.lot))),
      'amount', (v_part.quantity * v_factor)::bigint));
    if v_part.bin is not null or v_part.lot is not null then
      insert into "better_supabase"."stock_buckets" as x ("tenant_id", "variant_id", "location_id", "bin_id", "lot_id", "on_hand")
      values (move_stock.tenant, move_stock.variant, move_stock.location, v_part.bin, v_part.lot, v_part.quantity)
      on conflict ("variant_id", "location_id", "bin_id", "lot_id") do update
        set "on_hand" = x."on_hand" + excluded."on_hand", "updated_at" = now()
      returning x."on_hand" into v_bucket;
      if v_bucket < 0 and v_strict then
        raise exception 'not enough stock in this bin or lot' using errcode = '23514', hint = 'INVENTORY_INSUFFICIENT';
      end if;
      if v_part.bin is not null and (select x."hold" from "better_supabase"."stock_bins" x where x."id" = v_part.bin) then
        v_held := v_held + v_part.quantity;
      end if;
    end if;
  end loop;

  v_suffix := case when v_unit = 'item' and v_scale = 0 then '' else ':' || v_unit || ':' || v_scale::text end;
  v_lines := v_lines || jsonb_build_array(jsonb_build_object('account', "better_supabase"."ledger_account_for"(move_stock.tenant, 'stock_counter',
    case move_stock.reason when 'adjustment' then 'stock:adjustments' when 'damage' then 'stock:adjustments' when 'loss' then 'stock:adjustments' when 'count' then 'stock:adjustments' when 'expired' then 'stock:adjustments' when 'scrap' then 'stock:adjustments' when 'receipt' then 'stock:suppliers' when 'sale' then 'stock:customers' when 'return' then 'stock:customers' when 'transfer_out' then 'stock:transit' when 'transfer_in' then 'stock:transit' end || v_suffix, case move_stock.reason when 'adjustment' then 'Adjustments' when 'damage' then 'Adjustments' when 'loss' then 'Adjustments' when 'count' then 'Adjustments' when 'expired' then 'Adjustments' when 'scrap' then 'Adjustments' when 'receipt' then 'Suppliers' when 'sale' then 'Customers' when 'return' then 'Customers' when 'transfer_out' then 'In transit' when 'transfer_in' then 'In transit' end, v_unit, v_scale,
    null, null, null, true, 'inventory.read', 'inventory', null), 'amount', -(move_stock.quantity * v_factor)::bigint));

  if v_costing = 'average' and move_stock.reason not in ('transfer_in', 'transfer_out') then
    if move_stock.detail ? 'currency' and upper(move_stock.detail ->> 'currency') is distinct from v_currency then
      raise exception 'the unit cost is in another currency than the variant''s costing' using errcode = '22023', hint = 'INVENTORY_COST_CURRENCY_MISMATCH';
    end if;
    select coalesce(sum(x."on_hand"), 0) into v_total from "better_supabase"."stock_levels" x where x."variant_id" = move_stock.variant;
    v_value_account := "better_supabase"."ledger_account_for"(move_stock.tenant, 'stock_value', 'stock_value:' || move_stock.variant::text, 'Stock value',
      v_currency, 0::smallint, 'product-variants', move_stock.variant::text, null, true, 'inventory.read', 'inventory',
      jsonb_build_object('variantId', move_stock.variant));
    v_balance := coalesce((select y."balance" from "better_supabase"."ledger_balances" y where y."account_id" = v_value_account), 0);
    if move_stock.quantity > 0 then
      v_value := round(move_stock.quantity * coalesce(nullif(move_stock.detail ->> 'unitCost', '')::numeric, v_average, 0));
    elsif v_total + move_stock.quantity <= 0 then
      v_value := -v_balance;
    else
      v_value := -round(-move_stock.quantity * coalesce(v_average, 0));
    end if;
    if v_value <> 0 then
      v_lines := v_lines || jsonb_build_array(
        jsonb_build_object('account', v_value_account, 'amount', v_value),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(move_stock.tenant, 'stock_value_counter', case move_stock.reason when 'receipt' then 'stock_value:suppliers' when 'sale' then 'stock_value:cogs' when 'return' then 'stock_value:cogs' else 'stock_value:adjustments' end || ':' || v_currency,
          case move_stock.reason when 'receipt' then 'Stock purchases' when 'sale' then 'Cost of goods sold' when 'return' then 'Cost of goods sold' else 'Stock adjustments' end || ' ' || v_currency, v_currency, 0::smallint, null, null, null, true, 'inventory.read', 'inventory', null),
          'amount', -v_value));
    end if;
    update "better_supabase"."stock_items" x set "average_cost" = case when v_total + move_stock.quantity > 0
        then round((v_balance + v_value)::numeric / (v_total + move_stock.quantity), 6) else x."average_cost" end,
      "updated_at" = now()
    where x."variant_id" = move_stock.variant;
  end if;

  v_id := "better_supabase"."ledger_post"(move_stock.tenant, 'stock.' || move_stock.reason, v_lines,
    move_stock.reference_type, move_stock.reference_id, move_stock.note, null, null,
    jsonb_strip_nulls(jsonb_build_object('variantId', move_stock.variant, 'locationId', move_stock.location, 'reason', move_stock.reason,
      'quantity', move_stock.quantity::text, 'unit', nullif(v_unit, 'item'))));
  if v_value <> 0 then
    perform "better_supabase"."accounting_post_source"('stock_movement', v_id::text);
  end if;
  if v_serials is not null then
    update "better_supabase"."stock_serials" x set "movement_id" = v_id
    where x."variant_id" = move_stock.variant and x."serial" = any (v_serials);
  end if;
  insert into "better_supabase"."stock_levels" as x ("tenant_id", "variant_id", "location_id", "on_hand", "held")
  values (move_stock.tenant, move_stock.variant, move_stock.location, move_stock.quantity, greatest(v_held, 0))
  on conflict ("variant_id", "location_id") do update
    set "on_hand" = x."on_hand" + excluded."on_hand", "held" = greatest(x."held" + v_held, 0), "updated_at" = now()
  returning x."on_hand", x."available", x."reorder_point" into v_on_hand, v_after, v_point;
  if move_stock.quantity < 0 and v_strict then
    select v_on_hand - coalesce(sum(y."on_hand"), 0) into v_unbinned from "better_supabase"."stock_buckets" y
    where y."variant_id" = move_stock.variant and y."location_id" = move_stock.location;
    if v_on_hand < 0 or v_unbinned < 0 or (v_after < 0 and move_stock.reason in ('sale', 'transfer_out')) then
      raise exception 'not enough stock at this location' using errcode = '23514', hint = 'INVENTORY_INSUFFICIENT';
    end if;
  end if;
  if v_point is not null and (v_after - move_stock.quantity + v_held) > v_point and v_after <= v_point then
    perform "better_supabase".emit_event('stock.reorder_point_reached', jsonb_build_object('organizationId', move_stock.tenant, 'subjectType', 'product_variant', 'subjectId', move_stock.variant::text, 'variantId', move_stock.variant, 'locationId', move_stock.location, 'available', v_after::text, 'reorderPoint', v_point::text), 'stock-levels/' || move_stock.variant::text || '/' || move_stock.location::text, (move_stock.tenant)::text, null, 'better-supabase/inventory');
  end if;
  if move_stock.quantity > 0 then
    perform "better_supabase"."fill_backorders"(move_stock.tenant, move_stock.variant, move_stock.location);
  end if;
  return v_id;
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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'journalId', v_row."journal_id", 'number', v_row."number", 'fiscalYear', v_row."fiscal_year", 'entryDate', v_row."entry_date", 'periodId', v_row."period_id", 'status', v_row."status", 'reference', v_row."reference", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'reversesId', v_row."reverses_id", 'memo', v_row."memo", 'total', coalesce((select sum(et."debit") from "better_supabase"."accounting_entry_lines" et where et."entry_id" = v_row."id"), 0)::text, 'postedAt', v_row."posted_at", 'postedBy', v_row."posted_by", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'lines', coalesce((select jsonb_agg(jsonb_build_object('id', el."id", 'accountId', el."account_id", 'accountCode', ea."code", 'accountName', ea."name", 'debit', el."debit"::text, 'credit', el."credit"::text, 'currency', el."currency", 'amountCurrency', el."amount_currency"::text, 'fxRate', el."fx_rate"::text, 'taxCodeId', el."tax_code_id", 'partyId', el."party_id", 'dimensions', el."dimensions", 'description', el."description") order by el."position", el."id") from "better_supabase"."accounting_entry_lines" el join "better_supabase"."accounting_accounts" ea on ea."id" = el."account_id" where el."entry_id" = v_row."id"), '[]'::jsonb));
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
  v_row "better_supabase"."lease_agreements"%rowtype;
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
    select * from "better_supabase"."lease_agreements" x
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
          jsonb_build_object('leaseId', v_row."id", 'periodStart', v_start, 'periodEnd', v_end));
        insert into "better_supabase"."lease_charges" ("tenant_id", "lease_id", "period_start", "period_end", "amount", "currency", "transaction_id")
        values (v_row."tenant_id", v_row."id", v_start, v_end, v_row."rent", v_row."currency", v_tx)
        returning * into v_charge;
        perform "better_supabase"."accounting_post_source"('lease_rent', v_charge."id"::text);
        perform "better_supabase".emit_event('lease.charged', jsonb_build_object('organizationId', v_charge."tenant_id", 'id', v_charge."id", 'leaseId', v_charge."lease_id", 'periodStart', v_charge."period_start", 'periodEnd', v_charge."period_end", 'amount', v_charge."amount"::text, 'currency', v_charge."currency", 'transactionId', v_charge."transaction_id"), 'lease-charges/' || v_charge."id"::text, (v_charge."tenant_id")::text, null, 'better-supabase/leases');
  perform better_supabase.audit_event(
    event_type => 'lease.charged',
    category => 'billing',
    target_type => 'lease_charge',
    record_id => v_charge."id"::text,
    summary => 'posted rent from ' || v_charge."period_start"::text,
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

CREATE OR REPLACE FUNCTION better_supabase.record_invoice_payment (
  invoice   uuid,
  amount    bigint,
  currency  text,
  paid_at   timestamp with time zone,
  method    text,
  reference text,
  note      text                     DEFAULT NULL::text,
  actor     jsonb                    DEFAULT NULL::jsonb,
  reason    text                     DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."invoices";
  v_payment uuid;
  v_reference text;
  v_was text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."invoices" x where x."id" = record_invoice_payment.invoice and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.write'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such invoice you can edit' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  if v_row."kind" <> 'invoice' or v_row."status" not in ('issued', 'partially_paid', 'paid') then
    raise exception 'only an issued invoice takes payments' using errcode = '55000', hint = 'INVOICE_NOT_PAYABLE';
  end if;
  if coalesce(record_invoice_payment.amount, 0) = 0 then
    raise exception 'a payment has an amount' using errcode = '22023', hint = 'INVOICE_PAYMENT_INVALID';
  end if;
  if upper(record_invoice_payment.currency) is distinct from v_row."currency" then
    raise exception 'a payment must be in the invoice''s currency' using errcode = '22023', hint = 'INVOICE_CURRENCY_MISMATCH';
  end if;
  if record_invoice_payment.actor is not null then
    if jsonb_typeof(record_invoice_payment.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(record_invoice_payment.actor ->> 'ip', '')::inet, nullif(record_invoice_payment.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(record_invoice_payment.actor::text, ''), true);
  -- A recorded reference is a replay that adds nothing, so it skips the check.
  v_reference := nullif(trim(record_invoice_payment.reference), '');
  if v_reference is not null and exists (
    select 1 from "better_supabase"."ledger_transactions" y
    where y."tenant_id" = v_row."tenant_id" and y."idempotency_key" = 'invoice-payment:' || v_reference
  ) then
    return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'deposit_amount', v_row."deposit_amount"::text, 'discount_amount', v_row."discount_amount"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb));
  end if;
  if record_invoice_payment.amount < 0 and v_row."paid_total" + record_invoice_payment.amount < 0 then
    raise exception 'a refund can''t exceed what was paid' using errcode = '23514', hint = 'INVOICE_REFUND_TOO_LARGE';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_invoice_payment"(uuid, bigint)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::bigint)', v_hook::oid::regproc)
        using v_row."id", record_invoice_payment.amount;
    end if;
  end;
  v_was := v_row."status";
  perform set_config('better_supabase.transition_reason', coalesce(nullif(trim(record_invoice_payment.reason), ''), ''), true);
  v_payment := "better_supabase"."ledger_post"(v_row."tenant_id", case when record_invoice_payment.amount < 0 then 'invoice.refund' else 'invoice.payment' end,
    jsonb_build_array(
      jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'receivable',
      'invoice:' || v_row."id"::text, 'Receivable ' || coalesce(v_row."identifier", v_row."id"::text),
      v_row."currency"::text, 0::smallint, 'invoices', v_row."id"::text,
      null, true, 'invoices.read', 'invoices', null), 'amount', -record_invoice_payment.amount),
      jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'cash',
      'invoices:cash:' || v_row."currency", 'Invoice payments ' || v_row."currency",
      v_row."currency"::text, 0::smallint, null, null,
      null, true, 'invoices.read', 'invoices', null), 'amount', record_invoice_payment.amount)),
    'invoices', v_row."id"::text, null,
    case when v_reference is not null then 'invoice-payment:' || v_reference end, coalesce(record_invoice_payment.paid_at, now()),
    jsonb_strip_nulls(jsonb_build_object('invoiceId', v_row."id", 'method', record_invoice_payment.method, 'reference', v_reference, 'note', nullif(trim(record_invoice_payment.note), ''))));
  update "better_supabase"."invoices" x set
    "paid_total" = coalesce(-(select sum(e."amount") from "better_supabase"."ledger_entries" e where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text)), 0),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  update "better_supabase"."invoices" x set
    "status" = case
      when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then 'paid'
      when x."paid_total" > 0 or x."credited_total" > 0 then 'partially_paid'
      else 'issued' end,
    "paid_at" = case when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then coalesce(x."paid_at", now()) end
  where x."id" = v_row."id" and x."status" in ('issued', 'partially_paid', 'paid')
  returning * into v_row;
  perform "better_supabase"."accounting_post_source"('invoice_payment', v_payment::text);
  perform set_config('better_supabase.transition_reason', '', true);
  perform "better_supabase".emit_event('invoice.payment_recorded', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'paymentId', v_payment, 'amount', record_invoice_payment.amount::text, 'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  if v_row."status" = 'paid' and v_was <> 'paid' then
    perform "better_supabase".emit_event('invoice.paid', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'total', v_row."total"::text), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_invoice_payment"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using v_row."id", v_payment;
    end if;
  end;
  return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'deposit_amount', v_row."deposit_amount"::text, 'discount_amount', v_row."discount_amount"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb));
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
  v_row "better_supabase"."lease_agreements"%rowtype;
  v_key text;
  v_tx uuid;
begin
  select * into v_row from "better_supabase"."lease_agreements" x where x."id" = record_rent_payment.lease_id;
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
      jsonb_strip_nulls(jsonb_build_object('leaseId', v_row."id", 'reference', nullif(trim(record_rent_payment.reference), ''))));
    perform "better_supabase"."accounting_post_source"('lease_payment', v_tx::text);
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
    jsonb_strip_nulls(jsonb_build_object('reportId', v_row."id", 'reference', nullif(trim(reimburse_expense_report.reference), ''))));
  update "better_supabase"."expense_reports" x set "reimbursed_at" = coalesce(reimburse_expense_report.paid_at, now()), "reimbursement_transaction_id" = v_tx, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  perform "better_supabase"."accounting_post_source"('expense_reimbursement', v_row."id"::text);
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
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', (select count(*) from "better_supabase"."attachments" t where t."subject_type" = 'expense_line' and t."subject_id" = l."id"::text and t."uploaded_at" is not null and t."status" <> 'infected'), 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = v_row."id"));
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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'journalId', v_row."journal_id", 'number', v_row."number", 'fiscalYear', v_row."fiscal_year", 'entryDate', v_row."entry_date", 'periodId', v_row."period_id", 'status', v_row."status", 'reference', v_row."reference", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'reversesId', v_row."reverses_id", 'memo', v_row."memo", 'total', coalesce((select sum(et."debit") from "better_supabase"."accounting_entry_lines" et where et."entry_id" = v_row."id"), 0)::text, 'postedAt', v_row."posted_at", 'postedBy', v_row."posted_by", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'lines', coalesce((select jsonb_agg(jsonb_build_object('id', el."id", 'accountId', el."account_id", 'accountCode', ea."code", 'accountName', ea."name", 'debit', el."debit"::text, 'credit', el."credit"::text, 'currency', el."currency", 'amountCurrency', el."amount_currency"::text, 'fxRate', el."fx_rate"::text, 'taxCodeId', el."tax_code_id", 'partyId', el."party_id", 'dimensions', el."dimensions", 'description', el."description") order by el."position", el."id") from "better_supabase"."accounting_entry_lines" el join "better_supabase"."accounting_accounts" ea on ea."id" = el."account_id" where el."entry_id" = v_row."id"), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.reverse_invoice_payment (
  payment uuid,
  reason  text  DEFAULT NULL::text,
  actor   jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."invoices";
  v_meta jsonb;
  v_amount bigint;
  v_reversal uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select y."metadata" into v_meta from "better_supabase"."ledger_transactions" y
  where y."id" = reverse_invoice_payment.payment and y."reference_type" = 'invoices';
  select * into v_row from "better_supabase"."invoices" x where x."id" = (v_meta ->> 'invoiceId')::uuid and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.manage'), false)) for update;
  if v_meta is null or v_row."id" is null then
    raise exception 'no such payment on an invoice you can manage' using errcode = 'P0002', hint = 'INVOICE_PAYMENT_NOT_FOUND';
  end if;
  if coalesce(v_meta ->> 'method', '') = any ('{stripe,order}'::text[]) then
    raise exception 'a payment provider''s payment is refunded through the provider, not reversed' using errcode = '55000', hint = 'INVOICE_PAYMENT_PROVIDER';
  end if;
  if (v_meta ->> 'reversal')::boolean is true
    or exists (select 1 from "better_supabase"."ledger_transactions" y where y."reverses" = reverse_invoice_payment.payment) then
    raise exception 'this payment is a reversal or is already reversed' using errcode = '55000', hint = 'INVOICE_PAYMENT_REVERSED';
  end if;
  if reverse_invoice_payment.actor is not null then
    if jsonb_typeof(reverse_invoice_payment.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(reverse_invoice_payment.actor ->> 'ip', '')::inet, nullif(reverse_invoice_payment.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(reverse_invoice_payment.actor::text, ''), true);
  perform set_config('better_supabase.transition_reason', coalesce(nullif(trim(reverse_invoice_payment.reason), ''), ''), true);
  v_amount := coalesce(-(select sum(e."amount") from "better_supabase"."ledger_entries" e where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), 0);
  v_reversal := "better_supabase"."ledger_post"(v_row."tenant_id", 'invoice.payment_reversal',
    (select jsonb_agg(jsonb_build_object('account', e."account_id", 'amount', (-e."amount")::text) order by e."created_at", e."id")
      from "better_supabase"."ledger_entries" e where e."transaction_id" = reverse_invoice_payment.payment),
    'invoices', v_row."id"::text, null, null, null,
    (select y."metadata" from "better_supabase"."ledger_transactions" y where y."id" = reverse_invoice_payment.payment) || jsonb_strip_nulls(jsonb_build_object('reversal', true, 'reason', nullif(trim(reverse_invoice_payment.reason), ''))),
    reverse_invoice_payment.payment);
  v_amount := v_amount - coalesce(-(select sum(e."amount") from "better_supabase"."ledger_entries" e where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), 0);
  update "better_supabase"."invoices" x set
    "paid_total" = coalesce(-(select sum(e."amount") from "better_supabase"."ledger_entries" e where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text)), 0),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  update "better_supabase"."invoices" x set
    "status" = case
      when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then 'paid'
      when x."paid_total" > 0 or x."credited_total" > 0 then 'partially_paid'
      else 'issued' end,
    "paid_at" = case when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then coalesce(x."paid_at", now()) end
  where x."id" = v_row."id" and x."status" in ('issued', 'partially_paid', 'paid')
  returning * into v_row;
  perform "better_supabase"."accounting_reverse_source"(v_row."tenant_id", 'invoice_payment', reverse_invoice_payment.payment::text);
  perform set_config('better_supabase.transition_reason', '', true);
  perform "better_supabase".emit_event('invoice.payment_reversed', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'paymentId', reverse_invoice_payment.payment, 'reversalId', v_reversal, 'amount', v_amount::text, 'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text, 'reason', nullif(trim(reverse_invoice_payment.reason), '')), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  perform better_supabase.audit_event(
    event_type => 'invoice.payment_reversed',
    category => 'billing',
    target_type => 'invoice',
    record_id => v_row."id"::text,
    target_label => v_row."identifier",
    summary => 'invoice payment_reversed',
    tenant => (v_row."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'paymentId', reverse_invoice_payment.payment, 'reversalId', v_reversal, 'amount', v_amount::text, 'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text, 'reason', nullif(trim(reverse_invoice_payment.reason), ''))
  );
  return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'deposit_amount', v_row."deposit_amount"::text, 'discount_amount', v_row."discount_amount"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_accounting_budget (
  tenant      uuid,
  name        text,
  fiscal_year integer,
  status      text    DEFAULT NULL::text,
  lines       jsonb   DEFAULT NULL::jsonb,
  budget_id   uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."accounting_budgets"%rowtype;
  v_line record;
  v_account uuid;
  v_created boolean := save_accounting_budget.budget_id is null;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_accounting_budget.tenant, 'accounting.write'), false)) then
    raise exception 'not allowed to write budgets' using errcode = '42501', hint = 'ACCOUNTING_BUDGET_FORBIDDEN';
  end if;
  if length(trim(coalesce(save_accounting_budget.name, ''))) not between 1 and 200
    or coalesce(save_accounting_budget.fiscal_year, 0) not between 1900 and 9999 then
    raise exception 'a budget needs a name of 1 to 200 characters and a fiscal year' using errcode = '22023', hint = 'ACCOUNTING_BUDGET_INVALID';
  end if;
  if coalesce(save_accounting_budget.status, 'draft') not in ('draft', 'approved', 'archived') then
    raise exception 'status must be draft, approved or archived' using errcode = '22023', hint = 'ACCOUNTING_BUDGET_INVALID';
  end if;
  if save_accounting_budget.lines is not null and jsonb_typeof(save_accounting_budget.lines) <> 'array' then
    raise exception 'lines is an array' using errcode = '22023', hint = 'ACCOUNTING_BUDGET_INVALID';
  end if;
  if v_created then
    insert into "better_supabase"."accounting_budgets" ("tenant_id", "name", "fiscal_year", "status", "created_by")
    values (save_accounting_budget.tenant, trim(save_accounting_budget.name), save_accounting_budget.fiscal_year,
      coalesce(save_accounting_budget.status, 'draft'), auth.uid())
    returning * into v_row;
  else
    update "better_supabase"."accounting_budgets" y set "name" = trim(save_accounting_budget.name), "fiscal_year" = save_accounting_budget.fiscal_year,
      "status" = coalesce(save_accounting_budget.status, y."status"), "updated_at" = now()
    where y."id" = save_accounting_budget.budget_id and y."tenant_id" = save_accounting_budget.tenant
    returning * into v_row;
    if not found then
      raise exception 'budget not found' using errcode = 'P0002', hint = 'ACCOUNTING_BUDGET_NOT_FOUND';
    end if;
  end if;
  if save_accounting_budget.lines is not null then
    delete from "better_supabase"."accounting_budget_lines" y where y."budget_id" = v_row."id";
    for v_line in select q.value from jsonb_array_elements(save_accounting_budget.lines) q loop
      if jsonb_typeof(v_line.value) is distinct from 'object'
        or coalesce(v_line.value ->> 'amount', '') !~ '^-?[0-9]{1,18}$'
        or coalesce(v_line.value ->> 'periodNumber', '') !~ '^([1-9]|1[0-2])$'
        or (v_line.value ? 'dimensions' and jsonb_typeof(v_line.value -> 'dimensions') <> 'object') then
        raise exception 'every line has an account, a periodNumber from 1 to 12, an integer amount and dimensions as an object' using errcode = '22023', hint = 'ACCOUNTING_BUDGET_INVALID';
      end if;
      select y."id" into v_account from "better_supabase"."accounting_accounts" y
      where y."tenant_id" = v_row."tenant_id"
        and (y."id"::text = v_line.value ->> 'accountId' or y."code" = v_line.value ->> 'accountCode');
      if v_account is null then
        raise exception 'a budget line''s account doesn''t exist here' using errcode = 'P0002', hint = 'ACCOUNTING_ACCOUNT_NOT_FOUND';
      end if;
      insert into "better_supabase"."accounting_budget_lines" ("tenant_id", "budget_id", "account_id", "period_number", "dimensions", "amount")
      values (v_row."tenant_id", v_row."id", v_account, (v_line.value ->> 'periodNumber')::smallint,
        coalesce(v_line.value -> 'dimensions', '{}'::jsonb), (v_line.value ->> 'amount')::bigint)
      on conflict ("budget_id", "account_id", "period_number", "dimensions")
      do update set "amount" = "better_supabase"."accounting_budget_lines"."amount" + excluded."amount";
      v_account := null;
    end loop;
  end if;
  if v_created then
    perform "better_supabase".emit_event('accounting_budget.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'name', v_row."name", 'fiscalYear', v_row."fiscal_year", 'status', v_row."status"), 'accounting-budgets/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/accounting');
  perform better_supabase.audit_event(
    event_type => 'accounting_budget.created',
    category => 'data',
    target_type => 'accounting_budget',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'created budget ' || v_row."name",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'name', v_row."name", 'fiscalYear', v_row."fiscal_year", 'status', v_row."status")
  );
  else
    perform "better_supabase".emit_event('accounting_budget.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'name', v_row."name", 'fiscalYear', v_row."fiscal_year", 'status', v_row."status"), 'accounting-budgets/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/accounting');
  perform better_supabase.audit_event(
    event_type => 'accounting_budget.updated',
    category => 'data',
    target_type => 'accounting_budget',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'updated budget ' || v_row."name",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'name', v_row."name", 'fiscalYear', v_row."fiscal_year", 'status', v_row."status")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'fiscalYear', v_row."fiscal_year", 'status', v_row."status", 'total', coalesce((select sum(bt."amount") from "better_supabase"."accounting_budget_lines" bt where bt."budget_id" = v_row."id"), 0)::text, 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'lines', coalesce((select jsonb_agg(jsonb_build_object('id', bx."id", 'accountId', bx."account_id", 'accountCode', ba."code", 'periodNumber', bx."period_number", 'dimensions', bx."dimensions", 'amount', bx."amount"::text) order by ba."code", bx."period_number", bx."id") from "better_supabase"."accounting_budget_lines" bx join "better_supabase"."accounting_accounts" ba on ba."id" = bx."account_id" where bx."budget_id" = v_row."id"), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_accounting_account_role (
  tenant     uuid,
  role       text,
  account_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', set_accounting_account_role.tenant, 'accounting.manage'), false)) then
    raise exception 'not allowed to manage the chart of accounts' using errcode = '42501', hint = 'ACCOUNTING_ACCOUNT_FORBIDDEN';
  end if;
  if set_accounting_account_role.role is null or set_accounting_account_role.role not in ('receivable', 'payable', 'bank', 'revenue', 'cogs', 'inventory', 'tax_payable', 'tax_receivable', 'retained_earnings', 'fx_gain', 'fx_loss', 'fixed_asset', 'accumulated_depreciation', 'depreciation_expense', 'expense', 'suspense') then
    raise exception 'unknown account role' using errcode = '22023', hint = 'ACCOUNTING_ACCOUNT_ROLE_INVALID';
  end if;
  if set_accounting_account_role.account_id is null then
    delete from "better_supabase"."accounting_account_roles" y where y."tenant_id" = set_accounting_account_role.tenant and y."role" = set_accounting_account_role.role;
  else
    if not exists (
      select 1 from "better_supabase"."accounting_accounts" y where y."id" = set_accounting_account_role.account_id
        and y."tenant_id" = set_accounting_account_role.tenant and y."archived_at" is null
    ) then
      raise exception 'account not found' using errcode = 'P0002', hint = 'ACCOUNTING_ACCOUNT_NOT_FOUND';
    end if;
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    values (set_accounting_account_role.tenant, set_accounting_account_role.role, set_accounting_account_role.account_id)
    on conflict ("tenant_id", "role") do update set "account_id" = excluded."account_id", "updated_at" = now();
  end if;
  return coalesce((
    select jsonb_object_agg(y."role", y."account_id") from "better_supabase"."accounting_account_roles" y where y."tenant_id" = set_accounting_account_role.tenant
  ), '{}'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.setup_accounting (
  tenant                  uuid,
  functional_currency     text    DEFAULT NULL::text,
  fiscal_year_start_month integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."accounting_settings"%rowtype;
  v_currency text := upper(coalesce(nullif(trim(setup_accounting.functional_currency), ''), 'EUR'));
  v_month integer := coalesce(setup_accounting.fiscal_year_start_month, 1);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', setup_accounting.tenant, 'accounting.manage'), false)) then
    raise exception 'not allowed to manage accounting' using errcode = '42501', hint = 'ACCOUNTING_SETTING_FORBIDDEN';
  end if;
  if v_currency !~ '^[A-Z]{3}$' then
    raise exception 'the functional currency must be an ISO 4217 code such as EUR' using errcode = '22023', hint = 'ACCOUNTING_SETTING_INVALID';
  end if;
  if v_month < 1 or v_month > 12 then
    raise exception 'the fiscal year starts in a month from 1 to 12' using errcode = '22023', hint = 'ACCOUNTING_SETTING_INVALID';
  end if;
  select * into v_row from "better_supabase"."accounting_settings" y where y."tenant_id" = setup_accounting.tenant for update;
  if found then
    if setup_accounting.functional_currency is not null and v_row."functional_currency" <> v_currency
      and exists (select 1 from "better_supabase"."accounting_entries" y where y."tenant_id" = setup_accounting.tenant and y."status" <> 'draft') then
      raise exception 'the functional currency can''t change once entries are posted' using errcode = '22023', hint = 'ACCOUNTING_SETTING_INVALID';
    end if;
    if setup_accounting.fiscal_year_start_month is not null and v_row."fiscal_year_start_month" <> v_month
      and exists (select 1 from "better_supabase"."accounting_periods" y where y."tenant_id" = setup_accounting.tenant) then
      raise exception 'the fiscal year start can''t change once periods exist' using errcode = '22023', hint = 'ACCOUNTING_SETTING_INVALID';
    end if;
    update "better_supabase"."accounting_settings" y set
      "functional_currency" = case when setup_accounting.functional_currency is null then y."functional_currency" else v_currency end,
      "fiscal_year_start_month" = case when setup_accounting.fiscal_year_start_month is null then y."fiscal_year_start_month" else v_month end,
      "updated_at" = now()
    where y."tenant_id" = setup_accounting.tenant
    returning * into v_row;
  else
    insert into "better_supabase"."accounting_settings" ("tenant_id", "functional_currency", "fiscal_year_start_month")
    values (setup_accounting.tenant, v_currency, v_month)
    returning * into v_row;
  end if;
  if not exists (select 1 from "better_supabase"."accounting_accounts" y where y."tenant_id" = setup_accounting.tenant) then
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable")
    values
      (setup_accounting.tenant, '1000', 'Bank', 'asset', 'bank', true),
      (setup_accounting.tenant, '1100', 'Cash', 'asset', 'cash', false),
      (setup_accounting.tenant, '1200', 'Accounts receivable', 'asset', 'receivable', true),
      (setup_accounting.tenant, '1300', 'Inventory', 'asset', 'inventory', false),
      (setup_accounting.tenant, '1400', 'Tax receivable', 'asset', 'current_asset', false),
      (setup_accounting.tenant, '1500', 'Fixed assets', 'asset', 'fixed_asset', false),
      (setup_accounting.tenant, '1510', 'Accumulated depreciation', 'asset', 'fixed_asset', false),
      (setup_accounting.tenant, '1900', 'Suspense', 'asset', 'current_asset', false),
      (setup_accounting.tenant, '2000', 'Accounts payable', 'liability', 'payable', true),
      (setup_accounting.tenant, '2100', 'Tax payable', 'liability', 'tax', false),
      (setup_accounting.tenant, '3000', 'Share capital', 'equity', 'equity', false),
      (setup_accounting.tenant, '3900', 'Retained earnings', 'equity', 'equity', false),
      (setup_accounting.tenant, '4000', 'Revenue', 'income', 'revenue', false),
      (setup_accounting.tenant, '4900', 'Exchange gains', 'income', 'other_income', false),
      (setup_accounting.tenant, '5000', 'Cost of goods sold', 'expense', 'cogs', false),
      (setup_accounting.tenant, '6000', 'Operating expenses', 'expense', 'operating_expense', false),
      (setup_accounting.tenant, '6800', 'Depreciation', 'expense', 'operating_expense', false),
      (setup_accounting.tenant, '6900', 'Exchange losses', 'expense', 'other_expense', false);
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    select setup_accounting.tenant, c.role, y."id"
    from (values ('bank', '1000'), ('receivable', '1200'), ('inventory', '1300'), ('tax_receivable', '1400'), ('fixed_asset', '1500'), ('accumulated_depreciation', '1510'), ('suspense', '1900'), ('payable', '2000'), ('tax_payable', '2100'), ('retained_earnings', '3900'), ('revenue', '4000'), ('fx_gain', '4900'), ('cogs', '5000'), ('expense', '6000'), ('depreciation_expense', '6800'), ('fx_loss', '6900')) c (role, code)
    join "better_supabase"."accounting_accounts" y on y."tenant_id" = setup_accounting.tenant and y."code" = c.code
    on conflict ("tenant_id", "role") do nothing;
  end if;
  if not exists (select 1 from "better_supabase"."accounting_journals" y where y."tenant_id" = setup_accounting.tenant) then
    insert into "better_supabase"."accounting_journals" ("tenant_id", "code", "name", "type", "default_account_id")
    select setup_accounting.tenant, c.code, c.name, c.type,
      (select y."id" from "better_supabase"."accounting_accounts" y where y."tenant_id" = setup_accounting.tenant and y."code" = c.account)
    from (values ('SAL', 'Sales', 'sales', null::text), ('PUR', 'Purchases', 'purchase', null::text), ('BNK', 'Bank', 'bank', '1000'), ('CSH', 'Cash', 'cash', '1100'), ('GEN', 'General', 'general', null::text)) c (code, name, type, account);
  end if;
  return jsonb_build_object('organizationId', v_row."tenant_id", 'functionalCurrency', v_row."functional_currency", 'fiscalYearStartMonth', v_row."fiscal_year_start_month", 'lockDate', v_row."lock_date", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.void_invoice (
  invoice uuid,
  reason  text,
  actor   jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."invoices";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."invoices" x where x."id" = void_invoice.invoice and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.manage'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such invoice you can manage' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  if v_row."status" not in ('draft', 'issued') or v_row."paid_total" <> 0 or v_row."credited_total" <> 0 then
    raise exception 'an invoice with payments or credits is credited, not voided' using errcode = '55000', hint = 'INVOICE_NOT_VOIDABLE';
  end if;
  if void_invoice.actor is not null then
    if jsonb_typeof(void_invoice.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(void_invoice.actor ->> 'ip', '')::inet, nullif(void_invoice.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(void_invoice.actor::text, ''), true);
  perform set_config('better_supabase.transition_reason', coalesce(nullif(trim(void_invoice.reason), ''), ''), true);
  update "better_supabase"."invoices" x set "status" = 'void', "voided_at" = now(),
    "void_reason" = nullif(trim(void_invoice.reason), ''), "updated_at" = now()
  where x."id" = v_row."id" returning * into v_row;
  perform "better_supabase"."accounting_reverse_source"(v_row."tenant_id", 'invoice', v_row."id"::text);
  perform set_config('better_supabase.transition_reason', '', true);
  perform "better_supabase".emit_event('invoice.voided', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'reason', v_row."void_reason"), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  perform better_supabase.audit_event(
    event_type => 'invoice.voided',
    category => 'billing',
    target_type => 'invoice',
    record_id => v_row."id"::text,
    target_label => v_row."identifier",
    summary => 'invoice voided',
    tenant => (v_row."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'reason', v_row."void_reason")
  );
  return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'deposit_amount', v_row."deposit_amount"::text, 'discount_amount', v_row."discount_amount"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb));
end;
$function$;

ALTER TABLE "better_supabase"."accounting_account_roles"
  ADD CONSTRAINT "accounting_account_roles_role_check"
    CHECK
    ((role = ANY (ARRAY['receivable'::text, 'payable'::text, 'bank'::text, 'revenue'::text, 'cogs'::text, 'inventory'::text, 'tax_payable'::text, 'tax_receivable'::text,
    'retained_earnings'::text,
    'fx_gain'::text, 'fx_loss'::text, 'fixed_asset'::text, 'accumulated_depreciation'::text, 'depreciation_expense'::text, 'expense'::text, 'suspense'::text])));

ALTER TABLE "better_supabase"."accounting_budget_lines"
  ADD CONSTRAINT "accounting_budget_lines_account_id_fkey" FOREIGN KEY (account_id) REFERENCES better_supabase.accounting_accounts(id) ON DELETE RESTRICT;

ALTER TABLE "better_supabase"."accounting_budget_lines"
  ADD CONSTRAINT "accounting_budget_lines_budget_id_fkey" FOREIGN KEY (budget_id) REFERENCES better_supabase.accounting_budgets(id) ON DELETE CASCADE;

CREATE INDEX accounting_budget_lines_account_idx ON better_supabase.accounting_budget_lines USING btree (account_id);

CREATE POLICY "accounting_budget_lines_read" ON "better_supabase"."accounting_budget_lines"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('accounting.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."accounting_budget_lines"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."accounting_budget_lines"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."accounting_budget_lines"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('accounting.read'::text) AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."accounting_budget_lines"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "accounting_budgets_read" ON "better_supabase"."accounting_budgets"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('accounting.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."accounting_budgets"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."accounting_budgets"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."accounting_budgets"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('accounting.read'::text) AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."accounting_budgets"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

REVOKE ALL ON FUNCTION "api"."accounting_budget_vs_actual"(uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."accounting_budget_vs_actual"(uuid, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."accounting_tax_report"(uuid, date, date) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."accounting_tax_report"(uuid, date, date) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_accounting_budget"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_accounting_budget"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_accounting_budgets"(uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_accounting_budgets"(uuid, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."post_accounting_source"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."post_accounting_source"(text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_accounting_budget"(uuid, text, integer, text, jsonb, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_accounting_budget"(uuid, text, integer, text, jsonb, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."accounting_budget_vs_actual"(uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."accounting_budget_vs_actual"(uuid, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."accounting_expense_reimbursement_lines"(text) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."accounting_expense_report_lines"(text) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."accounting_gift_lines"(text) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."accounting_invoice_lines"(text) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."accounting_invoice_payment_lines"(text) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."accounting_lease_payment_lines"(text) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."accounting_lease_rent_lines"(text) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."accounting_post_source"(text, text) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."accounting_reverse"(uuid, date) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."accounting_reverse_source"(uuid, text, text, date) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."accounting_stock_movement_lines"(text) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."accounting_tax_report"(uuid, date, date) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."accounting_tax_report"(uuid, date, date) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_accounting_budget"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_accounting_budget"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_accounting_budgets"(uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_accounting_budgets"(uuid, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."post_accounting_source"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."post_accounting_source"(text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_accounting_budget"(uuid, text, integer, text, jsonb, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_accounting_budget"(uuid, text, integer, text, jsonb, uuid) TO "authenticated", "service_role";

GRANT SELECT ON TABLE "better_supabase"."accounting_budget_lines" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."accounting_budget_lines" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."accounting_budgets" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."accounting_budgets" TO "service_role";
