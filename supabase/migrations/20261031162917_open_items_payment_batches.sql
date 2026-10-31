SET local check_function_bodies = off;

ALTER TABLE "better_supabase"."bank_matches"
  DROP CONSTRAINT "bank_matches_target_type_check";

CREATE TABLE "better_supabase"."invoice_allocations" (
  "id"                  uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"           uuid                     NOT NULL,
  "reference"           text                     NOT NULL,
  "party_id"            text                     NOT NULL,
  "invoice_id"          uuid                     NOT NULL,
  "source"              text                     NOT NULL DEFAULT 'payment'::text,
  "amount"              bigint                   NOT NULL,
  "discount"            bigint                   NOT NULL DEFAULT 0,
  "payment_id"          uuid,
  "discount_payment_id" uuid,
  "allocated_on"        date                     NOT NULL,
  "unallocated_at"      timestamp with time zone,
  "created_by"          uuid,
  "created_at"          timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "invoice_allocations_amount_check" CHECK ((amount > 0)),
  CONSTRAINT "invoice_allocations_discount_check" CHECK ((discount >= 0)),
  CONSTRAINT "invoice_allocations_pkey" PRIMARY KEY (id),
  CONSTRAINT "invoice_allocations_reference_check" CHECK (((length(reference) >= 1) AND (length(reference) <= 200))),
  CONSTRAINT "invoice_allocations_source_check" CHECK ((source = ANY (ARRAY['payment'::text, 'credit'::text]))),
  CONSTRAINT "invoice_allocations_tenant_id_reference_invoice_id_key" UNIQUE (tenant_id, reference, invoice_id)
);

ALTER TABLE "better_supabase"."invoice_allocations"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."invoice_approval_levels" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"       uuid                     NOT NULL,
  "legal_entity_id" uuid,
  "level"           integer                  NOT NULL,
  "min_amount"      bigint                   NOT NULL,
  "currency"        text,
  "approver_id"     uuid                     NOT NULL,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "invoice_approval_levels_currency_check" CHECK (((currency IS NULL) OR (currency ~ '^[A-Z]{3}$'::text))),
  CONSTRAINT "invoice_approval_levels_level_check" CHECK ((level >= 1)),
  CONSTRAINT "invoice_approval_levels_min_amount_check" CHECK ((min_amount >= 0)),
  CONSTRAINT "invoice_approval_levels_pkey" PRIMARY KEY (id)
);

ALTER TABLE "better_supabase"."invoice_approval_levels"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."invoice_approvals" (
  "id"          uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"   uuid                     NOT NULL,
  "invoice_id"  uuid                     NOT NULL,
  "level"       integer                  NOT NULL,
  "approver_id" uuid                     NOT NULL,
  "comment"     text,
  "decided_at"  timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "invoice_approvals_comment_check" CHECK (((comment IS NULL) OR (length(comment) <= 2000))),
  CONSTRAINT "invoice_approvals_invoice_id_level_key" UNIQUE (invoice_id, level),
  CONSTRAINT "invoice_approvals_level_check" CHECK ((level >= 1)),
  CONSTRAINT "invoice_approvals_pkey" PRIMARY KEY (id)
);

ALTER TABLE "better_supabase"."invoice_approvals"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."payment_batch_items" (
  "id"            uuid         NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"     uuid         NOT NULL,
  "batch_id"      uuid         NOT NULL,
  "invoice_id"    uuid         NOT NULL,
  "party_id"      text         NOT NULL,
  "creditor_name" text         NOT NULL,
  "creditor_iban" text         NOT NULL,
  "creditor_bic"  text,
  "amount"        bigint       NOT NULL,
  "discount"      bigint       NOT NULL DEFAULT 0,
  "currency"      character(3) NOT NULL,
  "end_to_end_id" text         NOT NULL,
  "remittance"    text,
  "status"        text         NOT NULL DEFAULT 'open'::text,
  CONSTRAINT "payment_batch_items_amount_check" CHECK ((amount > 0)),
  CONSTRAINT "payment_batch_items_creditor_bic_check" CHECK (((creditor_bic IS NULL) OR (creditor_bic ~ '^[A-Z]{6}[A-Z0-9]{2}([A-Z0-9]{3})?$'::text))),
  CONSTRAINT "payment_batch_items_creditor_iban_check" CHECK ((creditor_iban ~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$'::text)),
  CONSTRAINT "payment_batch_items_creditor_name_check" CHECK (((length(creditor_name) >= 1) AND (length(creditor_name) <= 140))),
  CONSTRAINT "payment_batch_items_currency_check" CHECK ((currency ~ '^[A-Z]{3}$'::text)),
  CONSTRAINT "payment_batch_items_discount_check" CHECK ((discount >= 0)),
  CONSTRAINT "payment_batch_items_end_to_end_id_check" CHECK (((length(end_to_end_id) >= 1) AND (length(end_to_end_id) <= 35))),
  CONSTRAINT "payment_batch_items_pkey" PRIMARY KEY (id),
  CONSTRAINT "payment_batch_items_remittance_check" CHECK (((remittance IS NULL) OR (length(remittance) <= 140))),
  CONSTRAINT "payment_batch_items_status_check" CHECK ((status = ANY (ARRAY['open'::text, 'posted'::text, 'paid'::text, 'cancelled'::text])))
);

ALTER TABLE "better_supabase"."payment_batch_items"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."payment_batches" (
  "id"                  uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"           uuid                     NOT NULL,
  "bank_account_id"     uuid                     NOT NULL,
  "reference"           text                     NOT NULL,
  "message_id"          text                     NOT NULL,
  "currency"            character(3)             NOT NULL,
  "due_by"              date                     NOT NULL,
  "execution_on"        date                     NOT NULL,
  "total"               bigint                   NOT NULL,
  "item_count"          integer                  NOT NULL,
  "status"              text                     NOT NULL DEFAULT 'draft'::text,
  "bank_transaction_id" uuid,
  "created_by"          uuid,
  "created_at"          timestamp with time zone NOT NULL DEFAULT now(),
  "posted_at"           timestamp with time zone,
  "reconciled_at"       timestamp with time zone,
  CONSTRAINT "payment_batches_currency_check" CHECK ((currency ~ '^[A-Z]{3}$'::text)),
  CONSTRAINT "payment_batches_item_count_check" CHECK ((item_count > 0)),
  CONSTRAINT "payment_batches_message_id_check" CHECK (((length(message_id) >= 1) AND (length(message_id) <= 35))),
  CONSTRAINT "payment_batches_pkey" PRIMARY KEY (id),
  CONSTRAINT "payment_batches_reference_check" CHECK (((length(reference) >= 1) AND (length(reference) <= 200))),
  CONSTRAINT "payment_batches_status_check" CHECK ((status = ANY (ARRAY['draft'::text, 'posted'::text, 'reconciled'::text, 'cancelled'::text]))),
  CONSTRAINT "payment_batches_tenant_id_id_key" UNIQUE (tenant_id, id),
  CONSTRAINT "payment_batches_tenant_id_reference_key" UNIQUE (tenant_id, reference),
  CONSTRAINT "payment_batches_total_check" CHECK ((total > 0))
);

ALTER TABLE "better_supabase"."payment_batches"
  ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION api.allocate_payment (
  tenant      uuid,
  payment     jsonb,
  allocations jsonb,
  actor       jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."allocate_payment"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.approve_purchase_invoice (
  invoice uuid,
  comment text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."approve_purchase_invoice"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.cancel_payment_batch (
  batch_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."cancel_payment_batch"($1) $function$;

CREATE OR REPLACE FUNCTION api.create_payment_batch (
  tenant uuid,
  input  jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."create_payment_batch"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.get_payment_batch (
  batch_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_payment_batch"($1) $function$;

CREATE OR REPLACE FUNCTION api.import_open_item (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."import_open_item"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.invoice_approval_state (
  invoice uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."invoice_approval_state"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_invoice_allocations (
  tenant     uuid,
  reference  text DEFAULT NULL::text,
  invoice_id uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_invoice_allocations"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.list_invoice_approval_levels (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_invoice_approval_levels"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_payment_batches (
  tenant    uuid,
  status    text    DEFAULT NULL::text,
  page_size integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_payment_batches"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.open_item_ageing (
  tenant uuid,
  side   text DEFAULT NULL::text,
  as_of  date DEFAULT NULL::date
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."open_item_ageing"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.open_items_for_party (
  tenant   uuid,
  party_id text DEFAULT NULL::text,
  as_of    date DEFAULT NULL::date,
  side     text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."open_items_for_party"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.post_payment_batch (
  batch_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."post_payment_batch"($1) $function$;

CREATE OR REPLACE FUNCTION api.purchase_invoice_approval_status (
  invoice uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."purchase_invoice_approval_status"($1) $function$;

CREATE OR REPLACE FUNCTION api.set_invoice_approval_levels (
  tenant          uuid,
  levels          jsonb,
  legal_entity_id uuid  DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_invoice_approval_levels"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.unallocate_payment (
  tenant    uuid,
  reference text,
  actor     jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."unallocate_payment"($1, $2, $3) $function$;

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
    'memo', 'Early payment discount on ' || coalesce(inv."identifier", inv."title"),
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
    or accounting_post_source.source_type not in ('stock_movement', 'invoice', 'invoice_payment', 'invoice_charge', 'invoice_discount', 'invoice_write_off', 'invoice_party_payment', 'asset_depreciation', 'asset_disposal', 'lease_rent', 'lease_payment', 'expense_report', 'expense_reimbursement', 'gift', 'production_order', 'bank_transaction') then
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

CREATE OR REPLACE FUNCTION better_supabase.allocate_payment (
  tenant      uuid,
  payment     jsonb,
  allocations jsonb,
  actor       jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid := allocate_payment.tenant;
  v_party text := nullif(trim(allocate_payment.payment ->> 'partyId'), '');
  v_side text := coalesce(allocate_payment.payment ->> 'side', 'customer');
  v_supplier boolean;
  v_use_credit boolean := coalesce(allocate_payment.payment ->> 'source', 'payment') = 'credit';
  v_currency text := upper(allocate_payment.payment ->> 'currency');
  v_reference text := nullif(trim(allocate_payment.payment ->> 'reference'), '');
  v_received date;
  v_amount bigint;
  v_allocations jsonb := coalesce(allocate_payment.allocations, '[]'::jsonb);
  v_sum bigint := 0;
  v_remainder bigint := 0;
  v_alloc record;
  v_row "better_supabase"."invoices";
  v_balance bigint;
  v_early bigint;
  v_due date;
  v_discount bigint;
  v_ref text;
  v_pay uuid;
  v_disc uuid;
  v_account uuid;
  v_credit uuid;
  v_was text;
  v_method text := coalesce(nullif(trim(allocate_payment.payment ->> 'method'), ''), 'allocation');
  v_note text := nullif(trim(allocate_payment.payment ->> 'note'), '');
  v_credited bigint := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', allocate_payment.tenant, 'invoices.write'), false)) then
    raise exception 'not allowed to record payments in this organization' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  if jsonb_typeof(allocate_payment.payment) is distinct from 'object' then
    raise exception 'payment is an object of partyId, amount, currency and reference' using errcode = '22023', hint = 'INVOICE_ALLOCATIONS_INVALID';
  end if;
  if v_party is null or length(v_party) > 150 then
    raise exception 'a party id is a non-empty text of at most 150 characters' using errcode = '22023', hint = 'INVOICE_PARTY_INVALID';
  end if;
  if v_side not in ('customer', 'supplier') then
    raise exception 'side is customer or supplier' using errcode = '22023', hint = 'INVOICE_ALLOCATIONS_INVALID';
  end if;
  v_supplier := v_side = 'supplier';
  if v_supplier and v_use_credit then
    raise exception 'only a customer''s credit is drawn on' using errcode = '22023', hint = 'INVOICE_ALLOCATIONS_INVALID';
  end if;
  if v_currency is null or v_currency !~ '^[A-Z]{3}$' then
    raise exception 'currency is a three-letter ISO 4217 code' using errcode = '22023', hint = 'INVOICE_CURRENCY_INVALID';
  end if;
  if v_reference is null then
    raise exception 'a payment needs a reference, such as the bank transaction id' using errcode = '22023', hint = 'INVOICE_PAYMENT_REFERENCE_REQUIRED';
  end if;
  begin
    v_received := coalesce(nullif(allocate_payment.payment ->> 'receivedOn', '')::date, current_date);
  exception when others then
    raise exception 'receivedOn is a date' using errcode = '22023', hint = 'INVOICE_ALLOCATIONS_INVALID';
  end;
  if not v_use_credit then
    if coalesce(allocate_payment.payment ->> 'amount', '') !~ '^[0-9]{1,18}$' or (allocate_payment.payment ->> 'amount')::bigint = 0 then
      raise exception 'a payment has a positive amount' using errcode = '22023', hint = 'INVOICE_PAYMENT_INVALID';
    end if;
    v_amount := (allocate_payment.payment ->> 'amount')::bigint;
  end if;
  if jsonb_typeof(v_allocations) <> 'array' or jsonb_array_length(v_allocations) = 0 or exists (
    select 1 from jsonb_array_elements(v_allocations) x
    where jsonb_typeof(x.value) <> 'object'
      or coalesce(x.value ->> 'invoiceId', '') !~ '^[0-9a-fA-F-]{36}$'
      or coalesce(x.value ->> 'amount', '') !~ '^[0-9]{1,18}$'
      or (x.value ->> 'amount')::bigint = 0
      or (x.value ? 'takeDiscount' and jsonb_typeof(x.value -> 'takeDiscount') <> 'boolean')
  ) or (
    select count(*) <> count(distinct x.value ->> 'invoiceId') from jsonb_array_elements(v_allocations) x
  ) then
    raise exception 'allocations is a non-empty array of { invoiceId, amount, takeDiscount? } with a positive amount, one per invoice' using errcode = '22023', hint = 'INVOICE_ALLOCATIONS_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."invoice_allocations" b where b."tenant_id" = v_tenant and b."reference" = v_reference) then
    if exists (select 1 from "better_supabase"."invoice_allocations" b where b."tenant_id" = v_tenant and b."reference" = v_reference and b."unallocated_at" is not null) then
      raise exception 'this payment reference was allocated and unallocated; allocate the payment again under a new reference' using errcode = '55000', hint = 'INVOICE_ALLOCATION_REFERENCE_USED';
    end if;
    return jsonb_build_object(
      'reference', v_reference,
      'currency', (select min(x."currency"::text) from "better_supabase"."invoices" x join "better_supabase"."invoice_allocations" b on b."invoice_id" = x."id" where b."tenant_id" = v_tenant and b."reference" = v_reference),
      'partyId', (select min(b."party_id") from "better_supabase"."invoice_allocations" b where b."tenant_id" = v_tenant and b."reference" = v_reference),
      'allocated', coalesce((select sum(b."amount") from "better_supabase"."invoice_allocations" b where b."tenant_id" = v_tenant and b."reference" = v_reference and b."unallocated_at" is null), 0)::text,
      'discount', coalesce((select sum(b."discount") from "better_supabase"."invoice_allocations" b where b."tenant_id" = v_tenant and b."reference" = v_reference and b."unallocated_at" is null), 0)::text,
      'allocations', coalesce((select jsonb_agg(jsonb_build_object('invoiceId', b."invoice_id", 'source', b."source", 'amount', b."amount"::text, 'discount', b."discount"::text,
          'paymentId', b."payment_id", 'discountPaymentId', b."discount_payment_id", 'allocatedOn', b."allocated_on", 'unallocatedAt', b."unallocated_at") order by b."created_at", b."id")
        from "better_supabase"."invoice_allocations" b where b."tenant_id" = v_tenant and b."reference" = v_reference), '[]'::jsonb)) || jsonb_build_object('credited', coalesce((
      select (y."metadata" ->> 'amount') from "better_supabase"."ledger_transactions" y
      where y."tenant_id" = v_tenant and y."idempotency_key" = 'invoice-party-payment:' || v_reference), '0'));
  end if;
  select coalesce(sum((x.value ->> 'amount')::bigint), 0) into v_sum from jsonb_array_elements(v_allocations) x;
  if v_use_credit then
    v_amount := v_sum;
  elsif v_sum > v_amount then
    raise exception 'the allocations add up to more than the payment' using errcode = '23514', hint = 'INVOICE_ALLOCATIONS_TOO_LARGE';
  end if;
  v_remainder := v_amount - v_sum;
  if v_supplier and v_remainder > 0 then
    raise exception 'a supplier payment is allocated in full; lower the payment or allocate the rest' using errcode = '23514', hint = 'INVOICE_ALLOCATIONS_REMAINDER';
  end if;
  if allocate_payment.actor is not null then
    if jsonb_typeof(allocate_payment.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(allocate_payment.actor ->> 'ip', '')::inet, nullif(allocate_payment.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(allocate_payment.actor::text, ''), true);
  for v_alloc in
    select (x.value ->> 'invoiceId')::uuid as invoice, (x.value ->> 'amount')::bigint as amount,
      coalesce((x.value ->> 'takeDiscount')::boolean, true) as take
    from jsonb_array_elements(v_allocations) with ordinality x
    order by x.ordinality
  loop
    select * into v_row from "better_supabase"."invoices" x
    where x."id" = v_alloc.invoice and x."tenant_id" = v_tenant
      and (x."company_id"::text = v_party or x."contact_id"::text = v_party) and (x."direction" = 'purchase') = v_supplier
    for update;
    if v_row."id" is null then
      raise exception 'an allocation names no invoice of this party and side' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
    end if;
    if v_row."kind" <> 'invoice' or v_row."status" not in ('issued', 'partially_paid') then
      raise exception 'only an open invoice takes an allocation' using errcode = '55000', hint = 'INVOICE_NOT_PAYABLE';
    end if;
    if v_row."currency"::text <> v_currency then
      raise exception 'an allocation must be in the invoice''s currency' using errcode = '22023', hint = 'INVOICE_CURRENCY_MISMATCH';
    end if;
    v_balance := (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total");
    if v_alloc.amount > v_balance then
      raise exception 'an allocation is more than the invoice''s balance' using errcode = '23514', hint = 'INVOICE_ALLOCATION_TOO_LARGE';
    end if;
    v_early := coalesce(v_row."discount_amount_early", 0);
    v_due := v_row."discount_due_on";
    v_discount := 0;
    if v_alloc.take and v_early > 0 and v_due is not null and v_received <= v_due
      and v_alloc.amount < v_balance and v_alloc.amount >= v_balance - v_early then
      v_discount := v_balance - v_alloc.amount;
    end if;
    v_ref := v_reference || '/' || v_alloc.invoice::text;
    v_was := v_row."status";
    if v_use_credit then
      select a."id" into v_account from "better_supabase"."ledger_accounts" a
      where a."tenant_id" = v_tenant and a."code" = 'invoices:credit:' || v_party || ':' || v_row."currency"
      for update;
      if v_account is null or v_alloc.amount > coalesce(-(select sum(e."amount") from "better_supabase"."ledger_entries" e where e."account_id" = v_account), 0) then
        raise exception 'the party doesn''t have this much credit in the invoice''s currency' using errcode = '23514', hint = 'INVOICE_CREDIT_INSUFFICIENT';
      end if;
      v_pay := "better_supabase"."ledger_post"(v_tenant, 'invoice.credit_applied',
        jsonb_build_array(
          jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'receivable',
      'invoice:' || v_row."id"::text, 'Receivable ' || coalesce(v_row."identifier", v_row."id"::text),
      v_row."currency"::text, 0::smallint, 'invoices', v_row."id"::text,
      null, true, 'invoices.read', 'invoices', null), 'amount', -v_alloc.amount),
          jsonb_build_object('account', v_account, 'amount', v_alloc.amount)),
        'invoices', v_row."id"::text, null, 'invoice-payment:' || v_ref, v_received::timestamptz,
        jsonb_strip_nulls(jsonb_build_object('invoiceId', v_row."id", 'method', 'credit', 'partyId', v_party, 'reference', v_ref)));
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
    else
      perform "better_supabase"."record_invoice_payment"(v_row."id", v_alloc.amount, v_currency, v_received::timestamptz,
        v_method, v_ref, v_note, allocate_payment.actor, null);
      select y."id" into v_pay from "better_supabase"."ledger_transactions" y where y."tenant_id" = v_tenant and y."idempotency_key" = 'invoice-payment:' || v_ref;
      select * into v_row from "better_supabase"."invoices" x where x."id" = v_alloc.invoice;
    end if;
    if v_discount > 0 then
      v_disc := "better_supabase"."ledger_post"(v_tenant, 'invoice.discount',
        jsonb_build_array(
          jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'receivable',
      'invoice:' || v_row."id"::text, 'Receivable ' || coalesce(v_row."identifier", v_row."id"::text),
      v_row."currency"::text, 0::smallint, 'invoices', v_row."id"::text,
      null, true, 'invoices.read', 'invoices', null), 'amount', -v_discount),
          jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_tenant, 'discount',
      'invoices:discount:' || case when v_row."direction" = 'purchase' then 'purchase' else 'sales' end || ':' || v_row."currency"::text,
      'Early payment discount ' || v_row."currency"::text, v_row."currency"::text, 0::smallint, null, null,
      null, true, 'invoices.read', 'invoices', null), 'amount', v_discount)),
        'invoices', v_row."id"::text, null, 'invoice-discount:' || v_ref, v_received::timestamptz,
        jsonb_strip_nulls(jsonb_build_object('invoiceId', v_row."id", 'method', 'early_payment_discount', 'reference', v_ref, 'partyId', v_party)));
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
      if not better_supabase.import_run() is not null then
    perform "better_supabase"."accounting_post_source"('invoice_discount', v_disc::text);
  end if;
      perform "better_supabase".emit_event('invoice.discount_applied', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'reference', v_reference, 'paymentId', v_disc, 'discount', v_discount::text, 'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  perform better_supabase.audit_event(
    event_type => 'invoice.discount_applied',
    category => 'billing',
    target_type => 'invoice',
    record_id => v_row."id"::text,
    target_label => v_row."identifier",
    summary => 'invoice discount_applied',
    tenant => (v_row."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'reference', v_reference, 'paymentId', v_disc, 'discount', v_discount::text, 'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text)
  );
    else
      v_disc := null;
    end if;
    insert into "better_supabase"."invoice_allocations" ("tenant_id", "reference", "party_id", "invoice_id", "source", "amount", "discount", "payment_id", "discount_payment_id", "allocated_on", "created_by")
    values (v_tenant, v_reference, v_party, v_row."id", case when v_use_credit then 'credit' else 'payment' end, v_alloc.amount, v_discount, v_pay, v_disc, v_received, auth.uid());
    perform "better_supabase".emit_event('invoice.allocated', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'reference', v_reference, 'paymentId', v_pay, 'partyId', v_party, 'amount', v_alloc.amount::text, 'discount', v_discount::text, 'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  perform better_supabase.audit_event(
    event_type => 'invoice.allocated',
    category => 'billing',
    target_type => 'invoice',
    record_id => v_row."id"::text,
    target_label => v_row."identifier",
    summary => 'invoice allocated',
    tenant => (v_row."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'reference', v_reference, 'paymentId', v_pay, 'partyId', v_party, 'amount', v_alloc.amount::text, 'discount', v_discount::text, 'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text)
  );
    if v_row."status" = 'paid' and v_was <> 'paid' and (v_use_credit or v_discount > 0) then
      perform "better_supabase".emit_event('invoice.paid', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'total', v_row."total"::text), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
    end if;
  end loop;
  if v_remainder > 0 then
    v_credit := "better_supabase"."ledger_post"(v_tenant, 'invoice.party_payment',
      jsonb_build_array(
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_tenant, 'cash', 'invoices:cash:' || v_currency,
      'Invoice payments ' || v_currency, v_currency, 0::smallint, null, null,
      null, true, 'invoices.read', 'invoices', null), 'amount', v_remainder),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_tenant, 'credit', 'invoices:credit:' || v_party || ':' || v_currency,
      'Credit ' || v_party || ' ' || v_currency, v_currency, 0::smallint, 'invoice_party', v_party,
      null, true, 'invoices.read', 'invoices', null), 'amount', -v_remainder)),
      'invoices', v_party, null, 'invoice-party-payment:' || v_reference, v_received::timestamptz,
      jsonb_strip_nulls(jsonb_build_object('partyId', v_party, 'currency', v_currency, 'method', v_method,
        'reference', v_reference, 'note', v_note, 'amount', v_remainder::text)));
    if not better_supabase.import_run() is not null then
    perform "better_supabase"."accounting_post_source"('invoice_party_payment', v_credit::text);
  end if;
    v_credited := v_remainder;
  end if;
  return jsonb_build_object(
      'reference', v_reference,
      'currency', (select min(x."currency"::text) from "better_supabase"."invoices" x join "better_supabase"."invoice_allocations" b on b."invoice_id" = x."id" where b."tenant_id" = v_tenant and b."reference" = v_reference),
      'partyId', (select min(b."party_id") from "better_supabase"."invoice_allocations" b where b."tenant_id" = v_tenant and b."reference" = v_reference),
      'allocated', coalesce((select sum(b."amount") from "better_supabase"."invoice_allocations" b where b."tenant_id" = v_tenant and b."reference" = v_reference and b."unallocated_at" is null), 0)::text,
      'discount', coalesce((select sum(b."discount") from "better_supabase"."invoice_allocations" b where b."tenant_id" = v_tenant and b."reference" = v_reference and b."unallocated_at" is null), 0)::text,
      'allocations', coalesce((select jsonb_agg(jsonb_build_object('invoiceId', b."invoice_id", 'source', b."source", 'amount', b."amount"::text, 'discount', b."discount"::text,
          'paymentId', b."payment_id", 'discountPaymentId', b."discount_payment_id", 'allocatedOn', b."allocated_on", 'unallocatedAt', b."unallocated_at") order by b."created_at", b."id")
        from "better_supabase"."invoice_allocations" b where b."tenant_id" = v_tenant and b."reference" = v_reference), '[]'::jsonb)) || jsonb_build_object('credited', v_credited::text);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.approve_purchase_invoice (
  invoice uuid,
  comment text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."invoices";
  v_state jsonb;
  v_level record;
  v_actor uuid := auth.uid();
  v_done integer := 0;
  v_last integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."invoices" x
  where x."id" = approve_purchase_invoice.invoice and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.approve'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such invoice you can approve' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  if v_row."direction" <> 'purchase' or v_row."kind" <> 'invoice' or v_row."status" not in ('issued', 'partially_paid') then
    raise exception 'only an open purchase bill is approved' using errcode = '55000', hint = 'INVOICE_NOT_APPROVABLE';
  end if;
  if length(approve_purchase_invoice.comment) > 2000 then
    raise exception 'a comment has at most 2000 characters' using errcode = '22023', hint = 'INVOICE_APPROVAL_INVALID';
  end if;
  v_state := "better_supabase"."invoice_approval_state"(v_row."id");
  if v_state ->> 'status' = 'not_required' then
    raise exception 'no approval level applies to this bill' using errcode = '55000', hint = 'INVOICE_APPROVAL_NOT_REQUIRED';
  end if;
  if v_state ->> 'status' = 'approved' then
    raise exception 'the bill has every approval it needs' using errcode = '55000', hint = 'INVOICE_ALREADY_APPROVED';
  end if;
  for v_level in
    select (p.value ->> 'level')::integer as level, (p.value ->> 'approverId')::uuid as approver
    from jsonb_array_elements(v_state -> 'pending') p
    order by 1
  loop
    if (v_actor is null and v_done = 0) or v_level.approver = v_actor then
      insert into "better_supabase"."invoice_approvals" ("tenant_id", "invoice_id", "level", "approver_id", "comment")
      values (v_row."tenant_id", v_row."id", v_level.level, v_level.approver, nullif(trim(approve_purchase_invoice.comment), ''));
      v_done := v_done + 1;
      v_last := v_level.level;
    end if;
  end loop;
  if v_done = 0 then
    raise exception 'the caller is not the approver of a pending level' using errcode = '42501', hint = 'INVOICE_APPROVER_FORBIDDEN';
  end if;
  v_state := "better_supabase"."invoice_approval_state"(v_row."id");
  perform "better_supabase".emit_event('invoice.approved', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'level', v_last, 'approvalStatus', v_state ->> 'status'), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  perform better_supabase.audit_event(
    event_type => 'invoice.approved',
    category => 'billing',
    target_type => 'invoice',
    record_id => v_row."id"::text,
    target_label => v_row."identifier",
    summary => 'invoice approved',
    tenant => (v_row."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'level', v_last, 'approvalStatus', v_state ->> 'status')
  );
  return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'deposit_amount', v_row."deposit_amount"::text, 'discount_amount', v_row."discount_amount"::text, 'discount_amount_early', v_row."discount_amount_early"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code", 'taxCodeId', il."tax_code_id", 'unitCost', il."unit_cost"::text) order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb)) || jsonb_build_object('approval', v_state);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.cancel_payment_batch (
  batch_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_batch "better_supabase"."payment_batches"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_batch from "better_supabase"."payment_batches" x where x."id" = cancel_payment_batch.batch_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_batch."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_batch."tenant_id", 'banking.reconcile'), false))) then
    raise exception 'no such payment batch' using errcode = 'P0002', hint = 'PAYMENT_BATCH_NOT_FOUND';
  end if;
  if v_batch."status" not in ('draft', 'posted') then
    raise exception 'only a draft or posted batch is cancelled' using errcode = '55000', hint = 'PAYMENT_BATCH_STATUS_INVALID',
      detail = jsonb_build_object('status', v_batch."status")::text;
  end if;
  update "better_supabase"."payment_batch_items" y set "status" = 'cancelled' where y."batch_id" = v_batch."id";
  update "better_supabase"."payment_batches" y set "status" = 'cancelled' where y."id" = v_batch."id" returning * into v_batch;
  return jsonb_build_object('id', v_batch."id", 'organizationId', v_batch."tenant_id", 'accountId', v_batch."bank_account_id", 'reference', v_batch."reference", 'messageId', v_batch."message_id", 'currency', v_batch."currency", 'dueBy', v_batch."due_by", 'executionOn', v_batch."execution_on", 'total', v_batch."total"::text, 'itemCount', v_batch."item_count", 'status', v_batch."status", 'transactionId', v_batch."bank_transaction_id", 'createdBy', v_batch."created_by", 'createdAt', v_batch."created_at", 'postedAt', v_batch."posted_at", 'reconciledAt', v_batch."reconciled_at", 'items', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'invoiceId', y."invoice_id", 'partyId', y."party_id", 'creditorName', y."creditor_name", 'creditorIban', y."creditor_iban", 'creditorBic', y."creditor_bic", 'amount', y."amount"::text, 'discount', y."discount"::text, 'currency', y."currency", 'endToEndId', y."end_to_end_id", 'remittance', y."remittance", 'status', y."status") order by y."creditor_name", y."id") from "better_supabase"."payment_batch_items" y where y."batch_id" = v_batch."id"), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_payment_batch (
  tenant uuid,
  input  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_account "better_supabase"."bank_accounts"%rowtype;
  v_batch "better_supabase"."payment_batches"%rowtype;
  v_due date;
  v_exec date;
  v_reference text;
  v_ids uuid[];
  v_item record;
  v_creditor jsonb;
  v_iban text;
  v_total bigint := 0;
  v_count integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_payment_batch.tenant is not null and coalesce(better_supabase.can('tenant', create_payment_batch.tenant, 'banking.reconcile'), false))) then
    raise exception 'not allowed to create payment batches' using errcode = '42501', hint = 'BANKING_FORBIDDEN';
  end if;
  if jsonb_typeof(create_payment_batch.input) is distinct from 'object'
    or coalesce(create_payment_batch.input ->> 'accountId', '') !~ '^[0-9a-fA-F-]{36}$'
    or coalesce(create_payment_batch.input ->> 'dueBy', '') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
    or jsonb_typeof(create_payment_batch.input -> 'creditors') is distinct from 'object' then
    raise exception 'input needs accountId, dueBy and creditors' using errcode = '22023', hint = 'PAYMENT_BATCH_INVALID';
  end if;
  select * into v_account from "better_supabase"."bank_accounts" x
  where x."id" = (create_payment_batch.input ->> 'accountId')::uuid and x."tenant_id" = create_payment_batch.tenant and x."archived_at" is null;
  if not found then
    raise exception 'no such bank account' using errcode = 'P0002', hint = 'BANK_ACCOUNT_NOT_FOUND';
  end if;
  if v_account."iban" is null then
    raise exception 'the bank account needs an IBAN to pay from' using errcode = '22023', hint = 'PAYMENT_BATCH_INVALID';
  end if;
  v_due := (create_payment_batch.input ->> 'dueBy')::date;
  v_exec := coalesce((create_payment_batch.input ->> 'executionOn')::date, current_date);
  v_reference := coalesce(nullif(trim(create_payment_batch.input ->> 'reference'), ''), 'Batch ' || to_char(v_exec, 'YYYY-MM-DD') || ' ' || left(gen_random_uuid()::text, 8));
  if jsonb_typeof(create_payment_batch.input -> 'invoiceIds') = 'array' then
    select array_agg(x.value::uuid) into v_ids from jsonb_array_elements_text(create_payment_batch.input -> 'invoiceIds') x;
  end if;
  insert into "better_supabase"."payment_batches" ("tenant_id", "bank_account_id", "reference", "message_id", "currency", "due_by", "execution_on", "total", "item_count", "created_by")
  values (create_payment_batch.tenant, v_account."id", v_reference, 'BSB' || replace(gen_random_uuid()::text, '-', ''), v_account."currency", v_due, v_exec, 1, 1, auth.uid())
  returning * into v_batch;
  for v_item in
    select r."documentId" as invoice_id, r."partyId" as party, r.identifier, r.balance::bigint as balance,
      r."discountDueOn" as discount_due_on, coalesce(r."discountAmount", 0)::bigint as discount_amount
    from jsonb_to_recordset("better_supabase"."open_items_for_party"(create_payment_batch.tenant, null, current_date, 'supplier'))
      as r("documentType" text, "documentId" uuid, "partyId" text, identifier text, currency text, "dueOn" date, balance bigint,
        "discountDueOn" date, "discountAmount" bigint, "approvalStatus" text)
    where r."documentType" = 'invoice' and r.currency = v_account."currency" and r.balance > 0
      and (v_ids is null or r."documentId" = any (v_ids))
      and (v_ids is not null or coalesce(r."approvalStatus", 'not_required') <> 'pending')
      and (r."dueOn" <= v_due or (r."discountDueOn" is not null and r."discountDueOn" >= v_exec and r."discountDueOn" <= v_due and r."discountAmount" > 0))
      and not exists (select 1 from "better_supabase"."payment_batch_items" y where y."invoice_id" = r."documentId" and y."status" in ('open', 'posted'))
    order by r."partyId", r."dueOn", r."documentId"
  loop
    if coalesce("better_supabase"."invoice_approval_state"(v_item.invoice_id) ->> 'status', 'not_required') = 'pending' then
      raise exception 'a bill in the batch still needs approval' using errcode = '55000', hint = 'PAYMENT_BATCH_APPROVAL_REQUIRED',
        detail = jsonb_build_object('invoiceId', v_item.invoice_id)::text;
    end if;
    v_creditor := create_payment_batch.input -> 'creditors' -> v_item.party;
    if jsonb_typeof(v_creditor) is distinct from 'object' or coalesce(trim(v_creditor ->> 'name'), '') = '' then
      raise exception 'a creditor is missing for a supplier in the batch' using errcode = '22023', hint = 'PAYMENT_BATCH_CREDITOR_MISSING',
        detail = jsonb_build_object('partyId', v_item.party)::text;
    end if;
    v_iban := upper(regexp_replace(coalesce(v_creditor ->> 'iban', ''), '\s', '', 'g'));
    if v_iban !~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$' or "better_supabase"."bank_mod97"(substr(v_iban, 5) || substr(v_iban, 1, 4)) is distinct from 1 then
      raise exception 'a creditor has an invalid IBAN' using errcode = '22023', hint = 'PAYMENT_BATCH_CREDITOR_INVALID',
        detail = jsonb_build_object('partyId', v_item.party)::text;
    end if;
    insert into "better_supabase"."payment_batch_items" ("tenant_id", "batch_id", "invoice_id", "party_id", "creditor_name", "creditor_iban", "creditor_bic", "amount", "discount", "currency", "end_to_end_id", "remittance")
    values (create_payment_batch.tenant, v_batch."id", v_item.invoice_id, v_item.party, left(trim(v_creditor ->> 'name'), 140), v_iban,
      nullif(upper(regexp_replace(coalesce(v_creditor ->> 'bic', ''), '\s', '', 'g')), ''),
      v_item.balance - case when v_item.discount_due_on >= v_exec then v_item.discount_amount else 0 end,
      case when v_item.discount_due_on >= v_exec then v_item.discount_amount else 0 end,
      v_account."currency", replace(gen_random_uuid()::text, '-', ''), left(v_item.identifier, 140));
    v_total := v_total + v_item.balance - case when v_item.discount_due_on >= v_exec then v_item.discount_amount else 0 end;
    v_count := v_count + 1;
  end loop;
  if v_count = 0 then
    raise exception 'no approved open bill is due by that date' using errcode = '22023', hint = 'PAYMENT_BATCH_EMPTY';
  end if;
  update "better_supabase"."payment_batches" y set "total" = v_total, "item_count" = v_count where y."id" = v_batch."id" returning * into v_batch;
  return jsonb_build_object('id', v_batch."id", 'organizationId', v_batch."tenant_id", 'accountId', v_batch."bank_account_id", 'reference', v_batch."reference", 'messageId', v_batch."message_id", 'currency', v_batch."currency", 'dueBy', v_batch."due_by", 'executionOn', v_batch."execution_on", 'total', v_batch."total"::text, 'itemCount', v_batch."item_count", 'status', v_batch."status", 'transactionId', v_batch."bank_transaction_id", 'createdBy', v_batch."created_by", 'createdAt', v_batch."created_at", 'postedAt', v_batch."posted_at", 'reconciledAt', v_batch."reconciled_at", 'items', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'invoiceId', y."invoice_id", 'partyId', y."party_id", 'creditorName', y."creditor_name", 'creditorIban', y."creditor_iban", 'creditorBic', y."creditor_bic", 'amount', y."amount"::text, 'discount', y."discount"::text, 'currency', y."currency", 'endToEndId', y."end_to_end_id", 'remittance', y."remittance", 'status', y."status") order by y."creditor_name", y."id") from "better_supabase"."payment_batch_items" y where y."batch_id" = v_batch."id"), '[]'::jsonb));
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
    ('user', 'better_supabase.ai_suggestions', '"better_supabase"."ai_suggestions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.knowledge_documents', '"better_supabase"."knowledge_documents"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.knowledge_collection_grants', '"better_supabase"."knowledge_collection_grants"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.memories', '"better_supabase"."memories"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.memory_message_embeddings', '"better_supabase"."memory_message_embeddings"', 'user_id', true, '{}'::text[], true),
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
    ('user', 'better_supabase.activities', '"better_supabase"."activities"', 'owner_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.quotes', '"better_supabase"."quotes"', 'owner_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.employees', '"better_supabase"."employees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.employee_private_details', '"better_supabase"."employee_private_details"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_reports', '"better_supabase"."moderation_reports"', 'reporter_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_bans', '"better_supabase"."moderation_bans"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.assets', '"better_supabase"."assets"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.score_models', '"better_supabase"."score_models"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.score_model_versions', '"better_supabase"."score_model_versions"', 'saved_by', true, '{}'::text[], true),
    ('user', 'better_supabase.passes', '"better_supabase"."passes"', 'holder_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.leases', '"better_supabase"."leases"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.expense_reports', '"better_supabase"."expense_reports"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.pledges', '"better_supabase"."pledges"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.donations', '"better_supabase"."donations"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_orders', '"better_supabase"."work_orders"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.dispatch_routes', '"better_supabase"."dispatch_routes"', 'technician_id', true, '{}'::text[], true),
    ('user', 'better_supabase.work_order_parts', '"better_supabase"."work_order_parts"', 'recorded_by', true, '{}'::text[], true),
    ('user', 'better_supabase.shipments', '"better_supabase"."shipments"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.contracts', '"better_supabase"."contracts"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.control_evidence', '"better_supabase"."control_evidence"', 'collected_by', true, '{}'::text[], true),
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
    ('user', 'better_supabase.post_boards', '"better_supabase"."post_boards"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.posts', '"better_supabase"."posts"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.content_entries', '"better_supabase"."content_entries"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.risk_assessments', '"better_supabase"."risk_assessments"', 'assessed_by', true, '{}'::text[], true),
    ('user', 'better_supabase.shift_assignments', '"better_supabase"."shift_assignments"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.shift_swaps', '"better_supabase"."shift_swaps"', 'from_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.shift_availability', '"better_supabase"."shift_availability"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.acknowledgements', '"better_supabase"."acknowledgements"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.acknowledgement_notices', '"better_supabase"."acknowledgement_notices"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.observations', '"better_supabase"."observations"', 'performer_id', true, '{}'::text[], true),
    ('user', 'better_supabase.care_plan_evaluations', '"better_supabase"."care_plan_evaluations"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.inspection_members', '"better_supabase"."inspection_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.meeting_attendees', '"better_supabase"."meeting_attendees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.payroll_lines', '"better_supabase"."payroll_lines"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.maintenance_meter_readings', '"better_supabase"."maintenance_meter_readings"', 'read_by', true, '{}'::text[], true),
    ('user', 'better_supabase.maintenance_calibrations', '"better_supabase"."maintenance_calibrations"', 'performed_by', true, '{}'::text[], true),
    ('user', 'better_supabase.dam_usage_rights', '"better_supabase"."dam_usage_rights"', 'created_by', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.attachment_document_types', '"better_supabase"."attachment_document_types"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.attachment_versions', '"better_supabase"."attachment_versions"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.retention_policies', '"better_supabase"."retention_policies"', 'organization_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.sso_domains', '"better_supabase"."sso_domains"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sso_providers', '"better_supabase"."sso_providers"', 'organization_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.inbox_conversations', '"better_supabase"."inbox_conversations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_conversation_events', '"better_supabase"."inbox_conversation_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_message_details', '"better_supabase"."inbox_message_details"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_message_deliveries', '"better_supabase"."inbox_message_deliveries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_inbound_events', '"better_supabase"."inbox_inbound_events"', 'tenant_id', true, array['headers']::text[], true),
    ('organization', 'better_supabase.inbox_message_templates', '"better_supabase"."inbox_message_templates"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.knowledge_collection_grants', '"better_supabase"."knowledge_collection_grants"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.memories', '"better_supabase"."memories"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.memory_message_embeddings', '"better_supabase"."memory_message_embeddings"', 'organization_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.import_records', '"better_supabase"."import_records"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.catalog_price_lists', '"better_supabase"."catalog_price_lists"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_prices', '"better_supabase"."product_prices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.catalog_categories', '"better_supabase"."catalog_categories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_categories', '"better_supabase"."product_categories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_collections', '"better_supabase"."product_collections"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.collection_products', '"better_supabase"."collection_products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.catalog_storefronts', '"better_supabase"."catalog_storefronts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.catalog_channels', '"better_supabase"."catalog_channels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.catalog_channel_products', '"better_supabase"."catalog_channel_products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_translations', '"better_supabase"."product_translations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_variant_translations', '"better_supabase"."product_variant_translations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_media', '"better_supabase"."product_media"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_identifiers', '"better_supabase"."product_identifiers"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_relations', '"better_supabase"."product_relations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.supplier_items', '"better_supabase"."supplier_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.supplier_item_mappings', '"better_supabase"."supplier_item_mappings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.discount_groups', '"better_supabase"."discount_groups"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.discount_group_parties', '"better_supabase"."discount_group_parties"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.discount_rules', '"better_supabase"."discount_rules"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.purchase_requisitions', '"better_supabase"."purchase_requisitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.purchase_requisition_lines', '"better_supabase"."purchase_requisition_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inventory_receipts', '"better_supabase"."inventory_receipts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inventory_receipt_lines', '"better_supabase"."inventory_receipt_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_items', '"better_supabase"."stock_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_bins', '"better_supabase"."stock_bins"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_lots', '"better_supabase"."stock_lots"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_serials', '"better_supabase"."stock_serials"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_buckets', '"better_supabase"."stock_buckets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_allocations', '"better_supabase"."stock_allocations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_counts', '"better_supabase"."stock_counts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_count_lines', '"better_supabase"."stock_count_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.carts', '"better_supabase"."carts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.cart_lines', '"better_supabase"."cart_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_shipping_rates', '"better_supabase"."order_shipping_rates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.orders', '"better_supabase"."orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_lines', '"better_supabase"."order_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_payments', '"better_supabase"."order_payments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_fulfillments', '"better_supabase"."order_fulfillments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_fulfillment_lines', '"better_supabase"."order_fulfillment_lines"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.case_kinds', '"better_supabase"."case_kinds"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.cases', '"better_supabase"."cases"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.case_actions', '"better_supabase"."case_actions"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.payment_terms', '"better_supabase"."payment_terms"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_delivery_preferences', '"better_supabase"."document_delivery_preferences"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.person_identities', '"better_supabase"."person_identities"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.activities', '"better_supabase"."activities"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.engagement_subjects', '"better_supabase"."engagement_subjects"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quotes', '"better_supabase"."quotes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_lines', '"better_supabase"."quote_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_versions', '"better_supabase"."quote_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_version_lines', '"better_supabase"."quote_version_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_tax_lines', '"better_supabase"."quote_tax_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoices', '"better_supabase"."invoices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_lines', '"better_supabase"."invoice_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_charges', '"better_supabase"."invoice_charges"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_dunning_levels', '"better_supabase"."invoice_dunning_levels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_dunning_runs', '"better_supabase"."invoice_dunning_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_dunning_run_items', '"better_supabase"."invoice_dunning_run_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_dunning_history', '"better_supabase"."invoice_dunning_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_allocations', '"better_supabase"."invoice_allocations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_approval_levels', '"better_supabase"."invoice_approval_levels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_approvals', '"better_supabase"."invoice_approvals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sla_policies', '"better_supabase"."sla_policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sla_clocks', '"better_supabase"."sla_clocks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.goals', '"better_supabase"."goals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employees', '"better_supabase"."employees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employee_private_details', '"better_supabase"."employee_private_details"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employee_contracts', '"better_supabase"."employee_contracts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_items', '"better_supabase"."moderation_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_reports', '"better_supabase"."moderation_reports"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_actions', '"better_supabase"."moderation_actions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_bans', '"better_supabase"."moderation_bans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.automations', '"better_supabase"."automations"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.automation_versions', '"better_supabase"."automation_versions"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.automation_evaluations', '"better_supabase"."automation_evaluations"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.asset_locations', '"better_supabase"."asset_locations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.assets', '"better_supabase"."assets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.asset_assignments', '"better_supabase"."asset_assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.asset_depreciations', '"better_supabase"."asset_depreciations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.score_models', '"better_supabase"."score_models"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.score_model_versions', '"better_supabase"."score_model_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scores', '"better_supabase"."scores"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.passes', '"better_supabase"."passes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pass_check_ins', '"better_supabase"."pass_check_ins"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.time_rates', '"better_supabase"."time_rates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.time_invoice_entries', '"better_supabase"."time_invoice_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.leases', '"better_supabase"."leases"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.intrastat_lines', '"better_supabase"."intrastat_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.contracts', '"better_supabase"."contracts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.contract_obligations', '"better_supabase"."contract_obligations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.control_frameworks', '"better_supabase"."control_frameworks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.controls', '"better_supabase"."controls"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.control_evidence', '"better_supabase"."control_evidence"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.evidence_tasks', '"better_supabase"."evidence_tasks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.compliance_policies', '"better_supabase"."compliance_policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_status_components', '"better_supabase"."incident_status_components"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_status_component_history', '"better_supabase"."incident_status_component_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incidents', '"better_supabase"."incidents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_updates', '"better_supabase"."incident_updates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_impacts', '"better_supabase"."incident_impacts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_postmortems', '"better_supabase"."incident_postmortems"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_postmortem_actions', '"better_supabase"."incident_postmortem_actions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_status_pages', '"better_supabase"."incident_status_pages"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.timeline_entries', '"better_supabase"."timeline_entries"', 'organization_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.tax_codes', '"better_supabase"."tax_codes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.tax_rates', '"better_supabase"."tax_rates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_tax_lines', '"better_supabase"."invoice_tax_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.tax_returns', '"better_supabase"."tax_returns"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.eu_sales_list_lines', '"better_supabase"."eu_sales_list_lines"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.accounting_opening_balances', '"better_supabase"."accounting_opening_balances"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_budgets', '"better_supabase"."accounting_budgets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_budget_lines', '"better_supabase"."accounting_budget_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.acknowledgement_assignments', '"better_supabase"."acknowledgement_assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.acknowledgements', '"better_supabase"."acknowledgements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.acknowledgement_notices', '"better_supabase"."acknowledgement_notices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.consent_purposes', '"better_supabase"."consent_purposes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.consents', '"better_supabase"."consents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.observation_definitions', '"better_supabase"."observation_definitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.observations', '"better_supabase"."observations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.medications', '"better_supabase"."medications"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.medication_orders', '"better_supabase"."medication_orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.medication_administrations', '"better_supabase"."medication_administrations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_plans', '"better_supabase"."care_plans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_plan_problems', '"better_supabase"."care_plan_problems"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_plan_goals', '"better_supabase"."care_plan_goals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_plan_actions', '"better_supabase"."care_plan_actions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_plan_evaluations', '"better_supabase"."care_plan_evaluations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inspection_programs', '"better_supabase"."inspection_programs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inspections', '"better_supabase"."inspections"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inspection_members', '"better_supabase"."inspection_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inspection_findings', '"better_supabase"."inspection_findings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.boms', '"better_supabase"."boms"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_centers', '"better_supabase"."work_centers"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bom_operations', '"better_supabase"."bom_operations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bom_components', '"better_supabase"."bom_components"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.production_orders', '"better_supabase"."production_orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.production_order_operations', '"better_supabase"."production_order_operations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.production_consumptions', '"better_supabase"."production_consumptions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_lot_links', '"better_supabase"."stock_lot_links"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bank_accounts', '"better_supabase"."bank_accounts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bank_rules', '"better_supabase"."bank_rules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bank_statements', '"better_supabase"."bank_statements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bank_transactions', '"better_supabase"."bank_transactions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bank_matches', '"better_supabase"."bank_matches"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.payment_batches', '"better_supabase"."payment_batches"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.payment_batch_items', '"better_supabase"."payment_batch_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.meetings', '"better_supabase"."meetings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.meeting_attendees', '"better_supabase"."meeting_attendees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.meeting_agenda_items', '"better_supabase"."meeting_agenda_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.meeting_decisions', '"better_supabase"."meeting_decisions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.meeting_action_items', '"better_supabase"."meeting_action_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.legal_entities', '"better_supabase"."legal_entities"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.legal_entity_settings', '"better_supabase"."legal_entity_settings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.funding_products', '"better_supabase"."funding_products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.funding_awards', '"better_supabase"."funding_awards"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.funding_deliveries', '"better_supabase"."funding_deliveries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.funding_claims', '"better_supabase"."funding_claims"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.funding_claim_lines', '"better_supabase"."funding_claim_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.payroll_runs', '"better_supabase"."payroll_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.payroll_lines', '"better_supabase"."payroll_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.maintenance_plans', '"better_supabase"."maintenance_plans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.maintenance_plan_parts', '"better_supabase"."maintenance_plan_parts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.maintenance_meters', '"better_supabase"."maintenance_meters"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.maintenance_meter_readings', '"better_supabase"."maintenance_meter_readings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.maintenance_calibrations', '"better_supabase"."maintenance_calibrations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.dam_usage_rights', '"better_supabase"."dam_usage_rights"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.dam_renditions', '"better_supabase"."dam_renditions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_templates', '"better_supabase"."document_templates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_text_blocks', '"better_supabase"."document_text_blocks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rendered_documents', '"better_supabase"."rendered_documents"', 'tenant_id', true, '{}'::text[], true)
  ) as t(subject, name, tbl, col, purge, omit, exported)
  ) as t(subject, name, tbl, col, purge, omit, exported)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_payment_batch (
  batch_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_batch "better_supabase"."payment_batches"%rowtype;
begin
  select * into v_batch from "better_supabase"."payment_batches" x where x."id" = get_payment_batch.batch_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_batch."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_batch."tenant_id", 'banking.read'), false))) then
    raise exception 'no such payment batch' using errcode = 'P0002', hint = 'PAYMENT_BATCH_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_batch."id", 'organizationId', v_batch."tenant_id", 'accountId', v_batch."bank_account_id", 'reference', v_batch."reference", 'messageId', v_batch."message_id", 'currency', v_batch."currency", 'dueBy', v_batch."due_by", 'executionOn', v_batch."execution_on", 'total', v_batch."total"::text, 'itemCount', v_batch."item_count", 'status', v_batch."status", 'transactionId', v_batch."bank_transaction_id", 'createdBy', v_batch."created_by", 'createdAt', v_batch."created_at", 'postedAt', v_batch."posted_at", 'reconciledAt', v_batch."reconciled_at", 'items', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'invoiceId', y."invoice_id", 'partyId', y."party_id", 'creditorName', y."creditor_name", 'creditorIban', y."creditor_iban", 'creditorBic', y."creditor_bic", 'amount', y."amount"::text, 'discount', y."discount"::text, 'currency', y."currency", 'endToEndId', y."end_to_end_id", 'remittance', y."remittance", 'status', y."status") order by y."creditor_name", y."id") from "better_supabase"."payment_batch_items" y where y."batch_id" = v_batch."id"), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_apply_batch (
  run    uuid,
  entity text,
  items  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_run_id uuid := import_apply_batch.run;
  v_entity text := import_apply_batch.entity;
  v_items jsonb := import_apply_batch.items;
  v_run "better_supabase"."import_runs";
  v_item jsonb;
  v_call jsonb;
  v_key text;
  v_scope text;
  v_data jsonb;
  v_hash text;
  v_rec "better_supabase"."import_records";
  v_other text;
  v_found boolean;
  v_done boolean;
  v_subject_id text;
  v_subject_type text;
  v_current timestamptz;
  v_out jsonb;
  v_subjects jsonb;
  v_subject jsonb;
  v_inserted integer := 0;
  v_updated integer := 0;
  v_unchanged integer := 0;
  v_conflicted integer := 0;
  v_errors jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_message text;
  v_hint text;
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = v_run_id;
  if v_entity <> all (array['attachment', 'data_lifecycle_row', 'field_value', 'supplier_item', 'product_identifier', 'discount_group', 'discount_rule', 'stock_count', 'order', 'payment_term', 'document_delivery_preference', 'quote', 'invoice', 'credit_note', 'open_item', 'accounting_account', 'accounting_journal', 'accounting_entry', 'accounting_opening_balance', 'tax_code', 'tax_rate', 'document_template', 'document_text_block', 'customer']::text[]) then
    raise exception 'no import target for this entity' using errcode = '22023', hint = 'IMPORT_TARGET_UNKNOWN';
  end if;
  if jsonb_typeof(v_items) <> 'array' then
    raise exception 'items must be an array of { key, scope, data, refs }' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;

  for v_item in select e.value from jsonb_array_elements(v_items) e loop
    v_key := v_item ->> 'key';
    v_scope := coalesce(v_item ->> 'scope', '');
    v_data := v_item -> 'data';

    if v_key is null or v_key = '' or jsonb_typeof(v_data) is distinct from 'object' then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'code', 'IMPORT_ITEM_INVALID', 'message', 'an item needs a key and a data object'));
      continue;
    end if;

    -- jsonb text is key-ordered, so equal content hashes equally.
    v_hash := encode(extensions.digest(v_data::text, 'sha256'), 'hex');

    begin
      v_done := false;
      select * into v_rec from "better_supabase"."import_records" x
      where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."scope" = v_scope
        and x."entity" = v_entity and x."external_key" = v_key and x."role" = 'primary';
      v_found := found;

      if not v_found then
        -- A cloned administration reuses the subjects of the scope it aliases
        -- when the content is equal there.
        for v_other in
          select a."of" from jsonb_to_recordset(v_run."scope_aliases") as a(scope text, "of" text, entities jsonb)
          where a.scope = v_scope
            and (a.entities is null or jsonb_typeof(a.entities) <> 'array' or jsonb_array_length(a.entities) = 0 or a.entities ? v_entity)
        loop
          if exists (
            select 1 from "better_supabase"."import_records" x
            where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."scope" = v_other
              and x."entity" = v_entity and x."external_key" = v_key and x."role" = 'primary' and x."content_hash" = v_hash
          ) then
            insert into "better_supabase"."import_records" ("tenant_id", "source", "scope", "entity", "external_key", "role", "subject_type", "subject_id", "content_hash", "first_run_id", "last_run_id", "subject_updated_at_at_import")
            select x."tenant_id", x."source", v_scope, x."entity", x."external_key", x."role", x."subject_type", x."subject_id", x."content_hash", v_run_id, v_run_id, x."subject_updated_at_at_import"
            from "better_supabase"."import_records" x
            where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."scope" = v_other
              and x."entity" = v_entity and x."external_key" = v_key
            on conflict ("tenant_id", "source", "scope", "entity", "external_key", "role") do nothing;
            v_unchanged := v_unchanged + 1;
            v_done := true;
            exit;
          end if;
        end loop;
      elsif v_rec."content_hash" = v_hash then
        update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "missing_since" = null
        where x."tenant_id" = v_rec."tenant_id" and x."source" = v_rec."source" and x."scope" = v_rec."scope"
          and x."entity" = v_rec."entity" and x."external_key" = v_rec."external_key"
          and (x."last_run_id" is distinct from v_run_id or x."missing_since" is not null);
        v_unchanged := v_unchanged + 1;
        v_done := true;
      else
        -- A row a user changed after the last import stays as it is.
        v_current := null;
        case v_entity
        when 'supplier_item' then
          v_current := "better_supabase"."supplier_item_updated_at"(v_rec."subject_id");
        when 'product_identifier' then
          v_current := "better_supabase"."product_identifier_updated_at"(v_rec."subject_id");
        when 'discount_group' then
          v_current := "better_supabase"."discount_group_updated_at"(v_rec."subject_id");
        when 'discount_rule' then
          v_current := "better_supabase"."discount_rule_updated_at"(v_rec."subject_id");
        when 'stock_count' then
          v_current := "better_supabase"."stock_count_updated_at"(v_rec."subject_id");
        when 'order' then
          v_current := "better_supabase"."order_updated_at"(v_rec."subject_id");
        when 'payment_term' then
          v_current := "better_supabase"."payment_term_updated_at"(v_rec."subject_id");
        when 'document_delivery_preference' then
          v_current := "better_supabase"."document_delivery_preference_updated_at"(v_rec."subject_id");
        when 'quote' then
          v_current := "better_supabase"."quote_updated_at"(v_rec."subject_id");
        when 'invoice' then
          v_current := "better_supabase"."invoice_updated_at"(v_rec."subject_id");
        when 'credit_note' then
          v_current := "better_supabase"."invoice_updated_at"(v_rec."subject_id");
        when 'open_item' then
          v_current := "better_supabase"."invoice_updated_at"(v_rec."subject_id");
        when 'tax_code' then
          v_current := "better_supabase"."tax_code_updated_at"(v_rec."subject_id");
        when 'document_template' then
          v_current := "better_supabase"."document_template_updated_at"(v_rec."subject_id");
        when 'document_text_block' then
          v_current := "better_supabase"."document_text_block_updated_at"(v_rec."subject_id");
        when 'customer' then
          v_current := "public"."import_customer_updated_at"(v_rec."subject_id");
          else null;
        end case;
        if v_current is not null and v_rec."subject_updated_at_at_import" is not null and v_current > v_rec."subject_updated_at_at_import" then
          update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "missing_since" = null
          where x."id" = v_rec."id";
          v_conflicted := v_conflicted + 1;
          v_done := true;
        end if;
      end if;

      if not v_done then
        v_subject_id := case when v_found then v_rec."subject_id" else null end;
        v_call := v_item || jsonb_build_object('tenant', v_run."tenant_id", 'scope', v_scope);
        case v_entity
      when 'attachment' then
        v_subject_type := 'attachment';
        v_out := "better_supabase"."import_attachment"(v_run_id, v_call, v_subject_id);
      when 'data_lifecycle_row' then
        v_subject_type := 'data_lifecycle_row';
        v_out := "better_supabase"."restore_data_row"(v_run_id, v_call, v_subject_id);
      when 'field_value' then
        v_subject_type := 'field_value';
        v_out := "better_supabase"."import_field_value"(v_run_id, v_call, v_subject_id);
      when 'supplier_item' then
        v_subject_type := 'supplier_item';
        v_out := "better_supabase"."import_supplier_item"(v_run_id, v_call, v_subject_id);
      when 'product_identifier' then
        v_subject_type := 'product_identifier';
        v_out := "better_supabase"."import_product_identifier"(v_run_id, v_call, v_subject_id);
      when 'discount_group' then
        v_subject_type := 'discount_group';
        v_out := "better_supabase"."import_discount_group"(v_run_id, v_call, v_subject_id);
      when 'discount_rule' then
        v_subject_type := 'discount_rule';
        v_out := "better_supabase"."import_discount_rule"(v_run_id, v_call, v_subject_id);
      when 'stock_count' then
        v_subject_type := 'stock_count';
        v_out := "better_supabase"."import_stock_count"(v_run_id, v_call, v_subject_id);
      when 'order' then
        v_subject_type := 'order';
        v_out := "better_supabase"."import_order"(v_run_id, v_call, v_subject_id);
      when 'payment_term' then
        v_subject_type := 'payment_term';
        v_out := "better_supabase"."import_payment_term"(v_run_id, v_call, v_subject_id);
      when 'document_delivery_preference' then
        v_subject_type := 'document_delivery_preference';
        v_out := "better_supabase"."import_document_delivery_preference"(v_run_id, v_call, v_subject_id);
      when 'quote' then
        v_subject_type := 'quote';
        v_out := "better_supabase"."import_quote"(v_run_id, v_call, v_subject_id);
      when 'invoice' then
        v_subject_type := 'invoice';
        v_out := "better_supabase"."import_invoice"(v_run_id, v_call, v_subject_id);
      when 'credit_note' then
        v_subject_type := 'invoice';
        v_out := "better_supabase"."import_credit_note"(v_run_id, v_call, v_subject_id);
      when 'open_item' then
        v_subject_type := 'invoice';
        v_out := "better_supabase"."import_open_item"(v_run_id, v_call, v_subject_id);
      when 'accounting_account' then
        v_subject_type := 'accounting_account';
        v_out := "better_supabase"."import_accounting_account"(v_run_id, v_call, v_subject_id);
      when 'accounting_journal' then
        v_subject_type := 'accounting_journal';
        v_out := "better_supabase"."import_accounting_journal"(v_run_id, v_call, v_subject_id);
      when 'accounting_entry' then
        v_subject_type := 'accounting_entry';
        v_out := "better_supabase"."import_accounting_entry"(v_run_id, v_call, v_subject_id);
      when 'accounting_opening_balance' then
        v_subject_type := 'accounting_opening_balance';
        v_out := "better_supabase"."import_accounting_opening_balance"(v_run_id, v_call, v_subject_id);
      when 'tax_code' then
        v_subject_type := 'tax_code';
        v_out := "better_supabase"."import_tax_code"(v_run_id, v_call, v_subject_id);
      when 'tax_rate' then
        v_subject_type := 'tax_rate';
        v_out := "better_supabase"."import_tax_rate"(v_run_id, v_call, v_subject_id);
      when 'document_template' then
        v_subject_type := 'document_template';
        v_out := "better_supabase"."import_document_template"(v_run_id, v_call, v_subject_id);
      when 'document_text_block' then
        v_subject_type := 'document_text_block';
        v_out := "better_supabase"."import_document_text_block"(v_run_id, v_call, v_subject_id);
      when 'customer' then
        v_subject_type := 'customer';
        v_out := "public"."import_customer"(v_run_id, v_call, v_subject_id);
      else
        raise exception 'no import target for this entity' using errcode = '22023', hint = 'IMPORT_TARGET_UNKNOWN';
    end case;

        v_subjects := case jsonb_typeof(v_out) when 'array' then v_out else jsonb_build_array(v_out) end;
        if not exists (
          select 1 from jsonb_array_elements(v_subjects) s
          where coalesce(s.value ->> 'role', 'primary') = 'primary' and nullif(s.value ->> 'subjectId', '') is not null
        ) then
          raise exception 'the import target returned no primary subject' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
        end if;

        for v_subject in select s.value from jsonb_array_elements(v_subjects) s loop
          if jsonb_typeof(v_subject -> 'warnings') = 'array' then
            v_warnings := v_warnings || (select coalesce(jsonb_agg(w.value || jsonb_build_object('entity', v_entity, 'key', v_key)), '[]'::jsonb) from jsonb_array_elements(v_subject -> 'warnings') w);
          end if;
          insert into "better_supabase"."import_records" ("tenant_id", "source", "scope", "entity", "external_key", "role", "subject_type", "subject_id", "content_hash", "first_run_id", "last_run_id", "subject_updated_at_at_import", "missing_since")
          values (
            v_run."tenant_id", v_run."source", v_scope, v_entity, v_key,
            coalesce(v_subject ->> 'role', 'primary'),
            coalesce(v_subject ->> 'subjectType', v_subject_type),
            v_subject ->> 'subjectId',
            v_hash, v_run_id, v_run_id,
            coalesce((v_subject ->> 'updatedAt')::timestamptz, now()),
            null
          )
          on conflict ("tenant_id", "source", "scope", "entity", "external_key", "role") do update set
            "subject_type" = excluded."subject_type",
            "subject_id" = excluded."subject_id",
            "content_hash" = excluded."content_hash",
            "last_run_id" = excluded."last_run_id",
            "subject_updated_at_at_import" = excluded."subject_updated_at_at_import",
            "missing_since" = null;
        end loop;

        if v_found then
          v_updated := v_updated + 1;
        else
          v_inserted := v_inserted + 1;
        end if;
      end if;
    exception when others then
      get stacked diagnostics v_message = message_text, v_hint = pg_exception_hint;
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'code', coalesce(nullif(v_hint, ''), 'IMPORT_ITEM_INVALID'), 'message', v_message));
    end;
  end loop;

  return jsonb_build_object('inserted', v_inserted, 'updated', v_updated, 'unchanged', v_unchanged, 'conflicted', v_conflicted, 'errors', v_errors) || case when jsonb_array_length(v_warnings) > 0 then jsonb_build_object('warnings', v_warnings) else '{}'::jsonb end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_open_item (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_data jsonb := import_open_item.item -> 'data';
  v_balance bigint;
begin
  if jsonb_typeof(v_data) is distinct from 'object' or coalesce(v_data ->> 'balance', '') !~ '^[0-9]{1,18}$' or (v_data ->> 'balance')::bigint = 0 then
    raise exception 'an open item has a positive integer balance in minor units' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if coalesce(v_data ->> 'side', 'customer') not in ('customer', 'supplier') then
    raise exception 'side is customer or supplier' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  v_balance := (v_data ->> 'balance')::bigint;
  return "better_supabase"."import_invoice_document"(jsonb_set(import_open_item.item, '{data}', jsonb_strip_nulls(jsonb_build_object(
    'number', v_data -> 'number', 'status', 'issued', 'issuedOn', v_data -> 'issuedOn', 'dueOn', v_data -> 'dueOn',
    'currency', v_data -> 'currency', 'company', v_data -> 'company', 'contact', v_data -> 'contact',
    'legalEntityId', v_data -> 'legalEntityId',
    'direction', case when v_data ->> 'side' = 'supplier' then 'purchase' else 'sales' end,
    'title', coalesce(nullif(v_data ->> 'title', ''), 'Opening balance ' || coalesce(v_data ->> 'number', '')),
    'lines', jsonb_build_array(jsonb_build_object('description', 'Opening balance ' || coalesce(v_data ->> 'number', ''),
      'quantity', 1, 'unitAmount', v_balance, 'taxRateBps', 0)),
    'totals', jsonb_build_object('subtotal', v_balance, 'tax', 0, 'total', v_balance)))),
    import_open_item.subject_id, false);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.invoice_approval_state (
  invoice uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."invoices";
  v_entity uuid;
  v_scoped boolean;
  v_required jsonb;
  v_approved jsonb;
  v_pending jsonb;
  v_status text;
begin
  select * into v_row from "better_supabase"."invoices" x where x."id" = invoice_approval_state.invoice;
  if not found then
    return null;
  end if;
  if v_row."direction" <> 'purchase' or v_row."kind" <> 'invoice' then
    return jsonb_build_object('status', 'not_required', 'required', '[]'::jsonb, 'approved', '[]'::jsonb, 'pending', '[]'::jsonb);
  end if;
  v_entity := v_row.legal_entity_id;
  v_scoped := v_entity is not null and exists (
    select 1 from "better_supabase"."invoice_approval_levels" l where l."tenant_id" = v_row."tenant_id" and l."legal_entity_id" = v_entity
  );
  select coalesce(jsonb_agg(l."level" order by l."level"), '[]'::jsonb),
    coalesce(jsonb_agg(l."level" order by l."level") filter (where a."id" is not null), '[]'::jsonb),
    coalesce(jsonb_agg(jsonb_build_object('level', l."level", 'approverId', l."approver_id", 'minAmount', l."min_amount"::text) order by l."level") filter (where a."id" is null), '[]'::jsonb)
  into v_required, v_approved, v_pending
  from "better_supabase"."invoice_approval_levels" l
  left join "better_supabase"."invoice_approvals" a on a."invoice_id" = v_row."id" and a."level" = l."level"
  where l."tenant_id" = v_row."tenant_id"
    and l."legal_entity_id" is not distinct from (case when v_scoped then v_entity end)
    and l."min_amount" <= v_row."total"
    and (l."currency" is null or l."currency" = v_row."currency"::text);
  v_status := case when jsonb_array_length(v_required) = 0 then 'not_required'
    when jsonb_array_length(v_pending) = 0 then 'approved' else 'pending' end;
  return jsonb_build_object('status', v_status, 'required', v_required, 'approved', v_approved, 'pending', v_pending);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_invoice_allocations (
  tenant     uuid,
  reference  text DEFAULT NULL::text,
  invoice_id uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', list_invoice_allocations.tenant, 'invoices.read'), false)) then
    raise exception 'not allowed to read this organization''s invoices' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('currency', (select x."currency"::text from "better_supabase"."invoices" x where x."id" = b."invoice_id"), 'reference', b."reference", 'partyId', b."party_id", 'invoiceId', b."invoice_id",
        'source', b."source", 'amount', b."amount"::text, 'discount', b."discount"::text,
        'paymentId', b."payment_id", 'discountPaymentId', b."discount_payment_id",
        'allocatedOn', b."allocated_on", 'unallocatedAt', b."unallocated_at") order by b."created_at", b."id")
    from "better_supabase"."invoice_allocations" b
    where b."tenant_id" = list_invoice_allocations.tenant
      and (list_invoice_allocations.reference is null or b."reference" = list_invoice_allocations.reference)
      and (list_invoice_allocations.invoice_id is null or b."invoice_id" = list_invoice_allocations.invoice_id)
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_invoice_approval_levels (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', list_invoice_approval_levels.tenant, 'invoices.read'), false)) then
    raise exception 'not allowed to read this organization''s invoices' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('legalEntityId', l."legal_entity_id", 'level', l."level",
        'minAmount', l."min_amount"::text, 'currency', l."currency", 'approverId', l."approver_id")
      order by l."legal_entity_id" nulls first, l."level")
    from "better_supabase"."invoice_approval_levels" l where l."tenant_id" = list_invoice_approval_levels.tenant
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_payment_batches (
  tenant    uuid,
  status    text    DEFAULT NULL::text,
  page_size integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_payment_batches.tenant is not null and coalesce(better_supabase.can('tenant', list_payment_batches.tenant, 'banking.read'), false))) then
    raise exception 'not allowed to read payment batches' using errcode = '42501', hint = 'BANKING_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', k."id", 'organizationId', k."tenant_id", 'accountId', k."bank_account_id", 'reference', k."reference", 'messageId', k."message_id", 'currency', k."currency", 'dueBy', k."due_by", 'executionOn', k."execution_on", 'total', k."total"::text, 'itemCount', k."item_count", 'status', k."status", 'transactionId', k."bank_transaction_id", 'createdBy', k."created_by", 'createdAt', k."created_at", 'postedAt', k."posted_at", 'reconciledAt', k."reconciled_at", 'items', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'invoiceId', y."invoice_id", 'partyId', y."party_id", 'creditorName', y."creditor_name", 'creditorIban', y."creditor_iban", 'creditorBic', y."creditor_bic", 'amount', y."amount"::text, 'discount', y."discount"::text, 'currency', y."currency", 'endToEndId', y."end_to_end_id", 'remittance', y."remittance", 'status', y."status") order by y."creditor_name", y."id") from "better_supabase"."payment_batch_items" y where y."batch_id" = k."id"), '[]'::jsonb)) order by k."created_at" desc, k."id")
    from (
      select * from "better_supabase"."payment_batches" x
      where x."tenant_id" = list_payment_batches.tenant and (list_payment_batches.status is null or x."status" = list_payment_batches.status)
      order by x."created_at" desc, x."id"
      limit least(greatest(coalesce(list_payment_batches.page_size, 50), 1), 200)
    ) k
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.match_bank_transaction (
  transaction_id uuid,
  matches        jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."bank_transactions"%rowtype;
  v_match "better_supabase"."bank_matches"%rowtype;
  v_invoice "better_supabase"."invoices"%rowtype;
  v_reimbursed timestamptz;
  v_currency text;
  v_batch "better_supabase"."payment_batches"%rowtype;
  v_group record;
  v_item jsonb;
  v_amount bigint;
  v_sum bigint := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."bank_transactions" x where x."id" = match_bank_transaction.transaction_id for update;
  if not found then
    raise exception 'no such bank transaction' using errcode = 'P0002', hint = 'BANK_TRANSACTION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'banking.reconcile'), false))) then
    raise exception 'not allowed to reconcile bank transactions' using errcode = '42501', hint = 'BANKING_FORBIDDEN';
  end if;
  if v_row."status" <> 'unmatched' then
    raise exception 'a % bank transaction can''t be matched', v_row."status" using errcode = '55000', hint = 'BANK_TRANSACTION_STATUS_INVALID', detail = jsonb_build_object('status', v_row."status", 'action', 'matched')::text;
  end if;
  if jsonb_typeof(match_bank_transaction.matches) is distinct from 'array' or jsonb_array_length(match_bank_transaction.matches) = 0 then
    raise exception 'matches is a non-empty array' using errcode = '22023', hint = 'BANK_TRANSACTION_MATCH_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_bank_transaction_match"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using v_row."id", match_bank_transaction.matches;
    end if;
  end;
  for v_item in select value from jsonb_array_elements(match_bank_transaction.matches) loop
    if coalesce(v_item ->> 'targetType', '') not in ('invoice', 'accounting_entry', 'expense_report', 'payment_batch')
      or coalesce(v_item ->> 'targetId', '') !~ '^[0-9a-fA-F-]{36}$'
      or coalesce(v_item ->> 'amount', '0') !~ '^-?[0-9]{1,18}$' then
      raise exception 'a match has a targetType (invoice, accounting_entry, expense_report, payment_batch), a targetId and an integer amount' using errcode = '22023', hint = 'BANK_TRANSACTION_MATCH_INVALID';
    end if;
    v_amount := coalesce((v_item ->> 'amount')::bigint,
      case when jsonb_array_length(match_bank_transaction.matches) = 1 then v_row."amount" end);
    if v_amount is null or v_amount = 0 or sign(v_amount) <> sign(v_row."amount") then
      raise exception 'a match''s amount is nonzero and has the transaction''s sign' using errcode = '22023', hint = 'BANK_TRANSACTION_MATCH_INVALID';
    end if;
    v_sum := v_sum + v_amount;
    insert into "better_supabase"."bank_matches" ("tenant_id", "transaction_id", "target_type", "target_id", "amount", "created_by")
    values (v_row."tenant_id", v_row."id", v_item ->> 'targetType', (v_item ->> 'targetId')::uuid, v_amount, auth.uid())
    returning * into v_match;
    if v_match."target_type" = 'invoice' then
      select * into v_invoice from "better_supabase"."invoices" x
      where x."id" = v_match."target_id" and x."tenant_id" = v_row."tenant_id";
      if not found then
        raise exception 'no such invoice in the organization' using errcode = '22023', hint = 'BANK_TRANSACTION_MATCH_INVALID';
      end if;
      perform "better_supabase"."record_invoice_payment"(v_invoice."id", v_match."amount" * case when v_invoice."direction" = 'purchase' then -1 else 1 end,
        v_row."currency", v_row."booked_on"::timestamptz, 'bank_transfer',
        'bank-match:' || v_match."id"::text,
        left(v_row."remittance", 500));
    elsif v_match."target_type" = 'accounting_entry' then
      if not exists (
        select 1 from "better_supabase"."accounting_entries" x
        where x."id" = v_match."target_id" and x."tenant_id" = v_row."tenant_id" and x."status" = 'posted'
      ) then
        raise exception 'no such posted accounting entry in the organization' using errcode = '22023', hint = 'BANK_TRANSACTION_MATCH_INVALID';
      end if;
    elsif v_match."target_type" = 'expense_report' then
      select x."reimbursed_at", x."currency" into v_reimbursed, v_currency from "better_supabase"."expense_reports" x
      where x."id" = v_match."target_id" and x."tenant_id" = v_row."tenant_id";
      if not found or v_currency <> v_row."currency" then
        raise exception 'no such expense report in the organization and currency' using errcode = '22023', hint = 'BANK_TRANSACTION_MATCH_INVALID';
      end if;
      if v_reimbursed is null then
        perform "better_supabase"."reimburse_expense_report"(v_match."target_id", v_row."booked_on"::timestamptz,
          'bank-match:' || v_match."id"::text);
      end if;
    elsif v_match."target_type" = 'payment_batch' then
      select * into v_batch from "better_supabase"."payment_batches" x
      where x."id" = v_match."target_id" and x."tenant_id" = v_row."tenant_id" for update;
      if not found or v_batch."status" <> 'posted'
        or v_batch."bank_account_id" <> v_row."account_id" or v_batch."currency" <> v_row."currency"
        or -v_match."amount" <> v_batch."total" then
        raise exception 'the match must name a posted payment batch of the account and currency, for its total' using errcode = '22023', hint = 'BANK_TRANSACTION_MATCH_INVALID';
      end if;
      for v_group in
        select y."party_id" as party, sum(y."amount")::bigint as amount,
          jsonb_agg(jsonb_build_object('invoiceId', y."invoice_id", 'amount', y."amount"::text) order by y."id") as allocations
        from "better_supabase"."payment_batch_items" y where y."batch_id" = v_batch."id" and y."status" = 'posted'
        group by y."party_id" order by y."party_id"
      loop
        perform "better_supabase"."allocate_payment"(v_row."tenant_id", jsonb_build_object('partyId', v_group.party, 'side', 'supplier',
          'amount', v_group.amount::text, 'currency', v_row."currency", 'receivedOn', v_row."booked_on",
          'reference', 'payment-batch:' || v_batch."id"::text || ':' || v_group.party, 'method', 'sepa_credit_transfer',
          'note', left(v_batch."reference", 500)), v_group.allocations, null);
      end loop;
      update "better_supabase"."payment_batch_items" y set "status" = 'paid' where y."batch_id" = v_batch."id" and y."status" = 'posted';
      update "better_supabase"."payment_batches" y set "status" = 'reconciled', "bank_transaction_id" = v_row."id", "reconciled_at" = now() where y."id" = v_batch."id";
    end if;
  end loop;
  if v_sum <> v_row."amount" then
    raise exception 'the matches must add up to the transaction''s amount' using errcode = '22023', hint = 'BANK_TRANSACTION_MATCH_INVALID';
  end if;
  update "better_supabase"."bank_transactions" x set "status" = 'matched', "matched_at" = now(), "matched_by" = auth.uid(), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('bank_transaction.matched', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'accountId', v_row."account_id", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'status', v_row."status", 'matches', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'transactionId', y."transaction_id", 'targetType', y."target_type", 'targetId', y."target_id", 'amount', y."amount"::text, 'createdBy', y."created_by", 'createdAt', y."created_at") order by y."created_at", y."id") from "better_supabase"."bank_matches" y where y."transaction_id" = v_row."id"), '[]'::jsonb), 'ruleId', null), 'bank-transactions/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/banking');
  perform better_supabase.audit_event(
    event_type => 'bank_transaction.matched',
    category => 'billing',
    target_type => 'bank_transaction',
    record_id => v_row."id"::text,
    target_label => v_row."booked_on"::text || ' ' || v_row."amount"::text || ' ' || v_row."currency",
    summary => 'matched a bank transaction',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'accountId', v_row."account_id", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'status', v_row."status", 'matches', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'transactionId', y."transaction_id", 'targetType', y."target_type", 'targetId', y."target_id", 'amount', y."amount"::text, 'createdBy', y."created_by", 'createdAt', y."created_at") order by y."created_at", y."id") from "better_supabase"."bank_matches" y where y."transaction_id" = v_row."id"), '[]'::jsonb), 'ruleId', null)
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_bank_transaction_match"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'accountId', v_row."account_id", 'statementId', v_row."statement_id", 'bookedOn', v_row."booked_on", 'valueOn', v_row."value_on", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'counterpartyName', v_row."counterparty_name", 'counterpartyIban', v_row."counterparty_iban", 'remittance', v_row."remittance", 'structuredReference', v_row."structured_reference", 'endToEndId', v_row."end_to_end_id", 'externalId', v_row."external_id", 'status', v_row."status", 'ruleId', v_row."rule_id", 'matchedAt', v_row."matched_at", 'matchedBy', v_row."matched_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'matches', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'transactionId', y."transaction_id", 'targetType', y."target_type", 'targetId', y."target_id", 'amount', y."amount"::text, 'createdBy', y."created_by", 'createdAt', y."created_at") order by y."created_at", y."id") from "better_supabase"."bank_matches" y where y."transaction_id" = v_row."id"), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.open_item_ageing (
  tenant uuid,
  side   text DEFAULT NULL::text,
  as_of  date DEFAULT NULL::date
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object('side', k.side, 'partyId', k.party, 'currency', k.currency,
        'current', k.cur::text, 'days1To30', k.d30::text, 'days31To60', k.d60::text, 'days61To90', k.d90::text,
        'over90', k.over::text, 'unallocated', k.unal::text, 'outstanding', k.total::text)
      order by k.side, k.party, k.currency)
    from (
      select r.side, r."partyId" as party, r.currency,
        coalesce(sum(r.balance) filter (where r.bucket = 'current'), 0) as cur,
        coalesce(sum(r.balance) filter (where r.bucket = 'days1To30'), 0) as d30,
        coalesce(sum(r.balance) filter (where r.bucket = 'days31To60'), 0) as d60,
        coalesce(sum(r.balance) filter (where r.bucket = 'days61To90'), 0) as d90,
        coalesce(sum(r.balance) filter (where r.bucket = 'over90'), 0) as over,
        coalesce(sum(r.balance) filter (where r.bucket = 'unallocated'), 0) as unal,
        coalesce(sum(r.balance), 0) as total
      from jsonb_to_recordset("better_supabase"."open_items_for_party"(open_item_ageing.tenant, null, open_item_ageing.as_of, open_item_ageing.side))
        as r(side text, "partyId" text, currency text, balance bigint, bucket text)
      group by r.side, r."partyId", r.currency
    ) k
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.open_items_for_party (
  tenant   uuid,
  party_id text DEFAULT NULL::text,
  as_of    date DEFAULT NULL::date,
  side     text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_as_of date := coalesce(open_items_for_party.as_of, current_date);
begin
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', open_items_for_party.tenant, 'invoices.read'), false)) then
    raise exception 'not allowed to read this organization''s invoices' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  if open_items_for_party.side is not null and open_items_for_party.side not in ('customer', 'supplier') then
    raise exception 'side is customer or supplier' using errcode = '22023', hint = 'INVOICE_OPEN_ITEMS_INVALID';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
        'side', e.side, 'partyId', e.party, 'documentType', e.document_type, 'documentId', e.id,
        'identifier', e.identifier, 'currency', e.currency, 'issuedOn', e.issued_on, 'dueOn', e.due_on,
        'amount', e.gross::text, 'balance', e.balance::text, 'daysOverdue', e.days,
        'bucket', case when e.document_type = 'unallocated_payment' then 'unallocated'
          when e.days <= 0 then 'current' when e.days <= 30 then 'days1To30' when e.days <= 60 then 'days31To60'
          when e.days <= 90 then 'days61To90' else 'over90' end,
        'discountDueOn', e.discount_due_on, 'discountAmount', e.discount_amount::text,
        'legalEntityId', e.entity, 'approvalStatus', e.approval)
      order by e.side, e.party, e.due_on nulls last, e.id)
    from (
      select d.*, case when d.due_on is null then 0 else v_as_of - d.due_on end as days
      from (
        select 'invoice'::text as document_type, x."id" as id, case when x."direction" = 'purchase' then 'supplier' else 'customer' end as side, coalesce(x."company_id"::text, x."contact_id"::text) as party,
          x."identifier"::text as identifier, x."currency"::text as currency, x."issued_on" as issued_on, x."due_on" as due_on,
          (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total")::bigint as gross,
          (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - (select coalesce(-sum(e."amount"), 0)::bigint from "better_supabase"."ledger_entries" e
      join "better_supabase"."ledger_accounts" a on a."id" = e."account_id"
      join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
      where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text
        and (y."effective_at" at time zone 'UTC')::date <= v_as_of))::bigint as balance,
          x."discount_due_on" as discount_due_on,
          coalesce(x."discount_amount_early", 0)::bigint as discount_amount,
          x.legal_entity_id as entity,
          case when x."direction" = 'purchase' then "better_supabase"."invoice_approval_state"(x."id") ->> 'status' end as approval
        from "better_supabase"."invoices" x
        where x."tenant_id" = open_items_for_party.tenant
          and x."kind" = 'invoice'
          and x."status" in ('issued', 'partially_paid', 'paid')
          and x."issued_on" <= v_as_of
          and (open_items_for_party.party_id is null or (x."company_id"::text = open_items_for_party.party_id or x."contact_id"::text = open_items_for_party.party_id))
        union all
        select 'unallocated_payment'::text, a."id", 'customer'::text, a."holder_id", null::text, a."unit"::text,
          null::date, null::date, (-c.amount)::bigint, (-c.amount)::bigint, null::date, 0::bigint, null::uuid, null::text
        from "better_supabase"."ledger_accounts" a
        cross join lateral (
          select coalesce(-sum(e."amount"), 0)::bigint as amount from "better_supabase"."ledger_entries" e
          join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
          where e."account_id" = a."id" and (y."effective_at" at time zone 'UTC')::date <= v_as_of
        ) c
        where a."tenant_id" = open_items_for_party.tenant and a."managed_by" = 'invoices'
          and a."holder_type" = 'invoice_party'
          and (open_items_for_party.party_id is null or a."holder_id" = open_items_for_party.party_id)
          and c.amount > 0
      ) d
      where d.balance <> 0
    ) e
    where open_items_for_party.side is null or e.side = open_items_for_party.side
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.operation_permission (
  op text
)
  RETURNS text
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select case op
    when 'access-requests.create' then 'access_requests.create'
    when 'access-requests.emergency' then 'access_requests.emergency'
    when 'access-requests.manage' then 'access_requests.manage'
    when 'access-requests.read' then 'access_requests.read'
    when 'access-requests.review' then 'access_requests.review'
    when 'accounting.close' then 'accounting.close'
    when 'accounting.manage' then 'accounting.manage'
    when 'accounting.post' then 'accounting.post'
    when 'accounting.read' then 'accounting.read'
    when 'accounting.write' then 'accounting.write'
    when 'acknowledgements.acknowledge' then 'acknowledgements.acknowledge'
    when 'acknowledgements.manage' then 'acknowledgements.manage'
    when 'acknowledgements.read' then 'acknowledgements.read'
    when 'activities.manage' then 'activities.manage'
    when 'activities.read' then 'activities.read'
    when 'activities.readRestricted' then 'activities.read_restricted'
    when 'activities.write' then 'activities.write'
    when 'agents.create' then 'agents.write'
    when 'agents.moderate' then 'agents.moderate'
    when 'agents.publish' then 'agents.publish'
    when 'agents.read' then 'agents.read'
    when 'ai-chat.admin' then 'ai_chat.manage'
    when 'ai-chat.create' then 'ai_chat.create'
    when 'ai-chat.moderate' then 'ai_chat.moderate'
    when 'ai-chat.read' then 'ai_chat.read'
    when 'ai-chat.share' then 'ai_chat.share'
    when 'ai-files.manage' then 'ai_files.manage'
    when 'ai-files.upload' then 'ai_files.upload'
    when 'ai-keys.manage' then 'ai_keys.manage'
    when 'ai-keys.use' then 'ai_keys.use'
    when 'ai-schedules.create' then 'ai_schedules.write'
    when 'ai-schedules.manage' then 'ai_schedules.manage'
    when 'announcements.manage' then 'announcements.manage'
    when 'api-keys.manage' then 'api_keys.manage'
    when 'api-keys.own' then 'api_keys.own'
    when 'approvals.manage' then 'approvals.manage'
    when 'approvals.read' then 'approvals.read'
    when 'approvals.request' then 'approvals.request'
    when 'assets.assign' then 'assets.assign'
    when 'assets.manage' then 'assets.manage'
    when 'assets.read' then 'assets.read'
    when 'assignment.assign' then 'assignment.assign'
    when 'assignment.manage' then 'assignment.manage'
    when 'assignment.read' then 'assignment.read'
    when 'attachments.manage' then 'attachments.manage'
    when 'attachments.read' then 'attachments.read'
    when 'attachments.upload' then 'attachments.upload'
    when 'audit.revert' then 'audit.revert'
    when 'audit.view' then 'audit.read'
    when 'audit.viewAll' then 'audit.read'
    when 'automations.admin' then 'automations.manage'
    when 'automations.edit' then 'automations.write'
    when 'automations.publish' then 'automations.publish'
    when 'automations.read' then 'automations.read'
    when 'banking.import' then 'banking.import'
    when 'banking.manage' then 'banking.manage'
    when 'banking.read' then 'banking.read'
    when 'banking.reconcile' then 'banking.reconcile'
    when 'billable-time.invoice' then 'billable_time.invoice'
    when 'billable-time.manage' then 'billable_time.manage'
    when 'billable-time.read' then 'billable_time.read'
    when 'bookings.create' then 'bookings.create'
    when 'bookings.manage' then 'bookings.manage'
    when 'bookings.read' then 'bookings.read'
    when 'bulk.run' then 'bulk.run'
    when 'calendar.manage' then 'calendar.manage'
    when 'calendar.read' then 'calendar.read'
    when 'calendar.write' then 'calendar.write'
    when 'care-plans.evaluate' then 'care_plans.evaluate'
    when 'care-plans.manage' then 'care_plans.manage'
    when 'care-plans.publish' then 'care_plans.publish'
    when 'care-plans.read' then 'care_plans.read'
    when 'care-plans.write' then 'care_plans.write'
    when 'cases.close' then 'cases.close'
    when 'cases.create' then 'cases.create'
    when 'cases.manage' then 'cases.manage'
    when 'cases.read' then 'cases.read'
    when 'cases.write' then 'cases.write'
    when 'catalog.manage' then 'catalog.manage'
    when 'catalog.read' then 'catalog.read'
    when 'channels.create' then 'channels.create'
    when 'channels.manage' then 'channels.manage'
    when 'channels.read' then 'messages.read'
    when 'comments.create' then 'messages.send'
    when 'comments.moderate' then 'messages.moderate'
    when 'comments.read' then 'messages.read'
    when 'compliance.collect' then 'compliance.collect'
    when 'compliance.manage' then 'compliance.manage'
    when 'compliance.read' then 'compliance.read'
    when 'connectors.manage' then 'connectors.manage'
    when 'connectors.read' then 'connectors.read'
    when 'connectors.use' then 'connectors.use'
    when 'consents.manage' then 'consents.manage'
    when 'consents.read' then 'consents.read'
    when 'consents.record' then 'consents.record'
    when 'contacts.approveSupplier' then 'contacts.approve_supplier'
    when 'contacts.manage' then 'contacts.manage'
    when 'contacts.read' then 'contacts.read'
    when 'contacts.write' then 'contacts.write'
    when 'content.publish' then 'content.publish'
    when 'content.read' then 'content.read'
    when 'content.write' then 'content.write'
    when 'contracts.manage' then 'contracts.manage'
    when 'contracts.read' then 'contracts.read'
    when 'contracts.write' then 'contracts.write'
    when 'courses.enroll' then 'courses.enroll'
    when 'courses.manage' then 'courses.manage'
    when 'courses.read' then 'courses.read'
    when 'custom-fields.manage' then 'custom_fields.manage'
    when 'custom-fields.read' then 'custom_fields.read'
    when 'custom-fields.sensitive' then 'custom_fields.read_sensitive'
    when 'dam.read' then 'dam.read'
    when 'dam.write' then 'dam.write'
    when 'data-lifecycle.cancelDelete' then 'organization.delete'
    when 'data-lifecycle.delete' then 'organization.delete'
    when 'data-lifecycle.export' then 'data_lifecycle.export'
    when 'deals.manage' then 'deals.manage'
    when 'deals.read' then 'deals.read'
    when 'deals.write' then 'deals.write'
    when 'dispatch.manage' then 'dispatch.manage'
    when 'dispatch.read' then 'dispatch.read'
    when 'dispatch.work' then 'dispatch.work'
    when 'document-templates.manage' then 'document_templates.manage'
    when 'document-templates.read' then 'document_templates.read'
    when 'documents.manage' then 'documents.manage'
    when 'documents.read' then 'documents.read'
    when 'documents.suggest' then 'documents.suggest'
    when 'documents.write' then 'documents.write'
    when 'donations.manage' then 'donations.manage'
    when 'donations.read' then 'donations.read'
    when 'drive.create' then 'drive.create'
    when 'drive.manage' then 'drive.manage'
    when 'drive.read' then 'drive.read'
    when 'employees.read' then 'employees.read'
    when 'employees.viewSensitive' then 'employees.read_sensitive'
    when 'employees.write' then 'employees.write'
    when 'enrichment.read' then 'enrichment.read'
    when 'enrichment.run' then 'enrichment.run'
    when 'enrollments.enroll' then 'enrollments.enroll'
    when 'enrollments.manage' then 'enrollments.manage'
    when 'enrollments.read' then 'enrollments.read'
    when 'expenses.approve' then 'expenses.approve'
    when 'expenses.manage' then 'expenses.manage'
    when 'expenses.read' then 'expenses.read'
    when 'expenses.submit' then 'expenses.submit'
    when 'field-history.read' then 'field_history.read'
    when 'flags.manage' then 'flags.manage'
    when 'forecasts.read' then 'forecasts.read'
    when 'forecasts.snapshot' then 'forecasts.snapshot'
    when 'forms.manage' then 'forms.manage'
    when 'forms.read' then 'forms.read'
    when 'forms.review' then 'forms.review'
    when 'forms.submit' then 'forms.submit'
    when 'funding.approve' then 'funding.approve'
    when 'funding.claim' then 'funding.claim'
    when 'funding.manage' then 'funding.manage'
    when 'funding.read' then 'funding.read'
    when 'funding.register' then 'funding.register'
    when 'funding.write' then 'funding.write'
    when 'goals.manage' then 'goals.manage'
    when 'goals.read' then 'goals.read'
    when 'guests.manage' then 'guests.manage'
    when 'guests.read' then 'guests.read'
    when 'hiring.manage' then 'hiring.manage'
    when 'hiring.read' then 'hiring.read'
    when 'hiring.write' then 'hiring.write'
    when 'imports.manage' then 'imports.manage'
    when 'inbox.assign' then 'inbox.assign'
    when 'inbox.manage' then 'inbox.manage'
    when 'inbox.read' then 'inbox.read'
    when 'inbox.reply' then 'inbox.reply'
    when 'incidents.manage' then 'incidents.manage'
    when 'incidents.read' then 'incidents.read'
    when 'incidents.write' then 'incidents.write'
    when 'inspections.manage' then 'inspections.manage'
    when 'inspections.read' then 'inspections.read'
    when 'inspections.write' then 'inspections.write'
    when 'inventory.manage' then 'inventory.manage'
    when 'inventory.purchase' then 'inventory.purchase'
    when 'inventory.read' then 'inventory.read'
    when 'inventory.reserve' then 'inventory.reserve'
    when 'invitations.invite' then 'members.invite'
    when 'invitations.invitePlatform' then 'platform.invite'
    when 'invitations.revoke' then 'members.invite'
    when 'invitations.view' then 'members.invite'
    when 'invoices.approve' then 'invoices.approve'
    when 'invoices.collect' then 'invoices.collect'
    when 'invoices.manage' then 'invoices.manage'
    when 'invoices.overrideMatch' then 'invoices.override_match'
    when 'invoices.purchase' then 'invoices.purchase'
    when 'invoices.read' then 'invoices.read'
    when 'invoices.write' then 'invoices.write'
    when 'knowledge.manage' then 'knowledge.manage'
    when 'knowledge.read' then 'knowledge.read'
    when 'knowledge.write' then 'knowledge.write'
    when 'leases.maintain' then 'leases.maintain'
    when 'leases.manage' then 'leases.manage'
    when 'leases.read' then 'leases.read'
    when 'ledger.manage' then 'ledger.manage'
    when 'ledger.post' then 'ledger.post'
    when 'ledger.read' then 'ledger.read'
    when 'legal-entities.manage' then 'legal_entities.manage'
    when 'legal-entities.read' then 'legal_entities.read'
    when 'mail-sync.connect' then 'mail_sync.connect'
    when 'mail-sync.manage' then 'mail_sync.manage'
    when 'mail-sync.read' then 'mail_sync.read'
    when 'mail-sync.send' then 'mail_sync.send'
    when 'maintenance.manage' then 'maintenance.manage'
    when 'maintenance.read' then 'maintenance.read'
    when 'maintenance.record' then 'maintenance.record'
    when 'manufacturing.manage' then 'manufacturing.manage'
    when 'manufacturing.produce' then 'manufacturing.produce'
    when 'manufacturing.read' then 'manufacturing.read'
    when 'manufacturing.write' then 'manufacturing.write'
    when 'medications.administer' then 'medications.administer'
    when 'medications.manage' then 'medications.manage'
    when 'medications.prescribe' then 'medications.prescribe'
    when 'medications.read' then 'medications.read'
    when 'meetings.manage' then 'meetings.manage'
    when 'meetings.read' then 'meetings.read'
    when 'meetings.write' then 'meetings.write'
    when 'memory.manage' then 'memory.manage'
    when 'memory.read' then 'memory.read'
    when 'messaging.moderate' then 'messages.moderate'
    when 'messaging.read' then 'messages.read'
    when 'messaging.send' then 'messages.send'
    when 'metrics.manage' then 'metrics.manage'
    when 'metrics.read' then 'metrics.read'
    when 'moderation.ban' then 'moderation.ban'
    when 'moderation.manage' then 'moderation.manage'
    when 'moderation.read' then 'moderation.read'
    when 'moderation.report' then 'moderation.report'
    when 'notifications.read' then 'notifications.read'
    when 'notifications.send' then 'notifications.send'
    when 'numbering.assign' then 'numbering.assign'
    when 'observations.manage' then 'observations.manage'
    when 'observations.read' then 'observations.read'
    when 'observations.record' then 'observations.record'
    when 'onboarding.complete' then 'onboarding.complete'
    when 'onboarding.read' then 'onboarding.read'
    when 'orders.manage' then 'orders.manage'
    when 'orders.overrideCredit' then 'orders.override_credit'
    when 'orders.prepare' then 'orders.prepare'
    when 'orders.read' then 'orders.read'
    when 'organizations.delete' then 'organization.delete'
    when 'organizations.listMembers' then 'members.read'
    when 'organizations.removeMember' then 'members.remove'
    when 'organizations.suspendMember' then 'members.remove'
    when 'organizations.transferOwnership' then 'organization.transfer_ownership'
    when 'organizations.update' then 'organization.update'
    when 'organizations.updateRole' then 'members.update_role'
    when 'passes.checkIn' then 'passes.check_in'
    when 'passes.manage' then 'passes.manage'
    when 'passes.read' then 'passes.read'
    when 'payroll-export.export' then 'payroll_export.export'
    when 'payroll-export.read' then 'payroll_export.read'
    when 'permissions.listRoles' then 'members.read'
    when 'permissions.setOverride' then 'roles.manage'
    when 'pipelines.manage' then 'pipelines.manage'
    when 'pipelines.read' then 'pipelines.read'
    when 'posts.manage' then 'posts.manage'
    when 'posts.moderate' then 'posts.moderate'
    when 'posts.read' then 'posts.read'
    when 'posts.write' then 'posts.write'
    when 'promotions.manage' then 'promotions.manage'
    when 'promotions.read' then 'promotions.read'
    when 'qualifications.grant' then 'qualifications.grant'
    when 'qualifications.manage' then 'qualifications.manage'
    when 'qualifications.read' then 'qualifications.read'
    when 'quotes.manage' then 'quotes.manage'
    when 'quotes.read' then 'quotes.read'
    when 'quotes.write' then 'quotes.write'
    when 'reactions.create' then 'reactions.create'
    when 'reactions.manage' then 'reactions.manage'
    when 'reactions.read' then 'reactions.read'
    when 'relations.manage' then 'relations.manage'
    when 'relations.read' then 'relations.read'
    when 'reminders.manage' then 'reminders.manage'
    when 'reminders.read' then 'reminders.read'
    when 'risks.assess' then 'risks.assess'
    when 'risks.manage' then 'risks.manage'
    when 'risks.read' then 'risks.read'
    when 'risks.write' then 'risks.write'
    when 'saved-views.read' then 'saved_views.read'
    when 'saved-views.share' then 'saved_views.share'
    when 'scores.compute' then 'scores.compute'
    when 'scores.manage' then 'scores.manage'
    when 'scores.read' then 'scores.read'
    when 'search.read' then 'search.read'
    when 'segments.edit' then 'segments.write'
    when 'segments.read' then 'segments.read'
    when 'sequences.enroll' then 'sequences.enroll'
    when 'sequences.manage' then 'sequences.manage'
    when 'sequences.read' then 'sequences.read'
    when 'service-accounts.manage' then 'service_accounts.manage'
    when 'service-accounts.read' then 'service_accounts.read'
    when 'settings.platform' then 'settings.manage'
    when 'settings.read' then 'settings.read'
    when 'settings.update' then 'settings.update'
    when 'share-links.create' then 'share_links.create'
    when 'share-links.read' then 'share_links.read'
    when 'shifts.manage' then 'shifts.manage'
    when 'shifts.read' then 'shifts.read'
    when 'shifts.request' then 'shifts.request'
    when 'shifts.write' then 'shifts.write'
    when 'shipments.manage' then 'shipments.manage'
    when 'shipments.read' then 'shipments.read'
    when 'signatures.manage' then 'signatures.manage'
    when 'signatures.read' then 'signatures.read'
    when 'signatures.request' then 'signatures.request'
    when 'sla.manage' then 'sla.manage'
    when 'sla.read' then 'sla.read'
    when 'sso.manage' then 'sso.manage'
    when 'subjects.manage' then 'subjects.manage'
    when 'tags.apply' then 'tags.apply'
    when 'tags.manage' then 'tags.manage'
    when 'tags.read' then 'tags.read'
    when 'tasks.manage' then 'tasks.manage'
    when 'tasks.read' then 'tasks.read'
    when 'tasks.write' then 'tasks.write'
    when 'tax.manage' then 'tax.manage'
    when 'tax.read' then 'tax.read'
    when 'teams.manage' then 'teams.manage'
    when 'teams.read' then 'teams.read'
    when 'templates.apply' then 'templates.apply'
    when 'templates.manage' then 'templates.manage'
    when 'templates.read' then 'templates.read'
    when 'time-tracking.approve' then 'time_tracking.approve'
    when 'time-tracking.manage' then 'time_tracking.manage'
    when 'time-tracking.read' then 'time_tracking.read'
    when 'time-tracking.track' then 'time_tracking.track'
    when 'timeline.read' then 'timeline.read'
    when 'trash.create' then 'trash.create'
    when 'trash.manage' then 'trash.manage'
    when 'trash.read' then 'trash.read'
    when 'trash.restore' then 'trash.restore'
    when 'usage.read' then 'usage.read'
    when 'usage.record' then 'usage.record'
    when 'versions.create' then 'versions.create'
    when 'versions.manage' then 'versions.manage'
    when 'versions.read' then 'versions.read'
    when 'versions.restore' then 'versions.restore'
    when 'waitlist.invite' then 'waitlist.invite'
    when 'waitlist.manage' then 'waitlist.manage'
    when 'webhooks-out.manage' then 'webhooks.manage'
    when 'webhooks-out.view' then 'webhooks.read'
    when 'workflow-editor.admin' then 'workflow_editor.manage'
    when 'workflow-editor.edit' then 'workflow_editor.write'
    when 'workflow-editor.publish' then 'workflow_editor.publish'
    when 'workflow-editor.read' then 'workflow_editor.read'
    when 'workflow-editor.run' then 'workflow_editor.run'
    when 'workflows.admin' then 'workflows.manage'
    when 'workflows.read' then 'workflows.read'
    when 'workflows.run' then 'workflows.run'
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.post_payment_batch (
  batch_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_batch "better_supabase"."payment_batches"%rowtype;
  v_item record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_batch from "better_supabase"."payment_batches" x where x."id" = post_payment_batch.batch_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_batch."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_batch."tenant_id", 'banking.reconcile'), false))) then
    raise exception 'no such payment batch' using errcode = 'P0002', hint = 'PAYMENT_BATCH_NOT_FOUND';
  end if;
  if v_batch."status" <> 'draft' then
    raise exception 'only a draft batch is posted' using errcode = '55000', hint = 'PAYMENT_BATCH_STATUS_INVALID',
      detail = jsonb_build_object('status', v_batch."status")::text;
  end if;
  for v_item in select y."invoice_id" as invoice_id from "better_supabase"."payment_batch_items" y where y."batch_id" = v_batch."id" loop
    if coalesce("better_supabase"."invoice_approval_state"(v_item.invoice_id) ->> 'status', 'not_required') = 'pending' then
      raise exception 'a bill in the batch still needs approval' using errcode = '55000', hint = 'PAYMENT_BATCH_APPROVAL_REQUIRED',
        detail = jsonb_build_object('invoiceId', v_item.invoice_id)::text;
    end if;
  end loop;
  update "better_supabase"."payment_batch_items" y set "status" = 'posted' where y."batch_id" = v_batch."id" and y."status" = 'open';
  update "better_supabase"."payment_batches" y set "status" = 'posted', "posted_at" = now() where y."id" = v_batch."id" returning * into v_batch;
  return jsonb_build_object('id', v_batch."id", 'organizationId', v_batch."tenant_id", 'accountId', v_batch."bank_account_id", 'reference', v_batch."reference", 'messageId', v_batch."message_id", 'currency', v_batch."currency", 'dueBy', v_batch."due_by", 'executionOn', v_batch."execution_on", 'total', v_batch."total"::text, 'itemCount', v_batch."item_count", 'status', v_batch."status", 'transactionId', v_batch."bank_transaction_id", 'createdBy', v_batch."created_by", 'createdAt', v_batch."created_at", 'postedAt', v_batch."posted_at", 'reconciledAt', v_batch."reconciled_at", 'items', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'invoiceId', y."invoice_id", 'partyId', y."party_id", 'creditorName', y."creditor_name", 'creditorIban', y."creditor_iban", 'creditorBic', y."creditor_bic", 'amount', y."amount"::text, 'discount', y."discount"::text, 'currency', y."currency", 'endToEndId', y."end_to_end_id", 'remittance', y."remittance", 'status', y."status") order by y."creditor_name", y."id") from "better_supabase"."payment_batch_items" y where y."batch_id" = v_batch."id"), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purchase_invoice_approval_status (
  invoice uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."invoices";
begin
  select * into v_row from "better_supabase"."invoices" x where x."id" = purchase_invoice_approval_status.invoice and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.read'), false));
  if v_row."id" is null then
    raise exception 'no such invoice you can read' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  return "better_supabase"."invoice_approval_state"(v_row."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_invoice_approval_levels (
  tenant          uuid,
  levels          jsonb,
  legal_entity_id uuid  DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', set_invoice_approval_levels.tenant, 'invoices.manage'), false)) then
    raise exception 'not allowed to manage invoices in this organization' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  if jsonb_typeof(set_invoice_approval_levels.levels) is distinct from 'array'
    or jsonb_array_length(set_invoice_approval_levels.levels) > 20
    or exists (
      select 1 from jsonb_array_elements(set_invoice_approval_levels.levels) x
      where jsonb_typeof(x.value) <> 'object'
        or coalesce(x.value ->> 'minAmount', '') !~ '^[0-9]{1,18}$'
        or coalesce(x.value ->> 'approverId', '') !~ '^[0-9a-fA-F-]{36}$'
        or (x.value ->> 'currency' is not null and upper(x.value ->> 'currency') !~ '^[A-Z]{3}$')
    ) then
    raise exception 'levels is an array of at most 20 { minAmount, currency?, approverId }' using errcode = '22023', hint = 'INVOICE_APPROVAL_LEVELS_INVALID';
  end if;
  delete from "better_supabase"."invoice_approval_levels" l
  where l."tenant_id" = set_invoice_approval_levels.tenant
    and l."legal_entity_id" is not distinct from set_invoice_approval_levels.legal_entity_id;
  insert into "better_supabase"."invoice_approval_levels" ("tenant_id", "legal_entity_id", "level", "min_amount", "currency", "approver_id")
  select set_invoice_approval_levels.tenant, set_invoice_approval_levels.legal_entity_id,
    (row_number() over (order by (x.value ->> 'minAmount')::bigint, x.ordinality))::integer,
    (x.value ->> 'minAmount')::bigint, upper(nullif(x.value ->> 'currency', '')), (x.value ->> 'approverId')::uuid
  from jsonb_array_elements(set_invoice_approval_levels.levels) with ordinality x;
  return "better_supabase"."list_invoice_approval_levels"(set_invoice_approval_levels.tenant);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.unallocate_payment (
  tenant    uuid,
  reference text,
  actor     jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid := unallocate_payment.tenant;
  v_alloc "better_supabase"."invoice_allocations"%rowtype;
  v_row "better_supabase"."invoices";
  v_reversal uuid;
  v_count integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', unallocate_payment.tenant, 'invoices.manage'), false)) then
    raise exception 'not allowed to reverse payments in this organization' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  if unallocate_payment.actor is not null then
    if jsonb_typeof(unallocate_payment.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(unallocate_payment.actor ->> 'ip', '')::inet, nullif(unallocate_payment.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(unallocate_payment.actor::text, ''), true);
  for v_alloc in
    select * from "better_supabase"."invoice_allocations" b
    where b."tenant_id" = v_tenant and b."reference" = unallocate_payment.reference and b."unallocated_at" is null
    order by b."created_at" desc, b."id"
    for update
  loop
    if v_alloc."discount_payment_id" is not null then
      select * into v_row from "better_supabase"."invoices" x where x."id" = v_alloc."invoice_id" for update;
      v_reversal := "better_supabase"."ledger_post"(v_row."tenant_id", 'invoice.payment_reversal',
    (select jsonb_agg(jsonb_build_object('account', e."account_id", 'amount', (-e."amount")::text) order by e."created_at", e."id")
      from "better_supabase"."ledger_entries" e where e."transaction_id" = v_alloc."discount_payment_id"),
    'invoices', v_row."id"::text, null, null, null,
    (select y."metadata" from "better_supabase"."ledger_transactions" y where y."id" = v_alloc."discount_payment_id") || jsonb_strip_nulls(jsonb_build_object('reversal', true, 'reason', 'Unallocated')),
    v_alloc."discount_payment_id");
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
      perform "better_supabase"."accounting_reverse_source"(v_row."tenant_id", 'invoice_discount', v_alloc."discount_payment_id"::text);
    end if;
    if v_alloc."source" = 'credit' then
      select * into v_row from "better_supabase"."invoices" x where x."id" = v_alloc."invoice_id" for update;
      v_reversal := "better_supabase"."ledger_post"(v_row."tenant_id", 'invoice.payment_reversal',
    (select jsonb_agg(jsonb_build_object('account', e."account_id", 'amount', (-e."amount")::text) order by e."created_at", e."id")
      from "better_supabase"."ledger_entries" e where e."transaction_id" = v_alloc."payment_id"),
    'invoices', v_row."id"::text, null, null, null,
    (select y."metadata" from "better_supabase"."ledger_transactions" y where y."id" = v_alloc."payment_id") || jsonb_strip_nulls(jsonb_build_object('reversal', true, 'reason', 'Unallocated')),
    v_alloc."payment_id");
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
    else
      perform "better_supabase"."reverse_invoice_payment"(v_alloc."payment_id", 'Unallocated', unallocate_payment.actor);
    end if;
    update "better_supabase"."invoice_allocations" b set "unallocated_at" = now() where b."id" = v_alloc."id";
    select * into v_row from "better_supabase"."invoices" x where x."id" = v_alloc."invoice_id";
    perform "better_supabase".emit_event('invoice.unallocated', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'reference', unallocate_payment.reference, 'amount', v_alloc."amount"::text, 'discount', v_alloc."discount"::text, 'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  perform better_supabase.audit_event(
    event_type => 'invoice.unallocated',
    category => 'billing',
    target_type => 'invoice',
    record_id => v_row."id"::text,
    target_label => v_row."identifier",
    summary => 'invoice unallocated',
    tenant => (v_row."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'reference', unallocate_payment.reference, 'amount', v_alloc."amount"::text, 'discount', v_alloc."discount"::text, 'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text)
  );
    v_count := v_count + 1;
  end loop;
  if v_count = 0 then
    raise exception 'no allocation with this reference is active' using errcode = 'P0002', hint = 'INVOICE_ALLOCATION_NOT_FOUND';
  end if;
  return jsonb_build_object('reference', unallocate_payment.reference, 'unallocated', v_count);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.unmatch_bank_transaction (
  transaction_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."bank_transactions"%rowtype;
  v_match "better_supabase"."bank_matches"%rowtype;
  v_invoice "better_supabase"."invoices"%rowtype;
  v_reimbursed timestamptz;
  v_currency text;
  v_batch "better_supabase"."payment_batches"%rowtype;
  v_group record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."bank_transactions" x where x."id" = unmatch_bank_transaction.transaction_id for update;
  if not found then
    raise exception 'no such bank transaction' using errcode = 'P0002', hint = 'BANK_TRANSACTION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'banking.reconcile'), false))) then
    raise exception 'not allowed to reconcile bank transactions' using errcode = '42501', hint = 'BANKING_FORBIDDEN';
  end if;
  if v_row."status" <> 'matched' then
    raise exception 'a % bank transaction can''t be unmatched', v_row."status" using errcode = '55000', hint = 'BANK_TRANSACTION_STATUS_INVALID', detail = jsonb_build_object('status', v_row."status", 'action', 'unmatched')::text;
  end if;
  for v_match in select * from "better_supabase"."bank_matches" y where y."transaction_id" = v_row."id" order by y."created_at", y."id" loop
    if v_match."target_type" = 'invoice' then
      select * into v_invoice from "better_supabase"."invoices" x
      where x."id" = v_match."target_id" and x."tenant_id" = v_row."tenant_id";
      if not found then
        raise exception 'no such invoice in the organization' using errcode = '22023', hint = 'BANK_TRANSACTION_MATCH_INVALID';
      end if;
      perform "better_supabase"."record_invoice_payment"(v_invoice."id", -v_match."amount" * case when v_invoice."direction" = 'purchase' then -1 else 1 end,
        v_row."currency", now(), 'bank_transfer',
        'bank-unmatch:' || v_match."id"::text,
        'Bank match undone');
    elsif v_match."target_type" = 'payment_batch' then
      select * into v_batch from "better_supabase"."payment_batches" x where x."id" = v_match."target_id" and x."tenant_id" = v_row."tenant_id";
      if found and v_batch."status" = 'reconciled' then
        for v_group in select distinct y."party_id" as party from "better_supabase"."payment_batch_items" y where y."batch_id" = v_batch."id" and y."status" = 'paid' loop
          perform "better_supabase"."unallocate_payment"(v_row."tenant_id", 'payment-batch:' || v_batch."id"::text || ':' || v_group.party, null);
        end loop;
        update "better_supabase"."payment_batch_items" y set "status" = 'posted' where y."batch_id" = v_batch."id" and y."status" = 'paid';
        update "better_supabase"."payment_batches" y set "status" = 'posted', "bank_transaction_id" = null, "reconciled_at" = null where y."id" = v_batch."id";
      end if;
    end if;
  end loop;
  if v_row."rule_id" is not null then
    perform "better_supabase"."accounting_reverse_source"(v_row."tenant_id", 'bank_transaction', v_row."id"::text);
  end if;
  delete from "better_supabase"."bank_matches" y where y."transaction_id" = v_row."id";
  update "better_supabase"."bank_transactions" x set "status" = 'unmatched', "rule_id" = null, "matched_at" = null,
    "matched_by" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('bank_transaction.unmatched', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'accountId', v_row."account_id", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'status', v_row."status"), 'bank-transactions/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/banking');
  perform better_supabase.audit_event(
    event_type => 'bank_transaction.unmatched',
    category => 'billing',
    target_type => 'bank_transaction',
    record_id => v_row."id"::text,
    target_label => v_row."booked_on"::text || ' ' || v_row."amount"::text || ' ' || v_row."currency",
    summary => 'unmatched a bank transaction',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'accountId', v_row."account_id", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'status', v_row."status")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'accountId', v_row."account_id", 'statementId', v_row."statement_id", 'bookedOn', v_row."booked_on", 'valueOn', v_row."value_on", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'counterpartyName', v_row."counterparty_name", 'counterpartyIban', v_row."counterparty_iban", 'remittance', v_row."remittance", 'structuredReference', v_row."structured_reference", 'endToEndId', v_row."end_to_end_id", 'externalId', v_row."external_id", 'status', v_row."status", 'ruleId', v_row."rule_id", 'matchedAt', v_row."matched_at", 'matchedBy', v_row."matched_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'matches', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'transactionId', y."transaction_id", 'targetType', y."target_type", 'targetId', y."target_id", 'amount', y."amount"::text, 'createdBy', y."created_by", 'createdAt', y."created_at") order by y."created_at", y."id") from "better_supabase"."bank_matches" y where y."transaction_id" = v_row."id"), '[]'::jsonb));
end;
$function$;

ALTER TABLE "better_supabase"."bank_matches"
  ADD CONSTRAINT "bank_matches_target_type_check" CHECK ((target_type = ANY (ARRAY['invoice'::text, 'accounting_entry'::text, 'expense_report'::text, 'payment_batch'::text])));

ALTER TABLE "better_supabase"."invoice_allocations"
  ADD CONSTRAINT "invoice_allocations_invoice_id_fkey" FOREIGN KEY (invoice_id) REFERENCES better_supabase.invoices(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."invoice_approvals"
  ADD CONSTRAINT "invoice_approvals_invoice_id_fkey" FOREIGN KEY (invoice_id) REFERENCES better_supabase.invoices(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."payment_batch_items"
  ADD CONSTRAINT "payment_batch_items_invoice_id_fkey" FOREIGN KEY (invoice_id) REFERENCES better_supabase.invoices(id) ON DELETE RESTRICT;

ALTER TABLE "better_supabase"."payment_batches"
  ADD CONSTRAINT "payment_batches_tenant_id_bank_account_id_fkey" FOREIGN KEY (tenant_id, bank_account_id) REFERENCES better_supabase.bank_accounts(tenant_id, id)
    ON DELETE RESTRICT;

ALTER TABLE "better_supabase"."payment_batches"
  ADD CONSTRAINT "payment_batches_tenant_id_bank_transaction_id_fkey" FOREIGN KEY (tenant_id, bank_transaction_id) REFERENCES better_supabase.bank_transactions(tenant_id, id)
    ON DELETE SET NULL (bank_transaction_id);

ALTER TABLE "better_supabase"."payment_batch_items"
  ADD CONSTRAINT "payment_batch_items_tenant_id_batch_id_fkey" FOREIGN KEY (tenant_id, batch_id) REFERENCES better_supabase.payment_batches(tenant_id, id) ON DELETE CASCADE;

CREATE INDEX invoice_allocations_invoice_idx ON better_supabase.invoice_allocations USING btree (invoice_id);

CREATE INDEX invoice_allocations_party_idx ON better_supabase.invoice_allocations USING btree (tenant_id, party_id, created_at DESC);

CREATE UNIQUE INDEX invoice_approval_levels_level_key ON better_supabase.invoice_approval_levels
  USING btree (tenant_id, COALESCE(legal_entity_id, '00000000-0000-0000-0000-000000000000'::uuid), level);

CREATE INDEX invoice_approvals_tenant_idx ON better_supabase.invoice_approvals USING btree (tenant_id, invoice_id);

CREATE INDEX payment_batch_items_invoice_idx ON better_supabase.payment_batch_items USING btree (invoice_id);

CREATE UNIQUE INDEX payment_batch_items_invoice_key ON better_supabase.payment_batch_items USING btree (invoice_id)
  WHERE (status = ANY (ARRAY['open'::text, 'posted'::text]));

CREATE INDEX payment_batch_items_parent_idx ON better_supabase.payment_batch_items USING btree (tenant_id, batch_id);

CREATE INDEX payment_batches_account_idx ON better_supabase.payment_batches USING btree (tenant_id, bank_account_id);

CREATE INDEX payment_batches_tenant_idx ON better_supabase.payment_batches USING btree (tenant_id, status, created_at);

CREATE INDEX payment_batches_transaction_idx ON better_supabase.payment_batches USING btree (tenant_id, bank_transaction_id);

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."invoice_allocations"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."invoice_allocations"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."invoice_allocations"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('invoices.read'::text)
    AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."invoice_allocations"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "invoice_allocations_read" ON "better_supabase"."invoice_allocations"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('invoices.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."invoice_approval_levels"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."invoice_approval_levels"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."invoice_approval_levels"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('invoices.read'::text)
    AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."invoice_approval_levels"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "invoice_approval_levels_read" ON "better_supabase"."invoice_approval_levels"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('invoices.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."invoice_approvals"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."invoice_approvals"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."invoice_approvals"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('invoices.read'::text)
    AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."invoice_approvals"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "invoice_approvals_read" ON "better_supabase"."invoice_approvals"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('invoices.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."payment_batch_items"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."payment_batch_items"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."payment_batch_items"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('banking.read'::text)
    AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."payment_batch_items"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "payment_batch_items_read" ON "better_supabase"."payment_batch_items"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('banking.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."payment_batches"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."payment_batches"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."payment_batches"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('banking.read'::text)
    AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."payment_batches"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "payment_batches_read" ON "better_supabase"."payment_batches"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('banking.read'::text) AS tenant_ids_with)));

REVOKE ALL ON FUNCTION "api"."allocate_payment"(uuid, jsonb, jsonb, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."allocate_payment"(uuid, jsonb, jsonb, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."approve_purchase_invoice"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."approve_purchase_invoice"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."cancel_payment_batch"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."cancel_payment_batch"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."create_payment_batch"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."create_payment_batch"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_payment_batch"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_payment_batch"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."import_open_item"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."import_open_item"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."invoice_approval_state"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."invoice_approval_state"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "api"."list_invoice_allocations"(uuid, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_invoice_allocations"(uuid, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_invoice_approval_levels"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_invoice_approval_levels"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_payment_batches"(uuid, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_payment_batches"(uuid, text, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."open_item_ageing"(uuid, text, date) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."open_item_ageing"(uuid, text, date) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."open_items_for_party"(uuid, text, date, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."open_items_for_party"(uuid, text, date, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."post_payment_batch"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."post_payment_batch"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."purchase_invoice_approval_status"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."purchase_invoice_approval_status"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_invoice_approval_levels"(uuid, jsonb, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_invoice_approval_levels"(uuid, jsonb, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."unallocate_payment"(uuid, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."unallocate_payment"(uuid, text, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."accounting_invoice_discount_lines"(text) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."allocate_payment"(uuid, jsonb, jsonb, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."allocate_payment"(uuid, jsonb, jsonb, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."approve_purchase_invoice"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."approve_purchase_invoice"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."cancel_payment_batch"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."cancel_payment_batch"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."create_payment_batch"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."create_payment_batch"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_payment_batch"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_payment_batch"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."import_open_item"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."import_open_item"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."invoice_approval_state"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."invoice_approval_state"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_invoice_allocations"(uuid, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_invoice_allocations"(uuid, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_invoice_approval_levels"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_invoice_approval_levels"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_payment_batches"(uuid, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_payment_batches"(uuid, text, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."open_item_ageing"(uuid, text, date) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."open_item_ageing"(uuid, text, date) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."open_items_for_party"(uuid, text, date, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."open_items_for_party"(uuid, text, date, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."post_payment_batch"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."post_payment_batch"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."purchase_invoice_approval_status"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."purchase_invoice_approval_status"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_invoice_approval_levels"(uuid, jsonb, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_invoice_approval_levels"(uuid, jsonb, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."unallocate_payment"(uuid, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."unallocate_payment"(uuid, text, jsonb) TO "authenticated", "service_role";

GRANT SELECT ON TABLE "better_supabase"."invoice_allocations" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."invoice_allocations" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."invoice_approval_levels" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."invoice_approval_levels" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."invoice_approvals" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."invoice_approvals" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."payment_batch_items" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."payment_batch_items" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."payment_batches" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."payment_batches" TO "service_role";
