SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.clone_invoice (
  source    uuid,
  overrides jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_src "better_supabase"."invoices";
  v_created jsonb;
  v_id uuid;
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_src from "better_supabase"."invoices" x where x."id" = clone_invoice.source;
  if not found then
    raise exception 'no such invoice' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  v_tenant := coalesce(nullif(coalesce(clone_invoice.overrides, '{}'::jsonb) ->> 'tenantId', '')::uuid, v_src."tenant_id");
  if v_tenant is distinct from v_src."tenant_id" and not ((auth.role() = 'service_role') or false) then
    raise exception 'not allowed to change invoices' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_tenant, 'invoices.write'), false)) then
    raise exception 'not allowed to change invoices' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_invoice_clone"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using clone_invoice.source, clone_invoice.overrides;
    end if;
  end;
  v_created := "better_supabase"."create_invoice"(v_tenant, jsonb_strip_nulls(jsonb_build_object('note', v_src."note", 'termsDays', v_src."terms_days", 'pricesIncludeTax', v_src."prices_include_tax", 'discountBps', v_src."discount_bps", 'discountAmount', v_src."discount_amount", 'depositBps', v_src."deposit_bps", 'depositAmount', v_src."deposit_amount", 'company', case when v_src."company_id" is null then null else jsonb_build_object('type', v_src."company_type", 'id', v_src."company_id") end, 'contact', case when v_src."contact_id" is null then null else jsonb_build_object('type', v_src."contact_type", 'id', v_src."contact_id") end, 'title', v_src."title", 'currency', v_src."currency", 'templateId', null, 'sourceTemplateId', null)) || (coalesce(clone_invoice.overrides, '{}'::jsonb) - 'templateId') || jsonb_strip_nulls(jsonb_build_object('templateId', null, 'sourceTemplateId', null)), null);
  v_id := (v_created ->> 'id')::uuid;
  insert into "better_supabase"."invoice_lines"
  select (jsonb_populate_record(null::"better_supabase"."invoice_lines", to_jsonb(l) || jsonb_build_object('id', gen_random_uuid(), 'parent_id', v_id, 'tenant_id', v_tenant))).*
  from "better_supabase"."invoice_lines" l where l."parent_id" = clone_invoice.source;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_invoice_clone"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'paid_total', x."paid_total"::text, 'credited_total', x."credited_total"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text, 'deposit_amount', x."deposit_amount"::text, 'discount_amount', x."discount_amount"::text, 'discount_amount_early', x."discount_amount_early"::text) || jsonb_build_object(
      'balance', (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), '[]'::jsonb),
      'overdue', x."status" in ('issued', 'partially_paid') and x."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code", 'taxCodeId', il."tax_code_id", 'unitCost', il."unit_cost"::text, 'dimensions', il."dimensions") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = x."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text)), '[]'::jsonb)) from "better_supabase"."invoices" x where x."id" = v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.clone_quote (
  source    uuid,
  overrides jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_src "better_supabase"."quotes";
  v_created jsonb;
  v_id uuid;
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_src from "better_supabase"."quotes" x where x."id" = clone_quote.source;
  if not found then
    raise exception 'no such quote' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  v_tenant := coalesce(nullif(coalesce(clone_quote.overrides, '{}'::jsonb) ->> 'tenantId', '')::uuid, v_src."tenant_id");
  if v_tenant is distinct from v_src."tenant_id" and not ((auth.role() = 'service_role') or false) then
    raise exception 'not allowed to change quotes' using errcode = '42501', hint = 'QUOTE_FORBIDDEN';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_tenant, 'quotes.write'), false)) then
    raise exception 'not allowed to change quotes' using errcode = '42501', hint = 'QUOTE_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_quote_clone"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using clone_quote.source, clone_quote.overrides;
    end if;
  end;
  v_created := "better_supabase"."create_quote"(v_tenant, jsonb_strip_nulls(jsonb_build_object('terms', v_src."terms", 'note', v_src."note", 'pricesIncludeTax', v_src."prices_include_tax", 'discountBps', v_src."discount_bps", 'discountAmount', v_src."discount_amount", 'depositBps', v_src."deposit_bps", 'depositAmount', v_src."deposit_amount", 'depositRequired', v_src."deposit_required", 'company', case when v_src."company_id" is null then null else jsonb_build_object('type', v_src."company_type", 'id', v_src."company_id") end, 'contact', case when v_src."contact_id" is null then null else jsonb_build_object('type', v_src."contact_type", 'id', v_src."contact_id") end, 'title', v_src."title", 'currency', v_src."currency", 'templateId', null, 'sourceTemplateId', null)) || (coalesce(clone_quote.overrides, '{}'::jsonb) - 'templateId') || jsonb_strip_nulls(jsonb_build_object('templateId', null, 'sourceTemplateId', null)), null);
  v_id := (v_created ->> 'id')::uuid;
  insert into "better_supabase"."quote_lines"
  select (jsonb_populate_record(null::"better_supabase"."quote_lines", to_jsonb(l) || jsonb_build_object('id', gen_random_uuid(), 'parent_id', v_id, 'tenant_id', v_tenant))).*
  from "better_supabase"."quote_lines" l where l."parent_id" = clone_quote.source;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_quote_clone"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return v_created;
end;
$function$;
