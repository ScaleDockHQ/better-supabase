SET local check_function_bodies = off;

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
    raise exception 'the entry is already reversed' using errcode = 'PT409', hint = 'ACCOUNTING_ENTRY_REVERSED';
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

CREATE OR REPLACE FUNCTION better_supabase.add_expense_line (
  report_id   uuid,
  category_id uuid,
  spent_on    date,
  amount      bigint,
  description text,
  merchant    text   DEFAULT NULL::text,
  currency    text   DEFAULT NULL::text,
  dimensions  jsonb  DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_category "better_supabase"."expense_categories"%rowtype;
  v_line "better_supabase"."expense_lines"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."expense_reports" x where x."id" = add_expense_line.report_id for update;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (coalesce(v_row."user_id" = auth.uid(), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.submit'), false)) then
    raise exception 'only the member who owns the report can change it' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) not in ('draft', 'rejected') then
    raise exception 'only a draft or rejected report can change' using errcode = 'PT409', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  select * into v_category from "better_supabase"."expense_categories" c
    where c."id" = add_expense_line.category_id and c."tenant_id" = v_row."tenant_id" and c."archived_at" is null;
  if not found then
    raise exception 'the category is unknown, archived or not in this organization' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if v_category."currency" is not null and v_category."currency" <> v_row."currency" then
    raise exception 'the category''s policy is in another currency than the report' using errcode = '22023', hint = 'EXPENSE_CURRENCY_MISMATCH';
  end if;
  if add_expense_line.spent_on is null then
    raise exception 'a line needs spent_on' using errcode = '22023', hint = 'EXPENSE_LINE_INVALID';
  end if;
  if add_expense_line.currency is not null and add_expense_line.currency <> v_row."currency" then
    raise exception 'the amount is in another currency than the report' using errcode = '22023', hint = 'EXPENSE_CURRENCY_MISMATCH';
  end if;
  if add_expense_line.amount is null or add_expense_line.amount <= 0 then
    raise exception 'an amount is more than zero minor units' using errcode = '22023', hint = 'EXPENSE_LINE_INVALID';
  end if;
  if nullif(trim(add_expense_line.description), '') is null then
    raise exception 'a line needs a description' using errcode = '22023', hint = 'EXPENSE_LINE_INVALID';
  end if;
  if add_expense_line.dimensions is not null and jsonb_typeof(add_expense_line.dimensions) not in ('object', 'null') then
    raise exception 'dimensions is an object of dimension keys and value codes' using errcode = '22023', hint = 'EXPENSE_LINE_INVALID';
  end if;
  insert into "better_supabase"."expense_lines" ("tenant_id", "report_id", "category_id", "spent_on", "description", "merchant", "dimensions", "amount")
  values (v_row."tenant_id", v_row."id", v_category."id", add_expense_line.spent_on, trim(add_expense_line.description),
    nullif(trim(add_expense_line.merchant), ''), coalesce(nullif(add_expense_line.dimensions, 'null'::jsonb), '{}'::jsonb), add_expense_line.amount)
  returning * into v_line;
  update "better_supabase"."expense_reports" x set "updated_at" = now() where x."id" = v_row."id";
  return jsonb_build_object('id', v_line."id", 'reportId', v_line."report_id", 'categoryId', v_line."category_id", 'spentOn', v_line."spent_on", 'description', v_line."description", 'merchant', v_line."merchant", 'dimensions', v_line."dimensions", 'amount', v_line."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = v_line."report_id"), 'receipts', (select count(*) from "better_supabase"."attachments" t where t."subject_type" = 'expense_line' and t."subject_id" = v_line."id"::text and t."uploaded_at" is not null and t."status" <> 'infected'), 'createdAt', v_line."created_at", 'updatedAt', v_line."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.add_invoice_charge (
  invoice     uuid,
  amount      bigint,
  currency    text,
  description text,
  actor       jsonb  DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."invoices";
  v_charge uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."invoices" x where x."id" = add_invoice_charge.invoice;
  if v_row."id" is null or (((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", case when v_row."direction" = 'purchase' then 'invoices.purchase' else 'invoices.write' end), false))) is not true then
    if v_row."id" is not null and (((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'invoices.read'), false)) or better_supabase.row_visible('"better_supabase"."invoices"'::regclass, 'id', v_row."id")) then
      raise exception 'you may not charge this invoice' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
    end if;
    raise exception 'no such invoice you can read' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  select * into v_row from "better_supabase"."invoices" x where x."id" = add_invoice_charge.invoice for update;
  if not found then
    raise exception 'no such invoice you can read' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  if v_row."kind" <> 'invoice' or v_row."status" not in ('issued', 'partially_paid', 'paid') then
    raise exception 'only an issued invoice takes charges' using errcode = '55000', hint = 'INVOICE_NOT_CHARGEABLE';
  end if;
  if coalesce(add_invoice_charge.amount, 0) <= 0 then
    raise exception 'a charge has a positive amount' using errcode = '22023', hint = 'INVOICE_CHARGE_INVALID';
  end if;
  if upper(add_invoice_charge.currency) is distinct from v_row."currency" then
    raise exception 'a charge must be in the invoice''s currency' using errcode = '22023', hint = 'INVOICE_CURRENCY_MISMATCH';
  end if;
  if add_invoice_charge.actor is not null then
    if jsonb_typeof(add_invoice_charge.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(add_invoice_charge.actor ->> 'ip', '')::inet, nullif(add_invoice_charge.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(add_invoice_charge.actor::text, ''), true);
  insert into "better_supabase"."invoice_charges" ("tenant_id", "invoice_id", "amount", "currency", "description", "created_by")
  values (v_row."tenant_id", v_row."id", add_invoice_charge.amount, v_row."currency", nullif(trim(add_invoice_charge.description), ''), auth.uid())
  returning "id" into v_charge;
  update "better_supabase"."invoices" x set
    "paid_total" = coalesce(-(select sum(e."amount") from "better_supabase"."ledger_entries" e where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text)), 0),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if v_row."status" in ('issued', 'partially_paid', 'paid') then
    update "better_supabase"."invoices" x set
      "status" = case
      when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then 'paid'
      when x."paid_total" > 0 or x."credited_total" > 0 then 'partially_paid'
      else 'issued' end,
      "paid_at" = case when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then coalesce(x."paid_at", now()) end
    where x."id" = v_row."id"
    returning * into v_row;
  end if;
  if not better_supabase.import_run() is not null then
    perform "better_supabase"."accounting_post_source"('invoice_charge', v_charge::text);
  end if;
  perform "better_supabase".emit_event('invoice.charged', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'chargeId', v_charge, 'amount', add_invoice_charge.amount::text, 'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  perform better_supabase.audit_event(
    event_type => 'invoice.charged',
    category => 'billing',
    target_type => 'invoice',
    record_id => v_row."id"::text,
    target_label => v_row."identifier",
    summary => 'invoice charged',
    tenant => (v_row."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'chargeId', v_charge, 'amount', add_invoice_charge.amount::text, 'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text)
  );
  return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'deposit_amount', v_row."deposit_amount"::text, 'discount_amount', v_row."discount_amount"::text, 'discount_amount_early', v_row."discount_amount_early"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code", 'taxCodeId', il."tax_code_id", 'unitCost', il."unit_cost"::text, 'dimensions', il."dimensions") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb));
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
  if v_row."status" in ('issued', 'partially_paid', 'paid') then
    update "better_supabase"."invoices" x set
      "status" = case
      when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then 'paid'
      when x."paid_total" > 0 or x."credited_total" > 0 then 'partially_paid'
      else 'issued' end,
      "paid_at" = case when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then coalesce(x."paid_at", now()) end
    where x."id" = v_row."id"
    returning * into v_row;
  end if;
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
  if v_row."status" in ('issued', 'partially_paid', 'paid') then
    update "better_supabase"."invoices" x set
      "status" = case
      when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then 'paid'
      when x."paid_total" > 0 or x."credited_total" > 0 then 'partially_paid'
      else 'issued' end,
      "paid_at" = case when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then coalesce(x."paid_at", now()) end
    where x."id" = v_row."id"
    returning * into v_row;
  end if;
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

CREATE OR REPLACE FUNCTION better_supabase.apply_party_credit (
  party_id text,
  invoice  uuid,
  amount   bigint,
  actor    jsonb  DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."invoices";
  v_account uuid;
  v_payment uuid;
  v_was text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."invoices" x where x."id" = apply_party_credit.invoice and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", case when x."direction" = 'purchase' then 'invoices.purchase' else 'invoices.write' end), false)) for update;
  if v_row."id" is null then
    raise exception 'no such invoice you can edit' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  if not (v_row."company_id"::text = apply_party_credit.party_id or v_row."contact_id"::text = apply_party_credit.party_id) then
    raise exception 'the invoice isn''t this party''s' using errcode = '22023', hint = 'INVOICE_PARTY_MISMATCH';
  end if;
  if v_row."kind" <> 'invoice' or v_row."status" not in ('issued', 'partially_paid') or v_row."direction" <> 'sales' then
    raise exception 'only an open sales invoice takes credit' using errcode = '55000', hint = 'INVOICE_NOT_PAYABLE';
  end if;
  if coalesce(apply_party_credit.amount, 0) <= 0 then
    raise exception 'credit is applied in a positive amount' using errcode = '22023', hint = 'INVOICE_PAYMENT_INVALID';
  end if;
  if apply_party_credit.amount > (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total") then
    raise exception 'the amount is more than the invoice''s balance' using errcode = '23514', hint = 'INVOICE_CREDIT_TOO_LARGE';
  end if;
  select a."id" into v_account from "better_supabase"."ledger_accounts" a
  where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoices:credit:' || apply_party_credit.party_id || ':' || v_row."currency"
  for update;
  if v_account is null or apply_party_credit.amount > coalesce(-(select sum(e."amount") from "better_supabase"."ledger_entries" e where e."account_id" = v_account), 0) then
    raise exception 'the party doesn''t have this much credit in the invoice''s currency' using errcode = '23514', hint = 'INVOICE_CREDIT_INSUFFICIENT';
  end if;
  if apply_party_credit.actor is not null then
    if jsonb_typeof(apply_party_credit.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(apply_party_credit.actor ->> 'ip', '')::inet, nullif(apply_party_credit.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(apply_party_credit.actor::text, ''), true);
  v_was := v_row."status";
  v_payment := "better_supabase"."ledger_post"(v_row."tenant_id", 'invoice.credit_applied',
    jsonb_build_array(
      jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'receivable',
      'invoice:' || v_row."id"::text, 'Receivable ' || coalesce(v_row."identifier", v_row."id"::text),
      v_row."currency"::text, 0::smallint, 'invoices', v_row."id"::text,
      null, true, 'invoices.read', 'invoices', null), 'amount', -apply_party_credit.amount),
      jsonb_build_object('account', v_account, 'amount', apply_party_credit.amount)),
    'invoices', v_row."id"::text, null, null, now(),
    jsonb_build_object('invoiceId', v_row."id", 'method', 'credit', 'partyId', apply_party_credit.party_id));
  update "better_supabase"."invoices" x set
    "paid_total" = coalesce(-(select sum(e."amount") from "better_supabase"."ledger_entries" e where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text)), 0),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if v_row."status" in ('issued', 'partially_paid', 'paid') then
    update "better_supabase"."invoices" x set
      "status" = case
      when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then 'paid'
      when x."paid_total" > 0 or x."credited_total" > 0 then 'partially_paid'
      else 'issued' end,
      "paid_at" = case when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then coalesce(x."paid_at", now()) end
    where x."id" = v_row."id"
    returning * into v_row;
  end if;
  perform "better_supabase".emit_event('invoice.credit_applied', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'paymentId', v_payment, 'partyId', apply_party_credit.party_id, 'amount', apply_party_credit.amount::text, 'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  perform better_supabase.audit_event(
    event_type => 'invoice.credit_applied',
    category => 'billing',
    target_type => 'invoice',
    record_id => v_row."id"::text,
    target_label => v_row."identifier",
    summary => 'invoice credit_applied',
    tenant => (v_row."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'paymentId', v_payment, 'partyId', apply_party_credit.party_id, 'amount', apply_party_credit.amount::text, 'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text)
  );
  if v_row."status" = 'paid' and v_was <> 'paid' then
    perform "better_supabase".emit_event('invoice.paid', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'total', v_row."total"::text), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  end if;
  return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'deposit_amount', v_row."deposit_amount"::text, 'discount_amount', v_row."discount_amount"::text, 'discount_amount_early', v_row."discount_amount_early"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code", 'taxCodeId', il."tax_code_id", 'unitCost', il."unit_cost"::text, 'dimensions', il."dimensions") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.approval_eligible (
  request better_supabase.approval_requests
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_req "better_supabase"."approval_requests"%rowtype := approval_eligible.request;
  v_step jsonb;
  v_approvers jsonb;
  v_me uuid := auth.uid();
begin
  if v_req."id" is null or v_me is null or v_req."status" <> 'pending' then
    return false;
  end if;
  if exists (
    select 1 from "better_supabase"."approval_decisions" x
    where x."request_id" = v_req."id" and x."step" = v_req."step" and x."approver" = v_me
  ) then
    return false;
  end if;
  if coalesce(v_req."policy" -> 'excludedUserIds', '[]'::jsonb) ? v_me::text then
    return false;
  end if;
  if v_me = v_req."requested_by" then
    if v_req."policy" ->> 'mode' = 'confirm' then
      return true;
    end if;
    if not coalesce((v_req."policy" ->> 'selfApproval')::boolean, false) then
      return false;
    end if;
  end if;
  if v_req."subject_type" = 'support_request' then
    return "better_supabase"."support_request_approvable"(v_req."subject_id"::uuid);
  end if;
  if v_req."subject_type" = 'ai_tool_approval' then
    return "better_supabase"."ai_tool_approval_approvable"(v_req."subject_id");
  end if;
  v_step := v_req."policy" -> 'steps' -> v_req."step";
  v_approvers := v_step -> 'approvers';
  if ((coalesce(v_approvers -> 'users', '[]'::jsonb) ? v_me::text)
    or (v_approvers ->> 'permission' is not null and coalesce(better_supabase.can('tenant', v_req."tenant_id", v_approvers ->> 'permission'), false))
    or (v_approvers ->> 'role' is not null and "better_supabase"."approval_fact"(v_req."tenant_id", 'role', v_approvers ->> 'role', null))
    or (v_approvers ->> 'team' is not null and "better_supabase"."approval_fact"(v_req."tenant_id", 'team', v_approvers ->> 'team', null))
    or (coalesce((v_approvers ->> 'manager')::boolean, false) and "better_supabase"."approval_fact"(v_req."tenant_id", 'manager', (v_req."policy" ->> 'managerOf'), v_req."requested_by"))) then
    return true;
  end if;
  if coalesce((v_step ->> 'escalated')::boolean, false) then
    v_approvers := v_step -> 'escalateTo';
    if ((coalesce(v_approvers -> 'users', '[]'::jsonb) ? v_me::text)
    or (v_approvers ->> 'permission' is not null and coalesce(better_supabase.can('tenant', v_req."tenant_id", v_approvers ->> 'permission'), false))
    or (v_approvers ->> 'role' is not null and "better_supabase"."approval_fact"(v_req."tenant_id", 'role', v_approvers ->> 'role', null))
    or (v_approvers ->> 'team' is not null and "better_supabase"."approval_fact"(v_req."tenant_id", 'team', v_approvers ->> 'team', null))
    or (coalesce((v_approvers ->> 'manager')::boolean, false) and "better_supabase"."approval_fact"(v_req."tenant_id", 'manager', (v_req."policy" ->> 'managerOf'), v_req."requested_by"))) then
      return true;
    end if;
  end if;
  return exists (
      select 1 from "better_supabase"."approval_decisions" x
      where x."request_id" = v_req."id" and x."step" = v_req."step"
        and x."decision" = 'delegated' and x."delegate_to" = v_me
    );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.approval_eligible_ids (
  tenant uuid DEFAULT NULL::uuid
)
  RETURNS SETOF uuid
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  return query
  with base as (
    select r.*, (select auth.uid()) as bsb_me from "better_supabase"."approval_requests" r
    where r."status" = 'pending' and (select auth.uid()) is not null
      and (approval_eligible_ids.tenant is null or r."tenant_id" = approval_eligible_ids.tenant)
  ),
  q as (
    select b.*, b."policy" -> 'steps' -> b."step" as bsb_step from base b
  ),
  needs as materialized (
    select distinct q."tenant_id" as t, s.ap ->> 'permission' as p
    from q, lateral (values ((q.bsb_step -> 'approvers'), (case when coalesce((q.bsb_step ->> 'escalated')::boolean, false) then (q.bsb_step -> 'escalateTo') end))) as s(ap)
    where s.ap ->> 'permission' is not null
  ),
  granted as materialized (
    select n.t, n.p from needs n
    where coalesce(better_supabase.can('tenant', n.t, n.p), false)
  )
  select q."id" from q
  where not exists (select 1 from "better_supabase"."approval_decisions" x where x."request_id" = q."id" and x."step" = q."step" and x."approver" = q.bsb_me)
    and not (coalesce(q."policy" -> 'excludedUserIds', '[]'::jsonb) ? q.bsb_me::text)
    and ((q.bsb_me = q."requested_by" and q."policy" ->> 'mode' = 'confirm')
      or ((q.bsb_me is distinct from q."requested_by" or coalesce((q."policy" ->> 'selfApproval')::boolean, false))
        and (case when q."subject_type" = 'support_request' then ("better_supabase"."support_request_approvable"(q."subject_id"::uuid))
          when q."subject_type" = 'ai_tool_approval' then ("better_supabase"."ai_tool_approval_approvable"(q."subject_id"))
          else (((coalesce((q.bsb_step -> 'approvers') -> 'users', '[]'::jsonb) ? q.bsb_me::text)
    or ((q.bsb_step -> 'approvers') ->> 'permission' is not null and exists (select 1 from granted g where g.t is not distinct from q."tenant_id" and g.p = (q.bsb_step -> 'approvers') ->> 'permission'))
    or ((q.bsb_step -> 'approvers') ->> 'role' is not null and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = q."tenant_id" and mm."user_id" = q.bsb_me and mm."role" = (select r."id" from "better_supabase"."roles" r where (r."id"::text = ((q.bsb_step -> 'approvers') ->> 'role')::text or r."key" = ((q.bsb_step -> 'approvers') ->> 'role')::text) order by (r."id"::text = ((q.bsb_step -> 'approvers') ->> 'role')::text) desc limit 1)
    ))
    or ((q.bsb_step -> 'approvers') ->> 'team' is not null and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = (q.bsb_step -> 'approvers') ->> 'team' and tm."user_id" = q.bsb_me))
    or (coalesce(((q.bsb_step -> 'approvers') ->> 'manager')::boolean, false) and (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = q."tenant_id" and (case when (q."policy" ->> 'managerOf') is not null then me."id"::text = (q."policy" ->> 'managerOf') else me."user_id" = q."requested_by" end)
        and mgr."user_id" is not null and mgr."status" <> 'offboarded' and (mgr."end_date" is null or mgr."end_date" >= current_date)
      limit 1) = q.bsb_me, false) and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = q."tenant_id" and mm."user_id" = q.bsb_me
    ))))
    or (coalesce((q.bsb_step ->> 'escalated')::boolean, false) and ((coalesce((q.bsb_step -> 'escalateTo') -> 'users', '[]'::jsonb) ? q.bsb_me::text)
    or ((q.bsb_step -> 'escalateTo') ->> 'permission' is not null and exists (select 1 from granted g where g.t is not distinct from q."tenant_id" and g.p = (q.bsb_step -> 'escalateTo') ->> 'permission'))
    or ((q.bsb_step -> 'escalateTo') ->> 'role' is not null and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = q."tenant_id" and mm."user_id" = q.bsb_me and mm."role" = (select r."id" from "better_supabase"."roles" r where (r."id"::text = ((q.bsb_step -> 'escalateTo') ->> 'role')::text or r."key" = ((q.bsb_step -> 'escalateTo') ->> 'role')::text) order by (r."id"::text = ((q.bsb_step -> 'escalateTo') ->> 'role')::text) desc limit 1)
    ))
    or ((q.bsb_step -> 'escalateTo') ->> 'team' is not null and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = (q.bsb_step -> 'escalateTo') ->> 'team' and tm."user_id" = q.bsb_me))
    or (coalesce(((q.bsb_step -> 'escalateTo') ->> 'manager')::boolean, false) and (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = q."tenant_id" and (case when (q."policy" ->> 'managerOf') is not null then me."id"::text = (q."policy" ->> 'managerOf') else me."user_id" = q."requested_by" end)
        and mgr."user_id" is not null and mgr."status" <> 'offboarded' and (mgr."end_date" is null or mgr."end_date" >= current_date)
      limit 1) = q.bsb_me, false) and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = q."tenant_id" and mm."user_id" = q.bsb_me
    )))))
    or exists (select 1 from "better_supabase"."approval_decisions" x where x."request_id" = q."id" and x."step" = q."step" and x."decision" = 'delegated' and x."delegate_to" = q.bsb_me)) end)));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.approval_notify (
  request_id uuid,
  kind       text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_req "better_supabase"."approval_requests"%rowtype;
  v_approvers jsonb;
  v_permission text;
  v_recipients uuid[] := '{}';
  v_claims text;
  v_note jsonb;
  v_hook regprocedure;
  v_extra jsonb;
begin
  select * into v_req from "better_supabase"."approval_requests" r where r."id" = approval_notify.request_id;
  if not found then
    return;
  end if;
  if approval_notify.kind in ('approved', 'rejected', 'expired') then
    v_recipients := array[v_req."requested_by"];
    v_permission := null;
  else
    v_approvers := v_req."policy" -> 'steps' -> v_req."step" -> case when approval_notify.kind = 'escalated' then 'escalateTo' else 'approvers' end;
    v_permission := v_approvers ->> 'permission';
    v_recipients := array(
      select x::uuid from jsonb_array_elements_text(coalesce(v_approvers -> 'users', '[]'::jsonb)) x
      union
      select m."user_id" from "public"."memberships" m
      where m."organization_id" = v_req."tenant_id" and m."role" = (select r."id" from "better_supabase"."roles" r where (r."id"::text = (v_approvers ->> 'role')::text or r."key" = (v_approvers ->> 'role')::text) order by (r."id"::text = (v_approvers ->> 'role')::text) desc limit 1)
      union
      select tm."user_id" from "better_supabase"."team_members" tm
      where tm."team_id"::text = v_approvers ->> 'team'
      union
      select (select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = v_req."tenant_id" and (case when (v_req."policy" ->> 'managerOf') is not null then me."id"::text = (v_req."policy" ->> 'managerOf') else me."user_id" = v_req."requested_by" end)
        and mgr."user_id" is not null and mgr."status" <> 'offboarded' and (mgr."end_date" is null or mgr."end_date" >= current_date)
      limit 1) where coalesce((v_approvers ->> 'manager')::boolean, false)
      union
      select x."delegate_to" from "better_supabase"."approval_decisions" x
      where x."request_id" = v_req."id" and x."step" = v_req."step" and x."decision" = 'delegated'
    );
    if approval_notify.kind = 'delegated' then
      v_recipients := array(
        select x."delegate_to" from "better_supabase"."approval_decisions" x
        where x."request_id" = v_req."id" and x."step" = v_req."step" and x."decision" = 'delegated'
        order by x."created_at" desc limit 1
      );
      v_permission := null;
    end if;
    -- Approvers who already decided this step aren't asked again.
    v_recipients := array(
      select u from unnest(v_recipients) u
      where not exists (
        select 1 from "better_supabase"."approval_decisions" x
        where x."request_id" = v_req."id" and x."step" = v_req."step" and x."approver" = u
      )
    );
  end if;
  if cardinality(v_recipients) = 0 and v_permission is null then
    return;
  end if;
  v_note := jsonb_build_object(
      'type', 'approval.' || approval_notify.kind,
      'tenant', v_req."tenant_id",
      'actor', coalesce(auth.uid(), v_req."requested_by"),
      'subject_type', v_req."subject_type",
      'subject_id', v_req."subject_id",
      'summary', left(v_req."action" || coalesce(': ' || v_req."reason", ''), 140),
      'recipients', to_jsonb(v_recipients),
      'permission', v_permission,
      'exclude', case when approval_notify.kind in ('approved', 'rejected', 'expired') then '[]'::jsonb when coalesce((v_req."policy" ->> 'selfApproval')::boolean, false) then coalesce(v_req."policy" -> 'excludedUserIds', '[]'::jsonb) else jsonb_build_array(v_req."requested_by") || coalesce(v_req."policy" -> 'excludedUserIds', '[]'::jsonb) end,
      'include_actor', approval_notify.kind in ('approved', 'rejected', 'expired'),
      'key', 'approval.' || approval_notify.kind || ':' || v_req."id"::text || ':' || v_req."step"::text || ':' || extract(epoch from now())::bigint::text,
      'data', jsonb_build_object('requestId', v_req."id", 'action', v_req."action", 'step', v_req."step")
    );
  v_hook := to_regprocedure('"public"."approval_notification"(uuid, text, jsonb)');
  if v_hook is not null then
    execute format('select %s($1, $2, $3)', v_hook::oid::regproc) into v_extra
      using v_req."id", approval_notify.kind, v_note;
    if v_extra is null then
      return;
    end if;
    v_note := v_note || (v_extra - 'data') || jsonb_build_object('data', coalesce(v_note -> 'data', '{}'::jsonb) || coalesce(v_extra -> 'data', '{}'::jsonb));
  end if;
  if better_supabase.import_run() is null then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(v_note);
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
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
    raise exception 'the bill has every approval it needs' using errcode = 'PT409', hint = 'INVOICE_ALREADY_APPROVED';
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
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code", 'taxCodeId', il."tax_code_id", 'unitCost', il."unit_cost"::text, 'dimensions', il."dimensions") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb)) || jsonb_build_object('approval', v_state);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_time_entry (
  entry_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."time_entries"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."time_entries" x where x."id" = archive_time_entry.entry_id for update;
  if not found then
    raise exception 'time entry not found' using errcode = 'P0002', hint = 'TIME_ENTRY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(v_row."user_id" = auth.uid(), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_entries.track'), false)) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_entries.manage'), false)) then
    raise exception 'not allowed to change this entry' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if v_row."archived_at" is not null then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
  end if;
  if v_row."ended_at" is null then
    raise exception 'stop the running timer before archiving it' using errcode = 'PT409', hint = 'TIME_TIMER_RUNNING';
  end if;
  update "better_supabase"."time_entries" x set
    "archived_at" = now(),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('time_entry.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'id', v_row."id", 'userId', v_row."user_id", 'startedAt', v_row."started_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency"), 'time-entries/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/time-entries');
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.begin_import_session (
  run uuid
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_status text;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role can begin an import session' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  select r."status"::text into v_status from "better_supabase"."import_runs" r where r."id" = begin_import_session.run;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if v_status <> 'running' then
    raise exception 'the import is not running' using errcode = 'PT409', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;
  perform set_config('better_supabase.import_run', begin_import_session.run::text, true);
  perform set_config('better_supabase.correlation_id', 'import:' || begin_import_session.run::text, true);
  perform set_config('better_supabase.import_events', '{"customer.imported":"tag","customer.synced":"emit"}', true);
  perform set_config('better_supabase.import_audit', 'summary', true);
  return begin_import_session.run;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.cancel_expense_report (
  report_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."expense_reports" x where x."id" = cancel_expense_report.report_id for update;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (coalesce(v_row."user_id" = auth.uid(), false) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.manage'), false))) then
    raise exception 'not allowed to cancel this expense report' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) not in ('draft', 'submitted', 'rejected') then
    raise exception 'an approved, reimbursed or cancelled report can''t be cancelled' using errcode = 'PT409', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  update "better_supabase"."approval_requests" p set "status" = 'cancelled', "decided_at" = now()
    where p."id" = v_row."approval_id" and p."status" = 'pending';
  update "better_supabase"."expense_reports" x set "cancelled_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  perform "better_supabase".emit_event('expense_report.cancelled', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'currency', v_row."currency"), 'expense-reports/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/expenses');
  perform better_supabase.audit_event(
    event_type => 'expense_report.cancelled',
    category => 'data',
    target_type => 'expense_report',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'cancelled an expense report',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'currency', v_row."currency")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'title', v_row."title", 'currency', v_row."currency", 'note', v_row."note", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'approvalId', v_row."approval_id", 'submittedAt', v_row."submitted_at", 'approvedAt', v_row."approved_at", 'approvalTransactionId', v_row."approval_transaction_id", 'reimbursedAt', v_row."reimbursed_at", 'reimbursementTransactionId', v_row."reimbursement_transaction_id", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'dimensions', l."dimensions", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', (select count(*) from "better_supabase"."attachments" t where t."subject_type" = 'expense_line' and t."subject_id" = l."id"::text and t."uploaded_at" is not null and t."status" <> 'infected'), 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = v_row."id"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.cancel_import_run (
  id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_run "better_supabase"."import_runs";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_run from "better_supabase"."import_runs" r where r."id" = cancel_import_run.id for update;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_run."tenant_id", 'imports.manage'), false)) then
    raise exception 'not allowed to cancel this import' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  if v_run."status" not in ('pending', 'running') then
    raise exception 'this import already finished' using errcode = 'PT409', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;
  update "better_supabase"."import_runs" r set "status" = 'canceled', "finished_at" = now()
  where r."id" = cancel_import_run.id;
  perform "better_supabase"."search_refresh_run"(cancel_import_run.id);
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.cancel_leave_request (
  request_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."leave_requests"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_manager boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."leave_requests" x where x."id" = cancel_leave_request.request_id for update;
  if not found then
    raise exception 'leave request not found' using errcode = 'P0002', hint = 'LEAVE_REQUEST_NOT_FOUND';
  end if;
  v_manager := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leave.manage'), false);
  if not (v_manager or coalesce(v_row."user_id" = auth.uid(), false)) then
    raise exception 'not allowed to cancel this leave request' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  if v_row."cancelled_at" is not null then
    raise exception 'this leave request is already cancelled' using errcode = 'PT409', hint = 'LEAVE_REQUEST_CLOSED';
  end if;
  if not v_manager and v_row."approved_at" is not null and v_row."starts_on" <= current_date then
    raise exception 'leave that has started can only be cancelled by a manager' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  update "better_supabase"."approval_requests" p set "status" = 'cancelled', "decided_at" = now()
    where p."id" = v_row."approval_id" and p."status" = 'pending';
  if v_row."approved_at" is not null then
    perform "better_supabase"."leave_post"(v_row."tenant_id", v_row."user_id", v_row."type_id", 'taken', v_row."amount", extract(year from v_row."starts_on")::integer, v_row."id", 'cancelled')
    from "better_supabase"."leave_types" t where t."id" = v_row."type_id" and t."tracked";
  end if;
  update "better_supabase"."leave_requests" x set "cancelled_at" = now(), "cancelled_by" = auth.uid(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_row."approval_id";
  perform "better_supabase".emit_event('leave_request.cancelled', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'typeId', v_row."type_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'amount', v_row."amount"::text, 'approvalId', v_row."approval_id"), 'leave-requests/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/leave');
  perform better_supabase.audit_event(
    event_type => 'leave_request.cancelled',
    category => 'data',
    target_type => 'leave_request',
    record_id => v_row."id"::text,
    summary => 'cancelled leave' || ' from ' || v_row."starts_on"::text || ' to ' || v_row."ends_on"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'typeId', v_row."type_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'amount', v_row."amount"::text, 'approvalId', v_row."approval_id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'typeId', v_row."type_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'partial', v_row."partial", 'amount', v_row."amount"::text, 'note', case when (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."user_id" = auth.uid(), false) or (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = v_row."tenant_id" and me."user_id" = v_row."user_id"
        and mgr."user_id" is not null and mgr."status" <> 'offboarded' and (mgr."end_date" is null or mgr."end_date" >= current_date)
      limit 1) = auth.uid(), false) and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = v_row."tenant_id" and mm."user_id" = auth.uid()
    )) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leave.approve'), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leave.manage'), false)) then v_row."note" end, 'status', case when v_row."cancelled_at" is not null then 'cancelled' when v_row."approved_at" is not null then 'approved' when v_approval."status" in ('rejected', 'expired') then 'rejected' when v_approval."status" = 'cancelled' then 'cancelled' else 'pending' end, 'approvalId', v_row."approval_id", 'approvedAt', v_row."approved_at", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.claim_attachment_upload (
  id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."attachments";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."attachments" a where a."id" = claim_attachment_upload.id for update;
  if v_row."id" is null then
    raise exception 'No attachment has this id' using errcode = 'P0002', hint = 'ATTACHMENT_NOT_FOUND';
  end if;
  if not ((coalesce(better_supabase.can('tenant', v_row."tenant_id", case v_row."subject_type" when 'message' then 'messages.send' when 'conversation' then 'messages.send' when 'expense_line' then 'expenses.submit' when 'warranty_claim' then 'warranty.write' else 'attachments.upload' end), false) or ((v_row."tenant_id")::text, (v_row."subject_type")::text, (v_row."subject_id")::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('upload') g)) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'attachments.manage'), false) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))) then
    raise exception 'not allowed to upload this attachment' using errcode = '42501', hint = 'ATTACHMENT_FORBIDDEN';
  end if;
  if v_row."uploaded_at" is not null or v_row."storage_status" = 'stored' then
    raise exception 'the file is already stored' using errcode = 'PT409', hint = 'ATTACHMENT_NOT_CLAIMABLE';
  end if;
  update "better_supabase"."attachments" a set
    "storage_status" = 'pending_upload',
    "uploaded_by" = case when (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then a."uploaded_by" else auth.uid() end
  where a."id" = v_row."id"
  returning * into v_row;
  return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
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
    raise exception 'the fiscal year is already closed; reverse its closing entry to close it again' using errcode = 'PT409', hint = 'PERIOD_CLOSED';
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
    raise exception 'the fiscal year is already closed' using errcode = 'PT409', hint = 'PERIOD_CLOSED';
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

CREATE OR REPLACE FUNCTION better_supabase.consume_agent_mandate (
  mandate_id uuid,
  session_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."agent_mandates";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."agent_mandates" x where x."id" = consume_agent_mandate.mandate_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agent_checkout.read'), false))) then
    raise exception 'no such mandate' using errcode = 'P0002', hint = 'AGENT_MANDATE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agent_checkout.write'), false))) then
    raise exception 'not allowed to use mandates' using errcode = '42501', hint = 'AGENT_MANDATE_FORBIDDEN';
  end if;
  if v_row."vct" <> 'mandate.checkout.1' then
    raise exception 'only a closed mandate is consumed' using errcode = '22023', hint = 'AGENT_MANDATE_INVALID';
  end if;
  if v_row."status" <> 'active' then
    raise exception 'the mandate was already used or revoked' using errcode = 'PT409', hint = 'AGENT_MANDATE_USED';
  end if;
  if v_row."expires_at" <= now() then
    raise exception 'the mandate expired' using errcode = '55000', hint = 'AGENT_MANDATE_EXPIRED';
  end if;
  if v_row."session_id" is not null and v_row."session_id" <> consume_agent_mandate.session_id then
    raise exception 'the mandate belongs to another session' using errcode = '22023', hint = 'AGENT_MANDATE_INVALID';
  end if;
  update "better_supabase"."agent_mandates" x set "status" = 'consumed', "consumed_at" = now(), "session_id" = coalesce(x."session_id", consume_agent_mandate.session_id)
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('agent_mandate.consumed', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'vct', v_row."vct", 'sessionId', v_row."session_id"), 'agent-mandates/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/agent-checkout');
  perform better_supabase.audit_event(
    event_type => 'agent_mandate.consumed',
    category => 'security',
    target_type => 'agent_mandate',
    record_id => v_row."id"::text,
    summary => 'agent mandate used',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'vct', v_row."vct", 'sessionId', v_row."session_id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'sessionId', v_row."session_id", 'vct', v_row."vct", 'status', v_row."status", 'credential', v_row."credential", 'credentialHash', v_row."credential_hash", 'issuerKid', v_row."issuer_kid", 'subject', v_row."subject", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" = 'active' and v_row."expires_at" <= now()), 'consumedAt', v_row."consumed_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.decide_approval (
  request_id uuid,
  decision   text,
  comment    text DEFAULT NULL::text,
  decided_by uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_req "better_supabase"."approval_requests"%rowtype;
  v_count integer;
  v_service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  v_actor uuid := coalesce(decide_approval.decided_by, auth.uid());
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if decide_approval.decision not in ('approved', 'rejected') then
    raise exception 'decision must be approved or rejected' using errcode = '22023', hint = 'APPROVAL_DECISION_INVALID';
  end if;
  if decide_approval.decided_by is not null and not v_service and decide_approval.decided_by is distinct from auth.uid() then
    raise exception 'only the service role decides for another user' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
  end if;
  select * into v_req from "better_supabase"."approval_requests" r where r."id" = decide_approval.request_id for update;
  if not found then
    raise exception 'approval request not found' using errcode = 'P0002', hint = 'APPROVAL_NOT_FOUND';
  end if;
  if v_req."status" <> 'pending' then
    raise exception 'this request is no longer pending' using errcode = '22023', hint = 'APPROVAL_CLOSED';
  end if;
  if v_req."expires_at" is not null and v_req."expires_at" <= now() then
    raise exception 'this request has expired' using errcode = '22023', hint = 'APPROVAL_EXPIRED';
  end if;
  if exists (select 1 from "better_supabase"."approval_items" x where x."request_id" = v_req."id") then
    raise exception 'this request has items; use decide_approval_items' using errcode = '22023', hint = 'APPROVAL_ITEMS_REQUIRED';
  end if;
  if v_service then
    if v_actor is not null and v_actor = v_req."requested_by" and coalesce(v_req."policy" ->> 'mode', 'authorize') <> 'confirm'
      and not coalesce((v_req."policy" ->> 'selfApproval')::boolean, false) then
      raise exception 'the requester can''t decide their own request' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
    end if;
    if v_actor is not null and coalesce(v_req."policy" -> 'excludedUserIds', '[]'::jsonb) ? v_actor::text then
      raise exception 'this user is left out of deciding this request' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
    end if;
    if v_actor is not null and exists (
      select 1 from "better_supabase"."approval_decisions" x
      where x."request_id" = v_req."id" and x."step" = v_req."step" and x."approver" = v_actor
    ) then
      raise exception 'this user already decided this step' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
    end if;
  elsif not "better_supabase"."approval_eligible"(v_req."id") then
    raise exception 'not an approver for this step' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_approval_decide"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_req."id", decide_approval.decision;
    end if;
  end;
  insert into "better_supabase"."approval_decisions" ("request_id", "tenant_id", "step", "approver", "decision", "comment")
  values (v_req."id", v_req."tenant_id", v_req."step", v_actor, decide_approval.decision, decide_approval.comment);
  if decide_approval.decision = 'rejected' then
    update "better_supabase"."approval_requests" r set "status" = 'rejected', "decided_at" = now()
      where r."id" = v_req."id" returning * into v_req;
    perform "better_supabase".emit_event('approval.rejected', jsonb_build_object('organizationId', v_req."tenant_id"::text, 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step"), 'approval-requests/' || v_req."id"::text, (v_req."tenant_id")::text, null, 'better-supabase/approvals');
  perform better_supabase.audit_event(
    event_type => 'approval.rejected',
    category => 'data',
    target_type => 'approval_request',
    record_id => v_req."id"::text,
    summary => 'rejected' || ' ' || v_req."action" || ' on ' || v_req."subject_type" || ' ' || v_req."subject_id",
    tenant => (v_req."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_req."tenant_id"::text, 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step")
  );
    perform "better_supabase"."approval_notify"(v_req."id", 'rejected');
    if v_req."subject_type" = 'support_request' then
      perform "better_supabase"."close_support_request"(v_req."subject_id"::uuid);
    end if;
    if v_req."subject_type" = 'ai_tool_approval' then
      perform "better_supabase"."apply_ai_tool_approval"(v_req."subject_id", false, decide_approval.comment);
    end if;
    if v_req."subject_type" = 'purchase_requisition' then
      perform "better_supabase"."purchase_requisition_decided"(v_req."subject_id"::uuid, false);
    end if;
    if v_req."subject_type" = 'drive_node' then
      perform "better_supabase"."drive_document_decided"(v_req."id", false);
    end if;
    if v_req."subject_type" = 'warranty_claim' then
      perform "better_supabase"."decide_warranty_claim"(v_req."subject_id"::uuid, 'denied', decide_approval.comment);
    end if;
    if v_req."subject_type" = 'appraisal' then
      perform "better_supabase"."appraisal_rejected"(v_req."subject_id"::uuid);
    end if;
  else
    select count(*) into v_count from "better_supabase"."approval_decisions" x
      where x."request_id" = v_req."id" and x."step" = v_req."step" and x."decision" = 'approved';
    if v_req."policy" ->> 'mode' = 'confirm' and v_req."requested_by" = v_actor then
      update "better_supabase"."approval_requests" r set "status" = 'approved', "decided_at" = now()
        where r."id" = v_req."id" returning * into v_req;
      perform "better_supabase"."approval_finalize"(v_req."id");
    elsif (case when coalesce((v_req."policy" -> 'steps' -> v_req."step" ->> 'all')::boolean, false)
        and not coalesce((v_req."policy" -> 'steps' -> v_req."step" ->> 'escalated')::boolean, false)
      then jsonb_array_length(coalesce(v_req."policy" -> 'steps' -> v_req."step" -> 'approvers' -> 'users', '[]'::jsonb)) > 0
        and not exists (
          select 1 from jsonb_array_elements_text(v_req."policy" -> 'steps' -> v_req."step" -> 'approvers' -> 'users') u(id)
          where not exists (
            select 1 from "better_supabase"."approval_decisions" x
            where x."request_id" = v_req."id" and x."step" = v_req."step" and x."decision" = 'approved'
              and (x."approver" = u.id::uuid or exists (
                select 1 from "better_supabase"."approval_decisions" y
                where y."request_id" = x."request_id" and y."step" = x."step" and y."decision" = 'delegated'
                  and y."approver" = u.id::uuid and y."delegate_to" = x."approver"
              ))
          )
        )
      else v_count >= coalesce((v_req."policy" -> 'steps' -> v_req."step" ->> 'required')::integer, 1) end) then
      if v_req."step" + 1 >= jsonb_array_length(v_req."policy" -> 'steps') then
        update "better_supabase"."approval_requests" r set "status" = 'approved', "decided_at" = now()
          where r."id" = v_req."id" returning * into v_req;
        perform "better_supabase"."approval_finalize"(v_req."id");
      else
        update "better_supabase"."approval_requests" r set "step" = r."step" + 1, "reminded_at" = null
          where r."id" = v_req."id" returning * into v_req;
        perform "better_supabase"."approval_notify"(v_req."id", 'requested');
      end if;
    end if;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_approval_decide"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_req."id", v_req."status";
    end if;
  end;
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step", 'steps', v_req."policy" -> 'steps', 'requestedBy', v_req."requested_by", 'reason', v_req."reason", 'payload', v_req."payload", 'expiresAt', v_req."expires_at", 'decidedAt', v_req."decided_at", 'mode', coalesce(v_req."policy" ->> 'mode', 'authorize'), 'fingerprint', v_req."fingerprint", 'consumedAt', v_req."consumed_at", 'createdAt', v_req."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.decide_approval_items (
  request_id uuid,
  decisions  jsonb,
  decided_by uuid  DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_req "better_supabase"."approval_requests"%rowtype;
  v_item "better_supabase"."approval_items"%rowtype;
  v_each jsonb;
  v_decision text;
  v_service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  v_actor uuid := coalesce(decide_approval_items.decided_by, auth.uid());
  v_pending integer;
  v_approved integer;
  v_outcome text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(decide_approval_items.decisions) is distinct from 'array' or jsonb_array_length(decide_approval_items.decisions) = 0 then
    raise exception 'decisions must be a non-empty array' using errcode = '22023', hint = 'APPROVAL_DECISION_INVALID';
  end if;
  if decide_approval_items.decided_by is not null and not v_service and decide_approval_items.decided_by is distinct from auth.uid() then
    raise exception 'only the service role decides for another user' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
  end if;
  select * into v_req from "better_supabase"."approval_requests" r where r."id" = decide_approval_items.request_id for update;
  if not found then
    raise exception 'approval request not found' using errcode = 'P0002', hint = 'APPROVAL_NOT_FOUND';
  end if;
  if v_req."status" <> 'pending' then
    raise exception 'this request is no longer pending' using errcode = '22023', hint = 'APPROVAL_CLOSED';
  end if;
  if v_req."expires_at" is not null and v_req."expires_at" <= now() then
    raise exception 'this request has expired' using errcode = '22023', hint = 'APPROVAL_EXPIRED';
  end if;
  if not exists (select 1 from "better_supabase"."approval_items" x where x."request_id" = v_req."id") then
    raise exception 'this request has no items; use decide_approval' using errcode = '22023', hint = 'APPROVAL_ITEMS_NONE';
  end if;
  if v_actor is not null and v_actor = v_req."requested_by" and coalesce(v_req."policy" ->> 'mode', 'authorize') <> 'confirm'
    and not coalesce((v_req."policy" ->> 'selfApproval')::boolean, false) then
    raise exception 'the requester can''t decide their own request' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
  end if;
  if v_actor is not null and coalesce(v_req."policy" -> 'excludedUserIds', '[]'::jsonb) ? v_actor::text then
    raise exception 'this user is left out of deciding this request' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
  end if;
  for v_each in select e.value from jsonb_array_elements(decide_approval_items.decisions) e loop
    v_decision := v_each ->> 'decision';
    if v_decision is null or v_decision not in ('approved', 'rejected') or jsonb_typeof(v_each -> 'key') is distinct from 'string' then
      raise exception 'each decision needs a key and a decision of approved or rejected' using errcode = '22023', hint = 'APPROVAL_DECISION_INVALID';
    end if;
    select * into v_item from "better_supabase"."approval_items" x
    where x."request_id" = v_req."id" and x."key" = v_each ->> 'key' for update;
    if not found then
      raise exception 'this request has no such item' using errcode = 'P0002', hint = 'APPROVAL_ITEM_NOT_FOUND';
    end if;
    if v_item."status" <> 'pending' then
      raise exception 'this item is no longer pending' using errcode = '22023', hint = 'APPROVAL_ITEM_CLOSED';
    end if;
    if not v_service then
      if v_item."permission" is not null then
        if not (coalesce(better_supabase.can('tenant', v_req."tenant_id", v_item."permission"), false)) then
          raise exception 'not an approver for this item' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
        end if;
      elsif not "better_supabase"."approval_eligible"(v_req."id") then
        raise exception 'not an approver for this item' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
      end if;
    end if;
    if v_decision = 'approved' and exists (
      select 1 from "better_supabase"."approval_items" dep
      where dep."request_id" = v_req."id" and dep."key" = any(v_item."depends_on") and dep."status" <> 'approved'
    ) then
      raise exception 'an item this one depends on is not approved' using errcode = '22023', hint = 'APPROVAL_ITEM_BLOCKED';
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_approval_decide"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_req."id", v_decision;
    end if;
  end;
    update "better_supabase"."approval_items" x set "status" = v_decision, "decided_by" = v_actor, "decided_at" = now()
    where x."id" = v_item."id";
    if v_decision = 'rejected' then
      with recursive blocked(key) as (
        select y."key" from "better_supabase"."approval_items" y
        where y."request_id" = v_req."id" and v_item."key" = any(y."depends_on")
        union
        select y."key" from "better_supabase"."approval_items" y join blocked b on b.key = any(y."depends_on")
        where y."request_id" = v_req."id"
      )
      update "better_supabase"."approval_items" x set "status" = 'rejected', "decided_by" = v_actor, "decided_at" = now()
      where x."request_id" = v_req."id" and x."status" = 'pending' and x."key" in (select key from blocked);
    end if;
  end loop;
  select count(*) filter (where x."status" = 'pending'), count(*) filter (where x."status" = 'approved')
    into v_pending, v_approved
  from "better_supabase"."approval_items" x where x."request_id" = v_req."id";
  if v_pending = 0 then
    v_outcome := case when v_approved > 0 then 'approved' else 'rejected' end;
    insert into "better_supabase"."approval_decisions" ("request_id", "tenant_id", "step", "approver", "decision")
    values (v_req."id", v_req."tenant_id", v_req."step", v_actor, v_outcome)
    on conflict do nothing;
    update "better_supabase"."approval_requests" r set "status" = v_outcome, "decided_at" = now()
      where r."id" = v_req."id" returning * into v_req;
    if v_outcome = 'approved' then
      perform "better_supabase"."approval_finalize"(v_req."id");
    else
      perform "better_supabase".emit_event('approval.rejected', jsonb_build_object('organizationId', v_req."tenant_id"::text, 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step"), 'approval-requests/' || v_req."id"::text, (v_req."tenant_id")::text, null, 'better-supabase/approvals');
  perform better_supabase.audit_event(
    event_type => 'approval.rejected',
    category => 'data',
    target_type => 'approval_request',
    record_id => v_req."id"::text,
    summary => 'rejected' || ' ' || v_req."action" || ' on ' || v_req."subject_type" || ' ' || v_req."subject_id",
    tenant => (v_req."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_req."tenant_id"::text, 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step")
  );
      perform "better_supabase"."approval_notify"(v_req."id", 'rejected');
    end if;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_approval_decide"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_req."id", v_req."status";
    end if;
  end;
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step", 'steps', v_req."policy" -> 'steps', 'requestedBy', v_req."requested_by", 'reason', v_req."reason", 'payload', v_req."payload", 'expiresAt', v_req."expires_at", 'decidedAt', v_req."decided_at", 'mode', coalesce(v_req."policy" ->> 'mode', 'authorize'), 'fingerprint', v_req."fingerprint", 'consumedAt', v_req."consumed_at", 'createdAt', v_req."created_at") || jsonb_build_object('items', coalesce((
      select jsonb_agg(jsonb_build_object('id', x."id", 'key', x."key", 'label', x."label", 'payload', x."payload", 'permission', x."permission", 'dependsOn', to_jsonb(x."depends_on"), 'status', x."status", 'createdType', x."created_type", 'createdId', x."created_id", 'decidedBy', x."decided_by", 'decidedAt', x."decided_at", 'createdAt', x."created_at") order by x."created_at", x."key")
      from "better_supabase"."approval_items" x where x."request_id" = v_req."id"
    ), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.decide_care_alert (
  alert_id uuid,
  decision text,
  reason   text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."care_alerts";
  v_reason text := nullif(trim(decide_care_alert.reason), '');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."care_alerts" x where x."id" = decide_care_alert.alert_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'clinical_decision_support.read'), false))) then
    raise exception 'no such alert' using errcode = 'P0002', hint = 'DECISION_SUPPORT_ALERT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'clinical_decision_support.write'), false))) then
    raise exception 'not allowed to decide on care alerts' using errcode = '42501', hint = 'DECISION_SUPPORT_ALERT_FORBIDDEN';
  end if;
  if decide_care_alert.decision is null or decide_care_alert.decision not in ('acknowledged', 'overridden') then
    raise exception 'decision is acknowledged or overridden' using errcode = '22023', hint = 'DECISION_SUPPORT_ALERT_INVALID';
  end if;
  if v_row."status" = 'resolved' or (v_row."status" = 'overridden') or (v_row."status" = 'acknowledged' and decide_care_alert.decision = 'acknowledged') then
    raise exception 'this alert has already been decided or resolved' using errcode = 'PT409', hint = 'DECISION_SUPPORT_ALERT_STATUS';
  end if;
  if v_reason is null and (decide_care_alert.decision = 'overridden' or v_row."severity" = 'critical') then
    raise exception 'overriding an alert, or deciding on a critical one, needs a reason' using errcode = '22023', hint = 'DECISION_SUPPORT_ALERT_INVALID';
  end if;
  if v_reason is not null and length(v_reason) > 1000 then
    raise exception 'a reason is up to 1000 characters' using errcode = '22023', hint = 'DECISION_SUPPORT_ALERT_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_care_alert_decide"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_row."id", decide_care_alert.decision;
    end if;
  end;
  update "better_supabase"."care_alerts" x set "status" = decide_care_alert.decision, "decided_by" = auth.uid(), "decided_at" = now(),
    "decision_reason" = v_reason, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('care_alert.decided', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'kind', v_row."kind", 'severity', v_row."severity", 'source', v_row."source", 'status', v_row."status"), 'care-alerts/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/clinical-decision-support');
  perform better_supabase.audit_event(
    event_type => 'care_alert.decided',
    category => 'data',
    target_type => 'care_alert',
    record_id => v_row."id"::text,
    target_label => v_row."kind",
    summary => 'care alert decided',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'kind', v_row."kind", 'severity', v_row."severity", 'source', v_row."source", 'status', v_row."status")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_care_alert_decide"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'kind', v_row."kind", 'severity', v_row."severity", 'source', v_row."source", 'ruleId', v_row."rule_id", 'orderIds', to_jsonb(v_row."order_ids"), 'message', v_row."message", 'details', v_row."details", 'fingerprint', v_row."fingerprint", 'status', v_row."status", 'decidedBy', v_row."decided_by", 'decidedAt', v_row."decided_at", 'decisionReason', v_row."decision_reason", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.decide_document_suggestion (
  suggestion_id uuid,
  decision      text,
  note          text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
  v_suggestion "better_supabase"."document_suggestions"%rowtype;
  v_seq bigint;
  v_since bigint;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_suggestion from "better_supabase"."document_suggestions" x where x."id" = decide_document_suggestion.suggestion_id for update;
  if found then
    select * into v_doc from "better_supabase"."documents" d where d."id" = v_suggestion."document_id";
  end if;
  if v_suggestion."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and case v_doc."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contacts.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contacts.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'posts.read'), false)
    when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'activities.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'tasks.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'invoices.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'rfq' then exists (select 1 from "better_supabase"."rfqs" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'rfqs.read'), false)
    when 'till' then exists (select 1 from "better_supabase"."tills" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'tills.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'donations.read'), false)
    when 'warranty_claim' then exists (select 1 from "better_supabase"."warranty_claims" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'warranty.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'compliance.read'), false)
    when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'compliance.read'), false)
    when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'qualifications.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'risks.read'), false)
    when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'cases.read'), false)
    when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'inspections.read'), false)
    when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'inspections.read'), false)
    when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'inspections.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'forms.read'), false)
    when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'meetings.read'), false)
    when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'meetings.read'), false)
    when 'maintenance_plan' then exists (select 1 from "better_supabase"."maintenance_plans" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'maintenance.read'), false)
    when 'dam_usage_right' then exists (select 1 from "better_supabase"."dam_usage_rights" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dam.read'), false)
    when 'lims_sample' then exists (select 1 from "better_supabase"."lims_samples" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'lims.read'), false)
    when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'tax.read'), false)
    when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'manufacturing.read'), false)
    when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'manufacturing.read'), false)
    when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'banking.read'), false)
    when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'care_plans.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'incidents.read'), false)
    when 'advisory' then exists (select 1 from "better_supabase"."advisories" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'advisories.read'), false)
    when 'advisory_product' then exists (select 1 from "better_supabase"."advisory_products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'advisories.read'), false)
    when 'vulnerability' then exists (select 1 from "better_supabase"."vulnerabilities" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'advisories.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'content.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id" and (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'organization' then exists (select 1 from "public"."organizations" s where s."id" = (v_doc."subject_id")::uuid and s."id" = v_doc."tenant_id")
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    else false
  end) or coalesce(v_suggestion."created_by" = auth.uid(), false)) then
    raise exception 'suggestion not found' using errcode = 'P0002', hint = 'DOCUMENT_SUGGESTION_NOT_FOUND';
  end if;
  if decide_document_suggestion.decision is null or decide_document_suggestion.decision not in ('accepted', 'rejected', 'withdrawn') then
    raise exception 'decide with accepted, rejected or withdrawn' using errcode = '22023', hint = 'DOCUMENT_SUGGESTION_INVALID';
  end if;
  if decide_document_suggestion.decision = 'withdrawn' then
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_suggestion."created_by" = auth.uid(), false)) then
      raise exception 'only the author can withdraw a suggestion' using errcode = '42501', hint = 'DOCUMENT_FORBIDDEN';
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and case v_doc."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contacts.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contacts.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'posts.read'), false)
    when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'activities.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'tasks.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'invoices.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'rfq' then exists (select 1 from "better_supabase"."rfqs" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'rfqs.read'), false)
    when 'till' then exists (select 1 from "better_supabase"."tills" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'tills.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'donations.read'), false)
    when 'warranty_claim' then exists (select 1 from "better_supabase"."warranty_claims" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'warranty.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'compliance.read'), false)
    when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'compliance.read'), false)
    when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'qualifications.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'risks.read'), false)
    when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'cases.read'), false)
    when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'inspections.read'), false)
    when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'inspections.read'), false)
    when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'inspections.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'forms.read'), false)
    when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'meetings.read'), false)
    when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'meetings.read'), false)
    when 'maintenance_plan' then exists (select 1 from "better_supabase"."maintenance_plans" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'maintenance.read'), false)
    when 'dam_usage_right' then exists (select 1 from "better_supabase"."dam_usage_rights" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dam.read'), false)
    when 'lims_sample' then exists (select 1 from "better_supabase"."lims_samples" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'lims.read'), false)
    when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'tax.read'), false)
    when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'manufacturing.read'), false)
    when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'manufacturing.read'), false)
    when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'banking.read'), false)
    when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'care_plans.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'incidents.read'), false)
    when 'advisory' then exists (select 1 from "better_supabase"."advisories" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'advisories.read'), false)
    when 'advisory_product' then exists (select 1 from "better_supabase"."advisory_products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'advisories.read'), false)
    when 'vulnerability' then exists (select 1 from "better_supabase"."vulnerabilities" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'advisories.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'content.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id" and (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'organization' then exists (select 1 from "public"."organizations" s where s."id" = (v_doc."subject_id")::uuid and s."id" = v_doc."tenant_id")
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    else false
  end and case v_doc."subject_type"
    when 'message' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.send'), false)
    when 'conversation' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.send'), false)
    when 'channel' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'channels.manage'), false)
    when 'company' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contacts.write'), false)
    when 'person' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contacts.write'), false)
    when 'deal' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.write'), false)
    when 'course' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'courses.manage'), false)
    when 'post' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'posts.write'), false)
    when 'activity' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'activities.write'), false)
    when 'quote' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'quotes.write'), false)
    when 'work_item' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'tasks.write'), false)
    when 'employee' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.write'), false)
    when 'ledger_account' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.manage'), false)
    when 'invoice' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'invoices.write'), false)
    when 'product' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.manage'), false)
    when 'product_variant' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.manage'), false)
    when 'rfq' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'rfqs.write'), false)
    when 'till' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'tills.write'), false)
    when 'order' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'orders.manage'), false)
    when 'calendar_event' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.write'), false)
    when 'booking' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'bookings.manage'), false)
    when 'asset' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.manage'), false)
    when 'asset_location' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.manage'), false)
    when 'lease' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.manage'), false)
    when 'expense_report' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.manage'), false)
    when 'expense_line' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.manage'), false)
    when 'donation_fund' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'donations.manage'), false)
    when 'warranty_claim' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'warranty.write'), false)
    when 'work_order' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dispatch.manage'), false)
    when 'shipment' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'shipments.manage'), false)
    when 'contract' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contracts.write'), false)
    when 'control' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'compliance.manage'), false)
    when 'compliance_policy' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'compliance.manage'), false)
    when 'qualification_type' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'qualifications.manage'), false)
    when 'risk' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'risks.write'), false)
    when 'case' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'cases.write'), false)
    when 'inspection' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'inspections.write'), false)
    when 'inspection_program' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'inspections.manage'), false)
    when 'inspection_finding' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'inspections.write'), false)
    when 'form' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'forms.manage'), false)
    when 'meeting' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'meetings.write'), false)
    when 'meeting_decision' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'meetings.write'), false)
    when 'maintenance_plan' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'maintenance.manage'), false)
    when 'dam_usage_right' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dam.write'), false)
    when 'lims_sample' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'lims.write'), false)
    when 'tax_code' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'tax.manage'), false)
    when 'production_order' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'manufacturing.write'), false)
    when 'work_center' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'manufacturing.manage'), false)
    when 'bank_account' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'banking.manage'), false)
    when 'care_plan' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'care_plans.write'), false)
    when 'incident' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'incidents.write'), false)
    when 'advisory' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'advisories.write'), false)
    when 'advisory_product' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'advisories.write'), false)
    when 'vulnerability' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'advisories.write'), false)
    when 'content_entry' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'content.write'), false)
    when 'document' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false)
    when 'customer' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.write'), false)
    when 'drive_node' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.manage'), false)
    when 'application' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.write'), false)
    else true
  end)) then
    raise exception 'not allowed to decide suggestions on this document' using errcode = '42501', hint = 'DOCUMENT_FORBIDDEN';
  end if;
  if v_suggestion."status" <> 'open' then
    raise exception 'the suggestion was already decided' using errcode = 'PT409', hint = 'DOCUMENT_SUGGESTION_CLOSED';
  end if;
  if decide_document_suggestion.decision = 'accepted' then
    insert into "better_supabase"."document_updates" ("document_id", "tenant_id", "payload", "actor")
  values (v_doc."id", v_doc."tenant_id", v_suggestion."payload", v_suggestion."created_by")
  returning "seq" into v_seq;
  update "better_supabase"."documents" d set "updated_at" = now() where d."id" = v_doc."id";
  select count(*) into v_since from "better_supabase"."document_updates" x
  where x."document_id" = v_doc."id"
    and x."seq" > coalesce((select y."seq" from "better_supabase"."document_snapshots" y where y."document_id" = v_doc."id"), 0);
  if v_since = 200 then
    perform "better_supabase"."enqueue_job"(queue => 'documents.compact', payload => jsonb_build_object('documentId', v_doc."id"), dedupe_key => 'documents.compact:' || v_doc."id"::text, dedupe_running => false);
  end if;
  end if;
  update "better_supabase"."document_suggestions" x
    set "status" = decide_document_suggestion.decision, "decided_by" = auth.uid(), "decided_at" = now(), "note" = nullif(trim(decide_document_suggestion.note), '')
    where x."id" = v_suggestion."id"
    returning * into v_suggestion;
  if v_suggestion."status" = 'accepted' then
    perform "better_supabase".emit_event('document.suggestion_accepted', jsonb_build_object('organizationId', v_doc."tenant_id"::text, 'subjectType', v_doc."subject_type", 'subjectId', v_doc."subject_id", 'id', v_doc."id", 'name', v_doc."name", 'suggestionId', v_suggestion."id", 'authorId', v_suggestion."created_by", 'status', v_suggestion."status"), 'documents/' || v_doc."id"::text, (v_doc."tenant_id")::text, null, 'better-supabase/documents');
  perform better_supabase.audit_event(
    event_type => 'document.suggestion_accepted',
    category => 'data',
    target_type => 'document',
    record_id => v_doc."id"::text,
    tenant => (v_doc."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_doc."tenant_id"::text, 'subjectType', v_doc."subject_type", 'subjectId', v_doc."subject_id", 'id', v_doc."id", 'name', v_doc."name", 'suggestionId', v_suggestion."id", 'authorId', v_suggestion."created_by", 'status', v_suggestion."status")
  );
  elsif v_suggestion."status" = 'rejected' then
    perform "better_supabase".emit_event('document.suggestion_rejected', jsonb_build_object('organizationId', v_doc."tenant_id"::text, 'subjectType', v_doc."subject_type", 'subjectId', v_doc."subject_id", 'id', v_doc."id", 'name', v_doc."name", 'suggestionId', v_suggestion."id", 'authorId', v_suggestion."created_by", 'status', v_suggestion."status"), 'documents/' || v_doc."id"::text, (v_doc."tenant_id")::text, null, 'better-supabase/documents');
  perform better_supabase.audit_event(
    event_type => 'document.suggestion_rejected',
    category => 'data',
    target_type => 'document',
    record_id => v_doc."id"::text,
    tenant => (v_doc."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_doc."tenant_id"::text, 'subjectType', v_doc."subject_type", 'subjectId', v_doc."subject_id", 'id', v_doc."id", 'name', v_doc."name", 'suggestionId', v_suggestion."id", 'authorId', v_suggestion."created_by", 'status', v_suggestion."status")
  );
  end if;
  return jsonb_build_object('id', v_suggestion."id", 'documentId', v_suggestion."document_id", 'summary', v_suggestion."summary", 'status', v_suggestion."status", 'createdBy', v_suggestion."created_by", 'createdAt', v_suggestion."created_at", 'decidedBy', v_suggestion."decided_by", 'decidedAt', v_suggestion."decided_at", 'note', v_suggestion."note", 'update', replace(encode(v_suggestion."payload", 'base64'), E'\n', '')) || jsonb_build_object('seq', v_seq);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.dispose_asset (
  asset_id    uuid,
  disposed_on date,
  amount      bigint DEFAULT 0,
  currency    text   DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."assets"%rowtype;
  v_entry uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."assets" x where x."id" = dispose_asset.asset_id for update;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.manage'), false)) then
    raise exception 'not allowed to manage assets' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if v_row."disposed_on" is not null then
    raise exception 'the asset is already disposed of' using errcode = 'PT409', hint = 'ASSETS_DISPOSED';
  end if;
  if dispose_asset.disposed_on is null or coalesce(dispose_asset.amount, 0) < 0
    or dispose_asset.disposed_on < coalesce(v_row."acquired_on", dispose_asset.disposed_on) then
    raise exception 'a disposal needs a date on or after the acquisition and proceeds of 0 or more' using errcode = '22023', hint = 'ASSETS_DISPOSAL_INVALID';
  end if;
  if coalesce(dispose_asset.amount, 0) > 0 and (
    v_row."currency" is null or upper(coalesce(dispose_asset.currency, v_row."currency")) <> v_row."currency"
  ) then
    raise exception 'the proceeds need to be in the asset''s currency' using errcode = '22023', hint = 'ASSETS_DISPOSAL_INVALID';
  end if;
  perform "better_supabase"."asset_depreciate"(v_row."id", (date_trunc('month', dispose_asset.disposed_on) - interval '1 day')::date);
  update "better_supabase"."asset_assignments" y set "released_at" = now()
  where y."asset_id" = v_row."id" and y."released_at" is null;
  update "better_supabase"."assets" x set
    "disposed_on" = dispose_asset.disposed_on,
    "disposal_amount" = coalesce(dispose_asset.amount, 0),
    "status" = 'retired',
    "assignee_type" = null,
    "assignee_id" = null,
    "retired_at" = coalesce(x."retired_at", now()),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  v_entry := "better_supabase"."accounting_post_source"('asset_disposal', v_row."id"::text);
  perform "better_supabase".emit_event('asset.disposed', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'disposedOn', v_row."disposed_on", 'amount', v_row."disposal_amount"::text, 'currency', v_row."currency", 'entryId', v_entry), 'assets/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/assets');
  perform better_supabase.audit_event(
    event_type => 'asset.disposed',
    category => 'data',
    target_type => 'asset',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'disposed of asset',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'disposedOn', v_row."disposed_on", 'amount', v_row."disposal_amount"::text, 'currency', v_row."currency", 'entryId', v_entry)
  );
  return "better_supabase"."get_asset"(v_row."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.erase_data_subject (
  request_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."data_subject_requests";
  v_count bigint;
  v_removed jsonb := '{}'::jsonb;
  v_blanked jsonb := '{}'::jsonb;
  v_kept jsonb := '{}'::jsonb;
  v_held jsonb := '{}'::jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."data_subject_requests" x where x."id" = erase_data_subject.request_id for update;
  if v_row."id" is null then
    raise exception 'request not found' using errcode = 'P0002', hint = 'DSAR_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'data_lifecycle.export'), false)) then
    raise exception 'You may not handle data subject requests here' using errcode = '42501', hint = 'DSAR_FORBIDDEN';
  end if;
  if v_row."kind" <> 'erasure' then
    raise exception 'only an erasure request is executed' using errcode = '22023', hint = 'DSAR_INVALID';
  end if;
  if v_row."closed_at" is not null then
    raise exception 'the request is already fulfilled or refused' using errcode = 'PT409', hint = 'DSAR_CLOSED';
  end if;
  if v_row."verified_at" is null then
    raise exception 'verify the requester''s identity first' using errcode = '55000', hint = 'DSAR_UNVERIFIED';
  end if;
  if v_row."subject_type" is null then
    raise exception 'an erasure request names the record to erase' using errcode = '22023', hint = 'DSAR_INVALID';
  end if;

  if "better_supabase"."is_held"('audit', v_row."tenant_id"::text) then
    select count(*) into v_count from "better_supabase"."data_subject_requests" x where x."tenant_id"::text = v_row."tenant_id"::text and x."subject_type" = v_row."subject_type" and x."subject_id" = v_row."subject_id";
    v_held := v_held || jsonb_build_object('better_supabase.data_subject_requests', v_count);
  else
    select count(*) into v_count from "better_supabase"."data_subject_requests" x where x."tenant_id"::text = v_row."tenant_id"::text and x."subject_type" = v_row."subject_type" and x."subject_id" = v_row."subject_id";
      v_kept := v_kept || jsonb_build_object('better_supabase.data_subject_requests', v_count);
  end if;

  if "better_supabase"."is_held"('audit', v_row."tenant_id"::text) then
    select count(*) into v_count from "better_supabase"."field_changes" x where x."tenant_id"::text = v_row."tenant_id"::text and x."subject_type" = v_row."subject_type" and x."subject_id" = v_row."subject_id";
    v_held := v_held || jsonb_build_object('better_supabase.field_changes', v_count);
  else
    with blank as (update "better_supabase"."field_changes" x set "old_value" = null, "new_value" = null, "changed_by" = null where x."tenant_id"::text = v_row."tenant_id"::text and x."subject_type" = v_row."subject_type" and x."subject_id" = v_row."subject_id" returning 1) select count(*) into v_count from blank;
      v_blanked := v_blanked || jsonb_build_object('better_supabase.field_changes', v_count);
  end if;

  if "better_supabase"."is_held"('personal_data', v_row."tenant_id"::text) then
    select count(*) into v_count from "better_supabase"."consents" x where x."tenant_id"::text = v_row."tenant_id"::text and x."subject_type" = v_row."subject_type" and x."subject_id" = v_row."subject_id";
    v_held := v_held || jsonb_build_object('better_supabase.consents', v_count);
  else
    with blank as (update "better_supabase"."consents" x set "grantor_id" = null, "withdrawn_reason" = null, "signature_id" = null where x."tenant_id"::text = v_row."tenant_id"::text and x."subject_type" = v_row."subject_type" and x."subject_id" = v_row."subject_id" returning 1) select count(*) into v_count from blank;
      v_blanked := v_blanked || jsonb_build_object('better_supabase.consents', v_count);
  end if;

  if "better_supabase"."is_held"('personal_data', v_row."tenant_id"::text) then
    select count(*) into v_count from "better_supabase"."consent_signals" x where x."tenant_id"::text = v_row."tenant_id"::text and x."subject_type" = v_row."subject_type" and x."subject_id" = v_row."subject_id";
    v_held := v_held || jsonb_build_object('better_supabase.consent_signals', v_count);
  else
    with gone as (delete from "better_supabase"."consent_signals" x where x."tenant_id"::text = v_row."tenant_id"::text and x."subject_type" = v_row."subject_type" and x."subject_id" = v_row."subject_id" returning 1) select count(*) into v_count from gone;
      v_removed := v_removed || jsonb_build_object('better_supabase.consent_signals', v_count);
  end if;
  return jsonb_build_object('removed', v_removed, 'blanked', v_blanked, 'kept', v_kept, 'held', v_held);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.expense_line_guard()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_client boolean := current_user::text in ('authenticated', 'anon');
  v_state text;
begin
  if pg_trigger_depth() > 1 then
    return coalesce(new, old);
  end if;
  foreach v_state in array array[
    case when tg_op <> 'INSERT' then "better_supabase"."expense_report_state"(old."report_id") end,
    case when tg_op <> 'DELETE' then "better_supabase"."expense_report_state"(new."report_id") end
  ] loop
    if v_state = 'locked' then
      raise exception 'an approved, reimbursed or cancelled report keeps its lines' using errcode = 'PT409', hint = 'EXPENSE_REPORT_LOCKED';
    end if;
    if v_client and v_state is distinct from 'open' and v_state is not null then
      raise exception 'only a draft or rejected report''s lines change' using errcode = 'PT409', hint = 'EXPENSE_REPORT_LOCKED';
    end if;
  end loop;
  return coalesce(new, old);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.expense_report_guard()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_client boolean := current_user::text in ('authenticated', 'anon') and pg_trigger_depth() = 1;
  v_from text;
  v_to text := (case when new."cancelled_at" is not null then 'cancelled' when new."reimbursed_at" is not null then 'reimbursed' when new."approved_at" is not null then 'approved' when new."submitted_at" is not null then 'submitted' else 'draft' end);
begin
  if tg_op = 'INSERT' then
    if v_client and (coalesce(new."submitted_at"::text, new."approved_at"::text, new."approval_transaction_id"::text, new."reimbursed_at"::text, new."reimbursement_transaction_id"::text, new."cancelled_at"::text, new."approval_id"::text) is not null or new."user_id" is distinct from auth.uid()) then
      raise exception 'a new expense report is a draft of the caller; the expense functions submit and decide it' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
    end if;
    return new;
  end if;
  v_from := (case when old."cancelled_at" is not null then 'cancelled' when old."reimbursed_at" is not null then 'reimbursed' when old."approved_at" is not null then 'approved' when old."submitted_at" is not null then 'submitted' else 'draft' end);
  if v_client and ((new."submitted_at", new."approved_at", new."approval_transaction_id", new."reimbursed_at", new."reimbursement_transaction_id", new."cancelled_at", new."approval_id") is distinct from (old."submitted_at", old."approved_at", old."approval_transaction_id", old."reimbursed_at", old."reimbursement_transaction_id", old."cancelled_at", old."approval_id") or new."user_id" is distinct from old."user_id") then
    raise exception 'an expense report''s owner, status and decision change only through the expense functions' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if pg_trigger_depth() = 1 and v_from in ('approved', 'reimbursed', 'cancelled') and (new."user_id", new."currency") is distinct from (old."user_id", old."currency") then
    raise exception 'an approved, reimbursed or cancelled report keeps its owner and currency' using errcode = 'PT409', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  if v_client and "better_supabase"."expense_report_state"(old."id") <> 'open' and (new."user_id", new."currency") is distinct from (old."user_id", old."currency") then
    raise exception 'a submitted report keeps its owner and currency' using errcode = 'PT409', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  if v_from is not distinct from v_to then
    return new;
  end if;
  if (v_from, v_to) not in (('draft', 'submitted'), ('rejected', 'submitted'), ('submitted', 'approved'), ('submitted', 'rejected'), ('draft', 'cancelled'), ('submitted', 'cancelled'), ('rejected', 'cancelled'), ('approved', 'reimbursed')) then
    raise exception 'this status change is not allowed for an expense report' using errcode = 'PT409', hint = 'EXPENSE_TRANSITION_INVALID';
  end if;
  if v_to = 'submitted' then
    null;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.expense_report_state (
  report_id uuid
)
  RETURNS text
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select case when (case when p."cancelled_at" is not null then 'cancelled' when p."reimbursed_at" is not null then 'reimbursed' when p."approved_at" is not null then 'approved' when p."submitted_at" is not null then 'submitted' else 'draft' end) in ('approved', 'reimbursed', 'cancelled') then 'locked' when ((case when p."cancelled_at" is not null then 'cancelled' when p."reimbursed_at" is not null then 'reimbursed' when p."approved_at" is not null then 'approved' when p."submitted_at" is not null then 'submitted' else 'draft' end) = 'draft' or ((case when p."cancelled_at" is not null then 'cancelled' when p."reimbursed_at" is not null then 'reimbursed' when p."approved_at" is not null then 'approved' when p."submitted_at" is not null then 'submitted' else 'draft' end) = 'submitted' and exists (select 1 from "better_supabase"."approval_requests" ap where ap."id" = p."approval_id" and ap."status" in ('rejected', 'expired')))) then 'open' else 'submitted' end
  from "better_supabase"."expense_reports" p where p."id" = expense_report_state.report_id
$function$;

CREATE OR REPLACE FUNCTION better_supabase.extend_data_subject_request (
  id     uuid,
  reason text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."data_subject_requests";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."data_subject_requests" x where x."id" = extend_data_subject_request.id for update;
  if v_row."id" is null then
    raise exception 'request not found' using errcode = 'P0002', hint = 'DSAR_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'data_lifecycle.export'), false)) then
    raise exception 'You may not handle data subject requests here' using errcode = '42501', hint = 'DSAR_FORBIDDEN';
  end if;
  if v_row."closed_at" is not null then
    raise exception 'the request is already fulfilled or refused' using errcode = '55000', hint = 'DSAR_CLOSED';
  end if;
  if v_row."extended_at" is not null then
    raise exception 'the due date was already extended once' using errcode = 'PT409', hint = 'DSAR_EXTENDED';
  end if;
  if extend_data_subject_request.reason is null or length(trim(extend_data_subject_request.reason)) = 0 then
    raise exception 'reason is required' using errcode = '22023', hint = 'DSAR_INVALID';
  end if;
  update "better_supabase"."data_subject_requests" x set "due_at" = x."received_at" + interval '3 months', "extended_at" = now(), "extension_reason" = trim(extend_data_subject_request.reason)
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('data_subject_request.extended', jsonb_build_object('requestId', v_row."id", 'organizationId', v_row."tenant_id"::text, 'kind', v_row."kind"::text, 'status', v_row."status"::text, 'dueAt', v_row."due_at"), 'data-subject-requests/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/data-lifecycle');
  perform better_supabase.audit_event(
    event_type => 'data_subject_request.extended',
    category => 'data',
    target_type => 'data_subject_request',
    record_id => v_row."id"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('requestId', v_row."id", 'organizationId', v_row."tenant_id"::text, 'kind', v_row."kind"::text, 'status', v_row."status"::text, 'dueAt', v_row."due_at")
  );
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.finish_import_run (
  run uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_run_id uuid := finish_import_run.run;
  v_run "better_supabase"."import_runs";
  v_entity text;
  v_missing integer;
  v_total integer := 0;
  v_counts jsonb;
  v_outcome text := 'completed';
  v_expected integer;
  v_applied integer;
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = v_run_id for update;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if v_run."status" <> 'running' then
    raise exception 'the import is not running' using errcode = 'PT409', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;
  v_counts := v_run."counts";

  if v_run."full" then
    for v_entity in select k.key from jsonb_object_keys(v_run."counts") k(key) loop
      select count(*)::integer into v_missing from "better_supabase"."import_records" x
      where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."entity" = v_entity
        and x."role" = 'primary' and x."last_run_id" <> v_run_id
        and x."scope" in (select y."scope" from "better_supabase"."import_records" y where y."tenant_id" = v_run."tenant_id" and y."source" = v_run."source" and y."entity" = v_entity and y."last_run_id" = v_run_id);
      if not v_run."dry_run" then
        update "better_supabase"."import_records" x set "went_missing_at" = coalesce(x."went_missing_at", now())
        where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."entity" = v_entity
          and x."last_run_id" <> v_run_id
          and x."scope" in (select y."scope" from "better_supabase"."import_records" y where y."tenant_id" = v_run."tenant_id" and y."source" = v_run."source" and y."entity" = v_entity and y."last_run_id" = v_run_id);
      end if;
      v_counts := jsonb_set(v_counts, array[v_entity, 'missing'], to_jsonb(v_missing));
    end loop;
  end if;

  if v_run."plan" is not null and jsonb_typeof(v_run."plan") = 'object' then
    for v_entity in select k.key from jsonb_object_keys(v_run."plan") k(key) loop
      v_expected := coalesce((v_run."plan" ->> v_entity)::integer, 0);
      v_applied := coalesce((v_counts -> v_entity ->> 'inserted')::integer, 0)
        + coalesce((v_counts -> v_entity ->> 'updated')::integer, 0)
        + coalesce((v_counts -> v_entity ->> 'unchanged')::integer, 0);
      if v_applied < v_expected then
        v_outcome := 'incomplete';
        v_counts := jsonb_set(coalesce(v_counts, '{}'::jsonb), array[v_entity, 'missing'], to_jsonb(v_expected - v_applied), true);
      end if;
    end loop;
  end if;
  if v_outcome = 'completed' and (
    jsonb_array_length(coalesce(v_run."errors", '[]'::jsonb)) > 0
    or exists (
      select 1 from jsonb_each(coalesce(v_counts, '{}'::jsonb)) v_entity_counts(key, value)
      where coalesce((v_entity_counts.value ->> 'conflicted')::integer, 0) > 0
    )
  ) then
    v_outcome := 'completed_with_issues';
  end if;

  update "better_supabase"."import_runs" r set "status" = 'completed', "outcome" = v_outcome, "finished_at" = now(), "counts" = v_counts
  where r."id" = v_run_id;

  if not v_run."dry_run" then
    for v_entity in select k.key from jsonb_object_keys(v_counts) k(key) loop
      v_total := v_total + coalesce((v_counts -> v_entity ->> 'inserted')::integer, 0) + coalesce((v_counts -> v_entity ->> 'updated')::integer, 0);
      perform "better_supabase".emit_event('import.entity_completed', jsonb_build_object('organizationId', v_run."tenant_id", 'id', v_run_id, 'entity', v_entity, 'counts', v_counts -> v_entity), 'imports/' || v_run_id::text, (v_run."tenant_id")::text, null, 'better-supabase/imports');
      if coalesce((v_counts -> v_entity ->> 'inserted')::integer, 0) + coalesce((v_counts -> v_entity ->> 'updated')::integer, 0) > 0 then
        perform better_supabase.audit_event(
    event_type => 'import.entity_completed',
    category => 'integration',
    target_type => 'import',
    record_id => v_run_id::text,
    target_label => v_entity,
    summary => 'imported ' || v_entity,
    tenant => (v_run."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_run."tenant_id", 'id', v_run_id, 'entity', v_entity, 'counts', v_counts -> v_entity),
    idempotency_key => 'import:' || v_run_id::text || ':' || v_entity,
    actor_kind => 'integration',
    correlation_id => 'import:' || v_run_id::text
  );
      end if;
    end loop;
    perform "better_supabase".emit_event('import.completed', jsonb_build_object('organizationId', v_run."tenant_id", 'id', v_run_id, 'count', v_total), 'imports/' || v_run_id::text, (v_run."tenant_id")::text, null, 'better-supabase/imports');
  end if;
  perform "better_supabase"."search_refresh_run"(v_run_id);
  return v_counts;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.hand_over_to_collection (
  invoice_ids     uuid[],
  agency_party_id text,
  note            text   DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."invoices";
  v_id uuid;
  v_result jsonb := '[]'::jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if nullif(trim(hand_over_to_collection.agency_party_id), '') is null or length(hand_over_to_collection.agency_party_id) > 150
    or coalesce(array_length(hand_over_to_collection.invoice_ids, 1), 0) not between 1 and 500
    or length(hand_over_to_collection.note) > 2000 then
    raise exception 'hand over 1 to 500 invoices to an agency party, with a note of at most 2000 characters' using errcode = '22023', hint = 'INVOICE_HAND_OVER_INVALID';
  end if;
  for v_id in select distinct x from unnest(hand_over_to_collection.invoice_ids) x order by x loop
    select * into v_row from "better_supabase"."invoices" x where x."id" = v_id and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", case when x."direction" = 'purchase' then 'invoices.purchase' else 'invoices.collect' end), false)) for update;
    if v_row."id" is null then
      raise exception 'no such invoice you can edit' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
    end if;
    if not v_row."kind" = 'invoice' or v_row."status" not in ('issued', 'partially_paid') or v_row."direction" <> 'sales' then
      raise exception 'only an open sales invoice goes to collection' using errcode = '55000', hint = 'INVOICE_NOT_PAYABLE';
    end if;
    if v_row."collection_status" is not null then
      raise exception 'the invoice was handed over to collection already' using errcode = 'PT409', hint = 'INVOICE_ALREADY_HANDED_OVER';
    end if;
    update "better_supabase"."invoices" x set
      "collection_status" = 'handed_over',
      "collection_agency_id" = trim(hand_over_to_collection.agency_party_id),
      "collection_handed_at" = now(),
      "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
    insert into "better_supabase"."invoice_dunning_history" ("tenant_id", "invoice_id", "kind", "level", "balance", "note")
    values (v_row."tenant_id", v_row."id", 'handed_over', v_row."dunning_level", (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total"), nullif(trim(hand_over_to_collection.note), ''));
    perform "better_supabase".emit_event('invoice.collection_started', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'agencyPartyId', trim(hand_over_to_collection.agency_party_id), 'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text, 'level', v_row."dunning_level"), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  perform better_supabase.audit_event(
    event_type => 'invoice.collection_started',
    category => 'billing',
    target_type => 'invoice',
    record_id => v_row."id"::text,
    target_label => v_row."identifier",
    summary => 'invoice collection_started',
    tenant => (v_row."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'agencyPartyId', trim(hand_over_to_collection.agency_party_id), 'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text, 'level', v_row."dunning_level")
  );
    v_result := v_result || to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'deposit_amount', v_row."deposit_amount"::text, 'discount_amount', v_row."discount_amount"::text, 'discount_amount_early', v_row."discount_amount_early"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code", 'taxCodeId', il."tax_code_id", 'unitCost', il."unit_cost"::text, 'dimensions', il."dimensions") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb));
  end loop;
  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.heartbeat_import_run (
  run     uuid,
  seconds integer DEFAULT 30
)
  RETURNS timestamp WITH time zone
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_until timestamptz;
begin
  if not (auth.role() = 'service_role') then
    raise exception 'only the service role can heartbeat an import' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  update "better_supabase"."import_runs" r set "heartbeat_at" = now(), "lease_expires_at" = now() + make_interval(secs => greatest(heartbeat_import_run.seconds, 1))
  where r."id" = heartbeat_import_run.run and r."status" = 'running'
  returning r."lease_expires_at" into v_until;
  if v_until is null then
    raise exception 'the import is not running' using errcode = 'PT409', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;
  return v_until;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_upsert_batch (
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
  v_run_id uuid := import_upsert_batch.run;
  v_entity text := import_upsert_batch.entity;
  v_run "better_supabase"."import_runs";
  v_result jsonb;
  v_name text;
  v_previous jsonb := '{}'::jsonb;
begin
  -- No row lock here: two batches of one run write at the same time, and the
  -- counts update at the end is the only statement that locks the run row.
  select * into v_run from "better_supabase"."import_runs" r where r."id" = v_run_id;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if v_run."status" <> 'running' then
    raise exception 'the import is not running' using errcode = 'PT409', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;
  if coalesce((v_run."plan" ->> 'unordered')::boolean, false) is distinct from true
    and jsonb_typeof(v_run."plan" -> 'waves') = 'array'
    and exists (
      select 1 from jsonb_array_elements(v_run."plan" -> 'waves') with ordinality as w(wave, n)
      where w.wave ? v_entity and exists (
        select 1 from jsonb_array_elements(v_run."plan" -> 'waves') with ordinality as earlier(wave, n)
        cross join lateral jsonb_array_elements_text(earlier.wave) dep(entity)
        join "better_supabase"."import_chunks" c on c."run_id" = v_run_id
          and c."entity" = dep.entity and c."status" <> 'done'
        where earlier.n < w.n)) then
    raise exception 'an earlier import wave still has open chunks' using errcode = '55000', hint = 'IMPORT_DEPENDENCY_OPEN';
  end if;

  foreach v_name in array array['better_supabase.import_run', 'better_supabase.correlation_id', 'better_supabase.import_events', 'better_supabase.import_audit', 'better_supabase.search_deferred'] loop
    v_previous := v_previous || jsonb_build_object(v_name, coalesce(current_setting(v_name, true), ''));
  end loop;
  perform "better_supabase"."begin_import_session"(v_run_id);
  perform set_config('better_supabase.search_deferred', 'on', true);

  if v_run."dry_run" then
    begin
      v_result := "better_supabase"."import_apply_batch"(v_run_id, v_entity, import_upsert_batch.items);
      raise exception 'dry run' using errcode = 'BSDRY';
    exception when sqlstate 'BSDRY' then
      null;
    end;
  else
    v_result := "better_supabase"."import_apply_batch"(v_run_id, v_entity, import_upsert_batch.items);
  end if;

  foreach v_name in array array['better_supabase.import_run', 'better_supabase.correlation_id', 'better_supabase.import_events', 'better_supabase.import_audit', 'better_supabase.search_deferred'] loop
    perform set_config(v_name, v_previous ->> v_name, true);
  end loop;

  update "better_supabase"."import_runs" r set
    "counts" = jsonb_set(r."counts", array[v_entity], jsonb_build_object(
      'inserted', coalesce(r."counts" -> v_entity ->> 'inserted', '0')::integer + coalesce((v_result ->> 'inserted')::integer, 0),
      'updated', coalesce(r."counts" -> v_entity ->> 'updated', '0')::integer + coalesce((v_result ->> 'updated')::integer, 0),
      'unchanged', coalesce(r."counts" -> v_entity ->> 'unchanged', '0')::integer + coalesce((v_result ->> 'unchanged')::integer, 0),
      'conflicted', coalesce(r."counts" -> v_entity ->> 'conflicted', '0')::integer + coalesce((v_result ->> 'conflicted')::integer, 0),
      'missing', coalesce((r."counts" -> v_entity ->> 'missing')::integer, 0)
    )),
    "errors" = r."errors" || coalesce(v_result -> 'errors', '[]'::jsonb),
    "diff" = (select coalesce(jsonb_agg(d.value), '[]'::jsonb) from (
      select value from jsonb_array_elements(r."diff" || coalesce(v_result -> 'diff', '[]'::jsonb)) value limit 100
    ) d)
  where r."id" = v_run_id;
  return v_result || jsonb_build_object('dryRun', v_run."dry_run");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.issue_invoice (
  invoice      uuid,
  issued_on    date,
  due_on       date  DEFAULT NULL::date,
  actor        jsonb DEFAULT NULL::jsonb,
  fixed_number text  DEFAULT NULL::text
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
  v_was text;
  v_warnings jsonb;
  v_early_bps integer;
  v_early_days integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."invoices" x where x."id" = issue_invoice.invoice;
  if v_row."id" is null or (((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", case when v_row."direction" = 'purchase' then 'invoices.purchase' else 'invoices.write' end), false))) is not true then
    if v_row."id" is not null and (((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'invoices.read'), false)) or better_supabase.row_visible('"better_supabase"."invoices"'::regclass, 'id', v_row."id")) then
      raise exception 'you may not issue this invoice' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
    end if;
    raise exception 'no such invoice you can read' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  select * into v_row from "better_supabase"."invoices" x where x."id" = issue_invoice.invoice for update;
  if not found then
    raise exception 'no such invoice you can read' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  
  if v_row."status" <> 'draft' then
    raise exception 'the invoice was already issued' using errcode = 'PT409', hint = 'INVOICE_NOT_DRAFT';
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
  perform "better_supabase"."issue_invoice_tax"(v_row."id", v_issued_on);
  select z."discount_bps", z."discount_days" into v_early_bps, v_early_days
  from "better_supabase"."payment_terms" z where z."id" = v_row."payment_terms_id";
  if v_row."kind" = 'credit_note' then
    select * into v_original from "better_supabase"."invoices" x where x."id" = v_row."original_id" for update;
    if v_row."total" > v_original."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_original."id"), 0) - v_original."credited_total" then
      raise exception 'a credit note can''t exceed the invoice''s total less its earlier credits' using errcode = '23514', hint = 'INVOICE_CREDIT_TOO_LARGE';
    end if;
    if v_row."direction" = 'purchase' then
      if coalesce(issue_invoice.fixed_number, (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'purchase_credit_note' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end)) is not null then
    v_identifier := coalesce(issue_invoice.fixed_number, (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'purchase_credit_note' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end));
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_identifier from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_row."tenant_id"::text || ':purchase_credit_note' || ':' || "better_supabase"."number_scope"(v_row."tenant_id", v_row.legal_entity_id), 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from (select * from "better_supabase"."invoices" k where k."direction" = 'purchase' and k."kind" = 'credit_note') x where x."tenant_id" = v_row."tenant_id" and "better_supabase"."number_scope"(x."tenant_id", x.legal_entity_id) = "better_supabase"."number_scope"(v_row."tenant_id", v_row.legal_entity_id);
  v_identifier := 'BCN-' || v_seq::text;
  end if;
    else
      if coalesce(issue_invoice.fixed_number, (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'credit_note' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end)) is not null then
    v_identifier := coalesce(issue_invoice.fixed_number, (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'credit_note' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end));
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_identifier from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_row."tenant_id"::text || ':credit_note' || ':' || "better_supabase"."number_scope"(v_row."tenant_id", v_row.legal_entity_id), 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from (select * from "better_supabase"."invoices" k where k."direction" = 'sales' and k."kind" = 'credit_note') x where x."tenant_id" = v_row."tenant_id" and "better_supabase"."number_scope"(x."tenant_id", x.legal_entity_id) = "better_supabase"."number_scope"(v_row."tenant_id", v_row.legal_entity_id);
  v_identifier := 'CN-' || v_seq::text;
  end if;
    end if;
  else
    if v_row."direction" = 'purchase' then
      if coalesce(issue_invoice.fixed_number, (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'purchase_bill' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end)) is not null then
    v_identifier := coalesce(issue_invoice.fixed_number, (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'purchase_bill' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end));
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_identifier from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_row."tenant_id"::text || ':purchase_bill' || ':' || "better_supabase"."number_scope"(v_row."tenant_id", v_row.legal_entity_id), 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from (select * from "better_supabase"."invoices" k where k."direction" = 'purchase' and k."kind" = 'invoice') x where x."tenant_id" = v_row."tenant_id" and "better_supabase"."number_scope"(x."tenant_id", x.legal_entity_id) = "better_supabase"."number_scope"(v_row."tenant_id", v_row.legal_entity_id);
  v_identifier := 'BILL-' || v_seq::text;
  end if;
    else
      if coalesce(issue_invoice.fixed_number, (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'invoice' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end)) is not null then
    v_identifier := coalesce(issue_invoice.fixed_number, (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'invoice' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end));
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_identifier from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_row."tenant_id"::text || ':invoice' || ':' || "better_supabase"."number_scope"(v_row."tenant_id", v_row.legal_entity_id), 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from (select * from "better_supabase"."invoices" k where k."direction" = 'sales' and k."kind" = 'invoice') x where x."tenant_id" = v_row."tenant_id" and "better_supabase"."number_scope"(x."tenant_id", x.legal_entity_id) = "better_supabase"."number_scope"(v_row."tenant_id", v_row.legal_entity_id);
  v_identifier := 'INV-' || v_seq::text;
  end if;
    end if;
  end if;
  if v_row."kind" = 'invoice' and not v_row."direction" = 'purchase' and coalesce(v_row."company_id"::text, v_row."contact_id"::text) is not null then
    declare
      v_limit bigint;
      v_block text;
    begin
      select s.credit_limit, s.credit_block into v_limit, v_block from (select p."credit_limit", p."credit_currency", p."credit_block" from "better_supabase"."companies" p where p."id"::text = coalesce(v_row."company_id"::text, v_row."contact_id"::text) and p."tenant_id" = v_row."tenant_id" and p."merged_into" is null union all select p."credit_limit", p."credit_currency", p."credit_block" from "better_supabase"."people" p where p."id"::text = coalesce(v_row."company_id"::text, v_row."contact_id"::text) and p."tenant_id" = v_row."tenant_id" and p."merged_into" is null) s(credit_limit, credit_currency, credit_block)
      where s.credit_limit is not null and coalesce(s.credit_currency, v_row."currency") = v_row."currency"
      order by s.credit_limit limit 1;
      if v_limit is not null and v_block is distinct from 'none' and (select coalesce(sum((o."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = o."id"), 0) - o."credited_total" - o."paid_total")), 0) from "better_supabase"."invoices" o
        where o."tenant_id" = v_row."tenant_id" and o."id" <> v_row."id" and o."currency" = v_row."currency"
          and coalesce(o."company_id"::text, o."contact_id"::text) = coalesce(v_row."company_id"::text, v_row."contact_id"::text) and not o."direction" = 'purchase'
          and o."kind" = 'invoice' and o."status" in ('issued', 'partially_paid')) + v_row."total" > v_limit and not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'orders.override_credit'), false)) then
        if v_block = 'soft' then
          v_warnings := coalesce(v_warnings, '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
            'code', 'INVOICE_CREDIT_LIMIT_EXCEEDED', 'message', 'this invoice takes the customer over their credit limit', 'limit', v_limit::text));
        else
          raise exception 'this invoice takes the customer over their credit limit' using errcode = '55000', hint = 'INVOICE_CREDIT_LIMIT_EXCEEDED';
        end if;
      end if;
    end;
  end if;
  update "better_supabase"."invoices" x set "status" = 'issued', "number" = v_seq, "identifier" = v_identifier,
    "issued_on" = v_issued_on,
    "due_on" = coalesce(issue_invoice.due_on, v_issued_on + x."terms_days"),
    "discount_due_on" = case when coalesce(v_early_bps, 0) > 0 and x."kind" = 'invoice' then v_issued_on + v_early_days end,
    "discount_amount_early" = case when coalesce(v_early_bps, 0) > 0 and x."kind" = 'invoice'
      then ((x."total"::numeric * v_early_bps + 5000) / 10000)::bigint end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('invoice.issued', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'total', v_row."total"::text, 'currency', v_row."currency", 'dueOn', v_row."due_on"), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  if v_row."kind" = 'credit_note' then
    v_was := v_original."status"::text;
    update "better_supabase"."invoices" x set "credited_total" = x."credited_total" + v_row."total", "updated_at" = now()
    where x."id" = v_original."id"
    returning * into v_original;
  update "better_supabase"."invoices" x set
    "paid_total" = coalesce(-(select sum(e."amount") from "better_supabase"."ledger_entries" e where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text)), 0),
    "updated_at" = now()
  where x."id" = v_original."id"
  returning * into v_original;
  if v_original."status" in ('issued', 'partially_paid', 'paid') then
    update "better_supabase"."invoices" x set
      "status" = case
      when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then 'paid'
      when x."paid_total" > 0 or x."credited_total" > 0 then 'partially_paid'
      else 'issued' end,
      "paid_at" = case when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then coalesce(x."paid_at", now()) end
    where x."id" = v_original."id"
    returning * into v_original;
  end if;
    perform "better_supabase".emit_event('invoice.credited', jsonb_build_object('organizationId', v_original."tenant_id", 'invoiceId', v_original."id", 'subjectType', 'invoice', 'subjectId', v_original."id"::text, 'identifier', v_original."identifier", 'creditNoteId', v_row."id", 'amount', v_row."total"::text), 'invoices/' || v_original."id"::text, (v_original."tenant_id"::text)::text, null, 'better-supabase/invoices');
    if v_original."status" = 'paid' and v_was <> 'paid' then
      perform "better_supabase".emit_event('invoice.paid', jsonb_build_object('organizationId', v_original."tenant_id", 'invoiceId', v_original."id", 'subjectType', 'invoice', 'subjectId', v_original."id"::text, 'identifier', v_original."identifier", 'total', v_original."total"::text), 'invoices/' || v_original."id"::text, (v_original."tenant_id"::text)::text, null, 'better-supabase/invoices');
    end if;
  end if;
  if not better_supabase.import_run() is not null then
    perform "better_supabase"."accounting_post_source"('invoice', v_row."id"::text);
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_invoice_issue"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'deposit_amount', v_row."deposit_amount"::text, 'discount_amount', v_row."discount_amount"::text, 'discount_amount_early', v_row."discount_amount_early"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code", 'taxCodeId', il."tax_code_id", 'unitCost', il."unit_cost"::text, 'dimensions', il."dimensions") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb))|| case when v_warnings is null then '{}'::jsonb else jsonb_build_object('warnings', v_warnings) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.mark_activity_error (
  activity uuid,
  reason   text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid := mark_activity_error.activity;
  v_reason text := nullif(trim(mark_activity_error.reason), '');
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."activity_subjects" sx where sx."activity_id" = mark_activity_error.activity), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_reason is null then
    raise exception 'say why the activity is in error' using errcode = '23502', hint = 'ACTIVITY_REASON_REQUIRED';
  end if;
  if exists (select 1 from "better_supabase"."activities" x where x."id" = v_id and ((auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and x."archived_at" is null) and x."marked_error_at" is not null) then
    raise exception 'the activity is already marked in error' using errcode = 'PT409', hint = 'ACTIVITY_ALREADY_MARKED_ERROR';
  end if;
  update "better_supabase"."activities" x set
    "marked_error_at" = now(),
    "marked_error_by" = auth.uid(),
    "marked_error_reason" = v_reason,
    "locked_at" = least(coalesce(x."locked_at", now()), now())
  where x."id" = v_id and ((auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and x."archived_at" is null)
  returning x."tenant_id", x."type"::text into v_tenant, v_type;
  if v_tenant is null then
    raise exception 'no such activity you can edit' using errcode = 'P0002', hint = 'ACTIVITY_NOT_FOUND';
  end if;
  perform "better_supabase".emit_event('activity.error_marked', jsonb_build_object('organizationId', v_tenant, 'activityId', v_id, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects, 'reason', v_reason), 'activities/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."activity_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."activities" x where x."id" = v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.mark_attachment_missing (
  id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."attachments";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."attachments" a where a."id" = mark_attachment_missing.id for update;
  if v_row."id" is null then
    raise exception 'No attachment has this id' using errcode = 'P0002', hint = 'ATTACHMENT_NOT_FOUND';
  end if;
  if not (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'attachments.manage'), false) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))) then
    raise exception 'not allowed to manage this attachment' using errcode = '42501', hint = 'ATTACHMENT_FORBIDDEN';
  end if;
  if v_row."uploaded_at" is not null or v_row."storage_status" = 'stored' then
    raise exception 'the file is already stored' using errcode = 'PT409', hint = 'ATTACHMENT_NOT_CLAIMABLE';
  end if;
  update "better_supabase"."attachments" a set "storage_status" = 'missing' where a."id" = v_row."id"
  returning * into v_row;
  return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.open_approval (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  action       text,
  policy       jsonb,
  reason       text,
  payload      jsonb,
  requested_by uuid  DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_req "better_supabase"."approval_requests"%rowtype;
  v_policy jsonb := open_approval.policy;
  v_requester uuid := coalesce(open_approval.requested_by, auth.uid());
begin
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_approval_request"(uuid, text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::text)', v_hook::oid::regproc)
        using open_approval.tenant, open_approval.subject_type, open_approval.subject_id, open_approval.action;
    end if;
  end;
  if exists (select 1 from jsonb_array_elements(coalesce(v_policy -> 'steps', '[]'::jsonb)) e where e.value -> 'required' = '"all"'::jsonb) then
    v_policy := jsonb_set(v_policy, '{steps}', (
      select jsonb_agg(case when e.value -> 'required' = '"all"'::jsonb
        then e.value || jsonb_build_object('approvers', jsonb_build_object('users', h.users), 'required', jsonb_array_length(h.users), 'all', true, 'permission', e.value -> 'approvers' ->> 'permission')
        else e.value end order by e.ordinality)
      from jsonb_array_elements(v_policy -> 'steps') with ordinality e
      left join lateral (
        select coalesce(jsonb_agg(distinct to_jsonb(u.id::text)), '[]'::jsonb) as users
        from (select m."user_id" from "public"."memberships" m
        where m."organization_id" = open_approval.tenant
          and coalesce(better_supabase.can_user(m."user_id", 'tenant', open_approval.tenant, (e.value -> 'approvers' ->> 'permission')), false)) as u(id)
        where u.id is not null and (u.id is distinct from v_requester or coalesce((v_policy ->> 'selfApproval')::boolean, false))
          and not (coalesce(v_policy -> 'excludedUserIds', '[]'::jsonb) ? u.id::text)
      ) h on e.value -> 'required' = '"all"'::jsonb
    ));
    if exists (select 1 from jsonb_array_elements(v_policy -> 'steps') e where e.value -> 'required' = '0'::jsonb) then
      raise exception 'nobody holds the permission a step asks every holder of' using errcode = '22023', hint = 'APPROVAL_APPROVERS_EMPTY';
    end if;
  end if;
  insert into "better_supabase"."approval_requests" ("tenant_id", "subject_type", "subject_id", "action", "policy", "requested_by", "reason", "payload", "expires_at")
  values (open_approval.tenant, open_approval.subject_type, open_approval.subject_id, open_approval.action, v_policy, v_requester, open_approval.reason, coalesce(open_approval.payload, '{}'::jsonb),
    case when open_approval.policy ->> 'expiresIn' is not null then now() + (open_approval.policy ->> 'expiresIn')::interval end)
  on conflict ("subject_type", "subject_id", "action") where "status" = 'pending' do nothing
  returning * into v_req;
  if not found then
    raise exception 'this record already has a pending request for that action' using errcode = '23505', hint = 'APPROVAL_PENDING';
  end if;
  perform "better_supabase".emit_event('approval.requested', jsonb_build_object('organizationId', v_req."tenant_id"::text, 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step"), 'approval-requests/' || v_req."id"::text, (v_req."tenant_id")::text, null, 'better-supabase/approvals');
  perform better_supabase.audit_event(
    event_type => 'approval.requested',
    category => 'data',
    target_type => 'approval_request',
    record_id => v_req."id"::text,
    summary => 'requested' || ' ' || v_req."action" || ' on ' || v_req."subject_type" || ' ' || v_req."subject_id",
    tenant => (v_req."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_req."tenant_id"::text, 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step")
  );
  perform "better_supabase"."approval_notify"(v_req."id", 'requested');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_approval_request"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_req."id";
    end if;
  end;
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step", 'steps', v_req."policy" -> 'steps', 'requestedBy', v_req."requested_by", 'reason', v_req."reason", 'payload', v_req."payload", 'expiresAt', v_req."expires_at", 'decidedAt', v_req."decided_at", 'mode', coalesce(v_req."policy" ->> 'mode', 'authorize'), 'fingerprint', v_req."fingerprint", 'consumedAt', v_req."consumed_at", 'createdAt', v_req."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_delivery_proof (
  shipment_id     uuid,
  delivered_to    text,
  proof_reference text DEFAULT NULL::text,
  attachment_id   uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_ship "better_supabase"."shipments"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_ship from "better_supabase"."shipments" x where x."id" = record_delivery_proof.shipment_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_ship."tenant_id", 'shipments.manage'), false)) then
    raise exception 'shipment not found' using errcode = 'P0002', hint = 'SHIPMENT_NOT_FOUND';
  end if;
  if v_ship."status" <> 'delivered' then
    raise exception 'proof can only be recorded for a delivered shipment' using errcode = '55000', hint = 'SHIPMENT_NOT_DELIVERED';
  end if;
  if record_delivery_proof.delivered_to is null or length(btrim(record_delivery_proof.delivered_to)) not between 1 and 500 then
    raise exception 'delivered_to needs 1 to 500 characters' using errcode = '22023', hint = 'SHIPMENT_PROOF_INVALID';
  end if;
  if v_ship."proof_recorded_at" is not null then
    raise exception 'the proof of delivery is already recorded' using errcode = 'PT409', hint = 'SHIPMENT_PROOF_RECORDED';
  end if;
  update "better_supabase"."shipments" x set
      "delivered_to" = btrim(record_delivery_proof.delivered_to),
      "proof_reference" = record_delivery_proof.proof_reference,
      "proof_attachment_id" = record_delivery_proof.attachment_id,
      "proof_recorded_at" = now(),
    "updated_at" = now()
  where x."id" = v_ship."id"
  returning * into v_ship;
  perform "better_supabase".emit_event('shipment.proof_recorded', jsonb_build_object('organizationId', v_ship."tenant_id"::text, 'id', v_ship."id", 'deliveredTo', v_ship."delivered_to"), 'shipments/' || v_ship."id"::text, (v_ship."tenant_id")::text, null, 'better-supabase/shipments');
  perform better_supabase.audit_event(
    event_type => 'shipment.proof_recorded',
    category => 'data',
    target_type => 'shipment',
    record_id => v_ship."id"::text,
    target_label => v_ship."reference",
    summary => 'recorded proof of delivery',
    tenant => (v_ship."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_ship."tenant_id"::text, 'id', v_ship."id", 'deliveredTo', v_ship."delivered_to")
  );
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'direction', v_ship."direction", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'deliveredTo', v_ship."delivered_to", 'proofReference', v_ship."proof_reference", 'proofAttachmentId', v_ship."proof_attachment_id", 'proofRecordedAt', v_ship."proof_recorded_at", 'cancelledAt', v_ship."cancelled_at", 'archivedAt', v_ship."archived_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id"));
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
  select * into v_row from "better_supabase"."invoices" x where x."id" = record_invoice_payment.invoice;
  if v_row."id" is null or (((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", case when v_row."direction" = 'purchase' then 'invoices.purchase' else 'invoices.write' end), false))) is not true then
    if v_row."id" is not null and (((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'invoices.read'), false)) or better_supabase.row_visible('"better_supabase"."invoices"'::regclass, 'id', v_row."id")) then
      raise exception 'you may not record a payment on this invoice' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
    end if;
    raise exception 'no such invoice you can read' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  select * into v_row from "better_supabase"."invoices" x where x."id" = record_invoice_payment.invoice for update;
  if not found then
    raise exception 'no such invoice you can read' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
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
  if v_row."direction" = 'purchase' and v_row."purchase_order_id" is not null and record_invoice_payment.amount > 0
    and "better_supabase"."invoice_match_result"(v_row."id") ->> 'status' <> 'matched'
    and not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'invoices.override_match'), false)) then
    raise exception 'the bill doesn''t match its purchase order and receipts; someone with invoices.override_match can pay it' using errcode = '55000', hint = 'INVOICE_MATCH_FAILED';
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
    return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'deposit_amount', v_row."deposit_amount"::text, 'discount_amount', v_row."discount_amount"::text, 'discount_amount_early', v_row."discount_amount_early"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code", 'taxCodeId', il."tax_code_id", 'unitCost', il."unit_cost"::text, 'dimensions', il."dimensions") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
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
      case when v_row."direction" = 'purchase' then 'invoices:paid:' || v_row."currency" else 'invoices:cash:' || v_row."currency" end, 'Invoice payments ' || v_row."currency",
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
  if v_row."status" in ('issued', 'partially_paid', 'paid') then
    update "better_supabase"."invoices" x set
      "status" = case
      when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then 'paid'
      when x."paid_total" > 0 or x."credited_total" > 0 then 'partially_paid'
      else 'issued' end,
      "paid_at" = case when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then coalesce(x."paid_at", now()) end
    where x."id" = v_row."id"
    returning * into v_row;
  end if;
  if not better_supabase.import_run() is not null then
    perform "better_supabase"."accounting_post_source"('invoice_payment', v_payment::text);
  end if;
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
  return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'deposit_amount', v_row."deposit_amount"::text, 'discount_amount', v_row."discount_amount"::text, 'discount_amount_early', v_row."discount_amount_early"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code", 'taxCodeId', il."tax_code_id", 'unitCost', il."unit_cost"::text, 'dimensions', il."dimensions") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.redeliver_webhook (
  delivery uuid
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_endpoint uuid;
  v_status text;
  v_tenant uuid;
  v_enabled boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select v."endpoint_id", v."status" into v_endpoint, v_status
  from "better_supabase"."webhook_deliveries" v where v."id" = redeliver_webhook.delivery;
  if not found then
    raise exception 'Webhook delivery not found' using errcode = 'P0002', hint = 'WEBHOOK_DELIVERY_NOT_FOUND';
  end if;
  select d."tenant_id", d."enabled" into v_tenant, v_enabled
  from "better_supabase"."webhook_endpoints" d where d."id" = v_endpoint;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not coalesce(better_supabase.can('tenant', v_tenant, 'webhooks.manage'), false) then
    raise exception 'Not allowed to manage this webhook endpoint' using errcode = '42501', hint = 'WEBHOOK_FORBIDDEN';
  end if;
  if v_status in ('pending', 'delivering') then
    raise exception 'The delivery is still in progress' using errcode = 'PT409', hint = 'WEBHOOK_DELIVERY_IN_PROGRESS';
  end if;
  if not v_enabled then
    raise exception 'Webhook endpoint is disabled' using errcode = '55000', hint = 'WEBHOOK_ENDPOINT_DISABLED';
  end if;
  update "better_supabase"."webhook_deliveries" v
  set "status" = 'pending', "attempt" = 0, "available_at" = now(), "lease_expires_at" = null, "processed_at" = null, "last_error" = null, "updated_at" = now()
  where v."id" = redeliver_webhook.delivery;
  return redeliver_webhook.delivery;
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
    raise exception 'only an approved report can be reimbursed' using errcode = 'PT409', hint = 'EXPENSE_REPORT_LOCKED';
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

CREATE OR REPLACE FUNCTION better_supabase.remove_expense_line (
  line_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_line "better_supabase"."expense_lines"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_line from "better_supabase"."expense_lines" l where l."id" = remove_expense_line.line_id;
  if not found then
    raise exception 'no such expense line' using errcode = 'P0002', hint = 'EXPENSE_LINE_NOT_FOUND';
  end if;
  select * into v_row from "better_supabase"."expense_reports" x where x."id" = v_line."report_id" for update;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (coalesce(v_row."user_id" = auth.uid(), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.submit'), false)) then
    raise exception 'only the member who owns the report can change it' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) not in ('draft', 'rejected') then
    raise exception 'only a draft or rejected report can change' using errcode = 'PT409', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  delete from "better_supabase"."expense_lines" l where l."id" = v_line."id";
  update "better_supabase"."expense_reports" x set "updated_at" = now() where x."id" = v_row."id"
    returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'title', v_row."title", 'currency', v_row."currency", 'note', v_row."note", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'approvalId', v_row."approval_id", 'submittedAt', v_row."submitted_at", 'approvedAt', v_row."approved_at", 'approvalTransactionId', v_row."approval_transaction_id", 'reimbursedAt', v_row."reimbursed_at", 'reimbursementTransactionId', v_row."reimbursement_transaction_id", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'dimensions', l."dimensions", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', (select count(*) from "better_supabase"."attachments" t where t."subject_type" = 'expense_line' and t."subject_id" = l."id"::text and t."uploaded_at" is not null and t."status" <> 'infected'), 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = v_row."id"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.remove_invoice_charge (
  charge uuid,
  actor  jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."invoices";
  v_amount bigint;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x.* into v_row from "better_supabase"."invoices" x join "better_supabase"."invoice_charges" c on c."invoice_id" = x."id"
  where c."id" = remove_invoice_charge.charge and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", case when x."direction" = 'purchase' then 'invoices.purchase' else 'invoices.write' end), false))
  for update of x;
  if v_row."id" is null then
    raise exception 'no such charge on an invoice you can edit' using errcode = 'P0002', hint = 'INVOICE_CHARGE_NOT_FOUND';
  end if;
  if v_row."status" not in ('issued', 'partially_paid', 'paid') then
    raise exception 'only an issued invoice changes its charges' using errcode = '55000', hint = 'INVOICE_NOT_CHARGEABLE';
  end if;
  if remove_invoice_charge.actor is not null then
    if jsonb_typeof(remove_invoice_charge.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(remove_invoice_charge.actor ->> 'ip', '')::inet, nullif(remove_invoice_charge.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(remove_invoice_charge.actor::text, ''), true);
  delete from "better_supabase"."invoice_charges" c where c."id" = remove_invoice_charge.charge
  returning c."amount" into v_amount;
  update "better_supabase"."invoices" x set
    "paid_total" = coalesce(-(select sum(e."amount") from "better_supabase"."ledger_entries" e where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text)), 0),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if v_row."status" in ('issued', 'partially_paid', 'paid') then
    update "better_supabase"."invoices" x set
      "status" = case
      when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then 'paid'
      when x."paid_total" > 0 or x."credited_total" > 0 then 'partially_paid'
      else 'issued' end,
      "paid_at" = case when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then coalesce(x."paid_at", now()) end
    where x."id" = v_row."id"
    returning * into v_row;
  end if;
  perform "better_supabase"."accounting_reverse_source"(v_row."tenant_id", 'invoice_charge', remove_invoice_charge.charge::text);
  perform "better_supabase".emit_event('invoice.charge_removed', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'chargeId', remove_invoice_charge.charge, 'amount', v_amount::text, 'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  perform better_supabase.audit_event(
    event_type => 'invoice.charge_removed',
    category => 'billing',
    target_type => 'invoice',
    record_id => v_row."id"::text,
    target_label => v_row."identifier",
    summary => 'invoice charge_removed',
    tenant => (v_row."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'chargeId', remove_invoice_charge.charge, 'amount', v_amount::text, 'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text)
  );
  return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'deposit_amount', v_row."deposit_amount"::text, 'discount_amount', v_row."discount_amount"::text, 'discount_amount_early', v_row."discount_amount_early"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code", 'taxCodeId', il."tax_code_id", 'unitCost', il."unit_cost"::text, 'dimensions', il."dimensions") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb));
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
  select * into v_row from "better_supabase"."invoices" x where x."id" = (v_meta ->> 'invoiceId')::uuid and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", case when x."direction" = 'purchase' then 'invoices.purchase' else 'invoices.manage' end), false)) for update;
  if v_meta is null or v_row."id" is null then
    raise exception 'no such payment on an invoice you can manage' using errcode = 'P0002', hint = 'INVOICE_PAYMENT_NOT_FOUND';
  end if;
  if coalesce(v_meta ->> 'method', '') = any ('{stripe,order}'::text[]) then
    raise exception 'a payment provider''s payment is refunded through the provider, not reversed' using errcode = '55000', hint = 'INVOICE_PAYMENT_PROVIDER';
  end if;
  if (v_meta ->> 'reversal')::boolean is true
    or exists (select 1 from "better_supabase"."ledger_transactions" y where y."reverses" = reverse_invoice_payment.payment) then
    raise exception 'this payment is a reversal or is already reversed' using errcode = 'PT409', hint = 'INVOICE_PAYMENT_REVERSED';
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
  if v_row."status" in ('issued', 'partially_paid', 'paid') then
    update "better_supabase"."invoices" x set
      "status" = case
      when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then 'paid'
      when x."paid_total" > 0 or x."credited_total" > 0 then 'partially_paid'
      else 'issued' end,
      "paid_at" = case when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then coalesce(x."paid_at", now()) end
    where x."id" = v_row."id"
    returning * into v_row;
  end if;
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
  return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'deposit_amount', v_row."deposit_amount"::text, 'discount_amount', v_row."discount_amount"::text, 'discount_amount_early', v_row."discount_amount_early"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code", 'taxCodeId', il."tax_code_id", 'unitCost', il."unit_cost"::text, 'dimensions', il."dimensions") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb));
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
    raise exception 'this transaction is a reversal or is already reversed' using errcode = 'PT409', hint = 'LEDGER_ALREADY_REVERSED';
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

CREATE OR REPLACE FUNCTION better_supabase.split_leave_request (
  request_id uuid,
  gap_starts date,
  gap_ends   date
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_old "better_supabase"."leave_requests"%rowtype;
  v_row "better_supabase"."leave_requests"%rowtype;
  v_type "better_supabase"."leave_types"%rowtype;
  v_partial text := 'full';
  v_amount numeric;
  v_approval "better_supabase"."approval_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_old from "better_supabase"."leave_requests" x where x."id" = split_leave_request.request_id for update;
  if not found then
    raise exception 'leave request not found' using errcode = 'P0002', hint = 'LEAVE_REQUEST_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_old."tenant_id", 'leave.manage'), false)) then
    raise exception 'approved leave is split by a manager' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  if v_old."approved_at" is null or v_old."cancelled_at" is not null then
    raise exception 'only approved leave is split' using errcode = 'PT409', hint = 'LEAVE_REQUEST_CLOSED';
  end if;
  select * into v_type from "better_supabase"."leave_types" x where x."id" = v_old."type_id";
  if v_type."unit" = 'hours' then
    raise exception 'leave in hours isn''t split' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  if split_leave_request.gap_starts is null or split_leave_request.gap_ends is null
    or split_leave_request.gap_ends < split_leave_request.gap_starts
    or split_leave_request.gap_starts <= v_old."starts_on" or split_leave_request.gap_ends >= v_old."ends_on" then
    raise exception 'the gap lies inside the leave with days on both sides; shorten leave with update_leave_request' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  if v_partial not in ('full', 'morning', 'afternoon', 'hours') then
    raise exception 'partial must be full, morning, afternoon or hours' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  if v_type."unit" = 'hours' then
    if v_partial <> 'hours' and v_partial <> 'full' then
      raise exception 'an hours type takes partial hours' using errcode = '22023', hint = 'LEAVE_INVALID';
    end if;
    if null is null or null <= 0 then
      raise exception 'an hours type needs hours greater than zero' using errcode = '22023', hint = 'LEAVE_INVALID';
    end if;
    v_partial := 'hours';
    v_amount := null;
  else
    if v_partial = 'hours' then
      raise exception 'a day type takes partial full, morning or afternoon' using errcode = '22023', hint = 'LEAVE_INVALID';
    end if;
    if v_partial in ('morning', 'afternoon') and (split_leave_request.gap_ends + 1) <> v_old."ends_on" then
      raise exception 'a half day starts and ends on the same date' using errcode = '22023', hint = 'LEAVE_INVALID';
    end if;
    v_amount := "better_supabase"."leave_working_days"((split_leave_request.gap_ends + 1), v_old."ends_on")
      * case when v_partial = 'full' then 1 else 0.5 end;
  end if;
  perform "better_supabase"."update_leave_request"(v_old."id", ends_on => split_leave_request.gap_starts - 1, partial => 'full');
  insert into "better_supabase"."leave_requests" ("tenant_id", "user_id", "type_id", "starts_on", "ends_on", "partial", "amount", "note", "approval_id", "approved_at")
  values (v_old."tenant_id", v_old."user_id", v_old."type_id", split_leave_request.gap_ends + 1, v_old."ends_on", v_partial, v_amount, v_old."note", v_old."approval_id", v_old."approved_at")
  returning * into v_row;
  perform "better_supabase"."leave_post"(v_row."tenant_id", v_row."user_id", v_row."type_id", 'taken', -v_row."amount", extract(year from v_row."starts_on")::integer, v_row."id")
  from "better_supabase"."leave_types" t where t."id" = v_row."type_id" and t."tracked";
  select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_row."approval_id";
  perform "better_supabase".emit_event('leave_request.split', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'typeId', v_row."type_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'amount', v_row."amount"::text, 'approvalId', v_row."approval_id"), 'leave-requests/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/leave');
  perform better_supabase.audit_event(
    event_type => 'leave_request.split',
    category => 'data',
    target_type => 'leave_request',
    record_id => v_row."id"::text,
    summary => 'split leave' || ' from ' || v_row."starts_on"::text || ' to ' || v_row."ends_on"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'typeId', v_row."type_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'amount', v_row."amount"::text, 'approvalId', v_row."approval_id")
  );
  return jsonb_build_object(
    'request', (select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'typeId', x."type_id", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'partial', x."partial", 'amount', x."amount"::text, 'note', case when (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(x."user_id" = auth.uid(), false) or (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = x."tenant_id" and me."user_id" = x."user_id"
        and mgr."user_id" is not null and mgr."status" <> 'offboarded' and (mgr."end_date" is null or mgr."end_date" >= current_date)
      limit 1) = auth.uid(), false) and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = x."tenant_id" and mm."user_id" = auth.uid()
    )) or coalesce(better_supabase.can('tenant', x."tenant_id", 'leave.approve'), false) or coalesce(better_supabase.can('tenant', x."tenant_id", 'leave.manage'), false)) then x."note" end, 'status', case when x."cancelled_at" is not null then 'cancelled' when x."approved_at" is not null then 'approved' when v_approval."status" in ('rejected', 'expired') then 'rejected' when v_approval."status" = 'cancelled' then 'cancelled' else 'pending' end, 'approvalId', x."approval_id", 'approvedAt', x."approved_at", 'cancelledAt', x."cancelled_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") from "better_supabase"."leave_requests" x where x."id" = v_old."id"),
    'split', jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'typeId', v_row."type_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'partial', v_row."partial", 'amount', v_row."amount"::text, 'note', case when (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."user_id" = auth.uid(), false) or (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = v_row."tenant_id" and me."user_id" = v_row."user_id"
        and mgr."user_id" is not null and mgr."status" <> 'offboarded' and (mgr."end_date" is null or mgr."end_date" >= current_date)
      limit 1) = auth.uid(), false) and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = v_row."tenant_id" and mm."user_id" = auth.uid()
    )) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leave.approve'), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leave.manage'), false)) then v_row."note" end, 'status', case when v_row."cancelled_at" is not null then 'cancelled' when v_row."approved_at" is not null then 'approved' when v_approval."status" in ('rejected', 'expired') then 'rejected' when v_approval."status" = 'cancelled' then 'cancelled' else 'pending' end, 'approvalId', v_row."approval_id", 'approvedAt', v_row."approved_at", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at")
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.submit_expense_report (
  report_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_violations jsonb;
  v_request jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."expense_reports" x where x."id" = submit_expense_report.report_id for update;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (coalesce(v_row."user_id" = auth.uid(), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.submit'), false)) then
    raise exception 'only the member who owns the report can change it' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) not in ('draft', 'rejected') then
    raise exception 'only a draft or rejected report can change' using errcode = 'PT409', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  if not exists (select 1 from "better_supabase"."expense_lines" l where l."report_id" = v_row."id") then
    raise exception 'a report needs at least one line' using errcode = '22023', hint = 'EXPENSE_REPORT_EMPTY';
  end if;
  v_violations := "better_supabase"."expense_report_violations"(v_row."id");
  if jsonb_array_length(v_violations) > 0 then
    raise exception 'the report breaks the spend policy: %', v_violations::text using errcode = '22023', hint = 'EXPENSE_POLICY_VIOLATION';
  end if;
  v_request := "better_supabase"."open_approval"(
    v_row."tenant_id", 'expense_report', v_row."id"::text, 'approve',
    '{"steps":[{"approvers":{"permission":"expenses.approve"},"required":1}],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb, v_row."note",
    jsonb_build_object('userId', v_row."user_id", 'title', v_row."title", 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'currency', v_row."currency")
  );
  update "better_supabase"."expense_reports" x set "approval_id" = (v_request ->> 'id')::uuid, "submitted_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  perform "better_supabase".emit_event('expense_report.submitted', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'currency', v_row."currency", 'approvalId', v_row."approval_id"), 'expense-reports/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/expenses');
  perform better_supabase.audit_event(
    event_type => 'expense_report.submitted',
    category => 'data',
    target_type => 'expense_report',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'submitted an expense report',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'currency', v_row."currency", 'approvalId', v_row."approval_id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'title', v_row."title", 'currency', v_row."currency", 'note', v_row."note", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'approvalId', v_row."approval_id", 'submittedAt', v_row."submitted_at", 'approvedAt', v_row."approved_at", 'approvalTransactionId', v_row."approval_transaction_id", 'reimbursedAt', v_row."reimbursed_at", 'reimbursementTransactionId', v_row."reimbursement_transaction_id", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'dimensions', l."dimensions", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', (select count(*) from "better_supabase"."attachments" t where t."subject_type" = 'expense_line' and t."subject_id" = l."id"::text and t."uploaded_at" is not null and t."status" <> 'infected'), 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = v_row."id"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.submit_timesheet (
  tenant uuid,
  week   date,
  note   text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_week date := date_trunc('week', submit_timesheet.week)::date;
  v_sheet "better_supabase"."timesheets"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_request jsonb;
  v_seconds bigint;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null or not coalesce(better_supabase.can('tenant', submit_timesheet.tenant, 'time_entries.track'), false) then
    raise exception 'not allowed to submit a timesheet here' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('time_entry:' || submit_timesheet.tenant::text || ':' || v_me::text, 0));
  if exists (
    select 1 from "better_supabase"."time_entries" x
    where x."tenant_id" = submit_timesheet.tenant and x."user_id" = v_me and x."ended_at" is null
      and "better_supabase"."time_week"(x."started_at") = v_week
  ) then
    raise exception 'stop the running timer before submitting this week' using errcode = '55000', hint = 'TIME_ENTRIES_TIMESHEET_TIMER_RUNNING';
  end if;
  insert into "better_supabase"."timesheets" ("tenant_id", "user_id", "week")
  values (submit_timesheet.tenant, v_me, v_week)
  on conflict ("tenant_id", "user_id", "week") do nothing;
  select * into v_sheet from "better_supabase"."timesheets" s
    where s."tenant_id" = submit_timesheet.tenant and s."user_id" = v_me and s."week" = v_week
    for update;
  if v_sheet."approved_at" is not null then
    raise exception 'this week is already approved' using errcode = 'PT409', hint = 'TIME_ENTRIES_TIMESHEET_APPROVED';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_sheet."approval_id";
  if v_approval."status" = 'pending' then
    raise exception 'this week is already waiting for approval' using errcode = 'PT409', hint = 'TIME_ENTRIES_TIMESHEET_SUBMITTED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_timesheet_submit"(uuid, uuid, date)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::date)', v_hook::oid::regproc)
        using v_sheet."id", submit_timesheet.tenant, v_week;
    end if;
  end;
  select coalesce(sum(extract(epoch from x."ended_at" - x."started_at")), 0)::bigint into v_seconds
    from "better_supabase"."time_entries" x
    where x."tenant_id" = submit_timesheet.tenant and x."user_id" = v_me
      and "better_supabase"."time_week"(x."started_at") = v_week and x."archived_at" is null;
  v_request := "better_supabase"."open_approval"(
    submit_timesheet.tenant, 'timesheet', v_sheet."id"::text, 'approve',
    '{"steps":[{"approvers":{"permission":"time_entries.approve"},"required":1}],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb, submit_timesheet.note,
    jsonb_build_object('userId', v_me, 'week', v_week, 'seconds', v_seconds)
  );
  update "better_supabase"."timesheets" s
  set "approval_id" = (v_request ->> 'id')::uuid, "note" = submit_timesheet.note, "submitted_at" = now()
  where s."id" = v_sheet."id"
  returning * into v_sheet;
  select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_sheet."approval_id";
  perform "better_supabase".emit_event('timesheet.submitted', jsonb_build_object('organizationId', v_sheet."tenant_id", 'id', v_sheet."id", 'userId', v_sheet."user_id", 'week', v_sheet."week", 'approvalId', v_sheet."approval_id"), 'timesheets/' || v_sheet."id"::text, (v_sheet."tenant_id")::text, null, 'better-supabase/time-entries');
  perform better_supabase.audit_event(
    event_type => 'timesheet.submitted',
    category => 'data',
    target_type => 'timesheet',
    record_id => v_sheet."id"::text,
    summary => 'submitted a timesheet' || ' for the week of ' || v_sheet."week"::text,
    tenant => (v_sheet."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_sheet."tenant_id", 'id', v_sheet."id", 'userId', v_sheet."user_id", 'week', v_sheet."week", 'approvalId', v_sheet."approval_id")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_timesheet_submit"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_sheet."id";
    end if;
  end;
  return jsonb_build_object('id', v_sheet."id", 'organizationId', v_sheet."tenant_id", 'userId', v_sheet."user_id", 'week', v_sheet."week", 'status', case when v_sheet."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" = 'rejected' then 'rejected' else 'open' end, 'approvalId', v_sheet."approval_id", 'note', v_sheet."note", 'submittedAt', v_sheet."submitted_at", 'approvedAt', v_sheet."approved_at", 'createdAt', v_sheet."created_at");
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
  if v_row."status" in ('issued', 'partially_paid', 'paid') then
    update "better_supabase"."invoices" x set
      "status" = case
      when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then 'paid'
      when x."paid_total" > 0 or x."credited_total" > 0 then 'partially_paid'
      else 'issued' end,
      "paid_at" = case when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then coalesce(x."paid_at", now()) end
    where x."id" = v_row."id"
    returning * into v_row;
  end if;
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
  if v_row."status" in ('issued', 'partially_paid', 'paid') then
    update "better_supabase"."invoices" x set
      "status" = case
      when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then 'paid'
      when x."paid_total" > 0 or x."credited_total" > 0 then 'partially_paid'
      else 'issued' end,
      "paid_at" = case when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then coalesce(x."paid_at", now()) end
    where x."id" = v_row."id"
    returning * into v_row;
  end if;
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

CREATE OR REPLACE FUNCTION better_supabase.update_asset (
  asset_id uuid,
  patch    jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."assets"%rowtype;
  v_location uuid;
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."assets" x where x."id" = update_asset.asset_id for update;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.manage'), false)) then
    raise exception 'not allowed to manage assets' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if jsonb_typeof(update_asset.patch) is distinct from 'object' then
    raise exception 'patch must be an object' using errcode = '22023', hint = 'ASSETS_PATCH_INVALID';
  end if;
  v_location := case when update_asset.patch ? 'locationId' then (update_asset.patch ->> 'locationId')::uuid else v_row."location_id" end;
  if v_location is distinct from v_row."location_id" then
    if v_location is not null and not exists (
    select 1 from "better_supabase"."asset_locations" y where y."id" = v_location and y."tenant_id" = v_row."tenant_id" and y."archived_at" is null
  ) then
    raise exception 'location not found' using errcode = 'P0002', hint = 'ASSETS_LOCATION_NOT_FOUND';
  end if;
  end if;
  v_status := case when update_asset.patch ? 'status' then update_asset.patch ->> 'status' else v_row."status" end;
  if update_asset.patch ? 'tag' and update_asset.patch ->> 'tag' is not null and exists (
    select 1 from "better_supabase"."assets" x where x."tenant_id" = v_row."tenant_id" and x."tag" = update_asset.patch ->> 'tag' and x."id" <> v_row."id"
  ) then
    raise exception 'an asset with this tag already exists' using errcode = '23505', hint = 'ASSETS_TAG_TAKEN';
  end if;
  if v_status = 'retired' and v_row."status" <> 'retired' then
    update "better_supabase"."asset_assignments" y set "released_at" = now()
    where y."asset_id" = v_row."id" and y."released_at" is null;
  end if;
  if v_row."disposed_on" is not null and (
    update_asset.patch ?| array['acquisitionCost', 'currency', 'acquiredOn', 'usefulLifeMonths', 'residualValue', 'depreciationMethod', 'depreciationRateBps'] or coalesce(update_asset.patch ->> 'status', 'retired') <> 'retired'
  ) then
    raise exception 'a disposed asset stays retired and its book value can''t change' using errcode = 'PT409', hint = 'ASSETS_DISPOSED';
  end if;
  if update_asset.patch ? 'currency' and not update_asset.patch ? 'acquisitionCost' and v_row."acquisition_cost" is not null
    and upper(update_asset.patch ->> 'currency') is distinct from v_row."currency" then
    raise exception 'the amounts are in another currency than the asset''s cost' using errcode = '22023', hint = 'ASSETS_DEPRECIATION_INVALID';
  end if;
  if (
    (update_asset.patch ? 'acquisitionCost' and (update_asset.patch ->> 'acquisitionCost')::bigint is distinct from v_row."acquisition_cost")
    or (update_asset.patch ? 'currency' and upper(update_asset.patch ->> 'currency') is distinct from v_row."currency")
    or (update_asset.patch ? 'acquiredOn' and (update_asset.patch ->> 'acquiredOn')::date is distinct from v_row."acquired_on")
  ) and exists (
    select 1 from "better_supabase"."asset_depreciations" y where y."asset_id" = v_row."id"
  ) then
    raise exception 'the cost, currency and acquisition date are fixed once the asset has depreciated' using errcode = '55000', hint = 'ASSETS_DEPRECIATION_STARTED';
  end if;
  update "better_supabase"."assets" x set
    "kind" = case when update_asset.patch ? 'kind' then update_asset.patch ->> 'kind' else x."kind" end,
    "name" = case when update_asset.patch ? 'name' then trim(update_asset.patch ->> 'name') else x."name" end,
    "location_id" = v_location,
    "tag" = case when update_asset.patch ? 'tag' then update_asset.patch ->> 'tag' else x."tag" end,
    "serial_number" = case when update_asset.patch ? 'serialNumber' then update_asset.patch ->> 'serialNumber' else x."serial_number" end,
    "status" = v_status,
    "latitude" = case when update_asset.patch ? 'latitude' then (update_asset.patch ->> 'latitude')::double precision else x."latitude" end,
    "longitude" = case when update_asset.patch ? 'longitude' then (update_asset.patch ->> 'longitude')::double precision else x."longitude" end,
    "metadata" = case when update_asset.patch ? 'metadata' then coalesce(nullif(update_asset.patch -> 'metadata', 'null'::jsonb), '{}'::jsonb) else x."metadata" end,
    "acquisition_cost" = case when update_asset.patch ? 'acquisitionCost' then (update_asset.patch ->> 'acquisitionCost')::bigint else x."acquisition_cost" end,
    "currency" = case when update_asset.patch ? 'currency' then upper(update_asset.patch ->> 'currency') else x."currency" end,
    "acquired_on" = case when update_asset.patch ? 'acquiredOn' then (update_asset.patch ->> 'acquiredOn')::date else x."acquired_on" end,
    "useful_life_months" = case when update_asset.patch ? 'usefulLifeMonths' then (update_asset.patch ->> 'usefulLifeMonths')::integer else x."useful_life_months" end,
    "residual_value" = case when update_asset.patch ? 'residualValue' then coalesce((update_asset.patch ->> 'residualValue')::bigint, 0) else x."residual_value" end,
    "depreciation_method" = case when update_asset.patch ? 'depreciationMethod' then coalesce(update_asset.patch ->> 'depreciationMethod', 'none') else x."depreciation_method" end,
    "depreciation_rate_bps" = case when update_asset.patch ? 'depreciationRateBps' then (update_asset.patch ->> 'depreciationRateBps')::integer else x."depreciation_rate_bps" end,
    "assignee_type" = case when v_status = 'retired' then null else x."assignee_type" end,
    "assignee_id" = case when v_status = 'retired' then null else x."assignee_id" end,
    "retired_at" = case when v_status = 'retired' then coalesce(x."retired_at", now()) else null end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if v_row."acquisition_cost" is not null and v_row."currency" is null then
    raise exception 'an acquisition cost needs a currency' using errcode = '22023', hint = 'ASSETS_DEPRECIATION_INVALID';
  end if;
  if v_row."residual_value" > coalesce(v_row."acquisition_cost", 0) and v_row."depreciation_method" <> 'none' then
    raise exception 'the residual value is more than the acquisition cost' using errcode = '22023', hint = 'ASSETS_DEPRECIATION_INVALID';
  end if;
  if v_row."depreciation_method" <> 'none' and (v_row."acquisition_cost" is null or v_row."acquired_on" is null) then
    raise exception 'depreciation needs an acquisition cost and date' using errcode = '22023', hint = 'ASSETS_DEPRECIATION_INVALID';
  end if;
  if v_row."depreciation_method" = 'straight_line' and v_row."useful_life_months" is null then
    raise exception 'straight-line depreciation needs a useful life' using errcode = '22023', hint = 'ASSETS_DEPRECIATION_INVALID';
  end if;
  if v_row."depreciation_method" = 'declining_balance' and v_row."depreciation_rate_bps" is null then
    raise exception 'declining-balance depreciation needs a rate' using errcode = '22023', hint = 'ASSETS_DEPRECIATION_INVALID';
  end if;
  perform "better_supabase".emit_event('asset.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'name', v_row."name", 'status', v_row."status", 'locationId', v_row."location_id", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id"), 'assets/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/assets');
  perform better_supabase.audit_event(
    event_type => 'asset.updated',
    category => 'data',
    target_type => 'asset',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'updated asset',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'name', v_row."name", 'status', v_row."status", 'locationId', v_row."location_id", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('acquisitionCost', v_row."acquisition_cost"::text, 'currency', v_row."currency", 'acquiredOn', v_row."acquired_on", 'usefulLifeMonths', v_row."useful_life_months", 'residualValue', v_row."residual_value"::text, 'depreciationMethod', v_row."depreciation_method", 'depreciationRateBps', v_row."depreciation_rate_bps", 'disposedOn', v_row."disposed_on", 'disposalAmount', v_row."disposal_amount"::text);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_expense_line (
  line_id     uuid,
  category_id uuid   DEFAULT NULL::uuid,
  spent_on    date   DEFAULT NULL::date,
  amount      bigint DEFAULT NULL::bigint,
  description text   DEFAULT NULL::text,
  merchant    text   DEFAULT NULL::text,
  currency    text   DEFAULT NULL::text,
  dimensions  jsonb  DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_category "better_supabase"."expense_categories"%rowtype;
  v_line "better_supabase"."expense_lines"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_line from "better_supabase"."expense_lines" l where l."id" = update_expense_line.line_id;
  if not found then
    raise exception 'no such expense line' using errcode = 'P0002', hint = 'EXPENSE_LINE_NOT_FOUND';
  end if;
  select * into v_row from "better_supabase"."expense_reports" x where x."id" = v_line."report_id" for update;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (coalesce(v_row."user_id" = auth.uid(), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.submit'), false)) then
    raise exception 'only the member who owns the report can change it' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) not in ('draft', 'rejected') then
    raise exception 'only a draft or rejected report can change' using errcode = 'PT409', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  if update_expense_line.category_id is not null then
  select * into v_category from "better_supabase"."expense_categories" c
    where c."id" = update_expense_line.category_id and c."tenant_id" = v_row."tenant_id" and c."archived_at" is null;
  if not found then
    raise exception 'the category is unknown, archived or not in this organization' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if v_category."currency" is not null and v_category."currency" <> v_row."currency" then
    raise exception 'the category''s policy is in another currency than the report' using errcode = '22023', hint = 'EXPENSE_CURRENCY_MISMATCH';
  end if;
  end if;
  if update_expense_line.currency is not null and update_expense_line.currency <> v_row."currency" then
    raise exception 'the amount is in another currency than the report' using errcode = '22023', hint = 'EXPENSE_CURRENCY_MISMATCH';
  end if;
  if update_expense_line.amount is not null and update_expense_line.amount <= 0 then
    raise exception 'an amount is more than zero minor units' using errcode = '22023', hint = 'EXPENSE_LINE_INVALID';
  end if;
  if update_expense_line.dimensions is not null and jsonb_typeof(update_expense_line.dimensions) not in ('object', 'null') then
    raise exception 'dimensions is an object of dimension keys and value codes' using errcode = '22023', hint = 'EXPENSE_LINE_INVALID';
  end if;
  update "better_supabase"."expense_lines" l set
      "category_id" = coalesce(update_expense_line.category_id, l."category_id"),
      "spent_on" = coalesce(update_expense_line.spent_on, l."spent_on"),
      "amount" = coalesce(update_expense_line.amount, l."amount"),
      "description" = coalesce(nullif(trim(update_expense_line.description), ''), l."description"),
      "merchant" = coalesce(nullif(trim(update_expense_line.merchant), ''), l."merchant"),
      "dimensions" = coalesce(nullif(update_expense_line.dimensions, 'null'::jsonb), l."dimensions"),
      "updated_at" = now()
    where l."id" = v_line."id"
    returning * into v_line;
  update "better_supabase"."expense_reports" x set "updated_at" = now() where x."id" = v_row."id";
  return jsonb_build_object('id', v_line."id", 'reportId', v_line."report_id", 'categoryId', v_line."category_id", 'spentOn', v_line."spent_on", 'description', v_line."description", 'merchant', v_line."merchant", 'dimensions', v_line."dimensions", 'amount', v_line."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = v_line."report_id"), 'receipts', (select count(*) from "better_supabase"."attachments" t where t."subject_type" = 'expense_line' and t."subject_id" = v_line."id"::text and t."uploaded_at" is not null and t."status" <> 'infected'), 'createdAt', v_line."created_at", 'updatedAt', v_line."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_leave_request (
  request_id uuid,
  starts_on  date    DEFAULT NULL::date,
  ends_on    date    DEFAULT NULL::date,
  partial    text    DEFAULT NULL::text,
  hours      numeric DEFAULT NULL::numeric,
  note       text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_me uuid;
  v_row "better_supabase"."leave_requests"%rowtype;
  v_old "better_supabase"."leave_requests"%rowtype;
  v_type "better_supabase"."leave_types"%rowtype;
  v_partial text;
  v_amount numeric;
  v_manager boolean;
  v_status text;
  v_starts date;
  v_ends date;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_request jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."leave_requests" x where x."id" = update_leave_request.request_id for update;
  if not found then
    raise exception 'leave request not found' using errcode = 'P0002', hint = 'LEAVE_REQUEST_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_row."approval_id";
  v_old := v_row;
  v_manager := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leave.manage'), false);
  if not (v_manager or coalesce(v_row."user_id" = auth.uid(), false)) then
    raise exception 'not allowed to change this leave request' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  v_status := case when v_row."cancelled_at" is not null then 'cancelled' when v_row."approved_at" is not null then 'approved' when v_approval."status" in ('rejected', 'expired') then 'rejected' when v_approval."status" = 'cancelled' then 'cancelled' else 'pending' end;
  if v_status not in ('pending', 'approved') then
    raise exception 'only a pending or approved leave request changes' using errcode = 'PT409', hint = 'LEAVE_REQUEST_CLOSED';
  end if;
  if v_status = 'approved' and not v_manager then
    raise exception 'approved leave is changed by a manager' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  select * into v_type from "better_supabase"."leave_types" x where x."id" = v_row."type_id";
  v_me := v_row."user_id";
  v_starts := coalesce(update_leave_request.starts_on, v_row."starts_on");
  v_ends := coalesce(update_leave_request.ends_on, v_row."ends_on");
  if v_ends < v_starts then
    raise exception 'ends_on must be on or after starts_on' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  v_partial := coalesce(update_leave_request.partial, (v_old."partial")::text);
  if v_partial not in ('full', 'morning', 'afternoon', 'hours') then
    raise exception 'partial must be full, morning, afternoon or hours' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  if v_type."unit" = 'hours' then
    if v_partial <> 'hours' and v_partial <> 'full' then
      raise exception 'an hours type takes partial hours' using errcode = '22023', hint = 'LEAVE_INVALID';
    end if;
    if coalesce(update_leave_request.hours, case when v_type."unit" = 'hours' then v_old."amount" end) is null or coalesce(update_leave_request.hours, case when v_type."unit" = 'hours' then v_old."amount" end) <= 0 then
      raise exception 'an hours type needs hours greater than zero' using errcode = '22023', hint = 'LEAVE_INVALID';
    end if;
    v_partial := 'hours';
    v_amount := coalesce(update_leave_request.hours, case when v_type."unit" = 'hours' then v_old."amount" end);
  else
    if v_partial = 'hours' then
      raise exception 'a day type takes partial full, morning or afternoon' using errcode = '22023', hint = 'LEAVE_INVALID';
    end if;
    if v_partial in ('morning', 'afternoon') and v_starts <> v_ends then
      raise exception 'a half day starts and ends on the same date' using errcode = '22023', hint = 'LEAVE_INVALID';
    end if;
    v_amount := "better_supabase"."leave_working_days"(v_starts, v_ends)
      * case when v_partial = 'full' then 1 else 0.5 end;
  end if;
  if v_amount <= 0 then
    raise exception 'the request covers no working days' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('leave:' || v_row."tenant_id"::text || ':' || v_me::text, 0));
  if exists (
    select 1 from "better_supabase"."leave_requests" r
    left join "better_supabase"."approval_requests" p on p."id" = r."approval_id"
    where r."tenant_id" = v_row."tenant_id" and r."user_id" = v_me
      and r."cancelled_at" is null and r."id" <> v_row."id" and (r."approved_at" is not null or p."status" = 'pending')
      and daterange(r."starts_on", r."ends_on", '[]') && daterange(v_starts, v_ends, '[]')
      and not (r."partial" = 'morning' and v_partial = 'afternoon')
      and not (r."partial" = 'afternoon' and v_partial = 'morning')
  ) then
    raise exception 'this overlaps another leave request' using errcode = '23P01', hint = 'LEAVE_OVERLAP';
  end if;
  if v_type."tracked" and "better_supabase"."leave_available"(v_row."tenant_id", v_me, v_type."id", extract(year from v_starts)::integer)
    + (case when extract(year from v_old."starts_on") = extract(year from v_starts) then v_old."amount" else 0 end) < v_amount then
    raise exception 'this request is more than the available balance' using errcode = '23514', hint = 'LEAVE_BALANCE_EXCEEDED';
  end if;
  if v_status = 'approved' then
    perform "better_supabase"."leave_post"(v_old."tenant_id", v_old."user_id", v_old."type_id", 'taken', v_old."amount", extract(year from v_old."starts_on")::integer, v_old."id", 'changed')
    from "better_supabase"."leave_types" t where t."id" = v_old."type_id" and t."tracked";
  end if;
  update "better_supabase"."leave_requests" x set "starts_on" = v_starts, "ends_on" = v_ends, "partial" = v_partial, "amount" = v_amount, "note" = case when update_leave_request.note is null then x."note" else nullif(trim(update_leave_request.note), '') end, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  if v_status = 'approved' then
    perform "better_supabase"."leave_post"(v_row."tenant_id", v_row."user_id", v_row."type_id", 'taken', -v_row."amount", extract(year from v_row."starts_on")::integer, v_row."id")
    from "better_supabase"."leave_types" t where t."id" = v_row."type_id" and t."tracked";
  end if;
  if v_status = 'pending' then
    update "better_supabase"."approval_requests" p set "status" = 'cancelled', "decided_at" = now()
      where p."id" = v_row."approval_id" and p."status" = 'pending';
    if not v_type."auto_approve" then
      v_request := "better_supabase"."open_approval"(
        v_row."tenant_id", 'leave_request', v_row."id"::text, 'approve',
        '{"steps":[{"approvers":{"permission":"leave.approve"},"required":1}],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb, v_row."note",
        jsonb_build_object('userId', v_me, 'typeId', v_type."id", 'type', v_type."name", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'amount', v_amount::text, 'unit', v_type."unit")
      );
      update "better_supabase"."leave_requests" x set "approval_id" = (v_request ->> 'id')::uuid
        where x."id" = v_row."id"
        returning * into v_row;
      select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_row."approval_id";
    end if;
    if v_type."auto_approve" then
      perform "better_supabase"."approve_leave_request"(v_row."id");
      select * into v_row from "better_supabase"."leave_requests" x where x."id" = v_row."id";
    end if;
  end if;
  perform "better_supabase".emit_event('leave_request.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'typeId', v_row."type_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'amount', v_row."amount"::text, 'approvalId', v_row."approval_id"), 'leave-requests/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/leave');
  perform better_supabase.audit_event(
    event_type => 'leave_request.updated',
    category => 'data',
    target_type => 'leave_request',
    record_id => v_row."id"::text,
    summary => 'changed leave' || ' from ' || v_row."starts_on"::text || ' to ' || v_row."ends_on"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'typeId', v_row."type_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'amount', v_row."amount"::text, 'approvalId', v_row."approval_id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'typeId', v_row."type_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'partial', v_row."partial", 'amount', v_row."amount"::text, 'note', case when (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."user_id" = auth.uid(), false) or (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = v_row."tenant_id" and me."user_id" = v_row."user_id"
        and mgr."user_id" is not null and mgr."status" <> 'offboarded' and (mgr."end_date" is null or mgr."end_date" >= current_date)
      limit 1) = auth.uid(), false) and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = v_row."tenant_id" and mm."user_id" = auth.uid()
    )) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leave.approve'), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leave.manage'), false)) then v_row."note" end, 'status', case when v_row."cancelled_at" is not null then 'cancelled' when v_row."approved_at" is not null then 'approved' when v_approval."status" in ('rejected', 'expired') then 'rejected' when v_approval."status" = 'cancelled' then 'cancelled' else 'pending' end, 'approvalId', v_row."approval_id", 'approvedAt', v_row."approved_at", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
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
  v_original "better_supabase"."invoices";
  v_issued boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."invoices" x where x."id" = void_invoice.invoice;
  if v_row."id" is null or (((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", case when v_row."direction" = 'purchase' then 'invoices.purchase' else 'invoices.manage' end), false))) is not true then
    if v_row."id" is not null and (((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'invoices.read'), false)) or better_supabase.row_visible('"better_supabase"."invoices"'::regclass, 'id', v_row."id")) then
      raise exception 'you may not void this invoice' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
    end if;
    raise exception 'no such invoice you can read' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  select * into v_row from "better_supabase"."invoices" x where x."id" = void_invoice.invoice for update;
  if not found then
    raise exception 'no such invoice you can read' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  if v_row."status" not in ('draft', 'issued') or v_row."paid_total" <> 0 or v_row."credited_total" <> 0 then
    raise exception 'an invoice with payments or credits is credited, not voided' using errcode = '55000', hint = 'INVOICE_NOT_VOIDABLE';
  end if;
  v_issued := v_row."status" = 'issued';
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
  if v_issued and v_row."kind" = 'credit_note' and v_row."original_id" is not null then
    update "better_supabase"."invoices" x set "credited_total" = greatest(x."credited_total" - v_row."total", 0), "updated_at" = now()
    where x."id" = v_row."original_id"
    returning * into v_original;
  update "better_supabase"."invoices" x set
    "paid_total" = coalesce(-(select sum(e."amount") from "better_supabase"."ledger_entries" e where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text)), 0),
    "updated_at" = now()
  where x."id" = v_original."id"
  returning * into v_original;
  if v_original."status" in ('issued', 'partially_paid', 'paid') then
    update "better_supabase"."invoices" x set
      "status" = case
      when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then 'paid'
      when x."paid_total" > 0 or x."credited_total" > 0 then 'partially_paid'
      else 'issued' end,
      "paid_at" = case when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then coalesce(x."paid_at", now()) end
    where x."id" = v_original."id"
    returning * into v_original;
  end if;
  end if;
  perform "better_supabase"."accounting_reverse_source"(v_row."tenant_id", 'invoice', v_row."id"::text);
  perform "better_supabase"."accounting_reverse_source"(v_row."tenant_id", 'invoice_charge', c."id"::text)
  from "better_supabase"."invoice_charges" c where c."invoice_id" = v_row."id";
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
  return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'deposit_amount', v_row."deposit_amount"::text, 'discount_amount', v_row."discount_amount"::text, 'discount_amount_early', v_row."discount_amount_early"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code", 'taxCodeId', il."tax_code_id", 'unitCost', il."unit_cost"::text, 'dimensions', il."dimensions") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb));
end;
$function$;

CREATE TRIGGER bsb_expense_line_guard
  BEFORE INSERT OR DELETE OR UPDATE ON better_supabase.expense_lines
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.expense_line_guard();

CREATE TRIGGER bsb_expense_report_guard
  BEFORE INSERT OR UPDATE ON better_supabase.expense_reports
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.expense_report_guard();

REVOKE ALL ON FUNCTION "better_supabase"."expense_line_guard"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."expense_report_guard"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."expense_report_state"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."expense_report_state"(uuid) TO "authenticated", "service_role";
