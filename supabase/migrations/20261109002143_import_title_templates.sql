SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.import_invoice_document (
  item       jsonb,
  subject_id text,
  v_credit   boolean
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid := (import_invoice_document.item ->> 'tenant')::uuid;
  v_data jsonb := import_invoice_document.item -> 'data';
  v_status text := case when v_credit then 'issued' else coalesce(v_data ->> 'status', 'issued') end;
  v_number text := nullif(btrim(v_data ->> 'number'), '');
  v_issued_on date;
  v_due_on date;
  v_original uuid;
  v_made jsonb;
  v_id uuid;
  v_row "better_supabase"."invoices";
  v_warnings jsonb := '[]'::jsonb;
  v_computed jsonb;
  v_given jsonb;
  v_pay jsonb;
  v_index integer := 0;
begin
  if import_invoice_document.subject_id is not null then
    select * into v_row from "better_supabase"."invoices" x where x."id" = import_invoice_document.subject_id::uuid and x."tenant_id" = v_tenant;
    if not found then
      raise exception 'the invoice no longer exists' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
    return jsonb_build_object('subjectId', v_row."id"::text, 'updatedAt', v_row."updated_at", 'warnings', jsonb_build_array(jsonb_build_object('code', 'IMPORT_DOCUMENT_CHANGED', 'message', 'the source document changed after it was imported; an imported document is kept as imported, so void or credit it and import the correction as a new document')));
  end if;
  if v_status not in ('draft', 'issued', 'partially_paid', 'paid', 'void', 'uncollectible') then
    raise exception 'status is draft, issued, partially_paid, paid, void or uncollectible' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if jsonb_typeof(v_data -> 'lines') is distinct from 'array' or jsonb_array_length(v_data -> 'lines') = 0 then
    raise exception 'a document needs at least one line' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if v_status <> 'draft' and v_number is null then
    raise exception 'an issued document needs its number' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  begin
    v_issued_on := nullif(v_data ->> 'issuedOn', '')::date;
    v_due_on := nullif(v_data ->> 'dueOn', '')::date;
  exception when others then
    raise exception 'issuedOn and dueOn are dates' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end;
  if v_status <> 'draft' and v_issued_on is null then
    raise exception 'an issued document needs its issue date' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;

  if v_credit then
    v_original := coalesce(
      nullif(v_data ->> 'originalId', '')::uuid,
      (select x."id" from "better_supabase"."invoices" x where x."tenant_id" = v_tenant and x."identifier" = v_data ->> 'original' limit 1)
    );
    if v_original is null then
      raise exception 'a credit note names the invoice it credits (originalId or original)' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
    v_made := "better_supabase"."credit_invoice"(v_original, v_data -> 'lines', nullif(v_data ->> 'note', ''), v_number, v_issued_on);
    v_id := (v_made ->> 'id')::uuid;
  else
    v_made := "better_supabase"."create_invoice"(v_tenant, coalesce(v_data -> 'attrs', '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
      'title', coalesce(nullif(v_data ->> 'title', ''), replace('Invoice {number}', '{number}', coalesce(v_number, 'draft'))),
      'currency', v_data -> 'currency',
      'termsDays', v_data -> 'termsDays',
      'note', v_data -> 'note',
      'company', v_data -> 'company',
      'contact', v_data -> 'contact',
      'origin', v_data -> 'origin',
      'direction', v_data -> 'direction',
      'pricesIncludeTax', v_data -> 'pricesIncludeTax',
      'discountBps', v_data -> 'discountBps',
      'discountAmount', v_data -> 'discountAmount')), v_data -> 'lines');
    v_id := (v_made ->> 'id')::uuid;
  end if;
  update "better_supabase"."invoices" x set legal_entity_id = case when v_credit then x.legal_entity_id else nullif(v_data ->> 'legalEntityId', '')::uuid end,
    "buyer" = case when jsonb_typeof(v_data -> 'buyer') = 'object' then v_data -> 'buyer' else x."buyer" end,
    "created_at" = coalesce(nullif(v_data ->> 'createdAt', '')::timestamptz, x."created_at")
  where x."id" = v_id;
  if v_status <> 'draft' and not v_credit then
    perform "better_supabase"."issue_invoice"(v_id, v_issued_on, v_due_on, null, v_number);
  end if;
  if jsonb_typeof(v_data -> 'taxLines') = 'array' then
    v_computed := coalesce((
      select jsonb_object_agg(k.key, jsonb_build_object('net', k.net, 'tax', k.tax))
      from (select coalesce(y."tax_code", '') || ':' || y."tax_rate_bps"::text as key, sum(y."net") as net, sum(y."tax") as tax
        from "better_supabase"."invoice_tax_lines" y where y."invoice_id" = v_id group by 1) k
    ), '{}'::jsonb);
    v_given := coalesce((
      select jsonb_object_agg(k.key, jsonb_build_object('net', k.net, 'tax', k.tax))
      from (select coalesce(g.value ->> 'taxCode', '') || ':' || coalesce((g.value ->> 'taxRateBps')::integer, 0)::text as key,
          sum((g.value ->> 'net')::bigint) as net, sum((g.value ->> 'tax')::bigint) as tax
        from jsonb_array_elements(v_data -> 'taxLines') g group by 1) k
    ), '{}'::jsonb);
    if v_computed <> v_given then
      v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'IMPORT_TAX_MISMATCH', 'message', 'the stored tax per code differs from the tax computed from the lines; the stored amounts were kept', 'computed', v_computed, 'given', v_given));
    end if;
    delete from "better_supabase"."invoice_tax_lines" y where y."invoice_id" = v_id;
    insert into "better_supabase"."invoice_tax_lines" ("tenant_id", "invoice_id", "tax_rate_bps", "tax_code", "tax_code_id", "net", "tax", "gross", "discount", "show_tax")
    select v_tenant, v_id, coalesce((g.value ->> 'taxRateBps')::integer, 0), nullif(g.value ->> 'taxCode', ''), nullif(g.value ->> 'taxCodeId', '')::uuid,
      (g.value ->> 'net')::bigint, (g.value ->> 'tax')::bigint,
      coalesce((g.value ->> 'gross')::bigint, (g.value ->> 'net')::bigint + (g.value ->> 'tax')::bigint),
      coalesce((g.value ->> 'discount')::bigint, 0), coalesce((g.value ->> 'showTax')::boolean, true)
    from jsonb_array_elements(v_data -> 'taxLines') g;
  end if;
  if jsonb_typeof(v_data -> 'totals') = 'object' then
    select * into v_row from "better_supabase"."invoices" x where x."id" = v_id;
    if (v_data -> 'totals' ->> 'subtotal' is not null and (v_data -> 'totals' ->> 'subtotal')::bigint <> v_row."subtotal")
      or (v_data -> 'totals' ->> 'tax' is not null and (v_data -> 'totals' ->> 'tax')::bigint <> v_row."tax_total")
      or (v_data -> 'totals' ->> 'total' is not null and (v_data -> 'totals' ->> 'total')::bigint <> v_row."total") then
      v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'IMPORT_TOTALS_MISMATCH', 'message', 'the stored totals differ from the totals computed from the lines; the stored totals were kept',
        'computed', jsonb_build_object('subtotal', v_row."subtotal"::text, 'tax', v_row."tax_total"::text, 'total', v_row."total"::text),
        'given', v_data -> 'totals'));
    end if;
    update "better_supabase"."invoices" x set
      "subtotal" = coalesce((v_data -> 'totals' ->> 'subtotal')::bigint, x."subtotal"),
      "tax_total" = coalesce((v_data -> 'totals' ->> 'tax')::bigint, x."tax_total"),
      "total" = coalesce((v_data -> 'totals' ->> 'total')::bigint, x."total")
    where x."id" = v_id;
  end if;
  if jsonb_typeof(v_data -> 'payments') = 'array' and jsonb_array_length(v_data -> 'payments') > 0 then
    if v_credit or v_status = 'draft' then
      raise exception 'only an issued invoice takes payments' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
    select * into v_row from "better_supabase"."invoices" x where x."id" = v_id;
    for v_pay in select p.value from jsonb_array_elements(v_data -> 'payments') p loop
      v_index := v_index + 1;
      perform "better_supabase"."record_invoice_payment"(
        v_id, (v_pay ->> 'amount')::bigint, upper(coalesce(v_pay ->> 'currency', v_row."currency")),
        (v_pay ->> 'paidAt')::timestamptz, coalesce(nullif(v_pay ->> 'method', ''), 'import'),
        coalesce(nullif(v_pay ->> 'reference', ''), import_invoice_document.item ->> 'key' || ':payment:' || v_index::text),
        nullif(v_pay ->> 'note', ''), null, null);
    end loop;
    update "better_supabase"."invoices" x set "paid_at" = (select max((p.value ->> 'paidAt')::timestamptz) from jsonb_array_elements(v_data -> 'payments') p)
    where x."id" = v_id and x."paid_at" is not null and jsonb_typeof(v_data -> 'payments') = 'array';
  end if;
  if v_status = 'void' then
    perform "better_supabase"."void_invoice"(v_id, coalesce(nullif(v_data ->> 'voidReason', ''), 'imported as void'));
  elsif v_status = 'uncollectible' then
    perform "better_supabase"."write_off_invoice"(v_id, nullif(v_data ->> 'writeOffReason', ''));
  end if;
  select * into v_row from "better_supabase"."invoices" x where x."id" = v_id;
  if v_status in ('partially_paid', 'paid') and v_row."status"::text <> v_status then
    v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'IMPORT_STATUS_MISMATCH', 'message', 'the payments give the status ' || v_row."status"::text || ', not ' || v_status, 'status', v_row."status"::text));
  end if;
  return jsonb_build_object('subjectId', v_id::text, 'updatedAt', v_row."updated_at", 'warnings', v_warnings);
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
    'title', coalesce(nullif(v_data ->> 'title', ''), replace('Opening balance {number}', '{number}', coalesce(v_data ->> 'number', ''))),
    'lines', jsonb_build_array(jsonb_build_object('description', replace('Opening balance {number}', '{number}', coalesce(v_data ->> 'number', '')),
      'quantity', 1, 'unitAmount', v_balance, 'taxRateBps', 0)),
    'totals', jsonb_build_object('subtotal', v_balance, 'tax', 0, 'total', v_balance)))),
    import_open_item.subject_id, false);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_quote (
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
  v_tenant uuid := (import_quote.item ->> 'tenant')::uuid;
  v_data jsonb := import_quote.item -> 'data';
  v_number text := nullif(btrim(v_data ->> 'number'), '');
  v_made jsonb;
  v_id uuid;
  v_row "better_supabase"."quotes";
  v_warnings jsonb := '[]'::jsonb;
  v_computed jsonb;
  v_given jsonb;
begin
  if import_quote.subject_id is not null then
    select * into v_row from "better_supabase"."quotes" y where y."id" = import_quote.subject_id::uuid and y."tenant_id" = v_tenant;
    if not found then
      raise exception 'the quote no longer exists' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
    return jsonb_build_object('subjectId', v_row."id"::text, 'updatedAt', v_row."updated_at", 'warnings', jsonb_build_array(jsonb_build_object('code', 'IMPORT_DOCUMENT_CHANGED', 'message', 'the source quote changed after it was imported; an imported quote is kept as imported, so import the correction as a new quote')));
  end if;
  if v_number is null then
    raise exception 'a quote needs its number' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if coalesce(v_data ->> 'status', 'draft') not in ('draft', 'sent', 'viewed', 'accepted', 'rejected', 'changes_requested', 'expired', 'withdrawn') then
    raise exception 'status is draft, sent, viewed, accepted, rejected, changes_requested, expired or withdrawn' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if jsonb_typeof(v_data -> 'lines') is distinct from 'array' or jsonb_array_length(v_data -> 'lines') = 0 then
    raise exception 'a quote needs at least one line' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  perform set_config('better_supabase.fixed_number', 'quote' || chr(31) || v_number, true);
  v_made := "better_supabase"."create_quote"(v_tenant, coalesce(v_data -> 'attrs', '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
    'title', coalesce(nullif(v_data ->> 'title', ''), replace('Quote {number}', '{number}', v_number)),
    'currency', v_data -> 'currency',
    'validUntil', v_data -> 'validUntil',
    'terms', v_data -> 'terms',
    'note', v_data -> 'note',
    'company', v_data -> 'company',
    'contact', v_data -> 'contact',
    'origin', v_data -> 'origin',
    'pricesIncludeTax', v_data -> 'pricesIncludeTax',
    'discountBps', v_data -> 'discountBps',
    'discountAmount', v_data -> 'discountAmount',
    'depositBps', v_data -> 'depositBps',
    'depositAmount', v_data -> 'depositAmount')), v_data -> 'lines');
  perform set_config('better_supabase.fixed_number', '', true);
  v_id := (v_made ->> 'id')::uuid;
  update "better_supabase"."quotes" y set
    "status" = coalesce(v_data ->> 'status', 'draft'),
    "created_at" = coalesce(nullif(v_data ->> 'createdAt', '')::timestamptz, y."created_at"),
    "sent_at" = nullif(v_data ->> 'sentAt', '')::timestamptz,
    "viewed_at" = nullif(v_data ->> 'viewedAt', '')::timestamptz,
    "decided_at" = nullif(v_data ->> 'decidedAt', '')::timestamptz,
    "decided_by" = nullif(v_data ->> 'decidedBy', ''),
    "decision_note" = nullif(v_data ->> 'decisionNote', ''),
    "buyer" = case when jsonb_typeof(v_data -> 'buyer') = 'object' then v_data -> 'buyer' end,
    legal_entity_id = nullif(v_data ->> 'legalEntityId', '')::uuid,
    "updated_at" = now()
  where y."id" = v_id;
  if jsonb_typeof(v_data -> 'taxLines') = 'array' then
    v_computed := coalesce((
      select jsonb_object_agg(k.key, jsonb_build_object('net', k.net, 'tax', k.tax))
      from (select coalesce(z."tax_code", '') || ':' || z."tax_rate_bps"::text as key, sum(z."net") as net, sum(z."tax") as tax
        from "better_supabase"."quote_tax_lines" z where z."parent_id" = v_id group by 1) k
    ), '{}'::jsonb);
    v_given := coalesce((
      select jsonb_object_agg(k.key, jsonb_build_object('net', k.net, 'tax', k.tax))
      from (select coalesce(g.value ->> 'taxCode', '') || ':' || coalesce((g.value ->> 'taxRateBps')::integer, 0)::text as key,
          sum((g.value ->> 'net')::bigint) as net, sum((g.value ->> 'tax')::bigint) as tax
        from jsonb_array_elements(v_data -> 'taxLines') g group by 1) k
    ), '{}'::jsonb);
    if v_computed <> v_given then
      v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'IMPORT_TAX_MISMATCH', 'message', 'the stored tax per code differs from the tax computed from the lines; the stored amounts were kept', 'computed', v_computed, 'given', v_given));
    end if;
    delete from "better_supabase"."quote_tax_lines" z where z."parent_id" = v_id;
    insert into "better_supabase"."quote_tax_lines" ("tenant_id", "parent_id", "tax_rate_bps", "tax_code", "net", "tax", "gross", "discount")
    select v_tenant, v_id, coalesce((g.value ->> 'taxRateBps')::integer, 0), nullif(g.value ->> 'taxCode', ''), (g.value ->> 'net')::bigint, (g.value ->> 'tax')::bigint,
      coalesce((g.value ->> 'gross')::bigint, (g.value ->> 'net')::bigint + (g.value ->> 'tax')::bigint), coalesce((g.value ->> 'discount')::bigint, 0)
    from jsonb_array_elements(v_data -> 'taxLines') g;
  end if;
  if jsonb_typeof(v_data -> 'totals') = 'object' then
    select * into v_row from "better_supabase"."quotes" y where y."id" = v_id;
    if (v_data -> 'totals' ->> 'subtotal' is not null and (v_data -> 'totals' ->> 'subtotal')::bigint <> v_row."subtotal")
      or (v_data -> 'totals' ->> 'tax' is not null and (v_data -> 'totals' ->> 'tax')::bigint <> v_row."tax_total")
      or (v_data -> 'totals' ->> 'total' is not null and (v_data -> 'totals' ->> 'total')::bigint <> v_row."total") then
      v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'IMPORT_TOTALS_MISMATCH', 'message', 'the stored totals differ from the totals computed from the lines; the stored totals were kept',
        'computed', jsonb_build_object('subtotal', v_row."subtotal"::text, 'tax', v_row."tax_total"::text, 'total', v_row."total"::text),
        'given', v_data -> 'totals'));
    end if;
    update "better_supabase"."quotes" y set
      "subtotal" = coalesce((v_data -> 'totals' ->> 'subtotal')::bigint, y."subtotal"),
      "tax_total" = coalesce((v_data -> 'totals' ->> 'tax')::bigint, y."tax_total"),
      "total" = coalesce((v_data -> 'totals' ->> 'total')::bigint, y."total")
    where y."id" = v_id;
  end if;
  select * into v_row from "better_supabase"."quotes" y where y."id" = v_id;
  return jsonb_build_object('subjectId', v_id::text, 'updatedAt', v_row."updated_at", 'warnings', v_warnings);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_payment (
  order_id  uuid,
  provider  text,
  reference text,
  status    text,
  currency  text,
  amount    bigint,
  captured  bigint DEFAULT 0,
  refunded  bigint DEFAULT 0
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_order record;
  v_line record;
  v_id uuid := record_payment.order_id;
  v_paid bigint;
  v_newly boolean := false;
  v_seq bigint;
  v_number text;
  v_invoice jsonb;
  v_claims text;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'only the service role can do this' using errcode = '42501', hint = 'ORDERS_FORBIDDEN';
  end if;
  if v_id is null then
    select x."order_id" into v_id from "better_supabase"."order_payments" x
    where x."provider" = record_payment.provider and x."reference" = record_payment.reference;
  end if;
  select x."id" as id, x."tenant_id" as tenant, x."number" as number, x."customer_id" as customer, x."status" as status, x."currency" as currency, x."total" as total, x."paid_total" as paid_total, x."refunded_total" as refunded_total, x."tax_total" as tax_total, x."tax_inclusive" as tax_inclusive, x."invoice_number" as invoice_number, x."placed_at" as placed_at into v_order from "better_supabase"."orders" x where x."id" = v_id for update;
  if not found then
    raise exception 'order not found' using errcode = 'P0002', hint = 'ORDERS_ORDER_NOT_FOUND';
  end if;
  if record_payment.status is null or record_payment.status not in ('requires_action', 'processing', 'authorized', 'succeeded', 'failed', 'canceled') then
    raise exception 'unknown payment status' using errcode = '22023', hint = 'ORDERS_PAYMENT_STATUS_INVALID';
  end if;
  if record_payment.currency is distinct from v_order.currency then
    raise exception 'the payment is in another currency than the order' using errcode = '22023', hint = 'ORDERS_CURRENCY_MISMATCH';
  end if;
  if coalesce(record_payment.amount, -1) < 0 or coalesce(record_payment.captured, 0) < 0 or coalesce(record_payment.refunded, 0) < 0 then
    raise exception 'payment amounts are zero or more' using errcode = '22023', hint = 'ORDERS_AMOUNT_INVALID';
  end if;
  insert into "better_supabase"."order_payments" as x ("tenant_id", "order_id", "provider", "reference", "status", "currency",
    "amount", "captured", "refunded")
  values (v_order.tenant, v_order.id, record_payment.provider, record_payment.reference, record_payment.status, record_payment.currency,
    record_payment.amount, coalesce(record_payment.captured, 0), coalesce(record_payment.refunded, 0))
  on conflict ("provider", "reference") do update set
    "status" = case when x."status" in ('succeeded', 'failed', 'canceled') and excluded."status" not in ('succeeded', 'failed', 'canceled') then x."status" else excluded."status" end,
    "amount" = excluded."amount",
    "captured" = greatest(x."captured", excluded."captured"),
    "refunded" = greatest(x."refunded", excluded."refunded"),
    "updated_at" = now()
  where x."order_id" = excluded."order_id";
  if not found then
    raise exception 'this payment reference belongs to another order' using errcode = '23505', hint = 'ORDERS_PAYMENT_CONFLICT';
  end if;
  select coalesce(sum(x."captured"), 0) into v_paid from "better_supabase"."order_payments" x
  where x."order_id" = v_order.id and x."status" = 'succeeded';
  update "better_supabase"."orders" x set "paid_total" = v_paid, "updated_at" = now() where x."id" = v_order.id;
  if v_order.status::text in ('pending_payment', 'confirmed') and v_paid >= v_order.total then
    perform "better_supabase"."order_transition"(v_order.id, 'paid');
    if not better_supabase.import_run() is not null then
    for v_line in
      select x."id" as id, x."variant_id" as variant, x."quantity" as quantity,
        x."location_id" as location, x."reservation_id" as reservation
      from "better_supabase"."order_lines" x
      where x."order_id" = v_order.id and x."reservation_id" is not null
      order by x."position"
    loop
      begin
        v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  perform "better_supabase"."commit_reservation"(v_line.reservation);
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      exception when sqlstate '55000' then
        begin
          v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  perform "better_supabase"."release_reservation"(v_line.reservation);
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
          perform "better_supabase"."move_stock"(v_order.tenant, v_line.variant, v_line.location, -v_line.quantity, 'sale', 'order', v_order.id::text, null, null);
        exception when sqlstate '23514' then
          update "better_supabase"."order_lines" x set "backordered" = true where x."id" = v_line.id;
        end;
      end;
    end loop;
    end if;
    v_invoice := "better_supabase"."create_invoice"(v_order.tenant,
      jsonb_build_object('title', replace('Order {number}', '{number}', v_order.number::text), 'currency', v_order.currency, 'termsDays', 0,
        'origin', jsonb_build_object('type', 'order', 'id', v_order.id::text)),
      (select coalesce(jsonb_agg(jsonb_build_object(
      'description', case when l."quantity" = 1 then l."title" else l."title" || ' x ' || l."quantity"::text end,
      'quantity', 1, 'unitAmount', (l."total" - l."tax")::text, 'currency', v_order.currency,
      'taxRateBps', case when (l."total" - l."tax") > 0 then round(l."tax" * 10000.0 / (l."total" - l."tax"))::integer else 0 end,
      'product', case when l."variant_id" is null then null else jsonb_build_object('type', 'product_variant', 'id', l."variant_id"::text) end)
      order by l."position"), '[]'::jsonb)
    from "better_supabase"."order_lines" l where l."order_id" = v_order.id)
    || (select case when x."shipping_total" > 0 then jsonb_build_array(jsonb_build_object('description', 'Shipping', 'quantity', 1, 'unitAmount', x."shipping_total"::text, 'currency', v_order.currency)) else '[]'::jsonb end
    from "better_supabase"."orders" x where x."id" = v_order.id));
    v_invoice := "better_supabase"."issue_invoice"((v_invoice ->> 'id')::uuid, current_date);
    v_invoice := "better_supabase"."record_invoice_payment"((v_invoice ->> 'id')::uuid, (v_invoice ->> 'total')::bigint,
      v_order.currency, now(), 'order', 'order:' || v_order.id::text);
    v_number := v_invoice ->> 'identifier';
    update "better_supabase"."orders" x set "invoice_number" = v_number, "invoice_sequence" = v_seq, "invoiced_at" = now()
    where x."id" = v_order.id;
    perform "better_supabase".emit_event('order.paid', jsonb_build_object('organizationId', v_order.tenant, 'subjectType', 'order', 'subjectId', v_order.id::text, 'id', v_order.id, 'number', v_order.number, 'customerId', v_order.customer, 'currency', v_order.currency, 'total', v_order.total::text, 'units', (select coalesce(sum(l."quantity"), 0)::text from "better_supabase"."order_lines" l where l."order_id" = v_order.id), 'invoiceNumber', v_number), 'orders/' || v_order.id::text, (v_order.tenant)::text, 'order.paid:' || v_order.id::text, 'better-supabase/orders');
    v_newly := true;
  end if;
  return jsonb_build_object('orderId', v_order.id, 'status', (select x."status" from "better_supabase"."orders" x where x."id" = v_order.id),
    'paidTotal', v_paid::text, 'newlyPaid', v_newly,
    'invoiceNumber', coalesce(v_number, v_order.invoice_number), 'invoiceId', v_invoice ->> 'id');
end;
$function$;
