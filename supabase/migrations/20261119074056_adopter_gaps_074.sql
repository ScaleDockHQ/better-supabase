SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.recompute_invoice_status (
  invoice uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."recompute_invoice_status"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.recompute_invoice_status (
  invoice uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."invoices";
  v_was text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."invoices" x where x."id" = recompute_invoice_status.invoice;
  if v_row."id" is null or (((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", case when v_row."direction" = 'purchase' then 'invoices.purchase' else 'invoices.manage' end), false))) is not true then
    if v_row."id" is not null and (((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'invoices.read'), false)) or better_supabase.row_visible('"better_supabase"."invoices"'::regclass, 'id', v_row."id")) then
      raise exception 'you may not recompute this invoice' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
    end if;
    raise exception 'no such invoice you can read' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  select * into v_row from "better_supabase"."invoices" x where x."id" = recompute_invoice_status.invoice for update;
  if not found then
    raise exception 'no such invoice you can read' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  v_was := v_row."status"::text;
  update "better_supabase"."invoices" x set "credited_total" = coalesce((
      select sum(y."total") from "better_supabase"."invoices" y
      where y."original_id" = x."id" and y."kind" = 'credit_note' and y."status" not in ('draft', 'void')
    ), 0)
  where x."id" = v_row."id"
  returning * into v_row;
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

REVOKE ALL ON FUNCTION "api"."recompute_invoice_status"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."recompute_invoice_status"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."recompute_invoice_status"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."recompute_invoice_status"(uuid) TO "authenticated", "service_role";
