SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.list_invoices_for_subject (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  page_size    integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_invoices_for_subject"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION better_supabase.list_invoices_for_subject (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  page_size    integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', list_invoices_for_subject.tenant, 'invoices.read'), false)) then
    raise exception 'not allowed to read this organization''s invoices' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(z.item order by z.created desc, z.id desc)
    from (
      select to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'paid_total', x."paid_total"::text, 'credited_total', x."credited_total"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text, 'deposit_amount', x."deposit_amount"::text, 'discount_amount', x."discount_amount"::text, 'discount_amount_early', x."discount_amount_early"::text) || jsonb_build_object(
      'balance', (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), '[]'::jsonb),
      'overdue', x."status" in ('issued', 'partially_paid') and x."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code", 'taxCodeId', il."tax_code_id", 'unitCost', il."unit_cost"::text, 'dimensions', il."dimensions") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = x."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text)), '[]'::jsonb)) as item, x."created_at" as created, x."id" as id
      from "better_supabase"."invoices" x
      where x."tenant_id" = list_invoices_for_subject.tenant
        and ((x."company_type" = list_invoices_for_subject.subject_type and x."company_id"::text = list_invoices_for_subject.subject_id) or (x."contact_type" = list_invoices_for_subject.subject_type and x."contact_id"::text = list_invoices_for_subject.subject_id))
      order by x."created_at" desc, x."id" desc
      limit least(greatest(coalesce(list_invoices_for_subject.page_size, 50), 1), 200)
    ) z
  ), '[]'::jsonb);
end;
$function$;

REVOKE ALL ON FUNCTION "api"."list_invoices_for_subject"(uuid, text, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_invoices_for_subject"(uuid, text, text, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_invoices_for_subject"(uuid, text, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_invoices_for_subject"(uuid, text, text, integer) TO "authenticated", "service_role";
