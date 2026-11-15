SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.get_invoice (
  invoice_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_invoice"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_time_rate (
  rate_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_time_rate"($1) $function$;

CREATE OR REPLACE FUNCTION api.page_accounting_accounts (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_accounting_accounts"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_accounting_entries (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_accounting_entries"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_bank_accounts (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_bank_accounts"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_expense_categories (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_expense_categories"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_expense_reports (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_expense_reports"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_invoices (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_invoices"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_payment_batches (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_payment_batches"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_score_models (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_score_models"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_time_rates (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_time_rates"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.get_invoice (
  invoice_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_json jsonb;
begin
  select to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'paid_total', x."paid_total"::text, 'credited_total', x."credited_total"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text, 'deposit_amount', x."deposit_amount"::text, 'discount_amount', x."discount_amount"::text, 'discount_amount_early', x."discount_amount_early"::text) || jsonb_build_object(
      'balance', (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), '[]'::jsonb),
      'overdue', x."status" in ('issued', 'partially_paid') and x."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code", 'taxCodeId', il."tax_code_id", 'unitCost', il."unit_cost"::text, 'dimensions', il."dimensions") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = x."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text)), '[]'::jsonb)) into v_json from "better_supabase"."invoices" x
  where x."id" = get_invoice.invoice_id and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.read'), false));
  if v_json is null then
    raise exception 'no such invoice you can read' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  return v_json;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_time_rate (
  rate_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."time_rates"%rowtype;
begin
  select * into v_row from "better_supabase"."time_rates" x where x."id" = get_time_rate.rate_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'billable_time.read'), false)) then
    raise exception 'time rate not found' using errcode = 'P0002', hint = 'BILLABLE_TIME_RATE_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'rate', v_row."rate"::text, 'currency', v_row."currency", 'effectiveFrom', v_row."effective_from", 'cost', v_row."cost_amount"::text, 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_accounting_accounts (
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
  v_filters jsonb := coalesce(page_accounting_accounts.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 100), 1), 500);
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
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'ACCOUNTING_ACCOUNT_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('type', 'active') then
      raise exception 'facet is one of type, active' using errcode = '22023', hint = 'ACCOUNTING_ACCOUNT_INVALID';
    end if;
    with s as (
      select (case v_facet when 'type' then (x."type")::text when 'active' then (x."active"::text)::text end) as v
      from "better_supabase"."accounting_accounts" x
      where x."tenant_id" = page_accounting_accounts.tenant
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."type" = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or x."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."code" ilike v_search or x."name" ilike v_search)
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
      select 1 from "better_supabase"."accounting_accounts" x
      where x."tenant_id" = page_accounting_accounts.tenant
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."type" = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or x."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."code" ilike v_search or x."name" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('code', 'name') then
    raise exception 'sort is one of code, name' using errcode = '22023', hint = 'ACCOUNTING_ACCOUNT_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'ACCOUNTING_ACCOUNT_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ACCOUNTING_ACCOUNT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'code', x."code", 'name', x."name", 'type', x."type", 'subtype', x."subtype", 'parentId', x."parent_id", 'currency', x."currency", 'reconcilable', x."reconcilable", 'normalSide', x."normal_side", 'level', x."level", 'defaultTaxCodeId', x."default_tax_code_id", 'active', x."active", 'roles', coalesce((select jsonb_agg(ar."role" order by ar."role") from "better_supabase"."accounting_account_roles" ar where ar."account_id" = x."id"), '[]'::jsonb), 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."code")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."accounting_accounts" x
      where x."tenant_id" = page_accounting_accounts.tenant
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."type" = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or x."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."code" ilike v_search or x."name" ilike v_search)
        and (v_after is null or (x."code", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."code" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ACCOUNTING_ACCOUNT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'code', x."code", 'name', x."name", 'type', x."type", 'subtype', x."subtype", 'parentId', x."parent_id", 'currency', x."currency", 'reconcilable', x."reconcilable", 'normalSide', x."normal_side", 'level', x."level", 'defaultTaxCodeId', x."default_tax_code_id", 'active', x."active", 'roles', coalesce((select jsonb_agg(ar."role" order by ar."role") from "better_supabase"."accounting_account_roles" ar where ar."account_id" = x."id"), '[]'::jsonb), 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."code")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."accounting_accounts" x
      where x."tenant_id" = page_accounting_accounts.tenant
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."type" = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or x."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."code" ilike v_search or x."name" ilike v_search)
        and (v_after is null or (x."code" <= (v_after ->> 0)::text and ((x."code" < (v_after ->> 0)::text) or (x."code" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."code" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'code' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ACCOUNTING_ACCOUNT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'code', x."code", 'name', x."name", 'type', x."type", 'subtype', x."subtype", 'parentId', x."parent_id", 'currency', x."currency", 'reconcilable', x."reconcilable", 'normalSide', x."normal_side", 'level', x."level", 'defaultTaxCodeId', x."default_tax_code_id", 'active', x."active", 'roles', coalesce((select jsonb_agg(ar."role" order by ar."role") from "better_supabase"."accounting_account_roles" ar where ar."account_id" = x."id"), '[]'::jsonb), 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."code")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."accounting_accounts" x
      where x."tenant_id" = page_accounting_accounts.tenant
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."type" = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or x."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."code" ilike v_search or x."name" ilike v_search)
        and (v_after is null or (x."code", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."code" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'code' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ACCOUNTING_ACCOUNT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'code', x."code", 'name', x."name", 'type', x."type", 'subtype', x."subtype", 'parentId', x."parent_id", 'currency', x."currency", 'reconcilable', x."reconcilable", 'normalSide', x."normal_side", 'level', x."level", 'defaultTaxCodeId', x."default_tax_code_id", 'active', x."active", 'roles', coalesce((select jsonb_agg(ar."role" order by ar."role") from "better_supabase"."accounting_account_roles" ar where ar."account_id" = x."id"), '[]'::jsonb), 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."code")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."accounting_accounts" x
      where x."tenant_id" = page_accounting_accounts.tenant
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."type" = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or x."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."code" ilike v_search or x."name" ilike v_search)
        and (v_after is null or (x."code" <= (v_after ->> 0)::text and ((x."code" < (v_after ->> 0)::text) or (x."code" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."code" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ACCOUNTING_ACCOUNT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'code', x."code", 'name', x."name", 'type', x."type", 'subtype', x."subtype", 'parentId', x."parent_id", 'currency', x."currency", 'reconcilable', x."reconcilable", 'normalSide', x."normal_side", 'level', x."level", 'defaultTaxCodeId', x."default_tax_code_id", 'active', x."active", 'roles', coalesce((select jsonb_agg(ar."role" order by ar."role") from "better_supabase"."accounting_account_roles" ar where ar."account_id" = x."id"), '[]'::jsonb), 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."accounting_accounts" x
      where x."tenant_id" = page_accounting_accounts.tenant
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."type" = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or x."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."code" ilike v_search or x."name" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ACCOUNTING_ACCOUNT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'code', x."code", 'name', x."name", 'type', x."type", 'subtype', x."subtype", 'parentId', x."parent_id", 'currency', x."currency", 'reconcilable', x."reconcilable", 'normalSide', x."normal_side", 'level', x."level", 'defaultTaxCodeId', x."default_tax_code_id", 'active', x."active", 'roles', coalesce((select jsonb_agg(ar."role" order by ar."role") from "better_supabase"."accounting_account_roles" ar where ar."account_id" = x."id"), '[]'::jsonb), 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."accounting_accounts" x
      where x."tenant_id" = page_accounting_accounts.tenant
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."type" = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or x."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."code" ilike v_search or x."name" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."accounting_accounts" x
      where x."tenant_id" = page_accounting_accounts.tenant
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."type" = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or x."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."code" ilike v_search or x."name" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
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
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
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
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
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
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'journalId', x."journal_id", 'number', x."number", 'fiscalYear', x."fiscal_year", 'entryDate', x."entry_date", 'periodId', x."period_id", 'status', x."status", 'reference', x."reference", 'sourceType', x."source_type", 'sourceId', x."source_id", 'reversesId', x."reverses_id", 'memo', x."memo", 'total', coalesce((select sum(et."debit") from "better_supabase"."accounting_entry_lines" et where et."entry_id" = x."id"), 0)::text, 'postedAt', x."posted_at", 'postedBy', x."posted_by", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."entry_date")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."accounting_entries" x
      where x."tenant_id" = page_accounting_entries.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
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
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'journalId', x."journal_id", 'number', x."number", 'fiscalYear', x."fiscal_year", 'entryDate', x."entry_date", 'periodId', x."period_id", 'status', x."status", 'reference', x."reference", 'sourceType', x."source_type", 'sourceId', x."source_id", 'reversesId', x."reverses_id", 'memo', x."memo", 'total', coalesce((select sum(et."debit") from "better_supabase"."accounting_entry_lines" et where et."entry_id" = x."id"), 0)::text, 'postedAt', x."posted_at", 'postedBy', x."posted_by", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."entry_date")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."accounting_entries" x
      where x."tenant_id" = page_accounting_entries.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
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
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'journalId', x."journal_id", 'number', x."number", 'fiscalYear', x."fiscal_year", 'entryDate', x."entry_date", 'periodId', x."period_id", 'status', x."status", 'reference', x."reference", 'sourceType', x."source_type", 'sourceId', x."source_id", 'reversesId', x."reverses_id", 'memo', x."memo", 'total', coalesce((select sum(et."debit") from "better_supabase"."accounting_entry_lines" et where et."entry_id" = x."id"), 0)::text, 'postedAt', x."posted_at", 'postedBy', x."posted_by", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."entry_date")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."accounting_entries" x
      where x."tenant_id" = page_accounting_entries.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
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
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'journalId', x."journal_id", 'number', x."number", 'fiscalYear', x."fiscal_year", 'entryDate', x."entry_date", 'periodId', x."period_id", 'status', x."status", 'reference', x."reference", 'sourceType', x."source_type", 'sourceId', x."source_id", 'reversesId', x."reverses_id", 'memo', x."memo", 'total', coalesce((select sum(et."debit") from "better_supabase"."accounting_entry_lines" et where et."entry_id" = x."id"), 0)::text, 'postedAt', x."posted_at", 'postedBy', x."posted_by", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."entry_date")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."accounting_entries" x
      where x."tenant_id" = page_accounting_entries.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
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
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'journalId', x."journal_id", 'number', x."number", 'fiscalYear', x."fiscal_year", 'entryDate', x."entry_date", 'periodId', x."period_id", 'status', x."status", 'reference', x."reference", 'sourceType', x."source_type", 'sourceId', x."source_id", 'reversesId', x."reverses_id", 'memo', x."memo", 'total', coalesce((select sum(et."debit") from "better_supabase"."accounting_entry_lines" et where et."entry_id" = x."id"), 0)::text, 'postedAt', x."posted_at", 'postedBy', x."posted_by", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."accounting_entries" x
      where x."tenant_id" = page_accounting_entries.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
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
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'journalId', x."journal_id", 'number', x."number", 'fiscalYear', x."fiscal_year", 'entryDate', x."entry_date", 'periodId', x."period_id", 'status', x."status", 'reference', x."reference", 'sourceType', x."source_type", 'sourceId', x."source_id", 'reversesId', x."reverses_id", 'memo', x."memo", 'total', coalesce((select sum(et."debit") from "better_supabase"."accounting_entry_lines" et where et."entry_id" = x."id"), 0)::text, 'postedAt', x."posted_at", 'postedBy', x."posted_by", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."accounting_entries" x
      where x."tenant_id" = page_accounting_entries.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
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
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
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

CREATE OR REPLACE FUNCTION better_supabase.page_bank_accounts (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_bank_accounts.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (page_bank_accounts.tenant is not null and coalesce(better_supabase.can('tenant', page_bank_accounts.tenant, 'banking.read'), false))) then
    raise exception 'not allowed to read bank accounts' using errcode = '42501', hint = 'BANKING_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'BANK_ACCOUNT_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('currency') then
      raise exception 'facet is one of currency' using errcode = '22023', hint = 'BANK_ACCOUNT_INVALID';
    end if;
    with s as (
      select (case v_facet when 'currency' then (x."currency")::text end) as v
      from "better_supabase"."bank_accounts" x
      where x."tenant_id" = page_bank_accounts.tenant
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."iban" ilike v_search or x."holder" ilike v_search)
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
      select 1 from "better_supabase"."bank_accounts" x
      where x."tenant_id" = page_bank_accounts.tenant
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."iban" ilike v_search or x."holder" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'createdAt') then
    raise exception 'sort is one of name, createdAt' using errcode = '22023', hint = 'BANK_ACCOUNT_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'BANK_ACCOUNT_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'BANK_ACCOUNT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'iban', x."iban", 'bic', x."bic", 'currency', x."currency", 'holder', x."holder", 'primary', x."is_primary", 'journalId', x."journal_id", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."bank_accounts" x
      where x."tenant_id" = page_bank_accounts.tenant
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."iban" ilike v_search or x."holder" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'BANK_ACCOUNT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'iban', x."iban", 'bic', x."bic", 'currency', x."currency", 'holder', x."holder", 'primary', x."is_primary", 'journalId', x."journal_id", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."bank_accounts" x
      where x."tenant_id" = page_bank_accounts.tenant
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."iban" ilike v_search or x."holder" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'BANK_ACCOUNT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'iban', x."iban", 'bic', x."bic", 'currency', x."currency", 'holder', x."holder", 'primary', x."is_primary", 'journalId', x."journal_id", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."bank_accounts" x
      where x."tenant_id" = page_bank_accounts.tenant
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."iban" ilike v_search or x."holder" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'BANK_ACCOUNT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'iban', x."iban", 'bic', x."bic", 'currency', x."currency", 'holder', x."holder", 'primary', x."is_primary", 'journalId', x."journal_id", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."bank_accounts" x
      where x."tenant_id" = page_bank_accounts.tenant
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."iban" ilike v_search or x."holder" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'BANK_ACCOUNT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'iban', x."iban", 'bic', x."bic", 'currency', x."currency", 'holder', x."holder", 'primary', x."is_primary", 'journalId', x."journal_id", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."bank_accounts" x
      where x."tenant_id" = page_bank_accounts.tenant
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."iban" ilike v_search or x."holder" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'BANK_ACCOUNT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'iban', x."iban", 'bic', x."bic", 'currency', x."currency", 'holder', x."holder", 'primary', x."is_primary", 'journalId', x."journal_id", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."bank_accounts" x
      where x."tenant_id" = page_bank_accounts.tenant
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."iban" ilike v_search or x."holder" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."bank_accounts" x
      where x."tenant_id" = page_bank_accounts.tenant
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."iban" ilike v_search or x."holder" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_expense_categories (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_expense_categories.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
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
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', page_expense_categories.tenant, 'expenses.read'), false)) or coalesce(better_supabase.can('tenant', page_expense_categories.tenant, 'expenses.submit'), false)) then
    raise exception 'not allowed to read expense categories' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('currency') then
      raise exception 'facet is one of currency' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
    end if;
    with s as (
      select (case v_facet when 'currency' then (coalesce(c."currency", ''))::text end) as v
      from "better_supabase"."expense_categories" c
      where c."tenant_id" = page_expense_categories.tenant
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (c."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else c."archived_at" is null end)
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or c."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or c."name" ilike v_search)
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
      select 1 from "better_supabase"."expense_categories" c
      where c."tenant_id" = page_expense_categories.tenant
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (c."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else c."archived_at" is null end)
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or c."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or c."name" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'createdAt') then
    raise exception 'sort is one of name, createdAt' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', c."id", 'organizationId', c."tenant_id", 'key', c."key", 'name', c."name", 'currency', c."currency", 'limitAmount', c."limit_amount"::text, 'receiptOver', c."receipt_over"::text, 'archivedAt', c."archived_at", 'createdAt', c."created_at", 'updatedAt', c."updated_at") as j, jsonb_build_array((lower(c."name"))::text, (c."id")::text) as k
    from (
      select * from "better_supabase"."expense_categories" c
      where c."tenant_id" = page_expense_categories.tenant
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (c."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else c."archived_at" is null end)
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or c."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or c."name" ilike v_search)
        and (v_after is null or (lower(c."name"), c."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(c."name") asc, c."id" asc
      limit v_limit + 1 offset v_offset
    ) c
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', c."id", 'organizationId', c."tenant_id", 'key', c."key", 'name', c."name", 'currency', c."currency", 'limitAmount', c."limit_amount"::text, 'receiptOver', c."receipt_over"::text, 'archivedAt', c."archived_at", 'createdAt', c."created_at", 'updatedAt', c."updated_at") as j, jsonb_build_array((lower(c."name"))::text, (c."id")::text) as k
    from (
      select * from "better_supabase"."expense_categories" c
      where c."tenant_id" = page_expense_categories.tenant
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (c."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else c."archived_at" is null end)
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or c."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or c."name" ilike v_search)
        and (v_after is null or (lower(c."name") <= (v_after ->> 0)::text and ((lower(c."name") < (v_after ->> 0)::text) or (lower(c."name") = (v_after ->> 0)::text and c."id" > (v_after ->> 1)::uuid))))
      order by lower(c."name") desc, c."id" asc
      limit v_limit + 1 offset v_offset
    ) c
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', c."id", 'organizationId', c."tenant_id", 'key', c."key", 'name', c."name", 'currency', c."currency", 'limitAmount', c."limit_amount"::text, 'receiptOver', c."receipt_over"::text, 'archivedAt', c."archived_at", 'createdAt', c."created_at", 'updatedAt', c."updated_at") as j, jsonb_build_array((lower(c."name"))::text, (c."id")::text) as k
    from (
      select * from "better_supabase"."expense_categories" c
      where c."tenant_id" = page_expense_categories.tenant
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (c."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else c."archived_at" is null end)
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or c."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or c."name" ilike v_search)
        and (v_after is null or (lower(c."name"), c."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(c."name") asc, c."id" asc
      limit v_limit + 1 offset v_offset
    ) c
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', c."id", 'organizationId', c."tenant_id", 'key', c."key", 'name', c."name", 'currency', c."currency", 'limitAmount', c."limit_amount"::text, 'receiptOver', c."receipt_over"::text, 'archivedAt', c."archived_at", 'createdAt', c."created_at", 'updatedAt', c."updated_at") as j, jsonb_build_array((lower(c."name"))::text, (c."id")::text) as k
    from (
      select * from "better_supabase"."expense_categories" c
      where c."tenant_id" = page_expense_categories.tenant
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (c."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else c."archived_at" is null end)
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or c."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or c."name" ilike v_search)
        and (v_after is null or (lower(c."name") <= (v_after ->> 0)::text and ((lower(c."name") < (v_after ->> 0)::text) or (lower(c."name") = (v_after ->> 0)::text and c."id" > (v_after ->> 1)::uuid))))
      order by lower(c."name") desc, c."id" asc
      limit v_limit + 1 offset v_offset
    ) c
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', c."id", 'organizationId', c."tenant_id", 'key', c."key", 'name', c."name", 'currency', c."currency", 'limitAmount', c."limit_amount"::text, 'receiptOver', c."receipt_over"::text, 'archivedAt', c."archived_at", 'createdAt', c."created_at", 'updatedAt', c."updated_at") as j, jsonb_build_array((c."created_at")::text, (c."id")::text) as k
    from (
      select * from "better_supabase"."expense_categories" c
      where c."tenant_id" = page_expense_categories.tenant
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (c."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else c."archived_at" is null end)
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or c."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or c."name" ilike v_search)
        and (v_after is null or (c."created_at", c."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by c."created_at" asc, c."id" asc
      limit v_limit + 1 offset v_offset
    ) c
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', c."id", 'organizationId', c."tenant_id", 'key', c."key", 'name', c."name", 'currency', c."currency", 'limitAmount', c."limit_amount"::text, 'receiptOver', c."receipt_over"::text, 'archivedAt', c."archived_at", 'createdAt', c."created_at", 'updatedAt', c."updated_at") as j, jsonb_build_array((c."created_at")::text, (c."id")::text) as k
    from (
      select * from "better_supabase"."expense_categories" c
      where c."tenant_id" = page_expense_categories.tenant
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (c."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else c."archived_at" is null end)
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or c."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or c."name" ilike v_search)
        and (v_after is null or (c."created_at" <= (v_after ->> 0)::timestamptz and ((c."created_at" < (v_after ->> 0)::timestamptz) or (c."created_at" = (v_after ->> 0)::timestamptz and c."id" > (v_after ->> 1)::uuid))))
      order by c."created_at" desc, c."id" asc
      limit v_limit + 1 offset v_offset
    ) c
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."expense_categories" c
      where c."tenant_id" = page_expense_categories.tenant
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (c."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else c."archived_at" is null end)
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or c."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or c."name" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_expense_reports (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_expense_reports.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_reader boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', page_expense_reports.tenant, 'expenses.read'), false));
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
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
  if not (v_reader or coalesce(better_supabase.can('tenant', page_expense_reports.tenant, 'expenses.submit'), false)) then
    raise exception 'not allowed to list expense reports' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'EXPENSE_REPORT_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'currency') then
      raise exception 'facet is one of status, currency' using errcode = '22023', hint = 'EXPENSE_REPORT_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then ((select (case when x."cancelled_at" is not null then 'cancelled' when x."reimbursed_at" is not null then 'reimbursed' when x."approved_at" is not null then 'approved' when ap."status" = 'pending' then 'submitted' when ap."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) from (values (1)) d(n) left join "better_supabase"."approval_requests" ap on ap."id" = x."approval_id"))::text when 'currency' then (x."currency")::text end) as v
      from "better_supabase"."expense_reports" x
      where x."tenant_id" = page_expense_reports.tenant
        and ((v_reader and not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false)) or x."user_id" = auth.uid())
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (select (case when x."cancelled_at" is not null then 'cancelled' when x."reimbursed_at" is not null then 'reimbursed' when x."approved_at" is not null then 'approved' when ap."status" = 'pending' then 'submitted' when ap."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) from (values (1)) d(n) left join "better_supabase"."approval_requests" ap on ap."id" = x."approval_id") = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or x."title" ilike v_search)
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
      select 1 from "better_supabase"."expense_reports" x
      where x."tenant_id" = page_expense_reports.tenant
        and ((v_reader and not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false)) or x."user_id" = auth.uid())
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (select (case when x."cancelled_at" is not null then 'cancelled' when x."reimbursed_at" is not null then 'reimbursed' when x."approved_at" is not null then 'approved' when ap."status" = 'pending' then 'submitted' when ap."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) from (values (1)) d(n) left join "better_supabase"."approval_requests" ap on ap."id" = x."approval_id") = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or x."title" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'title') then
    raise exception 'sort is one of createdAt, title' using errcode = '22023', hint = 'EXPENSE_REPORT_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'EXPENSE_REPORT_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EXPENSE_REPORT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'title', x."title", 'currency', x."currency", 'note', x."note", 'status', (case when x."cancelled_at" is not null then 'cancelled' when x."reimbursed_at" is not null then 'reimbursed' when x."approved_at" is not null then 'approved' when ap."status" = 'pending' then 'submitted' when ap."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = x."id"), 0)::text, 'approvalId', x."approval_id", 'submittedAt', x."submitted_at", 'approvedAt', x."approved_at", 'approvalTransactionId', x."approval_transaction_id", 'reimbursedAt', x."reimbursed_at", 'reimbursementTransactionId', x."reimbursement_transaction_id", 'cancelledAt', x."cancelled_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'dimensions', l."dimensions", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', (select count(*) from "better_supabase"."attachments" t where t."subject_type" = 'expense_line' and t."subject_id" = l."id"::text and t."uploaded_at" is not null and t."status" <> 'infected'), 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = x."id")) from (values (1)) d(n) left join "better_supabase"."approval_requests" ap on ap."id" = x."approval_id") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."expense_reports" x
      where x."tenant_id" = page_expense_reports.tenant
        and ((v_reader and not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false)) or x."user_id" = auth.uid())
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (select (case when x."cancelled_at" is not null then 'cancelled' when x."reimbursed_at" is not null then 'reimbursed' when x."approved_at" is not null then 'approved' when ap."status" = 'pending' then 'submitted' when ap."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) from (values (1)) d(n) left join "better_supabase"."approval_requests" ap on ap."id" = x."approval_id") = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EXPENSE_REPORT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'title', x."title", 'currency', x."currency", 'note', x."note", 'status', (case when x."cancelled_at" is not null then 'cancelled' when x."reimbursed_at" is not null then 'reimbursed' when x."approved_at" is not null then 'approved' when ap."status" = 'pending' then 'submitted' when ap."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = x."id"), 0)::text, 'approvalId', x."approval_id", 'submittedAt', x."submitted_at", 'approvedAt', x."approved_at", 'approvalTransactionId', x."approval_transaction_id", 'reimbursedAt', x."reimbursed_at", 'reimbursementTransactionId', x."reimbursement_transaction_id", 'cancelledAt', x."cancelled_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'dimensions', l."dimensions", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', (select count(*) from "better_supabase"."attachments" t where t."subject_type" = 'expense_line' and t."subject_id" = l."id"::text and t."uploaded_at" is not null and t."status" <> 'infected'), 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = x."id")) from (values (1)) d(n) left join "better_supabase"."approval_requests" ap on ap."id" = x."approval_id") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."expense_reports" x
      where x."tenant_id" = page_expense_reports.tenant
        and ((v_reader and not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false)) or x."user_id" = auth.uid())
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (select (case when x."cancelled_at" is not null then 'cancelled' when x."reimbursed_at" is not null then 'reimbursed' when x."approved_at" is not null then 'approved' when ap."status" = 'pending' then 'submitted' when ap."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) from (values (1)) d(n) left join "better_supabase"."approval_requests" ap on ap."id" = x."approval_id") = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EXPENSE_REPORT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'title', x."title", 'currency', x."currency", 'note', x."note", 'status', (case when x."cancelled_at" is not null then 'cancelled' when x."reimbursed_at" is not null then 'reimbursed' when x."approved_at" is not null then 'approved' when ap."status" = 'pending' then 'submitted' when ap."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = x."id"), 0)::text, 'approvalId', x."approval_id", 'submittedAt', x."submitted_at", 'approvedAt', x."approved_at", 'approvalTransactionId', x."approval_transaction_id", 'reimbursedAt', x."reimbursed_at", 'reimbursementTransactionId', x."reimbursement_transaction_id", 'cancelledAt', x."cancelled_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'dimensions', l."dimensions", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', (select count(*) from "better_supabase"."attachments" t where t."subject_type" = 'expense_line' and t."subject_id" = l."id"::text and t."uploaded_at" is not null and t."status" <> 'infected'), 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = x."id")) from (values (1)) d(n) left join "better_supabase"."approval_requests" ap on ap."id" = x."approval_id") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."expense_reports" x
      where x."tenant_id" = page_expense_reports.tenant
        and ((v_reader and not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false)) or x."user_id" = auth.uid())
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (select (case when x."cancelled_at" is not null then 'cancelled' when x."reimbursed_at" is not null then 'reimbursed' when x."approved_at" is not null then 'approved' when ap."status" = 'pending' then 'submitted' when ap."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) from (values (1)) d(n) left join "better_supabase"."approval_requests" ap on ap."id" = x."approval_id") = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EXPENSE_REPORT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'title', x."title", 'currency', x."currency", 'note', x."note", 'status', (case when x."cancelled_at" is not null then 'cancelled' when x."reimbursed_at" is not null then 'reimbursed' when x."approved_at" is not null then 'approved' when ap."status" = 'pending' then 'submitted' when ap."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = x."id"), 0)::text, 'approvalId', x."approval_id", 'submittedAt', x."submitted_at", 'approvedAt', x."approved_at", 'approvalTransactionId', x."approval_transaction_id", 'reimbursedAt', x."reimbursed_at", 'reimbursementTransactionId', x."reimbursement_transaction_id", 'cancelledAt', x."cancelled_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'dimensions', l."dimensions", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', (select count(*) from "better_supabase"."attachments" t where t."subject_type" = 'expense_line' and t."subject_id" = l."id"::text and t."uploaded_at" is not null and t."status" <> 'infected'), 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = x."id")) from (values (1)) d(n) left join "better_supabase"."approval_requests" ap on ap."id" = x."approval_id") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."expense_reports" x
      where x."tenant_id" = page_expense_reports.tenant
        and ((v_reader and not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false)) or x."user_id" = auth.uid())
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (select (case when x."cancelled_at" is not null then 'cancelled' when x."reimbursed_at" is not null then 'reimbursed' when x."approved_at" is not null then 'approved' when ap."status" = 'pending' then 'submitted' when ap."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) from (values (1)) d(n) left join "better_supabase"."approval_requests" ap on ap."id" = x."approval_id") = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EXPENSE_REPORT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'title', x."title", 'currency', x."currency", 'note', x."note", 'status', (case when x."cancelled_at" is not null then 'cancelled' when x."reimbursed_at" is not null then 'reimbursed' when x."approved_at" is not null then 'approved' when ap."status" = 'pending' then 'submitted' when ap."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = x."id"), 0)::text, 'approvalId', x."approval_id", 'submittedAt', x."submitted_at", 'approvedAt', x."approved_at", 'approvalTransactionId', x."approval_transaction_id", 'reimbursedAt', x."reimbursed_at", 'reimbursementTransactionId', x."reimbursement_transaction_id", 'cancelledAt', x."cancelled_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'dimensions', l."dimensions", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', (select count(*) from "better_supabase"."attachments" t where t."subject_type" = 'expense_line' and t."subject_id" = l."id"::text and t."uploaded_at" is not null and t."status" <> 'infected'), 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = x."id")) from (values (1)) d(n) left join "better_supabase"."approval_requests" ap on ap."id" = x."approval_id") as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."expense_reports" x
      where x."tenant_id" = page_expense_reports.tenant
        and ((v_reader and not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false)) or x."user_id" = auth.uid())
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (select (case when x."cancelled_at" is not null then 'cancelled' when x."reimbursed_at" is not null then 'reimbursed' when x."approved_at" is not null then 'approved' when ap."status" = 'pending' then 'submitted' when ap."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) from (values (1)) d(n) left join "better_supabase"."approval_requests" ap on ap."id" = x."approval_id") = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (lower(x."title"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."title") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EXPENSE_REPORT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'title', x."title", 'currency', x."currency", 'note', x."note", 'status', (case when x."cancelled_at" is not null then 'cancelled' when x."reimbursed_at" is not null then 'reimbursed' when x."approved_at" is not null then 'approved' when ap."status" = 'pending' then 'submitted' when ap."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = x."id"), 0)::text, 'approvalId', x."approval_id", 'submittedAt', x."submitted_at", 'approvedAt', x."approved_at", 'approvalTransactionId', x."approval_transaction_id", 'reimbursedAt', x."reimbursed_at", 'reimbursementTransactionId', x."reimbursement_transaction_id", 'cancelledAt', x."cancelled_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'dimensions', l."dimensions", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', (select count(*) from "better_supabase"."attachments" t where t."subject_type" = 'expense_line' and t."subject_id" = l."id"::text and t."uploaded_at" is not null and t."status" <> 'infected'), 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = x."id")) from (values (1)) d(n) left join "better_supabase"."approval_requests" ap on ap."id" = x."approval_id") as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."expense_reports" x
      where x."tenant_id" = page_expense_reports.tenant
        and ((v_reader and not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false)) or x."user_id" = auth.uid())
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (select (case when x."cancelled_at" is not null then 'cancelled' when x."reimbursed_at" is not null then 'reimbursed' when x."approved_at" is not null then 'approved' when ap."status" = 'pending' then 'submitted' when ap."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) from (values (1)) d(n) left join "better_supabase"."approval_requests" ap on ap."id" = x."approval_id") = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (lower(x."title") <= (v_after ->> 0)::text and ((lower(x."title") < (v_after ->> 0)::text) or (lower(x."title") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."title") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."expense_reports" x
      where x."tenant_id" = page_expense_reports.tenant
        and ((v_reader and not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false)) or x."user_id" = auth.uid())
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (select (case when x."cancelled_at" is not null then 'cancelled' when x."reimbursed_at" is not null then 'reimbursed' when x."approved_at" is not null then 'approved' when ap."status" = 'pending' then 'submitted' when ap."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) from (values (1)) d(n) left join "better_supabase"."approval_requests" ap on ap."id" = x."approval_id") = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or x."title" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_invoices (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_invoices.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
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
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', page_invoices.tenant, 'invoices.read'), false)) then
    raise exception 'not allowed to read this organization''s invoices' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'INVOICE_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'currency') then
      raise exception 'facet is one of status, currency' using errcode = '22023', hint = 'INVOICE_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'currency' then (x."currency")::text end) as v
      from "better_supabase"."invoices" x
      where x."tenant_id" = page_invoices.tenant
        and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.read'), false))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), '') is null or ((x."company_type" = nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '') and x."company_id"::text = nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), '')) or (x."contact_type" = nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '') and x."contact_id"::text = nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), ''))))
        and (v_search is null or x."number"::text ilike v_search)
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
      select 1 from "better_supabase"."invoices" x
      where x."tenant_id" = page_invoices.tenant
        and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.read'), false))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), '') is null or ((x."company_type" = nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '') and x."company_id"::text = nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), '')) or (x."contact_type" = nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '') and x."contact_id"::text = nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), ''))))
        and (v_search is null or x."number"::text ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'dueOn', 'total') then
    raise exception 'sort is one of createdAt, dueOn, total' using errcode = '22023', hint = 'INVOICE_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'INVOICE_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVOICE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'paid_total', x."paid_total"::text, 'credited_total', x."credited_total"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text, 'deposit_amount', x."deposit_amount"::text, 'discount_amount', x."discount_amount"::text, 'discount_amount_early', x."discount_amount_early"::text) || jsonb_build_object(
      'balance', (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), '[]'::jsonb),
      'overdue', x."status" in ('issued', 'partially_paid') and x."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code", 'taxCodeId', il."tax_code_id", 'unitCost', il."unit_cost"::text, 'dimensions', il."dimensions") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = x."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text)), '[]'::jsonb)) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."invoices" x
      where x."tenant_id" = page_invoices.tenant
        and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.read'), false))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), '') is null or ((x."company_type" = nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '') and x."company_id"::text = nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), '')) or (x."contact_type" = nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '') and x."contact_id"::text = nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), ''))))
        and (v_search is null or x."number"::text ilike v_search)
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVOICE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'paid_total', x."paid_total"::text, 'credited_total', x."credited_total"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text, 'deposit_amount', x."deposit_amount"::text, 'discount_amount', x."discount_amount"::text, 'discount_amount_early', x."discount_amount_early"::text) || jsonb_build_object(
      'balance', (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), '[]'::jsonb),
      'overdue', x."status" in ('issued', 'partially_paid') and x."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code", 'taxCodeId', il."tax_code_id", 'unitCost', il."unit_cost"::text, 'dimensions', il."dimensions") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = x."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text)), '[]'::jsonb)) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."invoices" x
      where x."tenant_id" = page_invoices.tenant
        and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.read'), false))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), '') is null or ((x."company_type" = nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '') and x."company_id"::text = nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), '')) or (x."contact_type" = nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '') and x."contact_id"::text = nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), ''))))
        and (v_search is null or x."number"::text ilike v_search)
        and (v_after is null or (x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVOICE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'paid_total', x."paid_total"::text, 'credited_total', x."credited_total"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text, 'deposit_amount', x."deposit_amount"::text, 'discount_amount', x."discount_amount"::text, 'discount_amount_early', x."discount_amount_early"::text) || jsonb_build_object(
      'balance', (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), '[]'::jsonb),
      'overdue', x."status" in ('issued', 'partially_paid') and x."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code", 'taxCodeId', il."tax_code_id", 'unitCost', il."unit_cost"::text, 'dimensions', il."dimensions") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = x."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text)), '[]'::jsonb)) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."invoices" x
      where x."tenant_id" = page_invoices.tenant
        and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.read'), false))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), '') is null or ((x."company_type" = nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '') and x."company_id"::text = nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), '')) or (x."contact_type" = nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '') and x."contact_id"::text = nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), ''))))
        and (v_search is null or x."number"::text ilike v_search)
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVOICE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'paid_total', x."paid_total"::text, 'credited_total', x."credited_total"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text, 'deposit_amount', x."deposit_amount"::text, 'discount_amount', x."discount_amount"::text, 'discount_amount_early', x."discount_amount_early"::text) || jsonb_build_object(
      'balance', (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), '[]'::jsonb),
      'overdue', x."status" in ('issued', 'partially_paid') and x."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code", 'taxCodeId', il."tax_code_id", 'unitCost', il."unit_cost"::text, 'dimensions', il."dimensions") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = x."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text)), '[]'::jsonb)) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."invoices" x
      where x."tenant_id" = page_invoices.tenant
        and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.read'), false))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), '') is null or ((x."company_type" = nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '') and x."company_id"::text = nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), '')) or (x."contact_type" = nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '') and x."contact_id"::text = nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), ''))))
        and (v_search is null or x."number"::text ilike v_search)
        and (v_after is null or (x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'dueOn' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVOICE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'paid_total', x."paid_total"::text, 'credited_total', x."credited_total"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text, 'deposit_amount', x."deposit_amount"::text, 'discount_amount', x."discount_amount"::text, 'discount_amount_early', x."discount_amount_early"::text) || jsonb_build_object(
      'balance', (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), '[]'::jsonb),
      'overdue', x."status" in ('issued', 'partially_paid') and x."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code", 'taxCodeId', il."tax_code_id", 'unitCost', il."unit_cost"::text, 'dimensions', il."dimensions") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = x."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text)), '[]'::jsonb)) as j, jsonb_build_array((coalesce(x."due_on", date '9999-12-31'))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."invoices" x
      where x."tenant_id" = page_invoices.tenant
        and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.read'), false))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), '') is null or ((x."company_type" = nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '') and x."company_id"::text = nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), '')) or (x."contact_type" = nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '') and x."contact_id"::text = nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), ''))))
        and (v_search is null or x."number"::text ilike v_search)
        and (v_after is null or (coalesce(x."due_on", date '9999-12-31') >= (v_after ->> 0)::date and ((coalesce(x."due_on", date '9999-12-31') > (v_after ->> 0)::date) or (coalesce(x."due_on", date '9999-12-31') = (v_after ->> 0)::date and x."id" < (v_after ->> 1)::uuid))))
      order by coalesce(x."due_on", date '9999-12-31') asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'dueOn' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVOICE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'paid_total', x."paid_total"::text, 'credited_total', x."credited_total"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text, 'deposit_amount', x."deposit_amount"::text, 'discount_amount', x."discount_amount"::text, 'discount_amount_early', x."discount_amount_early"::text) || jsonb_build_object(
      'balance', (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), '[]'::jsonb),
      'overdue', x."status" in ('issued', 'partially_paid') and x."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code", 'taxCodeId', il."tax_code_id", 'unitCost', il."unit_cost"::text, 'dimensions', il."dimensions") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = x."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text)), '[]'::jsonb)) as j, jsonb_build_array((coalesce(x."due_on", date '9999-12-31'))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."invoices" x
      where x."tenant_id" = page_invoices.tenant
        and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.read'), false))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), '') is null or ((x."company_type" = nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '') and x."company_id"::text = nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), '')) or (x."contact_type" = nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '') and x."contact_id"::text = nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), ''))))
        and (v_search is null or x."number"::text ilike v_search)
        and (v_after is null or (coalesce(x."due_on", date '9999-12-31'), x."id") < ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by coalesce(x."due_on", date '9999-12-31') desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'total' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVOICE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'paid_total', x."paid_total"::text, 'credited_total', x."credited_total"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text, 'deposit_amount', x."deposit_amount"::text, 'discount_amount', x."discount_amount"::text, 'discount_amount_early', x."discount_amount_early"::text) || jsonb_build_object(
      'balance', (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), '[]'::jsonb),
      'overdue', x."status" in ('issued', 'partially_paid') and x."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code", 'taxCodeId', il."tax_code_id", 'unitCost', il."unit_cost"::text, 'dimensions', il."dimensions") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = x."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text)), '[]'::jsonb)) as j, jsonb_build_array((x."total")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."invoices" x
      where x."tenant_id" = page_invoices.tenant
        and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.read'), false))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), '') is null or ((x."company_type" = nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '') and x."company_id"::text = nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), '')) or (x."contact_type" = nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '') and x."contact_id"::text = nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), ''))))
        and (v_search is null or x."number"::text ilike v_search)
        and (v_after is null or (x."total" >= (v_after ->> 0)::bigint and ((x."total" > (v_after ->> 0)::bigint) or (x."total" = (v_after ->> 0)::bigint and x."id" < (v_after ->> 1)::uuid))))
      order by x."total" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'total' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVOICE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'paid_total', x."paid_total"::text, 'credited_total', x."credited_total"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text, 'deposit_amount', x."deposit_amount"::text, 'discount_amount', x."discount_amount"::text, 'discount_amount_early', x."discount_amount_early"::text) || jsonb_build_object(
      'balance', (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), '[]'::jsonb),
      'overdue', x."status" in ('issued', 'partially_paid') and x."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code", 'taxCodeId', il."tax_code_id", 'unitCost', il."unit_cost"::text, 'dimensions', il."dimensions") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = x."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text)), '[]'::jsonb)) as j, jsonb_build_array((x."total")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."invoices" x
      where x."tenant_id" = page_invoices.tenant
        and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.read'), false))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), '') is null or ((x."company_type" = nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '') and x."company_id"::text = nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), '')) or (x."contact_type" = nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '') and x."contact_id"::text = nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), ''))))
        and (v_search is null or x."number"::text ilike v_search)
        and (v_after is null or (x."total", x."id") < ((v_after ->> 0)::bigint, (v_after ->> 1)::uuid))
      order by x."total" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."invoices" x
      where x."tenant_id" = page_invoices.tenant
        and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.read'), false))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), '') is null or ((x."company_type" = nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '') and x."company_id"::text = nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), '')) or (x."contact_type" = nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '') and x."contact_id"::text = nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), ''))))
        and (v_search is null or x."number"::text ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_payment_batches (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_payment_batches.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (page_payment_batches.tenant is not null and coalesce(better_supabase.can('tenant', page_payment_batches.tenant, 'banking.read'), false))) then
    raise exception 'not allowed to read payment batches' using errcode = '42501', hint = 'BANKING_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'PAYMENT_BATCH_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'currency') then
      raise exception 'facet is one of status, currency' using errcode = '22023', hint = 'PAYMENT_BATCH_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'currency' then (x."currency")::text end) as v
      from "better_supabase"."payment_batches" x
      where x."tenant_id" = page_payment_batches.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'accountId' is not null and jsonb_typeof(v_filters -> 'accountId') <> 'null' and not (jsonb_typeof(v_filters -> 'accountId') = 'array' and jsonb_array_length(v_filters -> 'accountId') = 0)) or x."bank_account_id"::text = any((case when jsonb_typeof(v_filters -> 'accountId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'accountId')) else array[v_filters ->> 'accountId'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or x."reference" ilike v_search or x."message_id" ilike v_search)
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
      select 1 from "better_supabase"."payment_batches" x
      where x."tenant_id" = page_payment_batches.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'accountId' is not null and jsonb_typeof(v_filters -> 'accountId') <> 'null' and not (jsonb_typeof(v_filters -> 'accountId') = 'array' and jsonb_array_length(v_filters -> 'accountId') = 0)) or x."bank_account_id"::text = any((case when jsonb_typeof(v_filters -> 'accountId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'accountId')) else array[v_filters ->> 'accountId'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or x."reference" ilike v_search or x."message_id" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'executionOn') then
    raise exception 'sort is one of createdAt, executionOn' using errcode = '22023', hint = 'PAYMENT_BATCH_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'PAYMENT_BATCH_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PAYMENT_BATCH_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'accountId', x."bank_account_id", 'reference', x."reference", 'messageId', x."message_id", 'currency', x."currency", 'dueBy', x."due_by", 'executionOn', x."execution_on", 'total', x."total"::text, 'itemCount', x."item_count", 'status', x."status", 'transactionId', x."bank_transaction_id", 'createdBy', x."created_by", 'createdAt', x."created_at", 'postedAt', x."posted_at", 'reconciledAt', x."reconciled_at", 'items', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'invoiceId', y."invoice_id", 'partyId', y."party_id", 'creditorName', y."creditor_name", 'creditorIban', y."creditor_iban", 'creditorBic', y."creditor_bic", 'amount', y."amount"::text, 'discount', y."discount"::text, 'currency', y."currency", 'endToEndId', y."end_to_end_id", 'remittance', y."remittance", 'status', y."status") order by y."creditor_name", y."id") from "better_supabase"."payment_batch_items" y where y."batch_id" = x."id"), '[]'::jsonb)) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."payment_batches" x
      where x."tenant_id" = page_payment_batches.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'accountId' is not null and jsonb_typeof(v_filters -> 'accountId') <> 'null' and not (jsonb_typeof(v_filters -> 'accountId') = 'array' and jsonb_array_length(v_filters -> 'accountId') = 0)) or x."bank_account_id"::text = any((case when jsonb_typeof(v_filters -> 'accountId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'accountId')) else array[v_filters ->> 'accountId'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or x."reference" ilike v_search or x."message_id" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PAYMENT_BATCH_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'accountId', x."bank_account_id", 'reference', x."reference", 'messageId', x."message_id", 'currency', x."currency", 'dueBy', x."due_by", 'executionOn', x."execution_on", 'total', x."total"::text, 'itemCount', x."item_count", 'status', x."status", 'transactionId', x."bank_transaction_id", 'createdBy', x."created_by", 'createdAt', x."created_at", 'postedAt', x."posted_at", 'reconciledAt', x."reconciled_at", 'items', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'invoiceId', y."invoice_id", 'partyId', y."party_id", 'creditorName', y."creditor_name", 'creditorIban', y."creditor_iban", 'creditorBic', y."creditor_bic", 'amount', y."amount"::text, 'discount', y."discount"::text, 'currency', y."currency", 'endToEndId', y."end_to_end_id", 'remittance', y."remittance", 'status', y."status") order by y."creditor_name", y."id") from "better_supabase"."payment_batch_items" y where y."batch_id" = x."id"), '[]'::jsonb)) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."payment_batches" x
      where x."tenant_id" = page_payment_batches.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'accountId' is not null and jsonb_typeof(v_filters -> 'accountId') <> 'null' and not (jsonb_typeof(v_filters -> 'accountId') = 'array' and jsonb_array_length(v_filters -> 'accountId') = 0)) or x."bank_account_id"::text = any((case when jsonb_typeof(v_filters -> 'accountId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'accountId')) else array[v_filters ->> 'accountId'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or x."reference" ilike v_search or x."message_id" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PAYMENT_BATCH_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'accountId', x."bank_account_id", 'reference', x."reference", 'messageId', x."message_id", 'currency', x."currency", 'dueBy', x."due_by", 'executionOn', x."execution_on", 'total', x."total"::text, 'itemCount', x."item_count", 'status', x."status", 'transactionId', x."bank_transaction_id", 'createdBy', x."created_by", 'createdAt', x."created_at", 'postedAt', x."posted_at", 'reconciledAt', x."reconciled_at", 'items', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'invoiceId', y."invoice_id", 'partyId', y."party_id", 'creditorName', y."creditor_name", 'creditorIban', y."creditor_iban", 'creditorBic', y."creditor_bic", 'amount', y."amount"::text, 'discount', y."discount"::text, 'currency', y."currency", 'endToEndId', y."end_to_end_id", 'remittance', y."remittance", 'status', y."status") order by y."creditor_name", y."id") from "better_supabase"."payment_batch_items" y where y."batch_id" = x."id"), '[]'::jsonb)) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."payment_batches" x
      where x."tenant_id" = page_payment_batches.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'accountId' is not null and jsonb_typeof(v_filters -> 'accountId') <> 'null' and not (jsonb_typeof(v_filters -> 'accountId') = 'array' and jsonb_array_length(v_filters -> 'accountId') = 0)) or x."bank_account_id"::text = any((case when jsonb_typeof(v_filters -> 'accountId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'accountId')) else array[v_filters ->> 'accountId'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or x."reference" ilike v_search or x."message_id" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PAYMENT_BATCH_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'accountId', x."bank_account_id", 'reference', x."reference", 'messageId', x."message_id", 'currency', x."currency", 'dueBy', x."due_by", 'executionOn', x."execution_on", 'total', x."total"::text, 'itemCount', x."item_count", 'status', x."status", 'transactionId', x."bank_transaction_id", 'createdBy', x."created_by", 'createdAt', x."created_at", 'postedAt', x."posted_at", 'reconciledAt', x."reconciled_at", 'items', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'invoiceId', y."invoice_id", 'partyId', y."party_id", 'creditorName', y."creditor_name", 'creditorIban', y."creditor_iban", 'creditorBic', y."creditor_bic", 'amount', y."amount"::text, 'discount', y."discount"::text, 'currency', y."currency", 'endToEndId', y."end_to_end_id", 'remittance', y."remittance", 'status', y."status") order by y."creditor_name", y."id") from "better_supabase"."payment_batch_items" y where y."batch_id" = x."id"), '[]'::jsonb)) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."payment_batches" x
      where x."tenant_id" = page_payment_batches.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'accountId' is not null and jsonb_typeof(v_filters -> 'accountId') <> 'null' and not (jsonb_typeof(v_filters -> 'accountId') = 'array' and jsonb_array_length(v_filters -> 'accountId') = 0)) or x."bank_account_id"::text = any((case when jsonb_typeof(v_filters -> 'accountId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'accountId')) else array[v_filters ->> 'accountId'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or x."reference" ilike v_search or x."message_id" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'executionOn' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PAYMENT_BATCH_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'accountId', x."bank_account_id", 'reference', x."reference", 'messageId', x."message_id", 'currency', x."currency", 'dueBy', x."due_by", 'executionOn', x."execution_on", 'total', x."total"::text, 'itemCount', x."item_count", 'status', x."status", 'transactionId', x."bank_transaction_id", 'createdBy', x."created_by", 'createdAt', x."created_at", 'postedAt', x."posted_at", 'reconciledAt', x."reconciled_at", 'items', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'invoiceId', y."invoice_id", 'partyId', y."party_id", 'creditorName', y."creditor_name", 'creditorIban', y."creditor_iban", 'creditorBic', y."creditor_bic", 'amount', y."amount"::text, 'discount', y."discount"::text, 'currency', y."currency", 'endToEndId', y."end_to_end_id", 'remittance', y."remittance", 'status', y."status") order by y."creditor_name", y."id") from "better_supabase"."payment_batch_items" y where y."batch_id" = x."id"), '[]'::jsonb)) as j, jsonb_build_array((coalesce(x."execution_on", date '9999-12-31'))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."payment_batches" x
      where x."tenant_id" = page_payment_batches.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'accountId' is not null and jsonb_typeof(v_filters -> 'accountId') <> 'null' and not (jsonb_typeof(v_filters -> 'accountId') = 'array' and jsonb_array_length(v_filters -> 'accountId') = 0)) or x."bank_account_id"::text = any((case when jsonb_typeof(v_filters -> 'accountId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'accountId')) else array[v_filters ->> 'accountId'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or x."reference" ilike v_search or x."message_id" ilike v_search)
        and (v_after is null or (coalesce(x."execution_on", date '9999-12-31'), x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by coalesce(x."execution_on", date '9999-12-31') asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'executionOn' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PAYMENT_BATCH_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'accountId', x."bank_account_id", 'reference', x."reference", 'messageId', x."message_id", 'currency', x."currency", 'dueBy', x."due_by", 'executionOn', x."execution_on", 'total', x."total"::text, 'itemCount', x."item_count", 'status', x."status", 'transactionId', x."bank_transaction_id", 'createdBy', x."created_by", 'createdAt', x."created_at", 'postedAt', x."posted_at", 'reconciledAt', x."reconciled_at", 'items', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'invoiceId', y."invoice_id", 'partyId', y."party_id", 'creditorName', y."creditor_name", 'creditorIban', y."creditor_iban", 'creditorBic', y."creditor_bic", 'amount', y."amount"::text, 'discount', y."discount"::text, 'currency', y."currency", 'endToEndId', y."end_to_end_id", 'remittance', y."remittance", 'status', y."status") order by y."creditor_name", y."id") from "better_supabase"."payment_batch_items" y where y."batch_id" = x."id"), '[]'::jsonb)) as j, jsonb_build_array((coalesce(x."execution_on", date '9999-12-31'))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."payment_batches" x
      where x."tenant_id" = page_payment_batches.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'accountId' is not null and jsonb_typeof(v_filters -> 'accountId') <> 'null' and not (jsonb_typeof(v_filters -> 'accountId') = 'array' and jsonb_array_length(v_filters -> 'accountId') = 0)) or x."bank_account_id"::text = any((case when jsonb_typeof(v_filters -> 'accountId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'accountId')) else array[v_filters ->> 'accountId'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or x."reference" ilike v_search or x."message_id" ilike v_search)
        and (v_after is null or (coalesce(x."execution_on", date '9999-12-31') <= (v_after ->> 0)::date and ((coalesce(x."execution_on", date '9999-12-31') < (v_after ->> 0)::date) or (coalesce(x."execution_on", date '9999-12-31') = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."execution_on", date '9999-12-31') desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."payment_batches" x
      where x."tenant_id" = page_payment_batches.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'accountId' is not null and jsonb_typeof(v_filters -> 'accountId') <> 'null' and not (jsonb_typeof(v_filters -> 'accountId') = 'array' and jsonb_array_length(v_filters -> 'accountId') = 0)) or x."bank_account_id"::text = any((case when jsonb_typeof(v_filters -> 'accountId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'accountId')) else array[v_filters ->> 'accountId'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or x."reference" ilike v_search or x."message_id" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_score_models (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_score_models.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', page_score_models.tenant, 'scores.read'), false)) then
    raise exception 'not allowed to read scores' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('subjectType', 'enabled') then
      raise exception 'facet is one of subjectType, enabled' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
    with s as (
      select (case v_facet when 'subjectType' then (x."subject_type")::text when 'enabled' then (x."enabled"::text)::text end) as v
      from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
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
      select 1 from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'key', 'version') then
    raise exception 'sort is one of name, key, version' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."key")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."key", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."key" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."key")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."key" <= (v_after ->> 0)::text and ((x."key" < (v_after ->> 0)::text) or (x."key" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."key" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'key' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."key")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."key", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."key" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'key' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."key")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."key" <= (v_after ->> 0)::text and ((x."key" < (v_after ->> 0)::text) or (x."key" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."key" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'version' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."version")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."version", x."id") > ((v_after ->> 0)::integer, (v_after ->> 1)::uuid))
      order by x."version" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'version' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."version")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."version" <= (v_after ->> 0)::integer and ((x."version" < (v_after ->> 0)::integer) or (x."version" = (v_after ->> 0)::integer and x."id" > (v_after ->> 1)::uuid))))
      order by x."version" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_time_rates (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_time_rates.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', page_time_rates.tenant, 'billable_time.read'), false)) then
    raise exception 'not allowed to read the rate card' using errcode = '42501', hint = 'BILLABLE_TIME_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'BILLABLE_TIME_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('currency', 'subjectType') then
      raise exception 'facet is one of currency, subjectType' using errcode = '22023', hint = 'BILLABLE_TIME_INVALID';
    end if;
    with s as (
      select (case v_facet when 'currency' then (x."currency")::text when 'subjectType' then (coalesce(x."subject_type", ''))::text end) as v
      from "better_supabase"."time_rates" x
      where x."tenant_id" = page_time_rates.tenant
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or x."subject_id" ilike v_search or x."subject_type" ilike v_search)
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
      select 1 from "better_supabase"."time_rates" x
      where x."tenant_id" = page_time_rates.tenant
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or x."subject_id" ilike v_search or x."subject_type" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('effectiveFrom', 'rate') then
    raise exception 'sort is one of effectiveFrom, rate' using errcode = '22023', hint = 'BILLABLE_TIME_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'BILLABLE_TIME_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'BILLABLE_TIME_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'rate', x."rate"::text, 'currency', x."currency", 'effectiveFrom', x."effective_from", 'cost', x."cost_amount"::text, 'createdBy', x."created_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."effective_from")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."time_rates" x
      where x."tenant_id" = page_time_rates.tenant
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or x."subject_id" ilike v_search or x."subject_type" ilike v_search)
        and (v_after is null or (x."effective_from", x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by x."effective_from" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'BILLABLE_TIME_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'rate', x."rate"::text, 'currency', x."currency", 'effectiveFrom', x."effective_from", 'cost', x."cost_amount"::text, 'createdBy', x."created_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."effective_from")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."time_rates" x
      where x."tenant_id" = page_time_rates.tenant
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or x."subject_id" ilike v_search or x."subject_type" ilike v_search)
        and (v_after is null or (x."effective_from" <= (v_after ->> 0)::date and ((x."effective_from" < (v_after ->> 0)::date) or (x."effective_from" = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by x."effective_from" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'effectiveFrom' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'BILLABLE_TIME_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'rate', x."rate"::text, 'currency', x."currency", 'effectiveFrom', x."effective_from", 'cost', x."cost_amount"::text, 'createdBy', x."created_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."effective_from")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."time_rates" x
      where x."tenant_id" = page_time_rates.tenant
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or x."subject_id" ilike v_search or x."subject_type" ilike v_search)
        and (v_after is null or (x."effective_from", x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by x."effective_from" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'effectiveFrom' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'BILLABLE_TIME_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'rate', x."rate"::text, 'currency', x."currency", 'effectiveFrom', x."effective_from", 'cost', x."cost_amount"::text, 'createdBy', x."created_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."effective_from")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."time_rates" x
      where x."tenant_id" = page_time_rates.tenant
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or x."subject_id" ilike v_search or x."subject_type" ilike v_search)
        and (v_after is null or (x."effective_from" <= (v_after ->> 0)::date and ((x."effective_from" < (v_after ->> 0)::date) or (x."effective_from" = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by x."effective_from" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'rate' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'BILLABLE_TIME_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'rate', x."rate"::text, 'currency', x."currency", 'effectiveFrom', x."effective_from", 'cost', x."cost_amount"::text, 'createdBy', x."created_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."rate")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."time_rates" x
      where x."tenant_id" = page_time_rates.tenant
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or x."subject_id" ilike v_search or x."subject_type" ilike v_search)
        and (v_after is null or (x."rate", x."id") > ((v_after ->> 0)::bigint, (v_after ->> 1)::uuid))
      order by x."rate" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'rate' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'BILLABLE_TIME_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'rate', x."rate"::text, 'currency', x."currency", 'effectiveFrom', x."effective_from", 'cost', x."cost_amount"::text, 'createdBy', x."created_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."rate")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."time_rates" x
      where x."tenant_id" = page_time_rates.tenant
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or x."subject_id" ilike v_search or x."subject_type" ilike v_search)
        and (v_after is null or (x."rate" <= (v_after ->> 0)::bigint and ((x."rate" < (v_after ->> 0)::bigint) or (x."rate" = (v_after ->> 0)::bigint and x."id" > (v_after ->> 1)::uuid))))
      order by x."rate" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."time_rates" x
      where x."tenant_id" = page_time_rates.tenant
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or x."subject_id" ilike v_search or x."subject_type" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

REVOKE ALL ON FUNCTION "api"."get_invoice"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_invoice"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_time_rate"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_time_rate"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_accounting_accounts"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_accounting_accounts"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_accounting_entries"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_accounting_entries"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_bank_accounts"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_bank_accounts"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_expense_categories"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_expense_categories"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_expense_reports"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_expense_reports"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_invoices"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_invoices"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_payment_batches"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_payment_batches"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_score_models"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_score_models"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_time_rates"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_time_rates"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_invoice"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_invoice"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_time_rate"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_time_rate"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_accounting_accounts"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_accounting_accounts"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_accounting_entries"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_accounting_entries"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_bank_accounts"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_bank_accounts"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_expense_categories"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_expense_categories"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_expense_reports"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_expense_reports"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_invoices"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_invoices"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_payment_batches"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_payment_batches"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_score_models"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_score_models"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_time_rates"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_time_rates"(uuid, jsonb) TO "authenticated", "service_role";
