SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.get_deal (
  deal uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_deal"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_pipeline (
  pipeline uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_pipeline"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_quote (
  quote uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_quote"($1) $function$;

CREATE OR REPLACE FUNCTION api.page_companies (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_companies"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_contract_obligations (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_contract_obligations"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_contracts (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_contracts"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_deals (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_deals"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_forecast_snapshots (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_forecast_snapshots"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_mail_accounts (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_mail_accounts"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_mail_threads (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_mail_threads"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_people (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_people"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_pipelines (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_pipelines"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_quotes (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_quotes"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_segments (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_segments"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.get_deal (
  deal uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_row jsonb;
begin
  select to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'amount', x."amount"::text, 'existing_amount', x."existing_amount"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text) || jsonb_build_object(
      'contacts', coalesce((select jsonb_agg(jsonb_build_object('type', ck."contact_type", 'id', ck."contact_id", 'role', ck."role", 'primary', ck."is_primary") order by ck."is_primary" desc, ck."contact_id") from "better_supabase"."deal_contacts" ck where ck."deal_id" = x."id"), '[]'::jsonb),
      'members', coalesce((select jsonb_agg(jsonb_build_object('userId', cm."user_id", 'role', cm."role") order by cm."user_id") from "better_supabase"."deal_members" cm where cm."deal_id" = x."id"), '[]'::jsonb)) into v_row from "better_supabase"."deals" x where x."id" = get_deal.deal;
  if v_row is null then
    raise exception 'no deal you can read has this id' using errcode = 'P0002', hint = 'DEAL_NOT_FOUND';
  end if;
  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_pipeline (
  pipeline uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_row jsonb;
begin
  select to_jsonb(x) || jsonb_build_object('stages', coalesce((
      select jsonb_agg(to_jsonb(st) order by st."rank" collate "C")
      from "better_supabase"."pipeline_stages" st where st."pipeline_id" = x."id" and st."archived_at" is null
    ), '[]'::jsonb)) into v_row from "better_supabase"."pipelines" x
  where x."id" = get_pipeline.pipeline and x."archived_at" is null;
  if v_row is null then
    raise exception 'pipeline not found' using errcode = 'P0002', hint = 'PIPELINE_NOT_FOUND';
  end if;
  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_quote (
  quote uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."quotes";
begin
  select * into v_row from "better_supabase"."quotes" x where x."id" = get_quote.quote;
  if v_row."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'quotes.read'), false)) then
    raise exception 'no quote you can read has this id' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'unit', ql."unit", 'discountKind', ql."discount_kind", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_companies (
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
  v_filters jsonb := coalesce(page_companies.filters, '{}'::jsonb);
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
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'PARTY_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('lifecycle', 'ownerId', 'supplierStatus') then
      raise exception 'facet is one of lifecycle, ownerId, supplierStatus' using errcode = '22023', hint = 'PARTY_INVALID';
    end if;
    with s as (
      select (case v_facet when 'lifecycle' then (x."lifecycle")::text when 'ownerId' then (coalesce(x."owner_id"::text, ''))::text when 'supplierStatus' then (coalesce(x."supplier_status"::text, ''))::text end) as v
      from "better_supabase"."companies" x
      where x."tenant_id" = page_companies.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'lifecycle' is not null and jsonb_typeof(v_filters -> 'lifecycle') <> 'null' and not (jsonb_typeof(v_filters -> 'lifecycle') = 'array' and jsonb_array_length(v_filters -> 'lifecycle') = 0)) or x."lifecycle" = any((case when jsonb_typeof(v_filters -> 'lifecycle') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'lifecycle')) else array[v_filters ->> 'lifecycle'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'role') = 'array' then v_filters -> 'role' else jsonb_build_array(v_filters ->> 'role') end) r where r = any (x."roles")))
        and (not (v_filters -> 'supplierStatus' is not null and jsonb_typeof(v_filters -> 'supplierStatus') <> 'null' and not (jsonb_typeof(v_filters -> 'supplierStatus') = 'array' and jsonb_array_length(v_filters -> 'supplierStatus') = 0)) or x."supplier_status"::text = any((case when jsonb_typeof(v_filters -> 'supplierStatus') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'supplierStatus')) else array[v_filters ->> 'supplierStatus'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."domain" ilike v_search)
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
      select 1 from "better_supabase"."companies" x
      where x."tenant_id" = page_companies.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'lifecycle' is not null and jsonb_typeof(v_filters -> 'lifecycle') <> 'null' and not (jsonb_typeof(v_filters -> 'lifecycle') = 'array' and jsonb_array_length(v_filters -> 'lifecycle') = 0)) or x."lifecycle" = any((case when jsonb_typeof(v_filters -> 'lifecycle') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'lifecycle')) else array[v_filters ->> 'lifecycle'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'role') = 'array' then v_filters -> 'role' else jsonb_build_array(v_filters ->> 'role') end) r where r = any (x."roles")))
        and (not (v_filters -> 'supplierStatus' is not null and jsonb_typeof(v_filters -> 'supplierStatus') <> 'null' and not (jsonb_typeof(v_filters -> 'supplierStatus') = 'array' and jsonb_array_length(v_filters -> 'supplierStatus') = 0)) or x."supplier_status"::text = any((case when jsonb_typeof(v_filters -> 'supplierStatus') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'supplierStatus')) else array[v_filters ->> 'supplierStatus'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."domain" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'createdAt', 'updatedAt') then
    raise exception 'sort is one of name, createdAt, updatedAt' using errcode = '22023', hint = 'PARTY_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'PARTY_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PARTY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('roles', x."roles", 'customer_terms_id', x."customer_terms_id", 'supplier_terms_id', x."supplier_terms_id", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'credit_block', x."credit_block", 'supplier_status', x."supplier_status", 'language', x."language") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."companies" x
      where x."tenant_id" = page_companies.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'lifecycle' is not null and jsonb_typeof(v_filters -> 'lifecycle') <> 'null' and not (jsonb_typeof(v_filters -> 'lifecycle') = 'array' and jsonb_array_length(v_filters -> 'lifecycle') = 0)) or x."lifecycle" = any((case when jsonb_typeof(v_filters -> 'lifecycle') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'lifecycle')) else array[v_filters ->> 'lifecycle'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'role') = 'array' then v_filters -> 'role' else jsonb_build_array(v_filters ->> 'role') end) r where r = any (x."roles")))
        and (not (v_filters -> 'supplierStatus' is not null and jsonb_typeof(v_filters -> 'supplierStatus') <> 'null' and not (jsonb_typeof(v_filters -> 'supplierStatus') = 'array' and jsonb_array_length(v_filters -> 'supplierStatus') = 0)) or x."supplier_status"::text = any((case when jsonb_typeof(v_filters -> 'supplierStatus') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'supplierStatus')) else array[v_filters ->> 'supplierStatus'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."domain" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PARTY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('roles', x."roles", 'customer_terms_id', x."customer_terms_id", 'supplier_terms_id', x."supplier_terms_id", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'credit_block', x."credit_block", 'supplier_status', x."supplier_status", 'language', x."language") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."companies" x
      where x."tenant_id" = page_companies.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'lifecycle' is not null and jsonb_typeof(v_filters -> 'lifecycle') <> 'null' and not (jsonb_typeof(v_filters -> 'lifecycle') = 'array' and jsonb_array_length(v_filters -> 'lifecycle') = 0)) or x."lifecycle" = any((case when jsonb_typeof(v_filters -> 'lifecycle') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'lifecycle')) else array[v_filters ->> 'lifecycle'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'role') = 'array' then v_filters -> 'role' else jsonb_build_array(v_filters ->> 'role') end) r where r = any (x."roles")))
        and (not (v_filters -> 'supplierStatus' is not null and jsonb_typeof(v_filters -> 'supplierStatus') <> 'null' and not (jsonb_typeof(v_filters -> 'supplierStatus') = 'array' and jsonb_array_length(v_filters -> 'supplierStatus') = 0)) or x."supplier_status"::text = any((case when jsonb_typeof(v_filters -> 'supplierStatus') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'supplierStatus')) else array[v_filters ->> 'supplierStatus'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."domain" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PARTY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('roles', x."roles", 'customer_terms_id', x."customer_terms_id", 'supplier_terms_id', x."supplier_terms_id", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'credit_block', x."credit_block", 'supplier_status', x."supplier_status", 'language', x."language") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."companies" x
      where x."tenant_id" = page_companies.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'lifecycle' is not null and jsonb_typeof(v_filters -> 'lifecycle') <> 'null' and not (jsonb_typeof(v_filters -> 'lifecycle') = 'array' and jsonb_array_length(v_filters -> 'lifecycle') = 0)) or x."lifecycle" = any((case when jsonb_typeof(v_filters -> 'lifecycle') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'lifecycle')) else array[v_filters ->> 'lifecycle'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'role') = 'array' then v_filters -> 'role' else jsonb_build_array(v_filters ->> 'role') end) r where r = any (x."roles")))
        and (not (v_filters -> 'supplierStatus' is not null and jsonb_typeof(v_filters -> 'supplierStatus') <> 'null' and not (jsonb_typeof(v_filters -> 'supplierStatus') = 'array' and jsonb_array_length(v_filters -> 'supplierStatus') = 0)) or x."supplier_status"::text = any((case when jsonb_typeof(v_filters -> 'supplierStatus') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'supplierStatus')) else array[v_filters ->> 'supplierStatus'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."domain" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PARTY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('roles', x."roles", 'customer_terms_id', x."customer_terms_id", 'supplier_terms_id', x."supplier_terms_id", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'credit_block', x."credit_block", 'supplier_status', x."supplier_status", 'language', x."language") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."companies" x
      where x."tenant_id" = page_companies.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'lifecycle' is not null and jsonb_typeof(v_filters -> 'lifecycle') <> 'null' and not (jsonb_typeof(v_filters -> 'lifecycle') = 'array' and jsonb_array_length(v_filters -> 'lifecycle') = 0)) or x."lifecycle" = any((case when jsonb_typeof(v_filters -> 'lifecycle') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'lifecycle')) else array[v_filters ->> 'lifecycle'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'role') = 'array' then v_filters -> 'role' else jsonb_build_array(v_filters ->> 'role') end) r where r = any (x."roles")))
        and (not (v_filters -> 'supplierStatus' is not null and jsonb_typeof(v_filters -> 'supplierStatus') <> 'null' and not (jsonb_typeof(v_filters -> 'supplierStatus') = 'array' and jsonb_array_length(v_filters -> 'supplierStatus') = 0)) or x."supplier_status"::text = any((case when jsonb_typeof(v_filters -> 'supplierStatus') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'supplierStatus')) else array[v_filters ->> 'supplierStatus'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."domain" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PARTY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('roles', x."roles", 'customer_terms_id', x."customer_terms_id", 'supplier_terms_id', x."supplier_terms_id", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'credit_block', x."credit_block", 'supplier_status', x."supplier_status", 'language', x."language") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."companies" x
      where x."tenant_id" = page_companies.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'lifecycle' is not null and jsonb_typeof(v_filters -> 'lifecycle') <> 'null' and not (jsonb_typeof(v_filters -> 'lifecycle') = 'array' and jsonb_array_length(v_filters -> 'lifecycle') = 0)) or x."lifecycle" = any((case when jsonb_typeof(v_filters -> 'lifecycle') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'lifecycle')) else array[v_filters ->> 'lifecycle'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'role') = 'array' then v_filters -> 'role' else jsonb_build_array(v_filters ->> 'role') end) r where r = any (x."roles")))
        and (not (v_filters -> 'supplierStatus' is not null and jsonb_typeof(v_filters -> 'supplierStatus') <> 'null' and not (jsonb_typeof(v_filters -> 'supplierStatus') = 'array' and jsonb_array_length(v_filters -> 'supplierStatus') = 0)) or x."supplier_status"::text = any((case when jsonb_typeof(v_filters -> 'supplierStatus') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'supplierStatus')) else array[v_filters ->> 'supplierStatus'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."domain" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PARTY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('roles', x."roles", 'customer_terms_id', x."customer_terms_id", 'supplier_terms_id', x."supplier_terms_id", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'credit_block', x."credit_block", 'supplier_status', x."supplier_status", 'language', x."language") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."companies" x
      where x."tenant_id" = page_companies.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'lifecycle' is not null and jsonb_typeof(v_filters -> 'lifecycle') <> 'null' and not (jsonb_typeof(v_filters -> 'lifecycle') = 'array' and jsonb_array_length(v_filters -> 'lifecycle') = 0)) or x."lifecycle" = any((case when jsonb_typeof(v_filters -> 'lifecycle') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'lifecycle')) else array[v_filters ->> 'lifecycle'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'role') = 'array' then v_filters -> 'role' else jsonb_build_array(v_filters ->> 'role') end) r where r = any (x."roles")))
        and (not (v_filters -> 'supplierStatus' is not null and jsonb_typeof(v_filters -> 'supplierStatus') <> 'null' and not (jsonb_typeof(v_filters -> 'supplierStatus') = 'array' and jsonb_array_length(v_filters -> 'supplierStatus') = 0)) or x."supplier_status"::text = any((case when jsonb_typeof(v_filters -> 'supplierStatus') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'supplierStatus')) else array[v_filters ->> 'supplierStatus'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."domain" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PARTY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('roles', x."roles", 'customer_terms_id', x."customer_terms_id", 'supplier_terms_id', x."supplier_terms_id", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'credit_block', x."credit_block", 'supplier_status', x."supplier_status", 'language', x."language") as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."companies" x
      where x."tenant_id" = page_companies.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'lifecycle' is not null and jsonb_typeof(v_filters -> 'lifecycle') <> 'null' and not (jsonb_typeof(v_filters -> 'lifecycle') = 'array' and jsonb_array_length(v_filters -> 'lifecycle') = 0)) or x."lifecycle" = any((case when jsonb_typeof(v_filters -> 'lifecycle') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'lifecycle')) else array[v_filters ->> 'lifecycle'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'role') = 'array' then v_filters -> 'role' else jsonb_build_array(v_filters ->> 'role') end) r where r = any (x."roles")))
        and (not (v_filters -> 'supplierStatus' is not null and jsonb_typeof(v_filters -> 'supplierStatus') <> 'null' and not (jsonb_typeof(v_filters -> 'supplierStatus') = 'array' and jsonb_array_length(v_filters -> 'supplierStatus') = 0)) or x."supplier_status"::text = any((case when jsonb_typeof(v_filters -> 'supplierStatus') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'supplierStatus')) else array[v_filters ->> 'supplierStatus'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."domain" ilike v_search)
        and (v_after is null or (x."updated_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."updated_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PARTY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('roles', x."roles", 'customer_terms_id', x."customer_terms_id", 'supplier_terms_id', x."supplier_terms_id", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'credit_block', x."credit_block", 'supplier_status', x."supplier_status", 'language', x."language") as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."companies" x
      where x."tenant_id" = page_companies.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'lifecycle' is not null and jsonb_typeof(v_filters -> 'lifecycle') <> 'null' and not (jsonb_typeof(v_filters -> 'lifecycle') = 'array' and jsonb_array_length(v_filters -> 'lifecycle') = 0)) or x."lifecycle" = any((case when jsonb_typeof(v_filters -> 'lifecycle') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'lifecycle')) else array[v_filters ->> 'lifecycle'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'role') = 'array' then v_filters -> 'role' else jsonb_build_array(v_filters ->> 'role') end) r where r = any (x."roles")))
        and (not (v_filters -> 'supplierStatus' is not null and jsonb_typeof(v_filters -> 'supplierStatus') <> 'null' and not (jsonb_typeof(v_filters -> 'supplierStatus') = 'array' and jsonb_array_length(v_filters -> 'supplierStatus') = 0)) or x."supplier_status"::text = any((case when jsonb_typeof(v_filters -> 'supplierStatus') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'supplierStatus')) else array[v_filters ->> 'supplierStatus'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."domain" ilike v_search)
        and (v_after is null or (x."updated_at" <= (v_after ->> 0)::timestamptz and ((x."updated_at" < (v_after ->> 0)::timestamptz) or (x."updated_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."updated_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."companies" x
      where x."tenant_id" = page_companies.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'lifecycle' is not null and jsonb_typeof(v_filters -> 'lifecycle') <> 'null' and not (jsonb_typeof(v_filters -> 'lifecycle') = 'array' and jsonb_array_length(v_filters -> 'lifecycle') = 0)) or x."lifecycle" = any((case when jsonb_typeof(v_filters -> 'lifecycle') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'lifecycle')) else array[v_filters ->> 'lifecycle'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'role') = 'array' then v_filters -> 'role' else jsonb_build_array(v_filters ->> 'role') end) r where r = any (x."roles")))
        and (not (v_filters -> 'supplierStatus' is not null and jsonb_typeof(v_filters -> 'supplierStatus') <> 'null' and not (jsonb_typeof(v_filters -> 'supplierStatus') = 'array' and jsonb_array_length(v_filters -> 'supplierStatus') = 0)) or x."supplier_status"::text = any((case when jsonb_typeof(v_filters -> 'supplierStatus') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'supplierStatus')) else array[v_filters ->> 'supplierStatus'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."domain" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_contract_obligations (
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
  v_filters jsonb := coalesce(page_contract_obligations.filters, '{}'::jsonb);
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
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'contractId') then
      raise exception 'facet is one of status, contractId' using errcode = '22023', hint = 'CONTRACT_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'contractId' then (x."contract_id"::text)::text end) as v
      from "better_supabase"."contract_obligations" x
      where x."tenant_id" = page_contract_obligations.tenant
        and (not (v_filters -> 'contractId' is not null and jsonb_typeof(v_filters -> 'contractId') <> 'null' and not (jsonb_typeof(v_filters -> 'contractId') = 'array' and jsonb_array_length(v_filters -> 'contractId') = 0)) or x."contract_id" = any((case when jsonb_typeof(v_filters -> 'contractId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'contractId')) else array[v_filters ->> 'contractId'] end)::uuid[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'dueBefore' is not null and jsonb_typeof(v_filters -> 'dueBefore') <> 'null' and not (jsonb_typeof(v_filters -> 'dueBefore') = 'array' and jsonb_array_length(v_filters -> 'dueBefore') = 0)) or x."due_on" <= (v_filters ->> 'dueBefore')::date)
        and (v_search is null or x."title" ilike v_search or x."description" ilike v_search)
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
      select 1 from "better_supabase"."contract_obligations" x
      where x."tenant_id" = page_contract_obligations.tenant
        and (not (v_filters -> 'contractId' is not null and jsonb_typeof(v_filters -> 'contractId') <> 'null' and not (jsonb_typeof(v_filters -> 'contractId') = 'array' and jsonb_array_length(v_filters -> 'contractId') = 0)) or x."contract_id" = any((case when jsonb_typeof(v_filters -> 'contractId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'contractId')) else array[v_filters ->> 'contractId'] end)::uuid[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'dueBefore' is not null and jsonb_typeof(v_filters -> 'dueBefore') <> 'null' and not (jsonb_typeof(v_filters -> 'dueBefore') = 'array' and jsonb_array_length(v_filters -> 'dueBefore') = 0)) or x."due_on" <= (v_filters ->> 'dueBefore')::date)
        and (v_search is null or x."title" ilike v_search or x."description" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('dueOn', 'createdAt') then
    raise exception 'sort is one of dueOn, createdAt' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'contractId', x."contract_id", 'title', x."title", 'description', x."description", 'dueOn', x."due_on", 'ownerId', x."owner_id", 'status', x."status", 'overdue', (x."status" = 'open' and x."due_on" < current_date), 'completedAt', x."completed_at", 'completedBy', x."completed_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."due_on", date '9999-12-31'))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."contract_obligations" x
      where x."tenant_id" = page_contract_obligations.tenant
        and (not (v_filters -> 'contractId' is not null and jsonb_typeof(v_filters -> 'contractId') <> 'null' and not (jsonb_typeof(v_filters -> 'contractId') = 'array' and jsonb_array_length(v_filters -> 'contractId') = 0)) or x."contract_id" = any((case when jsonb_typeof(v_filters -> 'contractId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'contractId')) else array[v_filters ->> 'contractId'] end)::uuid[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'dueBefore' is not null and jsonb_typeof(v_filters -> 'dueBefore') <> 'null' and not (jsonb_typeof(v_filters -> 'dueBefore') = 'array' and jsonb_array_length(v_filters -> 'dueBefore') = 0)) or x."due_on" <= (v_filters ->> 'dueBefore')::date)
        and (v_search is null or x."title" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (coalesce(x."due_on", date '9999-12-31'), x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by coalesce(x."due_on", date '9999-12-31') asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'contractId', x."contract_id", 'title', x."title", 'description', x."description", 'dueOn', x."due_on", 'ownerId', x."owner_id", 'status', x."status", 'overdue', (x."status" = 'open' and x."due_on" < current_date), 'completedAt', x."completed_at", 'completedBy', x."completed_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."due_on", date '9999-12-31'))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."contract_obligations" x
      where x."tenant_id" = page_contract_obligations.tenant
        and (not (v_filters -> 'contractId' is not null and jsonb_typeof(v_filters -> 'contractId') <> 'null' and not (jsonb_typeof(v_filters -> 'contractId') = 'array' and jsonb_array_length(v_filters -> 'contractId') = 0)) or x."contract_id" = any((case when jsonb_typeof(v_filters -> 'contractId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'contractId')) else array[v_filters ->> 'contractId'] end)::uuid[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'dueBefore' is not null and jsonb_typeof(v_filters -> 'dueBefore') <> 'null' and not (jsonb_typeof(v_filters -> 'dueBefore') = 'array' and jsonb_array_length(v_filters -> 'dueBefore') = 0)) or x."due_on" <= (v_filters ->> 'dueBefore')::date)
        and (v_search is null or x."title" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (coalesce(x."due_on", date '9999-12-31') <= (v_after ->> 0)::date and ((coalesce(x."due_on", date '9999-12-31') < (v_after ->> 0)::date) or (coalesce(x."due_on", date '9999-12-31') = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."due_on", date '9999-12-31') desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'dueOn' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'contractId', x."contract_id", 'title', x."title", 'description', x."description", 'dueOn', x."due_on", 'ownerId', x."owner_id", 'status', x."status", 'overdue', (x."status" = 'open' and x."due_on" < current_date), 'completedAt', x."completed_at", 'completedBy', x."completed_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."due_on", date '9999-12-31'))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."contract_obligations" x
      where x."tenant_id" = page_contract_obligations.tenant
        and (not (v_filters -> 'contractId' is not null and jsonb_typeof(v_filters -> 'contractId') <> 'null' and not (jsonb_typeof(v_filters -> 'contractId') = 'array' and jsonb_array_length(v_filters -> 'contractId') = 0)) or x."contract_id" = any((case when jsonb_typeof(v_filters -> 'contractId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'contractId')) else array[v_filters ->> 'contractId'] end)::uuid[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'dueBefore' is not null and jsonb_typeof(v_filters -> 'dueBefore') <> 'null' and not (jsonb_typeof(v_filters -> 'dueBefore') = 'array' and jsonb_array_length(v_filters -> 'dueBefore') = 0)) or x."due_on" <= (v_filters ->> 'dueBefore')::date)
        and (v_search is null or x."title" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (coalesce(x."due_on", date '9999-12-31'), x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by coalesce(x."due_on", date '9999-12-31') asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'dueOn' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'contractId', x."contract_id", 'title', x."title", 'description', x."description", 'dueOn', x."due_on", 'ownerId', x."owner_id", 'status', x."status", 'overdue', (x."status" = 'open' and x."due_on" < current_date), 'completedAt', x."completed_at", 'completedBy', x."completed_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."due_on", date '9999-12-31'))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."contract_obligations" x
      where x."tenant_id" = page_contract_obligations.tenant
        and (not (v_filters -> 'contractId' is not null and jsonb_typeof(v_filters -> 'contractId') <> 'null' and not (jsonb_typeof(v_filters -> 'contractId') = 'array' and jsonb_array_length(v_filters -> 'contractId') = 0)) or x."contract_id" = any((case when jsonb_typeof(v_filters -> 'contractId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'contractId')) else array[v_filters ->> 'contractId'] end)::uuid[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'dueBefore' is not null and jsonb_typeof(v_filters -> 'dueBefore') <> 'null' and not (jsonb_typeof(v_filters -> 'dueBefore') = 'array' and jsonb_array_length(v_filters -> 'dueBefore') = 0)) or x."due_on" <= (v_filters ->> 'dueBefore')::date)
        and (v_search is null or x."title" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (coalesce(x."due_on", date '9999-12-31') <= (v_after ->> 0)::date and ((coalesce(x."due_on", date '9999-12-31') < (v_after ->> 0)::date) or (coalesce(x."due_on", date '9999-12-31') = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."due_on", date '9999-12-31') desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'contractId', x."contract_id", 'title', x."title", 'description', x."description", 'dueOn', x."due_on", 'ownerId', x."owner_id", 'status', x."status", 'overdue', (x."status" = 'open' and x."due_on" < current_date), 'completedAt', x."completed_at", 'completedBy', x."completed_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."contract_obligations" x
      where x."tenant_id" = page_contract_obligations.tenant
        and (not (v_filters -> 'contractId' is not null and jsonb_typeof(v_filters -> 'contractId') <> 'null' and not (jsonb_typeof(v_filters -> 'contractId') = 'array' and jsonb_array_length(v_filters -> 'contractId') = 0)) or x."contract_id" = any((case when jsonb_typeof(v_filters -> 'contractId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'contractId')) else array[v_filters ->> 'contractId'] end)::uuid[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'dueBefore' is not null and jsonb_typeof(v_filters -> 'dueBefore') <> 'null' and not (jsonb_typeof(v_filters -> 'dueBefore') = 'array' and jsonb_array_length(v_filters -> 'dueBefore') = 0)) or x."due_on" <= (v_filters ->> 'dueBefore')::date)
        and (v_search is null or x."title" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'contractId', x."contract_id", 'title', x."title", 'description', x."description", 'dueOn', x."due_on", 'ownerId', x."owner_id", 'status', x."status", 'overdue', (x."status" = 'open' and x."due_on" < current_date), 'completedAt', x."completed_at", 'completedBy', x."completed_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."contract_obligations" x
      where x."tenant_id" = page_contract_obligations.tenant
        and (not (v_filters -> 'contractId' is not null and jsonb_typeof(v_filters -> 'contractId') <> 'null' and not (jsonb_typeof(v_filters -> 'contractId') = 'array' and jsonb_array_length(v_filters -> 'contractId') = 0)) or x."contract_id" = any((case when jsonb_typeof(v_filters -> 'contractId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'contractId')) else array[v_filters ->> 'contractId'] end)::uuid[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'dueBefore' is not null and jsonb_typeof(v_filters -> 'dueBefore') <> 'null' and not (jsonb_typeof(v_filters -> 'dueBefore') = 'array' and jsonb_array_length(v_filters -> 'dueBefore') = 0)) or x."due_on" <= (v_filters ->> 'dueBefore')::date)
        and (v_search is null or x."title" ilike v_search or x."description" ilike v_search)
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
      select 1 from "better_supabase"."contract_obligations" x
      where x."tenant_id" = page_contract_obligations.tenant
        and (not (v_filters -> 'contractId' is not null and jsonb_typeof(v_filters -> 'contractId') <> 'null' and not (jsonb_typeof(v_filters -> 'contractId') = 'array' and jsonb_array_length(v_filters -> 'contractId') = 0)) or x."contract_id" = any((case when jsonb_typeof(v_filters -> 'contractId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'contractId')) else array[v_filters ->> 'contractId'] end)::uuid[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'dueBefore' is not null and jsonb_typeof(v_filters -> 'dueBefore') <> 'null' and not (jsonb_typeof(v_filters -> 'dueBefore') = 'array' and jsonb_array_length(v_filters -> 'dueBefore') = 0)) or x."due_on" <= (v_filters ->> 'dueBefore')::date)
        and (v_search is null or x."title" ilike v_search or x."description" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_contracts (
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
  v_filters jsonb := coalesce(page_contracts.filters, '{}'::jsonb);
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
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'ownerId') then
      raise exception 'facet is one of status, ownerId' using errcode = '22023', hint = 'CONTRACT_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'ownerId' then (coalesce(x."owner_id"::text, ''))::text end) as v
      from "better_supabase"."contracts" x
      where x."tenant_id" = page_contracts.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'counterpartyType' is not null and jsonb_typeof(v_filters -> 'counterpartyType') <> 'null' and not (jsonb_typeof(v_filters -> 'counterpartyType') = 'array' and jsonb_array_length(v_filters -> 'counterpartyType') = 0)) or x."counterparty_type" = any((case when jsonb_typeof(v_filters -> 'counterpartyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'counterpartyType')) else array[v_filters ->> 'counterpartyType'] end)::text[]))
        and (not (v_filters -> 'counterpartyId' is not null and jsonb_typeof(v_filters -> 'counterpartyId') <> 'null' and not (jsonb_typeof(v_filters -> 'counterpartyId') = 'array' and jsonb_array_length(v_filters -> 'counterpartyId') = 0)) or x."counterparty_id" = any((case when jsonb_typeof(v_filters -> 'counterpartyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'counterpartyId')) else array[v_filters ->> 'counterpartyId'] end)::text[]))
        and (not (v_filters -> 'renewingBefore' is not null and jsonb_typeof(v_filters -> 'renewingBefore') <> 'null' and not (jsonb_typeof(v_filters -> 'renewingBefore') = 'array' and jsonb_array_length(v_filters -> 'renewingBefore') = 0)) or (x."status" = 'active' and case when x."ends_on" is null then null else x."ends_on" - x."notice_days" end <= (v_filters ->> 'renewingBefore')::date))
        and (v_search is null or x."title" ilike v_search or x."description" ilike v_search)
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
      select 1 from "better_supabase"."contracts" x
      where x."tenant_id" = page_contracts.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'counterpartyType' is not null and jsonb_typeof(v_filters -> 'counterpartyType') <> 'null' and not (jsonb_typeof(v_filters -> 'counterpartyType') = 'array' and jsonb_array_length(v_filters -> 'counterpartyType') = 0)) or x."counterparty_type" = any((case when jsonb_typeof(v_filters -> 'counterpartyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'counterpartyType')) else array[v_filters ->> 'counterpartyType'] end)::text[]))
        and (not (v_filters -> 'counterpartyId' is not null and jsonb_typeof(v_filters -> 'counterpartyId') <> 'null' and not (jsonb_typeof(v_filters -> 'counterpartyId') = 'array' and jsonb_array_length(v_filters -> 'counterpartyId') = 0)) or x."counterparty_id" = any((case when jsonb_typeof(v_filters -> 'counterpartyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'counterpartyId')) else array[v_filters ->> 'counterpartyId'] end)::text[]))
        and (not (v_filters -> 'renewingBefore' is not null and jsonb_typeof(v_filters -> 'renewingBefore') <> 'null' and not (jsonb_typeof(v_filters -> 'renewingBefore') = 'array' and jsonb_array_length(v_filters -> 'renewingBefore') = 0)) or (x."status" = 'active' and case when x."ends_on" is null then null else x."ends_on" - x."notice_days" end <= (v_filters ->> 'renewingBefore')::date))
        and (v_search is null or x."title" ilike v_search or x."description" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'endsOn', 'startsOn', 'title') then
    raise exception 'sort is one of createdAt, endsOn, startsOn, title' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'title', x."title", 'description', x."description", 'counterpartyType', x."counterparty_type", 'counterpartyId', x."counterparty_id", 'ownerId', x."owner_id", 'status', x."status", 'value', x."value"::text, 'currency', x."currency", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'autoRenew', x."auto_renew", 'renewalMonths', x."renewal_months", 'noticeDays', x."notice_days", 'noticeDeadline', case when x."ends_on" is null then null else x."ends_on" - x."notice_days" end, 'renewedCount', x."renewed_count", 'signatureRequestId', x."signature_request_id", 'signedAt', x."signed_at", 'terminatedAt', x."terminated_at", 'terminationReason', x."termination_reason", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."contracts" x
      where x."tenant_id" = page_contracts.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'counterpartyType' is not null and jsonb_typeof(v_filters -> 'counterpartyType') <> 'null' and not (jsonb_typeof(v_filters -> 'counterpartyType') = 'array' and jsonb_array_length(v_filters -> 'counterpartyType') = 0)) or x."counterparty_type" = any((case when jsonb_typeof(v_filters -> 'counterpartyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'counterpartyType')) else array[v_filters ->> 'counterpartyType'] end)::text[]))
        and (not (v_filters -> 'counterpartyId' is not null and jsonb_typeof(v_filters -> 'counterpartyId') <> 'null' and not (jsonb_typeof(v_filters -> 'counterpartyId') = 'array' and jsonb_array_length(v_filters -> 'counterpartyId') = 0)) or x."counterparty_id" = any((case when jsonb_typeof(v_filters -> 'counterpartyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'counterpartyId')) else array[v_filters ->> 'counterpartyId'] end)::text[]))
        and (not (v_filters -> 'renewingBefore' is not null and jsonb_typeof(v_filters -> 'renewingBefore') <> 'null' and not (jsonb_typeof(v_filters -> 'renewingBefore') = 'array' and jsonb_array_length(v_filters -> 'renewingBefore') = 0)) or (x."status" = 'active' and case when x."ends_on" is null then null else x."ends_on" - x."notice_days" end <= (v_filters ->> 'renewingBefore')::date))
        and (v_search is null or x."title" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'title', x."title", 'description', x."description", 'counterpartyType', x."counterparty_type", 'counterpartyId', x."counterparty_id", 'ownerId', x."owner_id", 'status', x."status", 'value', x."value"::text, 'currency', x."currency", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'autoRenew', x."auto_renew", 'renewalMonths', x."renewal_months", 'noticeDays', x."notice_days", 'noticeDeadline', case when x."ends_on" is null then null else x."ends_on" - x."notice_days" end, 'renewedCount', x."renewed_count", 'signatureRequestId', x."signature_request_id", 'signedAt', x."signed_at", 'terminatedAt', x."terminated_at", 'terminationReason', x."termination_reason", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."contracts" x
      where x."tenant_id" = page_contracts.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'counterpartyType' is not null and jsonb_typeof(v_filters -> 'counterpartyType') <> 'null' and not (jsonb_typeof(v_filters -> 'counterpartyType') = 'array' and jsonb_array_length(v_filters -> 'counterpartyType') = 0)) or x."counterparty_type" = any((case when jsonb_typeof(v_filters -> 'counterpartyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'counterpartyType')) else array[v_filters ->> 'counterpartyType'] end)::text[]))
        and (not (v_filters -> 'counterpartyId' is not null and jsonb_typeof(v_filters -> 'counterpartyId') <> 'null' and not (jsonb_typeof(v_filters -> 'counterpartyId') = 'array' and jsonb_array_length(v_filters -> 'counterpartyId') = 0)) or x."counterparty_id" = any((case when jsonb_typeof(v_filters -> 'counterpartyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'counterpartyId')) else array[v_filters ->> 'counterpartyId'] end)::text[]))
        and (not (v_filters -> 'renewingBefore' is not null and jsonb_typeof(v_filters -> 'renewingBefore') <> 'null' and not (jsonb_typeof(v_filters -> 'renewingBefore') = 'array' and jsonb_array_length(v_filters -> 'renewingBefore') = 0)) or (x."status" = 'active' and case when x."ends_on" is null then null else x."ends_on" - x."notice_days" end <= (v_filters ->> 'renewingBefore')::date))
        and (v_search is null or x."title" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'title', x."title", 'description', x."description", 'counterpartyType', x."counterparty_type", 'counterpartyId', x."counterparty_id", 'ownerId', x."owner_id", 'status', x."status", 'value', x."value"::text, 'currency', x."currency", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'autoRenew', x."auto_renew", 'renewalMonths', x."renewal_months", 'noticeDays', x."notice_days", 'noticeDeadline', case when x."ends_on" is null then null else x."ends_on" - x."notice_days" end, 'renewedCount', x."renewed_count", 'signatureRequestId', x."signature_request_id", 'signedAt', x."signed_at", 'terminatedAt', x."terminated_at", 'terminationReason', x."termination_reason", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."contracts" x
      where x."tenant_id" = page_contracts.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'counterpartyType' is not null and jsonb_typeof(v_filters -> 'counterpartyType') <> 'null' and not (jsonb_typeof(v_filters -> 'counterpartyType') = 'array' and jsonb_array_length(v_filters -> 'counterpartyType') = 0)) or x."counterparty_type" = any((case when jsonb_typeof(v_filters -> 'counterpartyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'counterpartyType')) else array[v_filters ->> 'counterpartyType'] end)::text[]))
        and (not (v_filters -> 'counterpartyId' is not null and jsonb_typeof(v_filters -> 'counterpartyId') <> 'null' and not (jsonb_typeof(v_filters -> 'counterpartyId') = 'array' and jsonb_array_length(v_filters -> 'counterpartyId') = 0)) or x."counterparty_id" = any((case when jsonb_typeof(v_filters -> 'counterpartyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'counterpartyId')) else array[v_filters ->> 'counterpartyId'] end)::text[]))
        and (not (v_filters -> 'renewingBefore' is not null and jsonb_typeof(v_filters -> 'renewingBefore') <> 'null' and not (jsonb_typeof(v_filters -> 'renewingBefore') = 'array' and jsonb_array_length(v_filters -> 'renewingBefore') = 0)) or (x."status" = 'active' and case when x."ends_on" is null then null else x."ends_on" - x."notice_days" end <= (v_filters ->> 'renewingBefore')::date))
        and (v_search is null or x."title" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'title', x."title", 'description', x."description", 'counterpartyType', x."counterparty_type", 'counterpartyId', x."counterparty_id", 'ownerId', x."owner_id", 'status', x."status", 'value', x."value"::text, 'currency', x."currency", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'autoRenew', x."auto_renew", 'renewalMonths', x."renewal_months", 'noticeDays', x."notice_days", 'noticeDeadline', case when x."ends_on" is null then null else x."ends_on" - x."notice_days" end, 'renewedCount', x."renewed_count", 'signatureRequestId', x."signature_request_id", 'signedAt', x."signed_at", 'terminatedAt', x."terminated_at", 'terminationReason', x."termination_reason", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."contracts" x
      where x."tenant_id" = page_contracts.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'counterpartyType' is not null and jsonb_typeof(v_filters -> 'counterpartyType') <> 'null' and not (jsonb_typeof(v_filters -> 'counterpartyType') = 'array' and jsonb_array_length(v_filters -> 'counterpartyType') = 0)) or x."counterparty_type" = any((case when jsonb_typeof(v_filters -> 'counterpartyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'counterpartyType')) else array[v_filters ->> 'counterpartyType'] end)::text[]))
        and (not (v_filters -> 'counterpartyId' is not null and jsonb_typeof(v_filters -> 'counterpartyId') <> 'null' and not (jsonb_typeof(v_filters -> 'counterpartyId') = 'array' and jsonb_array_length(v_filters -> 'counterpartyId') = 0)) or x."counterparty_id" = any((case when jsonb_typeof(v_filters -> 'counterpartyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'counterpartyId')) else array[v_filters ->> 'counterpartyId'] end)::text[]))
        and (not (v_filters -> 'renewingBefore' is not null and jsonb_typeof(v_filters -> 'renewingBefore') <> 'null' and not (jsonb_typeof(v_filters -> 'renewingBefore') = 'array' and jsonb_array_length(v_filters -> 'renewingBefore') = 0)) or (x."status" = 'active' and case when x."ends_on" is null then null else x."ends_on" - x."notice_days" end <= (v_filters ->> 'renewingBefore')::date))
        and (v_search is null or x."title" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'endsOn' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'title', x."title", 'description', x."description", 'counterpartyType', x."counterparty_type", 'counterpartyId', x."counterparty_id", 'ownerId', x."owner_id", 'status', x."status", 'value', x."value"::text, 'currency', x."currency", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'autoRenew', x."auto_renew", 'renewalMonths', x."renewal_months", 'noticeDays', x."notice_days", 'noticeDeadline', case when x."ends_on" is null then null else x."ends_on" - x."notice_days" end, 'renewedCount', x."renewed_count", 'signatureRequestId', x."signature_request_id", 'signedAt', x."signed_at", 'terminatedAt', x."terminated_at", 'terminationReason', x."termination_reason", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."ends_on", date '9999-12-31'))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."contracts" x
      where x."tenant_id" = page_contracts.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'counterpartyType' is not null and jsonb_typeof(v_filters -> 'counterpartyType') <> 'null' and not (jsonb_typeof(v_filters -> 'counterpartyType') = 'array' and jsonb_array_length(v_filters -> 'counterpartyType') = 0)) or x."counterparty_type" = any((case when jsonb_typeof(v_filters -> 'counterpartyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'counterpartyType')) else array[v_filters ->> 'counterpartyType'] end)::text[]))
        and (not (v_filters -> 'counterpartyId' is not null and jsonb_typeof(v_filters -> 'counterpartyId') <> 'null' and not (jsonb_typeof(v_filters -> 'counterpartyId') = 'array' and jsonb_array_length(v_filters -> 'counterpartyId') = 0)) or x."counterparty_id" = any((case when jsonb_typeof(v_filters -> 'counterpartyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'counterpartyId')) else array[v_filters ->> 'counterpartyId'] end)::text[]))
        and (not (v_filters -> 'renewingBefore' is not null and jsonb_typeof(v_filters -> 'renewingBefore') <> 'null' and not (jsonb_typeof(v_filters -> 'renewingBefore') = 'array' and jsonb_array_length(v_filters -> 'renewingBefore') = 0)) or (x."status" = 'active' and case when x."ends_on" is null then null else x."ends_on" - x."notice_days" end <= (v_filters ->> 'renewingBefore')::date))
        and (v_search is null or x."title" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (coalesce(x."ends_on", date '9999-12-31'), x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by coalesce(x."ends_on", date '9999-12-31') asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'endsOn' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'title', x."title", 'description', x."description", 'counterpartyType', x."counterparty_type", 'counterpartyId', x."counterparty_id", 'ownerId', x."owner_id", 'status', x."status", 'value', x."value"::text, 'currency', x."currency", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'autoRenew', x."auto_renew", 'renewalMonths', x."renewal_months", 'noticeDays', x."notice_days", 'noticeDeadline', case when x."ends_on" is null then null else x."ends_on" - x."notice_days" end, 'renewedCount', x."renewed_count", 'signatureRequestId', x."signature_request_id", 'signedAt', x."signed_at", 'terminatedAt', x."terminated_at", 'terminationReason', x."termination_reason", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."ends_on", date '9999-12-31'))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."contracts" x
      where x."tenant_id" = page_contracts.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'counterpartyType' is not null and jsonb_typeof(v_filters -> 'counterpartyType') <> 'null' and not (jsonb_typeof(v_filters -> 'counterpartyType') = 'array' and jsonb_array_length(v_filters -> 'counterpartyType') = 0)) or x."counterparty_type" = any((case when jsonb_typeof(v_filters -> 'counterpartyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'counterpartyType')) else array[v_filters ->> 'counterpartyType'] end)::text[]))
        and (not (v_filters -> 'counterpartyId' is not null and jsonb_typeof(v_filters -> 'counterpartyId') <> 'null' and not (jsonb_typeof(v_filters -> 'counterpartyId') = 'array' and jsonb_array_length(v_filters -> 'counterpartyId') = 0)) or x."counterparty_id" = any((case when jsonb_typeof(v_filters -> 'counterpartyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'counterpartyId')) else array[v_filters ->> 'counterpartyId'] end)::text[]))
        and (not (v_filters -> 'renewingBefore' is not null and jsonb_typeof(v_filters -> 'renewingBefore') <> 'null' and not (jsonb_typeof(v_filters -> 'renewingBefore') = 'array' and jsonb_array_length(v_filters -> 'renewingBefore') = 0)) or (x."status" = 'active' and case when x."ends_on" is null then null else x."ends_on" - x."notice_days" end <= (v_filters ->> 'renewingBefore')::date))
        and (v_search is null or x."title" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (coalesce(x."ends_on", date '9999-12-31') <= (v_after ->> 0)::date and ((coalesce(x."ends_on", date '9999-12-31') < (v_after ->> 0)::date) or (coalesce(x."ends_on", date '9999-12-31') = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."ends_on", date '9999-12-31') desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startsOn' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'title', x."title", 'description', x."description", 'counterpartyType', x."counterparty_type", 'counterpartyId', x."counterparty_id", 'ownerId', x."owner_id", 'status', x."status", 'value', x."value"::text, 'currency', x."currency", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'autoRenew', x."auto_renew", 'renewalMonths', x."renewal_months", 'noticeDays', x."notice_days", 'noticeDeadline', case when x."ends_on" is null then null else x."ends_on" - x."notice_days" end, 'renewedCount', x."renewed_count", 'signatureRequestId', x."signature_request_id", 'signedAt', x."signed_at", 'terminatedAt', x."terminated_at", 'terminationReason', x."termination_reason", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."starts_on", date '0001-01-01'))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."contracts" x
      where x."tenant_id" = page_contracts.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'counterpartyType' is not null and jsonb_typeof(v_filters -> 'counterpartyType') <> 'null' and not (jsonb_typeof(v_filters -> 'counterpartyType') = 'array' and jsonb_array_length(v_filters -> 'counterpartyType') = 0)) or x."counterparty_type" = any((case when jsonb_typeof(v_filters -> 'counterpartyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'counterpartyType')) else array[v_filters ->> 'counterpartyType'] end)::text[]))
        and (not (v_filters -> 'counterpartyId' is not null and jsonb_typeof(v_filters -> 'counterpartyId') <> 'null' and not (jsonb_typeof(v_filters -> 'counterpartyId') = 'array' and jsonb_array_length(v_filters -> 'counterpartyId') = 0)) or x."counterparty_id" = any((case when jsonb_typeof(v_filters -> 'counterpartyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'counterpartyId')) else array[v_filters ->> 'counterpartyId'] end)::text[]))
        and (not (v_filters -> 'renewingBefore' is not null and jsonb_typeof(v_filters -> 'renewingBefore') <> 'null' and not (jsonb_typeof(v_filters -> 'renewingBefore') = 'array' and jsonb_array_length(v_filters -> 'renewingBefore') = 0)) or (x."status" = 'active' and case when x."ends_on" is null then null else x."ends_on" - x."notice_days" end <= (v_filters ->> 'renewingBefore')::date))
        and (v_search is null or x."title" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (coalesce(x."starts_on", date '0001-01-01'), x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by coalesce(x."starts_on", date '0001-01-01') asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startsOn' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'title', x."title", 'description', x."description", 'counterpartyType', x."counterparty_type", 'counterpartyId', x."counterparty_id", 'ownerId', x."owner_id", 'status', x."status", 'value', x."value"::text, 'currency', x."currency", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'autoRenew', x."auto_renew", 'renewalMonths', x."renewal_months", 'noticeDays', x."notice_days", 'noticeDeadline', case when x."ends_on" is null then null else x."ends_on" - x."notice_days" end, 'renewedCount', x."renewed_count", 'signatureRequestId', x."signature_request_id", 'signedAt', x."signed_at", 'terminatedAt', x."terminated_at", 'terminationReason', x."termination_reason", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."starts_on", date '0001-01-01'))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."contracts" x
      where x."tenant_id" = page_contracts.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'counterpartyType' is not null and jsonb_typeof(v_filters -> 'counterpartyType') <> 'null' and not (jsonb_typeof(v_filters -> 'counterpartyType') = 'array' and jsonb_array_length(v_filters -> 'counterpartyType') = 0)) or x."counterparty_type" = any((case when jsonb_typeof(v_filters -> 'counterpartyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'counterpartyType')) else array[v_filters ->> 'counterpartyType'] end)::text[]))
        and (not (v_filters -> 'counterpartyId' is not null and jsonb_typeof(v_filters -> 'counterpartyId') <> 'null' and not (jsonb_typeof(v_filters -> 'counterpartyId') = 'array' and jsonb_array_length(v_filters -> 'counterpartyId') = 0)) or x."counterparty_id" = any((case when jsonb_typeof(v_filters -> 'counterpartyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'counterpartyId')) else array[v_filters ->> 'counterpartyId'] end)::text[]))
        and (not (v_filters -> 'renewingBefore' is not null and jsonb_typeof(v_filters -> 'renewingBefore') <> 'null' and not (jsonb_typeof(v_filters -> 'renewingBefore') = 'array' and jsonb_array_length(v_filters -> 'renewingBefore') = 0)) or (x."status" = 'active' and case when x."ends_on" is null then null else x."ends_on" - x."notice_days" end <= (v_filters ->> 'renewingBefore')::date))
        and (v_search is null or x."title" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (coalesce(x."starts_on", date '0001-01-01') <= (v_after ->> 0)::date and ((coalesce(x."starts_on", date '0001-01-01') < (v_after ->> 0)::date) or (coalesce(x."starts_on", date '0001-01-01') = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."starts_on", date '0001-01-01') desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'title', x."title", 'description', x."description", 'counterpartyType', x."counterparty_type", 'counterpartyId', x."counterparty_id", 'ownerId', x."owner_id", 'status', x."status", 'value', x."value"::text, 'currency', x."currency", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'autoRenew', x."auto_renew", 'renewalMonths', x."renewal_months", 'noticeDays', x."notice_days", 'noticeDeadline', case when x."ends_on" is null then null else x."ends_on" - x."notice_days" end, 'renewedCount', x."renewed_count", 'signatureRequestId', x."signature_request_id", 'signedAt', x."signed_at", 'terminatedAt', x."terminated_at", 'terminationReason', x."termination_reason", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."contracts" x
      where x."tenant_id" = page_contracts.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'counterpartyType' is not null and jsonb_typeof(v_filters -> 'counterpartyType') <> 'null' and not (jsonb_typeof(v_filters -> 'counterpartyType') = 'array' and jsonb_array_length(v_filters -> 'counterpartyType') = 0)) or x."counterparty_type" = any((case when jsonb_typeof(v_filters -> 'counterpartyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'counterpartyType')) else array[v_filters ->> 'counterpartyType'] end)::text[]))
        and (not (v_filters -> 'counterpartyId' is not null and jsonb_typeof(v_filters -> 'counterpartyId') <> 'null' and not (jsonb_typeof(v_filters -> 'counterpartyId') = 'array' and jsonb_array_length(v_filters -> 'counterpartyId') = 0)) or x."counterparty_id" = any((case when jsonb_typeof(v_filters -> 'counterpartyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'counterpartyId')) else array[v_filters ->> 'counterpartyId'] end)::text[]))
        and (not (v_filters -> 'renewingBefore' is not null and jsonb_typeof(v_filters -> 'renewingBefore') <> 'null' and not (jsonb_typeof(v_filters -> 'renewingBefore') = 'array' and jsonb_array_length(v_filters -> 'renewingBefore') = 0)) or (x."status" = 'active' and case when x."ends_on" is null then null else x."ends_on" - x."notice_days" end <= (v_filters ->> 'renewingBefore')::date))
        and (v_search is null or x."title" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (lower(x."title"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."title") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'title', x."title", 'description', x."description", 'counterpartyType', x."counterparty_type", 'counterpartyId', x."counterparty_id", 'ownerId', x."owner_id", 'status', x."status", 'value', x."value"::text, 'currency', x."currency", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'autoRenew', x."auto_renew", 'renewalMonths', x."renewal_months", 'noticeDays', x."notice_days", 'noticeDeadline', case when x."ends_on" is null then null else x."ends_on" - x."notice_days" end, 'renewedCount', x."renewed_count", 'signatureRequestId', x."signature_request_id", 'signedAt', x."signed_at", 'terminatedAt', x."terminated_at", 'terminationReason', x."termination_reason", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."contracts" x
      where x."tenant_id" = page_contracts.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'counterpartyType' is not null and jsonb_typeof(v_filters -> 'counterpartyType') <> 'null' and not (jsonb_typeof(v_filters -> 'counterpartyType') = 'array' and jsonb_array_length(v_filters -> 'counterpartyType') = 0)) or x."counterparty_type" = any((case when jsonb_typeof(v_filters -> 'counterpartyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'counterpartyType')) else array[v_filters ->> 'counterpartyType'] end)::text[]))
        and (not (v_filters -> 'counterpartyId' is not null and jsonb_typeof(v_filters -> 'counterpartyId') <> 'null' and not (jsonb_typeof(v_filters -> 'counterpartyId') = 'array' and jsonb_array_length(v_filters -> 'counterpartyId') = 0)) or x."counterparty_id" = any((case when jsonb_typeof(v_filters -> 'counterpartyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'counterpartyId')) else array[v_filters ->> 'counterpartyId'] end)::text[]))
        and (not (v_filters -> 'renewingBefore' is not null and jsonb_typeof(v_filters -> 'renewingBefore') <> 'null' and not (jsonb_typeof(v_filters -> 'renewingBefore') = 'array' and jsonb_array_length(v_filters -> 'renewingBefore') = 0)) or (x."status" = 'active' and case when x."ends_on" is null then null else x."ends_on" - x."notice_days" end <= (v_filters ->> 'renewingBefore')::date))
        and (v_search is null or x."title" ilike v_search or x."description" ilike v_search)
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
      select 1 from "better_supabase"."contracts" x
      where x."tenant_id" = page_contracts.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'counterpartyType' is not null and jsonb_typeof(v_filters -> 'counterpartyType') <> 'null' and not (jsonb_typeof(v_filters -> 'counterpartyType') = 'array' and jsonb_array_length(v_filters -> 'counterpartyType') = 0)) or x."counterparty_type" = any((case when jsonb_typeof(v_filters -> 'counterpartyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'counterpartyType')) else array[v_filters ->> 'counterpartyType'] end)::text[]))
        and (not (v_filters -> 'counterpartyId' is not null and jsonb_typeof(v_filters -> 'counterpartyId') <> 'null' and not (jsonb_typeof(v_filters -> 'counterpartyId') = 'array' and jsonb_array_length(v_filters -> 'counterpartyId') = 0)) or x."counterparty_id" = any((case when jsonb_typeof(v_filters -> 'counterpartyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'counterpartyId')) else array[v_filters ->> 'counterpartyId'] end)::text[]))
        and (not (v_filters -> 'renewingBefore' is not null and jsonb_typeof(v_filters -> 'renewingBefore') <> 'null' and not (jsonb_typeof(v_filters -> 'renewingBefore') = 'array' and jsonb_array_length(v_filters -> 'renewingBefore') = 0)) or (x."status" = 'active' and case when x."ends_on" is null then null else x."ends_on" - x."notice_days" end <= (v_filters ->> 'renewingBefore')::date))
        and (v_search is null or x."title" ilike v_search or x."description" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_deals (
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
  v_filters jsonb := coalesce(page_deals.filters, '{}'::jsonb);
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
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'DEAL_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('outcome', 'stageId', 'ownerId', 'priority', 'motion', 'forecast') then
      raise exception 'facet is one of outcome, stageId, ownerId, priority, motion, forecast' using errcode = '22023', hint = 'DEAL_INVALID';
    end if;
    with s as (
      select (case v_facet when 'outcome' then (x."outcome"::text)::text when 'stageId' then (x."stage_id"::text)::text when 'ownerId' then (x."owner_id"::text)::text when 'priority' then (x."priority"::text)::text when 'motion' then (x."motion"::text)::text when 'forecast' then (x."forecast_category"::text)::text end) as v
      from "better_supabase"."deals" x
      where x."tenant_id" = page_deals.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'pipelineId' is not null and jsonb_typeof(v_filters -> 'pipelineId') <> 'null' and not (jsonb_typeof(v_filters -> 'pipelineId') = 'array' and jsonb_array_length(v_filters -> 'pipelineId') = 0)) or x."pipeline_id"::text = any((case when jsonb_typeof(v_filters -> 'pipelineId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pipelineId')) else array[v_filters ->> 'pipelineId'] end)::text[]))
        and (not (v_filters -> 'stageId' is not null and jsonb_typeof(v_filters -> 'stageId') <> 'null' and not (jsonb_typeof(v_filters -> 'stageId') = 'array' and jsonb_array_length(v_filters -> 'stageId') = 0)) or x."stage_id"::text = any((case when jsonb_typeof(v_filters -> 'stageId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stageId')) else array[v_filters ->> 'stageId'] end)::text[]))
        and (not (v_filters -> 'outcome' is not null and jsonb_typeof(v_filters -> 'outcome') <> 'null' and not (jsonb_typeof(v_filters -> 'outcome') = 'array' and jsonb_array_length(v_filters -> 'outcome') = 0)) or x."outcome"::text = any((case when jsonb_typeof(v_filters -> 'outcome') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'outcome')) else array[v_filters ->> 'outcome'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'motion' is not null and jsonb_typeof(v_filters -> 'motion') <> 'null' and not (jsonb_typeof(v_filters -> 'motion') = 'array' and jsonb_array_length(v_filters -> 'motion') = 0)) or x."motion"::text = any((case when jsonb_typeof(v_filters -> 'motion') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'motion')) else array[v_filters ->> 'motion'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'forecast' is not null and jsonb_typeof(v_filters -> 'forecast') <> 'null' and not (jsonb_typeof(v_filters -> 'forecast') = 'array' and jsonb_array_length(v_filters -> 'forecast') = 0)) or x."forecast_category"::text = any((case when jsonb_typeof(v_filters -> 'forecast') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'forecast')) else array[v_filters ->> 'forecast'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'companyId' is not null and jsonb_typeof(v_filters -> 'companyId') <> 'null' and not (jsonb_typeof(v_filters -> 'companyId') = 'array' and jsonb_array_length(v_filters -> 'companyId') = 0)) or x."company_id"::text = any((case when jsonb_typeof(v_filters -> 'companyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'companyId')) else array[v_filters ->> 'companyId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."identifier" ilike v_search)
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
      select 1 from "better_supabase"."deals" x
      where x."tenant_id" = page_deals.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'pipelineId' is not null and jsonb_typeof(v_filters -> 'pipelineId') <> 'null' and not (jsonb_typeof(v_filters -> 'pipelineId') = 'array' and jsonb_array_length(v_filters -> 'pipelineId') = 0)) or x."pipeline_id"::text = any((case when jsonb_typeof(v_filters -> 'pipelineId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pipelineId')) else array[v_filters ->> 'pipelineId'] end)::text[]))
        and (not (v_filters -> 'stageId' is not null and jsonb_typeof(v_filters -> 'stageId') <> 'null' and not (jsonb_typeof(v_filters -> 'stageId') = 'array' and jsonb_array_length(v_filters -> 'stageId') = 0)) or x."stage_id"::text = any((case when jsonb_typeof(v_filters -> 'stageId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stageId')) else array[v_filters ->> 'stageId'] end)::text[]))
        and (not (v_filters -> 'outcome' is not null and jsonb_typeof(v_filters -> 'outcome') <> 'null' and not (jsonb_typeof(v_filters -> 'outcome') = 'array' and jsonb_array_length(v_filters -> 'outcome') = 0)) or x."outcome"::text = any((case when jsonb_typeof(v_filters -> 'outcome') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'outcome')) else array[v_filters ->> 'outcome'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'motion' is not null and jsonb_typeof(v_filters -> 'motion') <> 'null' and not (jsonb_typeof(v_filters -> 'motion') = 'array' and jsonb_array_length(v_filters -> 'motion') = 0)) or x."motion"::text = any((case when jsonb_typeof(v_filters -> 'motion') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'motion')) else array[v_filters ->> 'motion'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'forecast' is not null and jsonb_typeof(v_filters -> 'forecast') <> 'null' and not (jsonb_typeof(v_filters -> 'forecast') = 'array' and jsonb_array_length(v_filters -> 'forecast') = 0)) or x."forecast_category"::text = any((case when jsonb_typeof(v_filters -> 'forecast') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'forecast')) else array[v_filters ->> 'forecast'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'companyId' is not null and jsonb_typeof(v_filters -> 'companyId') <> 'null' and not (jsonb_typeof(v_filters -> 'companyId') = 'array' and jsonb_array_length(v_filters -> 'companyId') = 0)) or x."company_id"::text = any((case when jsonb_typeof(v_filters -> 'companyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'companyId')) else array[v_filters ->> 'companyId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."identifier" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'closeOn', 'amount', 'name') then
    raise exception 'sort is one of createdAt, closeOn, amount, name' using errcode = '22023', hint = 'DEAL_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'DEAL_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DEAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'amount', x."amount"::text, 'existing_amount', x."existing_amount"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text) || jsonb_build_object(
      'contacts', coalesce((select jsonb_agg(jsonb_build_object('type', ck."contact_type", 'id', ck."contact_id", 'role', ck."role", 'primary', ck."is_primary") order by ck."is_primary" desc, ck."contact_id") from "better_supabase"."deal_contacts" ck where ck."deal_id" = x."id"), '[]'::jsonb),
      'members', coalesce((select jsonb_agg(jsonb_build_object('userId', cm."user_id", 'role', cm."role") order by cm."user_id") from "better_supabase"."deal_members" cm where cm."deal_id" = x."id"), '[]'::jsonb)) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."deals" x
      where x."tenant_id" = page_deals.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'pipelineId' is not null and jsonb_typeof(v_filters -> 'pipelineId') <> 'null' and not (jsonb_typeof(v_filters -> 'pipelineId') = 'array' and jsonb_array_length(v_filters -> 'pipelineId') = 0)) or x."pipeline_id"::text = any((case when jsonb_typeof(v_filters -> 'pipelineId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pipelineId')) else array[v_filters ->> 'pipelineId'] end)::text[]))
        and (not (v_filters -> 'stageId' is not null and jsonb_typeof(v_filters -> 'stageId') <> 'null' and not (jsonb_typeof(v_filters -> 'stageId') = 'array' and jsonb_array_length(v_filters -> 'stageId') = 0)) or x."stage_id"::text = any((case when jsonb_typeof(v_filters -> 'stageId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stageId')) else array[v_filters ->> 'stageId'] end)::text[]))
        and (not (v_filters -> 'outcome' is not null and jsonb_typeof(v_filters -> 'outcome') <> 'null' and not (jsonb_typeof(v_filters -> 'outcome') = 'array' and jsonb_array_length(v_filters -> 'outcome') = 0)) or x."outcome"::text = any((case when jsonb_typeof(v_filters -> 'outcome') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'outcome')) else array[v_filters ->> 'outcome'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'motion' is not null and jsonb_typeof(v_filters -> 'motion') <> 'null' and not (jsonb_typeof(v_filters -> 'motion') = 'array' and jsonb_array_length(v_filters -> 'motion') = 0)) or x."motion"::text = any((case when jsonb_typeof(v_filters -> 'motion') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'motion')) else array[v_filters ->> 'motion'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'forecast' is not null and jsonb_typeof(v_filters -> 'forecast') <> 'null' and not (jsonb_typeof(v_filters -> 'forecast') = 'array' and jsonb_array_length(v_filters -> 'forecast') = 0)) or x."forecast_category"::text = any((case when jsonb_typeof(v_filters -> 'forecast') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'forecast')) else array[v_filters ->> 'forecast'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'companyId' is not null and jsonb_typeof(v_filters -> 'companyId') <> 'null' and not (jsonb_typeof(v_filters -> 'companyId') = 'array' and jsonb_array_length(v_filters -> 'companyId') = 0)) or x."company_id"::text = any((case when jsonb_typeof(v_filters -> 'companyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'companyId')) else array[v_filters ->> 'companyId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DEAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'amount', x."amount"::text, 'existing_amount', x."existing_amount"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text) || jsonb_build_object(
      'contacts', coalesce((select jsonb_agg(jsonb_build_object('type', ck."contact_type", 'id', ck."contact_id", 'role', ck."role", 'primary', ck."is_primary") order by ck."is_primary" desc, ck."contact_id") from "better_supabase"."deal_contacts" ck where ck."deal_id" = x."id"), '[]'::jsonb),
      'members', coalesce((select jsonb_agg(jsonb_build_object('userId', cm."user_id", 'role', cm."role") order by cm."user_id") from "better_supabase"."deal_members" cm where cm."deal_id" = x."id"), '[]'::jsonb)) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."deals" x
      where x."tenant_id" = page_deals.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'pipelineId' is not null and jsonb_typeof(v_filters -> 'pipelineId') <> 'null' and not (jsonb_typeof(v_filters -> 'pipelineId') = 'array' and jsonb_array_length(v_filters -> 'pipelineId') = 0)) or x."pipeline_id"::text = any((case when jsonb_typeof(v_filters -> 'pipelineId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pipelineId')) else array[v_filters ->> 'pipelineId'] end)::text[]))
        and (not (v_filters -> 'stageId' is not null and jsonb_typeof(v_filters -> 'stageId') <> 'null' and not (jsonb_typeof(v_filters -> 'stageId') = 'array' and jsonb_array_length(v_filters -> 'stageId') = 0)) or x."stage_id"::text = any((case when jsonb_typeof(v_filters -> 'stageId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stageId')) else array[v_filters ->> 'stageId'] end)::text[]))
        and (not (v_filters -> 'outcome' is not null and jsonb_typeof(v_filters -> 'outcome') <> 'null' and not (jsonb_typeof(v_filters -> 'outcome') = 'array' and jsonb_array_length(v_filters -> 'outcome') = 0)) or x."outcome"::text = any((case when jsonb_typeof(v_filters -> 'outcome') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'outcome')) else array[v_filters ->> 'outcome'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'motion' is not null and jsonb_typeof(v_filters -> 'motion') <> 'null' and not (jsonb_typeof(v_filters -> 'motion') = 'array' and jsonb_array_length(v_filters -> 'motion') = 0)) or x."motion"::text = any((case when jsonb_typeof(v_filters -> 'motion') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'motion')) else array[v_filters ->> 'motion'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'forecast' is not null and jsonb_typeof(v_filters -> 'forecast') <> 'null' and not (jsonb_typeof(v_filters -> 'forecast') = 'array' and jsonb_array_length(v_filters -> 'forecast') = 0)) or x."forecast_category"::text = any((case when jsonb_typeof(v_filters -> 'forecast') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'forecast')) else array[v_filters ->> 'forecast'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'companyId' is not null and jsonb_typeof(v_filters -> 'companyId') <> 'null' and not (jsonb_typeof(v_filters -> 'companyId') = 'array' and jsonb_array_length(v_filters -> 'companyId') = 0)) or x."company_id"::text = any((case when jsonb_typeof(v_filters -> 'companyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'companyId')) else array[v_filters ->> 'companyId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DEAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'amount', x."amount"::text, 'existing_amount', x."existing_amount"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text) || jsonb_build_object(
      'contacts', coalesce((select jsonb_agg(jsonb_build_object('type', ck."contact_type", 'id', ck."contact_id", 'role', ck."role", 'primary', ck."is_primary") order by ck."is_primary" desc, ck."contact_id") from "better_supabase"."deal_contacts" ck where ck."deal_id" = x."id"), '[]'::jsonb),
      'members', coalesce((select jsonb_agg(jsonb_build_object('userId', cm."user_id", 'role', cm."role") order by cm."user_id") from "better_supabase"."deal_members" cm where cm."deal_id" = x."id"), '[]'::jsonb)) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."deals" x
      where x."tenant_id" = page_deals.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'pipelineId' is not null and jsonb_typeof(v_filters -> 'pipelineId') <> 'null' and not (jsonb_typeof(v_filters -> 'pipelineId') = 'array' and jsonb_array_length(v_filters -> 'pipelineId') = 0)) or x."pipeline_id"::text = any((case when jsonb_typeof(v_filters -> 'pipelineId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pipelineId')) else array[v_filters ->> 'pipelineId'] end)::text[]))
        and (not (v_filters -> 'stageId' is not null and jsonb_typeof(v_filters -> 'stageId') <> 'null' and not (jsonb_typeof(v_filters -> 'stageId') = 'array' and jsonb_array_length(v_filters -> 'stageId') = 0)) or x."stage_id"::text = any((case when jsonb_typeof(v_filters -> 'stageId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stageId')) else array[v_filters ->> 'stageId'] end)::text[]))
        and (not (v_filters -> 'outcome' is not null and jsonb_typeof(v_filters -> 'outcome') <> 'null' and not (jsonb_typeof(v_filters -> 'outcome') = 'array' and jsonb_array_length(v_filters -> 'outcome') = 0)) or x."outcome"::text = any((case when jsonb_typeof(v_filters -> 'outcome') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'outcome')) else array[v_filters ->> 'outcome'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'motion' is not null and jsonb_typeof(v_filters -> 'motion') <> 'null' and not (jsonb_typeof(v_filters -> 'motion') = 'array' and jsonb_array_length(v_filters -> 'motion') = 0)) or x."motion"::text = any((case when jsonb_typeof(v_filters -> 'motion') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'motion')) else array[v_filters ->> 'motion'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'forecast' is not null and jsonb_typeof(v_filters -> 'forecast') <> 'null' and not (jsonb_typeof(v_filters -> 'forecast') = 'array' and jsonb_array_length(v_filters -> 'forecast') = 0)) or x."forecast_category"::text = any((case when jsonb_typeof(v_filters -> 'forecast') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'forecast')) else array[v_filters ->> 'forecast'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'companyId' is not null and jsonb_typeof(v_filters -> 'companyId') <> 'null' and not (jsonb_typeof(v_filters -> 'companyId') = 'array' and jsonb_array_length(v_filters -> 'companyId') = 0)) or x."company_id"::text = any((case when jsonb_typeof(v_filters -> 'companyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'companyId')) else array[v_filters ->> 'companyId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DEAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'amount', x."amount"::text, 'existing_amount', x."existing_amount"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text) || jsonb_build_object(
      'contacts', coalesce((select jsonb_agg(jsonb_build_object('type', ck."contact_type", 'id', ck."contact_id", 'role', ck."role", 'primary', ck."is_primary") order by ck."is_primary" desc, ck."contact_id") from "better_supabase"."deal_contacts" ck where ck."deal_id" = x."id"), '[]'::jsonb),
      'members', coalesce((select jsonb_agg(jsonb_build_object('userId', cm."user_id", 'role', cm."role") order by cm."user_id") from "better_supabase"."deal_members" cm where cm."deal_id" = x."id"), '[]'::jsonb)) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."deals" x
      where x."tenant_id" = page_deals.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'pipelineId' is not null and jsonb_typeof(v_filters -> 'pipelineId') <> 'null' and not (jsonb_typeof(v_filters -> 'pipelineId') = 'array' and jsonb_array_length(v_filters -> 'pipelineId') = 0)) or x."pipeline_id"::text = any((case when jsonb_typeof(v_filters -> 'pipelineId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pipelineId')) else array[v_filters ->> 'pipelineId'] end)::text[]))
        and (not (v_filters -> 'stageId' is not null and jsonb_typeof(v_filters -> 'stageId') <> 'null' and not (jsonb_typeof(v_filters -> 'stageId') = 'array' and jsonb_array_length(v_filters -> 'stageId') = 0)) or x."stage_id"::text = any((case when jsonb_typeof(v_filters -> 'stageId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stageId')) else array[v_filters ->> 'stageId'] end)::text[]))
        and (not (v_filters -> 'outcome' is not null and jsonb_typeof(v_filters -> 'outcome') <> 'null' and not (jsonb_typeof(v_filters -> 'outcome') = 'array' and jsonb_array_length(v_filters -> 'outcome') = 0)) or x."outcome"::text = any((case when jsonb_typeof(v_filters -> 'outcome') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'outcome')) else array[v_filters ->> 'outcome'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'motion' is not null and jsonb_typeof(v_filters -> 'motion') <> 'null' and not (jsonb_typeof(v_filters -> 'motion') = 'array' and jsonb_array_length(v_filters -> 'motion') = 0)) or x."motion"::text = any((case when jsonb_typeof(v_filters -> 'motion') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'motion')) else array[v_filters ->> 'motion'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'forecast' is not null and jsonb_typeof(v_filters -> 'forecast') <> 'null' and not (jsonb_typeof(v_filters -> 'forecast') = 'array' and jsonb_array_length(v_filters -> 'forecast') = 0)) or x."forecast_category"::text = any((case when jsonb_typeof(v_filters -> 'forecast') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'forecast')) else array[v_filters ->> 'forecast'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'companyId' is not null and jsonb_typeof(v_filters -> 'companyId') <> 'null' and not (jsonb_typeof(v_filters -> 'companyId') = 'array' and jsonb_array_length(v_filters -> 'companyId') = 0)) or x."company_id"::text = any((case when jsonb_typeof(v_filters -> 'companyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'companyId')) else array[v_filters ->> 'companyId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'closeOn' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DEAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'amount', x."amount"::text, 'existing_amount', x."existing_amount"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text) || jsonb_build_object(
      'contacts', coalesce((select jsonb_agg(jsonb_build_object('type', ck."contact_type", 'id', ck."contact_id", 'role', ck."role", 'primary', ck."is_primary") order by ck."is_primary" desc, ck."contact_id") from "better_supabase"."deal_contacts" ck where ck."deal_id" = x."id"), '[]'::jsonb),
      'members', coalesce((select jsonb_agg(jsonb_build_object('userId', cm."user_id", 'role', cm."role") order by cm."user_id") from "better_supabase"."deal_members" cm where cm."deal_id" = x."id"), '[]'::jsonb)) as j, jsonb_build_array((x."expected_close_on")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."deals" x
      where x."tenant_id" = page_deals.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'pipelineId' is not null and jsonb_typeof(v_filters -> 'pipelineId') <> 'null' and not (jsonb_typeof(v_filters -> 'pipelineId') = 'array' and jsonb_array_length(v_filters -> 'pipelineId') = 0)) or x."pipeline_id"::text = any((case when jsonb_typeof(v_filters -> 'pipelineId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pipelineId')) else array[v_filters ->> 'pipelineId'] end)::text[]))
        and (not (v_filters -> 'stageId' is not null and jsonb_typeof(v_filters -> 'stageId') <> 'null' and not (jsonb_typeof(v_filters -> 'stageId') = 'array' and jsonb_array_length(v_filters -> 'stageId') = 0)) or x."stage_id"::text = any((case when jsonb_typeof(v_filters -> 'stageId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stageId')) else array[v_filters ->> 'stageId'] end)::text[]))
        and (not (v_filters -> 'outcome' is not null and jsonb_typeof(v_filters -> 'outcome') <> 'null' and not (jsonb_typeof(v_filters -> 'outcome') = 'array' and jsonb_array_length(v_filters -> 'outcome') = 0)) or x."outcome"::text = any((case when jsonb_typeof(v_filters -> 'outcome') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'outcome')) else array[v_filters ->> 'outcome'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'motion' is not null and jsonb_typeof(v_filters -> 'motion') <> 'null' and not (jsonb_typeof(v_filters -> 'motion') = 'array' and jsonb_array_length(v_filters -> 'motion') = 0)) or x."motion"::text = any((case when jsonb_typeof(v_filters -> 'motion') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'motion')) else array[v_filters ->> 'motion'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'forecast' is not null and jsonb_typeof(v_filters -> 'forecast') <> 'null' and not (jsonb_typeof(v_filters -> 'forecast') = 'array' and jsonb_array_length(v_filters -> 'forecast') = 0)) or x."forecast_category"::text = any((case when jsonb_typeof(v_filters -> 'forecast') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'forecast')) else array[v_filters ->> 'forecast'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'companyId' is not null and jsonb_typeof(v_filters -> 'companyId') <> 'null' and not (jsonb_typeof(v_filters -> 'companyId') = 'array' and jsonb_array_length(v_filters -> 'companyId') = 0)) or x."company_id"::text = any((case when jsonb_typeof(v_filters -> 'companyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'companyId')) else array[v_filters ->> 'companyId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (x."expected_close_on", x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by x."expected_close_on" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'closeOn' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DEAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'amount', x."amount"::text, 'existing_amount', x."existing_amount"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text) || jsonb_build_object(
      'contacts', coalesce((select jsonb_agg(jsonb_build_object('type', ck."contact_type", 'id', ck."contact_id", 'role', ck."role", 'primary', ck."is_primary") order by ck."is_primary" desc, ck."contact_id") from "better_supabase"."deal_contacts" ck where ck."deal_id" = x."id"), '[]'::jsonb),
      'members', coalesce((select jsonb_agg(jsonb_build_object('userId', cm."user_id", 'role', cm."role") order by cm."user_id") from "better_supabase"."deal_members" cm where cm."deal_id" = x."id"), '[]'::jsonb)) as j, jsonb_build_array((x."expected_close_on")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."deals" x
      where x."tenant_id" = page_deals.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'pipelineId' is not null and jsonb_typeof(v_filters -> 'pipelineId') <> 'null' and not (jsonb_typeof(v_filters -> 'pipelineId') = 'array' and jsonb_array_length(v_filters -> 'pipelineId') = 0)) or x."pipeline_id"::text = any((case when jsonb_typeof(v_filters -> 'pipelineId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pipelineId')) else array[v_filters ->> 'pipelineId'] end)::text[]))
        and (not (v_filters -> 'stageId' is not null and jsonb_typeof(v_filters -> 'stageId') <> 'null' and not (jsonb_typeof(v_filters -> 'stageId') = 'array' and jsonb_array_length(v_filters -> 'stageId') = 0)) or x."stage_id"::text = any((case when jsonb_typeof(v_filters -> 'stageId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stageId')) else array[v_filters ->> 'stageId'] end)::text[]))
        and (not (v_filters -> 'outcome' is not null and jsonb_typeof(v_filters -> 'outcome') <> 'null' and not (jsonb_typeof(v_filters -> 'outcome') = 'array' and jsonb_array_length(v_filters -> 'outcome') = 0)) or x."outcome"::text = any((case when jsonb_typeof(v_filters -> 'outcome') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'outcome')) else array[v_filters ->> 'outcome'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'motion' is not null and jsonb_typeof(v_filters -> 'motion') <> 'null' and not (jsonb_typeof(v_filters -> 'motion') = 'array' and jsonb_array_length(v_filters -> 'motion') = 0)) or x."motion"::text = any((case when jsonb_typeof(v_filters -> 'motion') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'motion')) else array[v_filters ->> 'motion'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'forecast' is not null and jsonb_typeof(v_filters -> 'forecast') <> 'null' and not (jsonb_typeof(v_filters -> 'forecast') = 'array' and jsonb_array_length(v_filters -> 'forecast') = 0)) or x."forecast_category"::text = any((case when jsonb_typeof(v_filters -> 'forecast') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'forecast')) else array[v_filters ->> 'forecast'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'companyId' is not null and jsonb_typeof(v_filters -> 'companyId') <> 'null' and not (jsonb_typeof(v_filters -> 'companyId') = 'array' and jsonb_array_length(v_filters -> 'companyId') = 0)) or x."company_id"::text = any((case when jsonb_typeof(v_filters -> 'companyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'companyId')) else array[v_filters ->> 'companyId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (x."expected_close_on" <= (v_after ->> 0)::date and ((x."expected_close_on" < (v_after ->> 0)::date) or (x."expected_close_on" = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by x."expected_close_on" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'amount' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DEAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'amount', x."amount"::text, 'existing_amount', x."existing_amount"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text) || jsonb_build_object(
      'contacts', coalesce((select jsonb_agg(jsonb_build_object('type', ck."contact_type", 'id', ck."contact_id", 'role', ck."role", 'primary', ck."is_primary") order by ck."is_primary" desc, ck."contact_id") from "better_supabase"."deal_contacts" ck where ck."deal_id" = x."id"), '[]'::jsonb),
      'members', coalesce((select jsonb_agg(jsonb_build_object('userId', cm."user_id", 'role', cm."role") order by cm."user_id") from "better_supabase"."deal_members" cm where cm."deal_id" = x."id"), '[]'::jsonb)) as j, jsonb_build_array((x."amount")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."deals" x
      where x."tenant_id" = page_deals.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'pipelineId' is not null and jsonb_typeof(v_filters -> 'pipelineId') <> 'null' and not (jsonb_typeof(v_filters -> 'pipelineId') = 'array' and jsonb_array_length(v_filters -> 'pipelineId') = 0)) or x."pipeline_id"::text = any((case when jsonb_typeof(v_filters -> 'pipelineId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pipelineId')) else array[v_filters ->> 'pipelineId'] end)::text[]))
        and (not (v_filters -> 'stageId' is not null and jsonb_typeof(v_filters -> 'stageId') <> 'null' and not (jsonb_typeof(v_filters -> 'stageId') = 'array' and jsonb_array_length(v_filters -> 'stageId') = 0)) or x."stage_id"::text = any((case when jsonb_typeof(v_filters -> 'stageId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stageId')) else array[v_filters ->> 'stageId'] end)::text[]))
        and (not (v_filters -> 'outcome' is not null and jsonb_typeof(v_filters -> 'outcome') <> 'null' and not (jsonb_typeof(v_filters -> 'outcome') = 'array' and jsonb_array_length(v_filters -> 'outcome') = 0)) or x."outcome"::text = any((case when jsonb_typeof(v_filters -> 'outcome') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'outcome')) else array[v_filters ->> 'outcome'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'motion' is not null and jsonb_typeof(v_filters -> 'motion') <> 'null' and not (jsonb_typeof(v_filters -> 'motion') = 'array' and jsonb_array_length(v_filters -> 'motion') = 0)) or x."motion"::text = any((case when jsonb_typeof(v_filters -> 'motion') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'motion')) else array[v_filters ->> 'motion'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'forecast' is not null and jsonb_typeof(v_filters -> 'forecast') <> 'null' and not (jsonb_typeof(v_filters -> 'forecast') = 'array' and jsonb_array_length(v_filters -> 'forecast') = 0)) or x."forecast_category"::text = any((case when jsonb_typeof(v_filters -> 'forecast') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'forecast')) else array[v_filters ->> 'forecast'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'companyId' is not null and jsonb_typeof(v_filters -> 'companyId') <> 'null' and not (jsonb_typeof(v_filters -> 'companyId') = 'array' and jsonb_array_length(v_filters -> 'companyId') = 0)) or x."company_id"::text = any((case when jsonb_typeof(v_filters -> 'companyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'companyId')) else array[v_filters ->> 'companyId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (x."amount", x."id") > ((v_after ->> 0)::bigint, (v_after ->> 1)::uuid))
      order by x."amount" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'amount' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DEAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'amount', x."amount"::text, 'existing_amount', x."existing_amount"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text) || jsonb_build_object(
      'contacts', coalesce((select jsonb_agg(jsonb_build_object('type', ck."contact_type", 'id', ck."contact_id", 'role', ck."role", 'primary', ck."is_primary") order by ck."is_primary" desc, ck."contact_id") from "better_supabase"."deal_contacts" ck where ck."deal_id" = x."id"), '[]'::jsonb),
      'members', coalesce((select jsonb_agg(jsonb_build_object('userId', cm."user_id", 'role', cm."role") order by cm."user_id") from "better_supabase"."deal_members" cm where cm."deal_id" = x."id"), '[]'::jsonb)) as j, jsonb_build_array((x."amount")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."deals" x
      where x."tenant_id" = page_deals.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'pipelineId' is not null and jsonb_typeof(v_filters -> 'pipelineId') <> 'null' and not (jsonb_typeof(v_filters -> 'pipelineId') = 'array' and jsonb_array_length(v_filters -> 'pipelineId') = 0)) or x."pipeline_id"::text = any((case when jsonb_typeof(v_filters -> 'pipelineId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pipelineId')) else array[v_filters ->> 'pipelineId'] end)::text[]))
        and (not (v_filters -> 'stageId' is not null and jsonb_typeof(v_filters -> 'stageId') <> 'null' and not (jsonb_typeof(v_filters -> 'stageId') = 'array' and jsonb_array_length(v_filters -> 'stageId') = 0)) or x."stage_id"::text = any((case when jsonb_typeof(v_filters -> 'stageId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stageId')) else array[v_filters ->> 'stageId'] end)::text[]))
        and (not (v_filters -> 'outcome' is not null and jsonb_typeof(v_filters -> 'outcome') <> 'null' and not (jsonb_typeof(v_filters -> 'outcome') = 'array' and jsonb_array_length(v_filters -> 'outcome') = 0)) or x."outcome"::text = any((case when jsonb_typeof(v_filters -> 'outcome') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'outcome')) else array[v_filters ->> 'outcome'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'motion' is not null and jsonb_typeof(v_filters -> 'motion') <> 'null' and not (jsonb_typeof(v_filters -> 'motion') = 'array' and jsonb_array_length(v_filters -> 'motion') = 0)) or x."motion"::text = any((case when jsonb_typeof(v_filters -> 'motion') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'motion')) else array[v_filters ->> 'motion'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'forecast' is not null and jsonb_typeof(v_filters -> 'forecast') <> 'null' and not (jsonb_typeof(v_filters -> 'forecast') = 'array' and jsonb_array_length(v_filters -> 'forecast') = 0)) or x."forecast_category"::text = any((case when jsonb_typeof(v_filters -> 'forecast') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'forecast')) else array[v_filters ->> 'forecast'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'companyId' is not null and jsonb_typeof(v_filters -> 'companyId') <> 'null' and not (jsonb_typeof(v_filters -> 'companyId') = 'array' and jsonb_array_length(v_filters -> 'companyId') = 0)) or x."company_id"::text = any((case when jsonb_typeof(v_filters -> 'companyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'companyId')) else array[v_filters ->> 'companyId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (x."amount" <= (v_after ->> 0)::bigint and ((x."amount" < (v_after ->> 0)::bigint) or (x."amount" = (v_after ->> 0)::bigint and x."id" > (v_after ->> 1)::uuid))))
      order by x."amount" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DEAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'amount', x."amount"::text, 'existing_amount', x."existing_amount"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text) || jsonb_build_object(
      'contacts', coalesce((select jsonb_agg(jsonb_build_object('type', ck."contact_type", 'id', ck."contact_id", 'role', ck."role", 'primary', ck."is_primary") order by ck."is_primary" desc, ck."contact_id") from "better_supabase"."deal_contacts" ck where ck."deal_id" = x."id"), '[]'::jsonb),
      'members', coalesce((select jsonb_agg(jsonb_build_object('userId', cm."user_id", 'role', cm."role") order by cm."user_id") from "better_supabase"."deal_members" cm where cm."deal_id" = x."id"), '[]'::jsonb)) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."deals" x
      where x."tenant_id" = page_deals.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'pipelineId' is not null and jsonb_typeof(v_filters -> 'pipelineId') <> 'null' and not (jsonb_typeof(v_filters -> 'pipelineId') = 'array' and jsonb_array_length(v_filters -> 'pipelineId') = 0)) or x."pipeline_id"::text = any((case when jsonb_typeof(v_filters -> 'pipelineId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pipelineId')) else array[v_filters ->> 'pipelineId'] end)::text[]))
        and (not (v_filters -> 'stageId' is not null and jsonb_typeof(v_filters -> 'stageId') <> 'null' and not (jsonb_typeof(v_filters -> 'stageId') = 'array' and jsonb_array_length(v_filters -> 'stageId') = 0)) or x."stage_id"::text = any((case when jsonb_typeof(v_filters -> 'stageId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stageId')) else array[v_filters ->> 'stageId'] end)::text[]))
        and (not (v_filters -> 'outcome' is not null and jsonb_typeof(v_filters -> 'outcome') <> 'null' and not (jsonb_typeof(v_filters -> 'outcome') = 'array' and jsonb_array_length(v_filters -> 'outcome') = 0)) or x."outcome"::text = any((case when jsonb_typeof(v_filters -> 'outcome') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'outcome')) else array[v_filters ->> 'outcome'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'motion' is not null and jsonb_typeof(v_filters -> 'motion') <> 'null' and not (jsonb_typeof(v_filters -> 'motion') = 'array' and jsonb_array_length(v_filters -> 'motion') = 0)) or x."motion"::text = any((case when jsonb_typeof(v_filters -> 'motion') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'motion')) else array[v_filters ->> 'motion'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'forecast' is not null and jsonb_typeof(v_filters -> 'forecast') <> 'null' and not (jsonb_typeof(v_filters -> 'forecast') = 'array' and jsonb_array_length(v_filters -> 'forecast') = 0)) or x."forecast_category"::text = any((case when jsonb_typeof(v_filters -> 'forecast') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'forecast')) else array[v_filters ->> 'forecast'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'companyId' is not null and jsonb_typeof(v_filters -> 'companyId') <> 'null' and not (jsonb_typeof(v_filters -> 'companyId') = 'array' and jsonb_array_length(v_filters -> 'companyId') = 0)) or x."company_id"::text = any((case when jsonb_typeof(v_filters -> 'companyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'companyId')) else array[v_filters ->> 'companyId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DEAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'amount', x."amount"::text, 'existing_amount', x."existing_amount"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text) || jsonb_build_object(
      'contacts', coalesce((select jsonb_agg(jsonb_build_object('type', ck."contact_type", 'id', ck."contact_id", 'role', ck."role", 'primary', ck."is_primary") order by ck."is_primary" desc, ck."contact_id") from "better_supabase"."deal_contacts" ck where ck."deal_id" = x."id"), '[]'::jsonb),
      'members', coalesce((select jsonb_agg(jsonb_build_object('userId', cm."user_id", 'role', cm."role") order by cm."user_id") from "better_supabase"."deal_members" cm where cm."deal_id" = x."id"), '[]'::jsonb)) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."deals" x
      where x."tenant_id" = page_deals.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'pipelineId' is not null and jsonb_typeof(v_filters -> 'pipelineId') <> 'null' and not (jsonb_typeof(v_filters -> 'pipelineId') = 'array' and jsonb_array_length(v_filters -> 'pipelineId') = 0)) or x."pipeline_id"::text = any((case when jsonb_typeof(v_filters -> 'pipelineId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pipelineId')) else array[v_filters ->> 'pipelineId'] end)::text[]))
        and (not (v_filters -> 'stageId' is not null and jsonb_typeof(v_filters -> 'stageId') <> 'null' and not (jsonb_typeof(v_filters -> 'stageId') = 'array' and jsonb_array_length(v_filters -> 'stageId') = 0)) or x."stage_id"::text = any((case when jsonb_typeof(v_filters -> 'stageId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stageId')) else array[v_filters ->> 'stageId'] end)::text[]))
        and (not (v_filters -> 'outcome' is not null and jsonb_typeof(v_filters -> 'outcome') <> 'null' and not (jsonb_typeof(v_filters -> 'outcome') = 'array' and jsonb_array_length(v_filters -> 'outcome') = 0)) or x."outcome"::text = any((case when jsonb_typeof(v_filters -> 'outcome') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'outcome')) else array[v_filters ->> 'outcome'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'motion' is not null and jsonb_typeof(v_filters -> 'motion') <> 'null' and not (jsonb_typeof(v_filters -> 'motion') = 'array' and jsonb_array_length(v_filters -> 'motion') = 0)) or x."motion"::text = any((case when jsonb_typeof(v_filters -> 'motion') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'motion')) else array[v_filters ->> 'motion'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'forecast' is not null and jsonb_typeof(v_filters -> 'forecast') <> 'null' and not (jsonb_typeof(v_filters -> 'forecast') = 'array' and jsonb_array_length(v_filters -> 'forecast') = 0)) or x."forecast_category"::text = any((case when jsonb_typeof(v_filters -> 'forecast') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'forecast')) else array[v_filters ->> 'forecast'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'companyId' is not null and jsonb_typeof(v_filters -> 'companyId') <> 'null' and not (jsonb_typeof(v_filters -> 'companyId') = 'array' and jsonb_array_length(v_filters -> 'companyId') = 0)) or x."company_id"::text = any((case when jsonb_typeof(v_filters -> 'companyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'companyId')) else array[v_filters ->> 'companyId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."identifier" ilike v_search)
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
      select 1 from "better_supabase"."deals" x
      where x."tenant_id" = page_deals.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'pipelineId' is not null and jsonb_typeof(v_filters -> 'pipelineId') <> 'null' and not (jsonb_typeof(v_filters -> 'pipelineId') = 'array' and jsonb_array_length(v_filters -> 'pipelineId') = 0)) or x."pipeline_id"::text = any((case when jsonb_typeof(v_filters -> 'pipelineId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pipelineId')) else array[v_filters ->> 'pipelineId'] end)::text[]))
        and (not (v_filters -> 'stageId' is not null and jsonb_typeof(v_filters -> 'stageId') <> 'null' and not (jsonb_typeof(v_filters -> 'stageId') = 'array' and jsonb_array_length(v_filters -> 'stageId') = 0)) or x."stage_id"::text = any((case when jsonb_typeof(v_filters -> 'stageId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stageId')) else array[v_filters ->> 'stageId'] end)::text[]))
        and (not (v_filters -> 'outcome' is not null and jsonb_typeof(v_filters -> 'outcome') <> 'null' and not (jsonb_typeof(v_filters -> 'outcome') = 'array' and jsonb_array_length(v_filters -> 'outcome') = 0)) or x."outcome"::text = any((case when jsonb_typeof(v_filters -> 'outcome') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'outcome')) else array[v_filters ->> 'outcome'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'motion' is not null and jsonb_typeof(v_filters -> 'motion') <> 'null' and not (jsonb_typeof(v_filters -> 'motion') = 'array' and jsonb_array_length(v_filters -> 'motion') = 0)) or x."motion"::text = any((case when jsonb_typeof(v_filters -> 'motion') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'motion')) else array[v_filters ->> 'motion'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'forecast' is not null and jsonb_typeof(v_filters -> 'forecast') <> 'null' and not (jsonb_typeof(v_filters -> 'forecast') = 'array' and jsonb_array_length(v_filters -> 'forecast') = 0)) or x."forecast_category"::text = any((case when jsonb_typeof(v_filters -> 'forecast') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'forecast')) else array[v_filters ->> 'forecast'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'companyId' is not null and jsonb_typeof(v_filters -> 'companyId') <> 'null' and not (jsonb_typeof(v_filters -> 'companyId') = 'array' and jsonb_array_length(v_filters -> 'companyId') = 0)) or x."company_id"::text = any((case when jsonb_typeof(v_filters -> 'companyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'companyId')) else array[v_filters ->> 'companyId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."identifier" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_forecast_snapshots (
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
  v_filters jsonb := coalesce(page_forecast_snapshots.filters, '{}'::jsonb);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', page_forecast_snapshots.tenant, 'forecasts.read'), false)) then
    raise exception 'You need forecasts.read to list forecast snapshots' using errcode = '42501', hint = 'FORECAST_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'FORECAST_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('currency', 'pipelineId') then
      raise exception 'facet is one of currency, pipelineId' using errcode = '22023', hint = 'FORECAST_INVALID';
    end if;
    with s as (
      select (case v_facet when 'currency' then (x."currency")::text when 'pipelineId' then (coalesce(x."pipeline_id"::text, ''))::text end) as v
      from "better_supabase"."forecast_snapshots" x
      where x."tenant_id" = page_forecast_snapshots.tenant
        and (not (v_filters -> 'pipelineId' is not null and jsonb_typeof(v_filters -> 'pipelineId') <> 'null' and not (jsonb_typeof(v_filters -> 'pipelineId') = 'array' and jsonb_array_length(v_filters -> 'pipelineId') = 0)) or x."pipeline_id" = any((case when jsonb_typeof(v_filters -> 'pipelineId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pipelineId')) else array[v_filters ->> 'pipelineId'] end)::uuid[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'since' is not null and jsonb_typeof(v_filters -> 'since') <> 'null' and not (jsonb_typeof(v_filters -> 'since') = 'array' and jsonb_array_length(v_filters -> 'since') = 0)) or x."period_start" = any((case when jsonb_typeof(v_filters -> 'since') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'since')) else array[v_filters ->> 'since'] end)::date[]))
        and (not (v_filters -> 'until' is not null and jsonb_typeof(v_filters -> 'until') <> 'null' and not (jsonb_typeof(v_filters -> 'until') = 'array' and jsonb_array_length(v_filters -> 'until') = 0)) or x."period_end" = any((case when jsonb_typeof(v_filters -> 'until') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'until')) else array[v_filters ->> 'until'] end)::date[]))
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
      select 1 from "better_supabase"."forecast_snapshots" x
      where x."tenant_id" = page_forecast_snapshots.tenant
        and (not (v_filters -> 'pipelineId' is not null and jsonb_typeof(v_filters -> 'pipelineId') <> 'null' and not (jsonb_typeof(v_filters -> 'pipelineId') = 'array' and jsonb_array_length(v_filters -> 'pipelineId') = 0)) or x."pipeline_id" = any((case when jsonb_typeof(v_filters -> 'pipelineId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pipelineId')) else array[v_filters ->> 'pipelineId'] end)::uuid[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'since' is not null and jsonb_typeof(v_filters -> 'since') <> 'null' and not (jsonb_typeof(v_filters -> 'since') = 'array' and jsonb_array_length(v_filters -> 'since') = 0)) or x."period_start" = any((case when jsonb_typeof(v_filters -> 'since') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'since')) else array[v_filters ->> 'since'] end)::date[]))
        and (not (v_filters -> 'until' is not null and jsonb_typeof(v_filters -> 'until') <> 'null' and not (jsonb_typeof(v_filters -> 'until') = 'array' and jsonb_array_length(v_filters -> 'until') = 0)) or x."period_end" = any((case when jsonb_typeof(v_filters -> 'until') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'until')) else array[v_filters ->> 'until'] end)::date[]))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('takenAt', 'since', 'dealCount') then
    raise exception 'sort is one of takenAt, since, dealCount' using errcode = '22023', hint = 'FORECAST_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'FORECAST_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'FORECAST_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'pipelineId', x."pipeline_id", 'since', x."period_start", 'until', x."period_end", 'currency', x."currency", 'target', x."target"::text, 'totals', x."totals", 'dealCount', x."deal_count", 'takenBy', x."taken_by", 'takenAt', x."taken_at") as j, jsonb_build_array((x."taken_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."forecast_snapshots" x
      where x."tenant_id" = page_forecast_snapshots.tenant
        and (not (v_filters -> 'pipelineId' is not null and jsonb_typeof(v_filters -> 'pipelineId') <> 'null' and not (jsonb_typeof(v_filters -> 'pipelineId') = 'array' and jsonb_array_length(v_filters -> 'pipelineId') = 0)) or x."pipeline_id" = any((case when jsonb_typeof(v_filters -> 'pipelineId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pipelineId')) else array[v_filters ->> 'pipelineId'] end)::uuid[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'since' is not null and jsonb_typeof(v_filters -> 'since') <> 'null' and not (jsonb_typeof(v_filters -> 'since') = 'array' and jsonb_array_length(v_filters -> 'since') = 0)) or x."period_start" = any((case when jsonb_typeof(v_filters -> 'since') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'since')) else array[v_filters ->> 'since'] end)::date[]))
        and (not (v_filters -> 'until' is not null and jsonb_typeof(v_filters -> 'until') <> 'null' and not (jsonb_typeof(v_filters -> 'until') = 'array' and jsonb_array_length(v_filters -> 'until') = 0)) or x."period_end" = any((case when jsonb_typeof(v_filters -> 'until') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'until')) else array[v_filters ->> 'until'] end)::date[]))
        and (v_after is null or (x."taken_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."taken_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'FORECAST_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'pipelineId', x."pipeline_id", 'since', x."period_start", 'until', x."period_end", 'currency', x."currency", 'target', x."target"::text, 'totals', x."totals", 'dealCount', x."deal_count", 'takenBy', x."taken_by", 'takenAt', x."taken_at") as j, jsonb_build_array((x."taken_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."forecast_snapshots" x
      where x."tenant_id" = page_forecast_snapshots.tenant
        and (not (v_filters -> 'pipelineId' is not null and jsonb_typeof(v_filters -> 'pipelineId') <> 'null' and not (jsonb_typeof(v_filters -> 'pipelineId') = 'array' and jsonb_array_length(v_filters -> 'pipelineId') = 0)) or x."pipeline_id" = any((case when jsonb_typeof(v_filters -> 'pipelineId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pipelineId')) else array[v_filters ->> 'pipelineId'] end)::uuid[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'since' is not null and jsonb_typeof(v_filters -> 'since') <> 'null' and not (jsonb_typeof(v_filters -> 'since') = 'array' and jsonb_array_length(v_filters -> 'since') = 0)) or x."period_start" = any((case when jsonb_typeof(v_filters -> 'since') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'since')) else array[v_filters ->> 'since'] end)::date[]))
        and (not (v_filters -> 'until' is not null and jsonb_typeof(v_filters -> 'until') <> 'null' and not (jsonb_typeof(v_filters -> 'until') = 'array' and jsonb_array_length(v_filters -> 'until') = 0)) or x."period_end" = any((case when jsonb_typeof(v_filters -> 'until') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'until')) else array[v_filters ->> 'until'] end)::date[]))
        and (v_after is null or (x."taken_at" <= (v_after ->> 0)::timestamptz and ((x."taken_at" < (v_after ->> 0)::timestamptz) or (x."taken_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."taken_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'takenAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'FORECAST_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'pipelineId', x."pipeline_id", 'since', x."period_start", 'until', x."period_end", 'currency', x."currency", 'target', x."target"::text, 'totals', x."totals", 'dealCount', x."deal_count", 'takenBy', x."taken_by", 'takenAt', x."taken_at") as j, jsonb_build_array((x."taken_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."forecast_snapshots" x
      where x."tenant_id" = page_forecast_snapshots.tenant
        and (not (v_filters -> 'pipelineId' is not null and jsonb_typeof(v_filters -> 'pipelineId') <> 'null' and not (jsonb_typeof(v_filters -> 'pipelineId') = 'array' and jsonb_array_length(v_filters -> 'pipelineId') = 0)) or x."pipeline_id" = any((case when jsonb_typeof(v_filters -> 'pipelineId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pipelineId')) else array[v_filters ->> 'pipelineId'] end)::uuid[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'since' is not null and jsonb_typeof(v_filters -> 'since') <> 'null' and not (jsonb_typeof(v_filters -> 'since') = 'array' and jsonb_array_length(v_filters -> 'since') = 0)) or x."period_start" = any((case when jsonb_typeof(v_filters -> 'since') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'since')) else array[v_filters ->> 'since'] end)::date[]))
        and (not (v_filters -> 'until' is not null and jsonb_typeof(v_filters -> 'until') <> 'null' and not (jsonb_typeof(v_filters -> 'until') = 'array' and jsonb_array_length(v_filters -> 'until') = 0)) or x."period_end" = any((case when jsonb_typeof(v_filters -> 'until') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'until')) else array[v_filters ->> 'until'] end)::date[]))
        and (v_after is null or (x."taken_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."taken_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'takenAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'FORECAST_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'pipelineId', x."pipeline_id", 'since', x."period_start", 'until', x."period_end", 'currency', x."currency", 'target', x."target"::text, 'totals', x."totals", 'dealCount', x."deal_count", 'takenBy', x."taken_by", 'takenAt', x."taken_at") as j, jsonb_build_array((x."taken_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."forecast_snapshots" x
      where x."tenant_id" = page_forecast_snapshots.tenant
        and (not (v_filters -> 'pipelineId' is not null and jsonb_typeof(v_filters -> 'pipelineId') <> 'null' and not (jsonb_typeof(v_filters -> 'pipelineId') = 'array' and jsonb_array_length(v_filters -> 'pipelineId') = 0)) or x."pipeline_id" = any((case when jsonb_typeof(v_filters -> 'pipelineId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pipelineId')) else array[v_filters ->> 'pipelineId'] end)::uuid[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'since' is not null and jsonb_typeof(v_filters -> 'since') <> 'null' and not (jsonb_typeof(v_filters -> 'since') = 'array' and jsonb_array_length(v_filters -> 'since') = 0)) or x."period_start" = any((case when jsonb_typeof(v_filters -> 'since') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'since')) else array[v_filters ->> 'since'] end)::date[]))
        and (not (v_filters -> 'until' is not null and jsonb_typeof(v_filters -> 'until') <> 'null' and not (jsonb_typeof(v_filters -> 'until') = 'array' and jsonb_array_length(v_filters -> 'until') = 0)) or x."period_end" = any((case when jsonb_typeof(v_filters -> 'until') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'until')) else array[v_filters ->> 'until'] end)::date[]))
        and (v_after is null or (x."taken_at" <= (v_after ->> 0)::timestamptz and ((x."taken_at" < (v_after ->> 0)::timestamptz) or (x."taken_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."taken_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'since' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'FORECAST_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'pipelineId', x."pipeline_id", 'since', x."period_start", 'until', x."period_end", 'currency', x."currency", 'target', x."target"::text, 'totals', x."totals", 'dealCount', x."deal_count", 'takenBy', x."taken_by", 'takenAt', x."taken_at") as j, jsonb_build_array((x."period_start")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."forecast_snapshots" x
      where x."tenant_id" = page_forecast_snapshots.tenant
        and (not (v_filters -> 'pipelineId' is not null and jsonb_typeof(v_filters -> 'pipelineId') <> 'null' and not (jsonb_typeof(v_filters -> 'pipelineId') = 'array' and jsonb_array_length(v_filters -> 'pipelineId') = 0)) or x."pipeline_id" = any((case when jsonb_typeof(v_filters -> 'pipelineId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pipelineId')) else array[v_filters ->> 'pipelineId'] end)::uuid[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'since' is not null and jsonb_typeof(v_filters -> 'since') <> 'null' and not (jsonb_typeof(v_filters -> 'since') = 'array' and jsonb_array_length(v_filters -> 'since') = 0)) or x."period_start" = any((case when jsonb_typeof(v_filters -> 'since') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'since')) else array[v_filters ->> 'since'] end)::date[]))
        and (not (v_filters -> 'until' is not null and jsonb_typeof(v_filters -> 'until') <> 'null' and not (jsonb_typeof(v_filters -> 'until') = 'array' and jsonb_array_length(v_filters -> 'until') = 0)) or x."period_end" = any((case when jsonb_typeof(v_filters -> 'until') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'until')) else array[v_filters ->> 'until'] end)::date[]))
        and (v_after is null or (x."period_start", x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by x."period_start" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'since' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'FORECAST_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'pipelineId', x."pipeline_id", 'since', x."period_start", 'until', x."period_end", 'currency', x."currency", 'target', x."target"::text, 'totals', x."totals", 'dealCount', x."deal_count", 'takenBy', x."taken_by", 'takenAt', x."taken_at") as j, jsonb_build_array((x."period_start")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."forecast_snapshots" x
      where x."tenant_id" = page_forecast_snapshots.tenant
        and (not (v_filters -> 'pipelineId' is not null and jsonb_typeof(v_filters -> 'pipelineId') <> 'null' and not (jsonb_typeof(v_filters -> 'pipelineId') = 'array' and jsonb_array_length(v_filters -> 'pipelineId') = 0)) or x."pipeline_id" = any((case when jsonb_typeof(v_filters -> 'pipelineId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pipelineId')) else array[v_filters ->> 'pipelineId'] end)::uuid[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'since' is not null and jsonb_typeof(v_filters -> 'since') <> 'null' and not (jsonb_typeof(v_filters -> 'since') = 'array' and jsonb_array_length(v_filters -> 'since') = 0)) or x."period_start" = any((case when jsonb_typeof(v_filters -> 'since') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'since')) else array[v_filters ->> 'since'] end)::date[]))
        and (not (v_filters -> 'until' is not null and jsonb_typeof(v_filters -> 'until') <> 'null' and not (jsonb_typeof(v_filters -> 'until') = 'array' and jsonb_array_length(v_filters -> 'until') = 0)) or x."period_end" = any((case when jsonb_typeof(v_filters -> 'until') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'until')) else array[v_filters ->> 'until'] end)::date[]))
        and (v_after is null or (x."period_start" <= (v_after ->> 0)::date and ((x."period_start" < (v_after ->> 0)::date) or (x."period_start" = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by x."period_start" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'dealCount' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'FORECAST_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'pipelineId', x."pipeline_id", 'since', x."period_start", 'until', x."period_end", 'currency', x."currency", 'target', x."target"::text, 'totals', x."totals", 'dealCount', x."deal_count", 'takenBy', x."taken_by", 'takenAt', x."taken_at") as j, jsonb_build_array((x."deal_count")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."forecast_snapshots" x
      where x."tenant_id" = page_forecast_snapshots.tenant
        and (not (v_filters -> 'pipelineId' is not null and jsonb_typeof(v_filters -> 'pipelineId') <> 'null' and not (jsonb_typeof(v_filters -> 'pipelineId') = 'array' and jsonb_array_length(v_filters -> 'pipelineId') = 0)) or x."pipeline_id" = any((case when jsonb_typeof(v_filters -> 'pipelineId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pipelineId')) else array[v_filters ->> 'pipelineId'] end)::uuid[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'since' is not null and jsonb_typeof(v_filters -> 'since') <> 'null' and not (jsonb_typeof(v_filters -> 'since') = 'array' and jsonb_array_length(v_filters -> 'since') = 0)) or x."period_start" = any((case when jsonb_typeof(v_filters -> 'since') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'since')) else array[v_filters ->> 'since'] end)::date[]))
        and (not (v_filters -> 'until' is not null and jsonb_typeof(v_filters -> 'until') <> 'null' and not (jsonb_typeof(v_filters -> 'until') = 'array' and jsonb_array_length(v_filters -> 'until') = 0)) or x."period_end" = any((case when jsonb_typeof(v_filters -> 'until') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'until')) else array[v_filters ->> 'until'] end)::date[]))
        and (v_after is null or (x."deal_count", x."id") > ((v_after ->> 0)::integer, (v_after ->> 1)::uuid))
      order by x."deal_count" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'dealCount' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'FORECAST_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'pipelineId', x."pipeline_id", 'since', x."period_start", 'until', x."period_end", 'currency', x."currency", 'target', x."target"::text, 'totals', x."totals", 'dealCount', x."deal_count", 'takenBy', x."taken_by", 'takenAt', x."taken_at") as j, jsonb_build_array((x."deal_count")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."forecast_snapshots" x
      where x."tenant_id" = page_forecast_snapshots.tenant
        and (not (v_filters -> 'pipelineId' is not null and jsonb_typeof(v_filters -> 'pipelineId') <> 'null' and not (jsonb_typeof(v_filters -> 'pipelineId') = 'array' and jsonb_array_length(v_filters -> 'pipelineId') = 0)) or x."pipeline_id" = any((case when jsonb_typeof(v_filters -> 'pipelineId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pipelineId')) else array[v_filters ->> 'pipelineId'] end)::uuid[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'since' is not null and jsonb_typeof(v_filters -> 'since') <> 'null' and not (jsonb_typeof(v_filters -> 'since') = 'array' and jsonb_array_length(v_filters -> 'since') = 0)) or x."period_start" = any((case when jsonb_typeof(v_filters -> 'since') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'since')) else array[v_filters ->> 'since'] end)::date[]))
        and (not (v_filters -> 'until' is not null and jsonb_typeof(v_filters -> 'until') <> 'null' and not (jsonb_typeof(v_filters -> 'until') = 'array' and jsonb_array_length(v_filters -> 'until') = 0)) or x."period_end" = any((case when jsonb_typeof(v_filters -> 'until') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'until')) else array[v_filters ->> 'until'] end)::date[]))
        and (v_after is null or (x."deal_count" <= (v_after ->> 0)::integer and ((x."deal_count" < (v_after ->> 0)::integer) or (x."deal_count" = (v_after ->> 0)::integer and x."id" > (v_after ->> 1)::uuid))))
      order by x."deal_count" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."forecast_snapshots" x
      where x."tenant_id" = page_forecast_snapshots.tenant
        and (not (v_filters -> 'pipelineId' is not null and jsonb_typeof(v_filters -> 'pipelineId') <> 'null' and not (jsonb_typeof(v_filters -> 'pipelineId') = 'array' and jsonb_array_length(v_filters -> 'pipelineId') = 0)) or x."pipeline_id" = any((case when jsonb_typeof(v_filters -> 'pipelineId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pipelineId')) else array[v_filters ->> 'pipelineId'] end)::uuid[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'since' is not null and jsonb_typeof(v_filters -> 'since') <> 'null' and not (jsonb_typeof(v_filters -> 'since') = 'array' and jsonb_array_length(v_filters -> 'since') = 0)) or x."period_start" = any((case when jsonb_typeof(v_filters -> 'since') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'since')) else array[v_filters ->> 'since'] end)::date[]))
        and (not (v_filters -> 'until' is not null and jsonb_typeof(v_filters -> 'until') <> 'null' and not (jsonb_typeof(v_filters -> 'until') = 'array' and jsonb_array_length(v_filters -> 'until') = 0)) or x."period_end" = any((case when jsonb_typeof(v_filters -> 'until') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'until')) else array[v_filters ->> 'until'] end)::date[]))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_mail_accounts (
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
  v_filters jsonb := coalesce(page_mail_accounts.filters, '{}'::jsonb);
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
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'MAIL_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'provider', 'share') then
      raise exception 'facet is one of status, provider, share' using errcode = '22023', hint = 'MAIL_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'provider' then (x."provider")::text when 'share' then (x."share")::text end) as v
      from "better_supabase"."mail_accounts" x
      where x."tenant_id" = page_mail_accounts.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
        and (not (v_filters -> 'share' is not null and jsonb_typeof(v_filters -> 'share') <> 'null' and not (jsonb_typeof(v_filters -> 'share') = 'array' and jsonb_array_length(v_filters -> 'share') = 0)) or x."share" = any((case when jsonb_typeof(v_filters -> 'share') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'share')) else array[v_filters ->> 'share'] end)::text[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (v_search is null or x."address" ilike v_search)
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
      select 1 from "better_supabase"."mail_accounts" x
      where x."tenant_id" = page_mail_accounts.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
        and (not (v_filters -> 'share' is not null and jsonb_typeof(v_filters -> 'share') <> 'null' and not (jsonb_typeof(v_filters -> 'share') = 'array' and jsonb_array_length(v_filters -> 'share') = 0)) or x."share" = any((case when jsonb_typeof(v_filters -> 'share') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'share')) else array[v_filters ->> 'share'] end)::text[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (v_search is null or x."address" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('address', 'createdAt') then
    raise exception 'sort is one of address, createdAt' using errcode = '22023', hint = 'MAIL_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'MAIL_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((lower(x."address"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."mail_accounts" x
      where x."tenant_id" = page_mail_accounts.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
        and (not (v_filters -> 'share' is not null and jsonb_typeof(v_filters -> 'share') <> 'null' and not (jsonb_typeof(v_filters -> 'share') = 'array' and jsonb_array_length(v_filters -> 'share') = 0)) or x."share" = any((case when jsonb_typeof(v_filters -> 'share') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'share')) else array[v_filters ->> 'share'] end)::text[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (v_search is null or x."address" ilike v_search)
        and (v_after is null or (lower(x."address"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."address") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((lower(x."address"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."mail_accounts" x
      where x."tenant_id" = page_mail_accounts.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
        and (not (v_filters -> 'share' is not null and jsonb_typeof(v_filters -> 'share') <> 'null' and not (jsonb_typeof(v_filters -> 'share') = 'array' and jsonb_array_length(v_filters -> 'share') = 0)) or x."share" = any((case when jsonb_typeof(v_filters -> 'share') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'share')) else array[v_filters ->> 'share'] end)::text[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (v_search is null or x."address" ilike v_search)
        and (v_after is null or (lower(x."address") <= (v_after ->> 0)::text and ((lower(x."address") < (v_after ->> 0)::text) or (lower(x."address") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."address") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'address' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((lower(x."address"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."mail_accounts" x
      where x."tenant_id" = page_mail_accounts.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
        and (not (v_filters -> 'share' is not null and jsonb_typeof(v_filters -> 'share') <> 'null' and not (jsonb_typeof(v_filters -> 'share') = 'array' and jsonb_array_length(v_filters -> 'share') = 0)) or x."share" = any((case when jsonb_typeof(v_filters -> 'share') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'share')) else array[v_filters ->> 'share'] end)::text[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (v_search is null or x."address" ilike v_search)
        and (v_after is null or (lower(x."address"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."address") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'address' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((lower(x."address"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."mail_accounts" x
      where x."tenant_id" = page_mail_accounts.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
        and (not (v_filters -> 'share' is not null and jsonb_typeof(v_filters -> 'share') <> 'null' and not (jsonb_typeof(v_filters -> 'share') = 'array' and jsonb_array_length(v_filters -> 'share') = 0)) or x."share" = any((case when jsonb_typeof(v_filters -> 'share') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'share')) else array[v_filters ->> 'share'] end)::text[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (v_search is null or x."address" ilike v_search)
        and (v_after is null or (lower(x."address") <= (v_after ->> 0)::text and ((lower(x."address") < (v_after ->> 0)::text) or (lower(x."address") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."address") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."mail_accounts" x
      where x."tenant_id" = page_mail_accounts.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
        and (not (v_filters -> 'share' is not null and jsonb_typeof(v_filters -> 'share') <> 'null' and not (jsonb_typeof(v_filters -> 'share') = 'array' and jsonb_array_length(v_filters -> 'share') = 0)) or x."share" = any((case when jsonb_typeof(v_filters -> 'share') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'share')) else array[v_filters ->> 'share'] end)::text[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (v_search is null or x."address" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."mail_accounts" x
      where x."tenant_id" = page_mail_accounts.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
        and (not (v_filters -> 'share' is not null and jsonb_typeof(v_filters -> 'share') <> 'null' and not (jsonb_typeof(v_filters -> 'share') = 'array' and jsonb_array_length(v_filters -> 'share') = 0)) or x."share" = any((case when jsonb_typeof(v_filters -> 'share') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'share')) else array[v_filters ->> 'share'] end)::text[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (v_search is null or x."address" ilike v_search)
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
      select 1 from "better_supabase"."mail_accounts" x
      where x."tenant_id" = page_mail_accounts.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
        and (not (v_filters -> 'share' is not null and jsonb_typeof(v_filters -> 'share') <> 'null' and not (jsonb_typeof(v_filters -> 'share') = 'array' and jsonb_array_length(v_filters -> 'share') = 0)) or x."share" = any((case when jsonb_typeof(v_filters -> 'share') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'share')) else array[v_filters ->> 'share'] end)::text[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (v_search is null or x."address" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_mail_threads (
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
  v_filters jsonb := coalesce(page_mail_threads.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 25), 1), 100);
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
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'MAIL_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('accountId') then
      raise exception 'facet is one of accountId' using errcode = '22023', hint = 'MAIL_INVALID';
    end if;
    with s as (
      select (case v_facet when 'accountId' then (x."account_id"::text)::text end) as v
      from "better_supabase"."mail_threads" x
      where x."tenant_id" = page_mail_threads.tenant
        and (not (v_filters -> 'accountId' is not null and jsonb_typeof(v_filters -> 'accountId') <> 'null' and not (jsonb_typeof(v_filters -> 'accountId') = 'array' and jsonb_array_length(v_filters -> 'accountId') = 0)) or x."account_id" = any((case when jsonb_typeof(v_filters -> 'accountId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'accountId')) else array[v_filters ->> 'accountId'] end)::uuid[]))
        and (nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '') is null or exists (select 1 from "better_supabase"."mail_thread_subjects" s where s."thread_id" = x."id" and s."subject_type" = nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '') and (nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), '') is null or s."subject_id" = nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), ''))))
        and (v_search is null or x."subject" ilike v_search or x."snippet" ilike v_search)
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
      select 1 from "better_supabase"."mail_threads" x
      where x."tenant_id" = page_mail_threads.tenant
        and (not (v_filters -> 'accountId' is not null and jsonb_typeof(v_filters -> 'accountId') <> 'null' and not (jsonb_typeof(v_filters -> 'accountId') = 'array' and jsonb_array_length(v_filters -> 'accountId') = 0)) or x."account_id" = any((case when jsonb_typeof(v_filters -> 'accountId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'accountId')) else array[v_filters ->> 'accountId'] end)::uuid[]))
        and (nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '') is null or exists (select 1 from "better_supabase"."mail_thread_subjects" s where s."thread_id" = x."id" and s."subject_type" = nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '') and (nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), '') is null or s."subject_id" = nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), ''))))
        and (v_search is null or x."subject" ilike v_search or x."snippet" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('lastMessageAt', 'subject', 'messageCount') then
    raise exception 'sort is one of lastMessageAt, subject, messageCount' using errcode = '22023', hint = 'MAIL_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'MAIL_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('address', (select k."address" from "better_supabase"."mail_accounts" k where k."id" = x."account_id"), 'subjects', coalesce((select jsonb_agg(jsonb_build_object('type', s."subject_type", 'id', s."subject_id") order by s."created_at", s."subject_type", s."subject_id") from "better_supabase"."mail_thread_subjects" s where s."thread_id" = x."id"), '[]'::jsonb)) as j, jsonb_build_array((x."last_message_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."mail_threads" x
      where x."tenant_id" = page_mail_threads.tenant
        and (not (v_filters -> 'accountId' is not null and jsonb_typeof(v_filters -> 'accountId') <> 'null' and not (jsonb_typeof(v_filters -> 'accountId') = 'array' and jsonb_array_length(v_filters -> 'accountId') = 0)) or x."account_id" = any((case when jsonb_typeof(v_filters -> 'accountId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'accountId')) else array[v_filters ->> 'accountId'] end)::uuid[]))
        and (nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '') is null or exists (select 1 from "better_supabase"."mail_thread_subjects" s where s."thread_id" = x."id" and s."subject_type" = nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '') and (nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), '') is null or s."subject_id" = nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), ''))))
        and (v_search is null or x."subject" ilike v_search or x."snippet" ilike v_search)
        and (v_after is null or (x."last_message_at" >= (v_after ->> 0)::timestamptz and ((x."last_message_at" > (v_after ->> 0)::timestamptz) or (x."last_message_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."last_message_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('address', (select k."address" from "better_supabase"."mail_accounts" k where k."id" = x."account_id"), 'subjects', coalesce((select jsonb_agg(jsonb_build_object('type', s."subject_type", 'id', s."subject_id") order by s."created_at", s."subject_type", s."subject_id") from "better_supabase"."mail_thread_subjects" s where s."thread_id" = x."id"), '[]'::jsonb)) as j, jsonb_build_array((x."last_message_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."mail_threads" x
      where x."tenant_id" = page_mail_threads.tenant
        and (not (v_filters -> 'accountId' is not null and jsonb_typeof(v_filters -> 'accountId') <> 'null' and not (jsonb_typeof(v_filters -> 'accountId') = 'array' and jsonb_array_length(v_filters -> 'accountId') = 0)) or x."account_id" = any((case when jsonb_typeof(v_filters -> 'accountId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'accountId')) else array[v_filters ->> 'accountId'] end)::uuid[]))
        and (nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '') is null or exists (select 1 from "better_supabase"."mail_thread_subjects" s where s."thread_id" = x."id" and s."subject_type" = nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '') and (nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), '') is null or s."subject_id" = nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), ''))))
        and (v_search is null or x."subject" ilike v_search or x."snippet" ilike v_search)
        and (v_after is null or (x."last_message_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."last_message_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'lastMessageAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('address', (select k."address" from "better_supabase"."mail_accounts" k where k."id" = x."account_id"), 'subjects', coalesce((select jsonb_agg(jsonb_build_object('type', s."subject_type", 'id', s."subject_id") order by s."created_at", s."subject_type", s."subject_id") from "better_supabase"."mail_thread_subjects" s where s."thread_id" = x."id"), '[]'::jsonb)) as j, jsonb_build_array((x."last_message_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."mail_threads" x
      where x."tenant_id" = page_mail_threads.tenant
        and (not (v_filters -> 'accountId' is not null and jsonb_typeof(v_filters -> 'accountId') <> 'null' and not (jsonb_typeof(v_filters -> 'accountId') = 'array' and jsonb_array_length(v_filters -> 'accountId') = 0)) or x."account_id" = any((case when jsonb_typeof(v_filters -> 'accountId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'accountId')) else array[v_filters ->> 'accountId'] end)::uuid[]))
        and (nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '') is null or exists (select 1 from "better_supabase"."mail_thread_subjects" s where s."thread_id" = x."id" and s."subject_type" = nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '') and (nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), '') is null or s."subject_id" = nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), ''))))
        and (v_search is null or x."subject" ilike v_search or x."snippet" ilike v_search)
        and (v_after is null or (x."last_message_at" >= (v_after ->> 0)::timestamptz and ((x."last_message_at" > (v_after ->> 0)::timestamptz) or (x."last_message_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."last_message_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'lastMessageAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('address', (select k."address" from "better_supabase"."mail_accounts" k where k."id" = x."account_id"), 'subjects', coalesce((select jsonb_agg(jsonb_build_object('type', s."subject_type", 'id', s."subject_id") order by s."created_at", s."subject_type", s."subject_id") from "better_supabase"."mail_thread_subjects" s where s."thread_id" = x."id"), '[]'::jsonb)) as j, jsonb_build_array((x."last_message_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."mail_threads" x
      where x."tenant_id" = page_mail_threads.tenant
        and (not (v_filters -> 'accountId' is not null and jsonb_typeof(v_filters -> 'accountId') <> 'null' and not (jsonb_typeof(v_filters -> 'accountId') = 'array' and jsonb_array_length(v_filters -> 'accountId') = 0)) or x."account_id" = any((case when jsonb_typeof(v_filters -> 'accountId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'accountId')) else array[v_filters ->> 'accountId'] end)::uuid[]))
        and (nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '') is null or exists (select 1 from "better_supabase"."mail_thread_subjects" s where s."thread_id" = x."id" and s."subject_type" = nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '') and (nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), '') is null or s."subject_id" = nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), ''))))
        and (v_search is null or x."subject" ilike v_search or x."snippet" ilike v_search)
        and (v_after is null or (x."last_message_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."last_message_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'subject' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('address', (select k."address" from "better_supabase"."mail_accounts" k where k."id" = x."account_id"), 'subjects', coalesce((select jsonb_agg(jsonb_build_object('type', s."subject_type", 'id', s."subject_id") order by s."created_at", s."subject_type", s."subject_id") from "better_supabase"."mail_thread_subjects" s where s."thread_id" = x."id"), '[]'::jsonb)) as j, jsonb_build_array((lower(coalesce(x."subject", '')))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."mail_threads" x
      where x."tenant_id" = page_mail_threads.tenant
        and (not (v_filters -> 'accountId' is not null and jsonb_typeof(v_filters -> 'accountId') <> 'null' and not (jsonb_typeof(v_filters -> 'accountId') = 'array' and jsonb_array_length(v_filters -> 'accountId') = 0)) or x."account_id" = any((case when jsonb_typeof(v_filters -> 'accountId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'accountId')) else array[v_filters ->> 'accountId'] end)::uuid[]))
        and (nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '') is null or exists (select 1 from "better_supabase"."mail_thread_subjects" s where s."thread_id" = x."id" and s."subject_type" = nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '') and (nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), '') is null or s."subject_id" = nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), ''))))
        and (v_search is null or x."subject" ilike v_search or x."snippet" ilike v_search)
        and (v_after is null or (lower(coalesce(x."subject", '')), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(coalesce(x."subject", '')) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'subject' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('address', (select k."address" from "better_supabase"."mail_accounts" k where k."id" = x."account_id"), 'subjects', coalesce((select jsonb_agg(jsonb_build_object('type', s."subject_type", 'id', s."subject_id") order by s."created_at", s."subject_type", s."subject_id") from "better_supabase"."mail_thread_subjects" s where s."thread_id" = x."id"), '[]'::jsonb)) as j, jsonb_build_array((lower(coalesce(x."subject", '')))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."mail_threads" x
      where x."tenant_id" = page_mail_threads.tenant
        and (not (v_filters -> 'accountId' is not null and jsonb_typeof(v_filters -> 'accountId') <> 'null' and not (jsonb_typeof(v_filters -> 'accountId') = 'array' and jsonb_array_length(v_filters -> 'accountId') = 0)) or x."account_id" = any((case when jsonb_typeof(v_filters -> 'accountId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'accountId')) else array[v_filters ->> 'accountId'] end)::uuid[]))
        and (nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '') is null or exists (select 1 from "better_supabase"."mail_thread_subjects" s where s."thread_id" = x."id" and s."subject_type" = nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '') and (nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), '') is null or s."subject_id" = nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), ''))))
        and (v_search is null or x."subject" ilike v_search or x."snippet" ilike v_search)
        and (v_after is null or (lower(coalesce(x."subject", '')) <= (v_after ->> 0)::text and ((lower(coalesce(x."subject", '')) < (v_after ->> 0)::text) or (lower(coalesce(x."subject", '')) = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(coalesce(x."subject", '')) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'messageCount' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('address', (select k."address" from "better_supabase"."mail_accounts" k where k."id" = x."account_id"), 'subjects', coalesce((select jsonb_agg(jsonb_build_object('type', s."subject_type", 'id', s."subject_id") order by s."created_at", s."subject_type", s."subject_id") from "better_supabase"."mail_thread_subjects" s where s."thread_id" = x."id"), '[]'::jsonb)) as j, jsonb_build_array((x."message_count")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."mail_threads" x
      where x."tenant_id" = page_mail_threads.tenant
        and (not (v_filters -> 'accountId' is not null and jsonb_typeof(v_filters -> 'accountId') <> 'null' and not (jsonb_typeof(v_filters -> 'accountId') = 'array' and jsonb_array_length(v_filters -> 'accountId') = 0)) or x."account_id" = any((case when jsonb_typeof(v_filters -> 'accountId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'accountId')) else array[v_filters ->> 'accountId'] end)::uuid[]))
        and (nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '') is null or exists (select 1 from "better_supabase"."mail_thread_subjects" s where s."thread_id" = x."id" and s."subject_type" = nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '') and (nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), '') is null or s."subject_id" = nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), ''))))
        and (v_search is null or x."subject" ilike v_search or x."snippet" ilike v_search)
        and (v_after is null or (x."message_count" >= (v_after ->> 0)::integer and ((x."message_count" > (v_after ->> 0)::integer) or (x."message_count" = (v_after ->> 0)::integer and x."id" < (v_after ->> 1)::uuid))))
      order by x."message_count" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'messageCount' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('address', (select k."address" from "better_supabase"."mail_accounts" k where k."id" = x."account_id"), 'subjects', coalesce((select jsonb_agg(jsonb_build_object('type', s."subject_type", 'id', s."subject_id") order by s."created_at", s."subject_type", s."subject_id") from "better_supabase"."mail_thread_subjects" s where s."thread_id" = x."id"), '[]'::jsonb)) as j, jsonb_build_array((x."message_count")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."mail_threads" x
      where x."tenant_id" = page_mail_threads.tenant
        and (not (v_filters -> 'accountId' is not null and jsonb_typeof(v_filters -> 'accountId') <> 'null' and not (jsonb_typeof(v_filters -> 'accountId') = 'array' and jsonb_array_length(v_filters -> 'accountId') = 0)) or x."account_id" = any((case when jsonb_typeof(v_filters -> 'accountId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'accountId')) else array[v_filters ->> 'accountId'] end)::uuid[]))
        and (nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '') is null or exists (select 1 from "better_supabase"."mail_thread_subjects" s where s."thread_id" = x."id" and s."subject_type" = nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '') and (nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), '') is null or s."subject_id" = nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), ''))))
        and (v_search is null or x."subject" ilike v_search or x."snippet" ilike v_search)
        and (v_after is null or (x."message_count", x."id") < ((v_after ->> 0)::integer, (v_after ->> 1)::uuid))
      order by x."message_count" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."mail_threads" x
      where x."tenant_id" = page_mail_threads.tenant
        and (not (v_filters -> 'accountId' is not null and jsonb_typeof(v_filters -> 'accountId') <> 'null' and not (jsonb_typeof(v_filters -> 'accountId') = 'array' and jsonb_array_length(v_filters -> 'accountId') = 0)) or x."account_id" = any((case when jsonb_typeof(v_filters -> 'accountId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'accountId')) else array[v_filters ->> 'accountId'] end)::uuid[]))
        and (nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '') is null or exists (select 1 from "better_supabase"."mail_thread_subjects" s where s."thread_id" = x."id" and s."subject_type" = nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '') and (nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), '') is null or s."subject_id" = nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), ''))))
        and (v_search is null or x."subject" ilike v_search or x."snippet" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_people (
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
  v_filters jsonb := coalesce(page_people.filters, '{}'::jsonb);
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
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'PARTY_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('lifecycle', 'ownerId', 'supplierStatus') then
      raise exception 'facet is one of lifecycle, ownerId, supplierStatus' using errcode = '22023', hint = 'PARTY_INVALID';
    end if;
    with s as (
      select (case v_facet when 'lifecycle' then (x."lifecycle")::text when 'ownerId' then (coalesce(x."owner_id"::text, ''))::text when 'supplierStatus' then (coalesce(x."supplier_status"::text, ''))::text end) as v
      from "better_supabase"."people" x
      where x."tenant_id" = page_people.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'lifecycle' is not null and jsonb_typeof(v_filters -> 'lifecycle') <> 'null' and not (jsonb_typeof(v_filters -> 'lifecycle') = 'array' and jsonb_array_length(v_filters -> 'lifecycle') = 0)) or x."lifecycle" = any((case when jsonb_typeof(v_filters -> 'lifecycle') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'lifecycle')) else array[v_filters ->> 'lifecycle'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'role') = 'array' then v_filters -> 'role' else jsonb_build_array(v_filters ->> 'role') end) r where r = any (x."roles")))
        and (not (v_filters -> 'supplierStatus' is not null and jsonb_typeof(v_filters -> 'supplierStatus') <> 'null' and not (jsonb_typeof(v_filters -> 'supplierStatus') = 'array' and jsonb_array_length(v_filters -> 'supplierStatus') = 0)) or x."supplier_status"::text = any((case when jsonb_typeof(v_filters -> 'supplierStatus') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'supplierStatus')) else array[v_filters ->> 'supplierStatus'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search)
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
      select 1 from "better_supabase"."people" x
      where x."tenant_id" = page_people.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'lifecycle' is not null and jsonb_typeof(v_filters -> 'lifecycle') <> 'null' and not (jsonb_typeof(v_filters -> 'lifecycle') = 'array' and jsonb_array_length(v_filters -> 'lifecycle') = 0)) or x."lifecycle" = any((case when jsonb_typeof(v_filters -> 'lifecycle') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'lifecycle')) else array[v_filters ->> 'lifecycle'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'role') = 'array' then v_filters -> 'role' else jsonb_build_array(v_filters ->> 'role') end) r where r = any (x."roles")))
        and (not (v_filters -> 'supplierStatus' is not null and jsonb_typeof(v_filters -> 'supplierStatus') <> 'null' and not (jsonb_typeof(v_filters -> 'supplierStatus') = 'array' and jsonb_array_length(v_filters -> 'supplierStatus') = 0)) or x."supplier_status"::text = any((case when jsonb_typeof(v_filters -> 'supplierStatus') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'supplierStatus')) else array[v_filters ->> 'supplierStatus'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'createdAt', 'updatedAt') then
    raise exception 'sort is one of name, createdAt, updatedAt' using errcode = '22023', hint = 'PARTY_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'PARTY_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PARTY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('roles', x."roles", 'customer_terms_id', x."customer_terms_id", 'supplier_terms_id', x."supplier_terms_id", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'credit_block', x."credit_block", 'supplier_status', x."supplier_status", 'language', x."language") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."people" x
      where x."tenant_id" = page_people.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'lifecycle' is not null and jsonb_typeof(v_filters -> 'lifecycle') <> 'null' and not (jsonb_typeof(v_filters -> 'lifecycle') = 'array' and jsonb_array_length(v_filters -> 'lifecycle') = 0)) or x."lifecycle" = any((case when jsonb_typeof(v_filters -> 'lifecycle') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'lifecycle')) else array[v_filters ->> 'lifecycle'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'role') = 'array' then v_filters -> 'role' else jsonb_build_array(v_filters ->> 'role') end) r where r = any (x."roles")))
        and (not (v_filters -> 'supplierStatus' is not null and jsonb_typeof(v_filters -> 'supplierStatus') <> 'null' and not (jsonb_typeof(v_filters -> 'supplierStatus') = 'array' and jsonb_array_length(v_filters -> 'supplierStatus') = 0)) or x."supplier_status"::text = any((case when jsonb_typeof(v_filters -> 'supplierStatus') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'supplierStatus')) else array[v_filters ->> 'supplierStatus'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PARTY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('roles', x."roles", 'customer_terms_id', x."customer_terms_id", 'supplier_terms_id', x."supplier_terms_id", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'credit_block', x."credit_block", 'supplier_status', x."supplier_status", 'language', x."language") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."people" x
      where x."tenant_id" = page_people.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'lifecycle' is not null and jsonb_typeof(v_filters -> 'lifecycle') <> 'null' and not (jsonb_typeof(v_filters -> 'lifecycle') = 'array' and jsonb_array_length(v_filters -> 'lifecycle') = 0)) or x."lifecycle" = any((case when jsonb_typeof(v_filters -> 'lifecycle') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'lifecycle')) else array[v_filters ->> 'lifecycle'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'role') = 'array' then v_filters -> 'role' else jsonb_build_array(v_filters ->> 'role') end) r where r = any (x."roles")))
        and (not (v_filters -> 'supplierStatus' is not null and jsonb_typeof(v_filters -> 'supplierStatus') <> 'null' and not (jsonb_typeof(v_filters -> 'supplierStatus') = 'array' and jsonb_array_length(v_filters -> 'supplierStatus') = 0)) or x."supplier_status"::text = any((case when jsonb_typeof(v_filters -> 'supplierStatus') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'supplierStatus')) else array[v_filters ->> 'supplierStatus'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PARTY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('roles', x."roles", 'customer_terms_id', x."customer_terms_id", 'supplier_terms_id', x."supplier_terms_id", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'credit_block', x."credit_block", 'supplier_status', x."supplier_status", 'language', x."language") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."people" x
      where x."tenant_id" = page_people.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'lifecycle' is not null and jsonb_typeof(v_filters -> 'lifecycle') <> 'null' and not (jsonb_typeof(v_filters -> 'lifecycle') = 'array' and jsonb_array_length(v_filters -> 'lifecycle') = 0)) or x."lifecycle" = any((case when jsonb_typeof(v_filters -> 'lifecycle') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'lifecycle')) else array[v_filters ->> 'lifecycle'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'role') = 'array' then v_filters -> 'role' else jsonb_build_array(v_filters ->> 'role') end) r where r = any (x."roles")))
        and (not (v_filters -> 'supplierStatus' is not null and jsonb_typeof(v_filters -> 'supplierStatus') <> 'null' and not (jsonb_typeof(v_filters -> 'supplierStatus') = 'array' and jsonb_array_length(v_filters -> 'supplierStatus') = 0)) or x."supplier_status"::text = any((case when jsonb_typeof(v_filters -> 'supplierStatus') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'supplierStatus')) else array[v_filters ->> 'supplierStatus'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PARTY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('roles', x."roles", 'customer_terms_id', x."customer_terms_id", 'supplier_terms_id', x."supplier_terms_id", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'credit_block', x."credit_block", 'supplier_status', x."supplier_status", 'language', x."language") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."people" x
      where x."tenant_id" = page_people.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'lifecycle' is not null and jsonb_typeof(v_filters -> 'lifecycle') <> 'null' and not (jsonb_typeof(v_filters -> 'lifecycle') = 'array' and jsonb_array_length(v_filters -> 'lifecycle') = 0)) or x."lifecycle" = any((case when jsonb_typeof(v_filters -> 'lifecycle') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'lifecycle')) else array[v_filters ->> 'lifecycle'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'role') = 'array' then v_filters -> 'role' else jsonb_build_array(v_filters ->> 'role') end) r where r = any (x."roles")))
        and (not (v_filters -> 'supplierStatus' is not null and jsonb_typeof(v_filters -> 'supplierStatus') <> 'null' and not (jsonb_typeof(v_filters -> 'supplierStatus') = 'array' and jsonb_array_length(v_filters -> 'supplierStatus') = 0)) or x."supplier_status"::text = any((case when jsonb_typeof(v_filters -> 'supplierStatus') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'supplierStatus')) else array[v_filters ->> 'supplierStatus'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PARTY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('roles', x."roles", 'customer_terms_id', x."customer_terms_id", 'supplier_terms_id', x."supplier_terms_id", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'credit_block', x."credit_block", 'supplier_status', x."supplier_status", 'language', x."language") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."people" x
      where x."tenant_id" = page_people.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'lifecycle' is not null and jsonb_typeof(v_filters -> 'lifecycle') <> 'null' and not (jsonb_typeof(v_filters -> 'lifecycle') = 'array' and jsonb_array_length(v_filters -> 'lifecycle') = 0)) or x."lifecycle" = any((case when jsonb_typeof(v_filters -> 'lifecycle') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'lifecycle')) else array[v_filters ->> 'lifecycle'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'role') = 'array' then v_filters -> 'role' else jsonb_build_array(v_filters ->> 'role') end) r where r = any (x."roles")))
        and (not (v_filters -> 'supplierStatus' is not null and jsonb_typeof(v_filters -> 'supplierStatus') <> 'null' and not (jsonb_typeof(v_filters -> 'supplierStatus') = 'array' and jsonb_array_length(v_filters -> 'supplierStatus') = 0)) or x."supplier_status"::text = any((case when jsonb_typeof(v_filters -> 'supplierStatus') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'supplierStatus')) else array[v_filters ->> 'supplierStatus'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PARTY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('roles', x."roles", 'customer_terms_id', x."customer_terms_id", 'supplier_terms_id', x."supplier_terms_id", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'credit_block', x."credit_block", 'supplier_status', x."supplier_status", 'language', x."language") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."people" x
      where x."tenant_id" = page_people.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'lifecycle' is not null and jsonb_typeof(v_filters -> 'lifecycle') <> 'null' and not (jsonb_typeof(v_filters -> 'lifecycle') = 'array' and jsonb_array_length(v_filters -> 'lifecycle') = 0)) or x."lifecycle" = any((case when jsonb_typeof(v_filters -> 'lifecycle') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'lifecycle')) else array[v_filters ->> 'lifecycle'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'role') = 'array' then v_filters -> 'role' else jsonb_build_array(v_filters ->> 'role') end) r where r = any (x."roles")))
        and (not (v_filters -> 'supplierStatus' is not null and jsonb_typeof(v_filters -> 'supplierStatus') <> 'null' and not (jsonb_typeof(v_filters -> 'supplierStatus') = 'array' and jsonb_array_length(v_filters -> 'supplierStatus') = 0)) or x."supplier_status"::text = any((case when jsonb_typeof(v_filters -> 'supplierStatus') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'supplierStatus')) else array[v_filters ->> 'supplierStatus'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PARTY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('roles', x."roles", 'customer_terms_id', x."customer_terms_id", 'supplier_terms_id', x."supplier_terms_id", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'credit_block', x."credit_block", 'supplier_status', x."supplier_status", 'language', x."language") as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."people" x
      where x."tenant_id" = page_people.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'lifecycle' is not null and jsonb_typeof(v_filters -> 'lifecycle') <> 'null' and not (jsonb_typeof(v_filters -> 'lifecycle') = 'array' and jsonb_array_length(v_filters -> 'lifecycle') = 0)) or x."lifecycle" = any((case when jsonb_typeof(v_filters -> 'lifecycle') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'lifecycle')) else array[v_filters ->> 'lifecycle'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'role') = 'array' then v_filters -> 'role' else jsonb_build_array(v_filters ->> 'role') end) r where r = any (x."roles")))
        and (not (v_filters -> 'supplierStatus' is not null and jsonb_typeof(v_filters -> 'supplierStatus') <> 'null' and not (jsonb_typeof(v_filters -> 'supplierStatus') = 'array' and jsonb_array_length(v_filters -> 'supplierStatus') = 0)) or x."supplier_status"::text = any((case when jsonb_typeof(v_filters -> 'supplierStatus') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'supplierStatus')) else array[v_filters ->> 'supplierStatus'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search)
        and (v_after is null or (x."updated_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."updated_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PARTY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('roles', x."roles", 'customer_terms_id', x."customer_terms_id", 'supplier_terms_id', x."supplier_terms_id", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'credit_block', x."credit_block", 'supplier_status', x."supplier_status", 'language', x."language") as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."people" x
      where x."tenant_id" = page_people.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'lifecycle' is not null and jsonb_typeof(v_filters -> 'lifecycle') <> 'null' and not (jsonb_typeof(v_filters -> 'lifecycle') = 'array' and jsonb_array_length(v_filters -> 'lifecycle') = 0)) or x."lifecycle" = any((case when jsonb_typeof(v_filters -> 'lifecycle') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'lifecycle')) else array[v_filters ->> 'lifecycle'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'role') = 'array' then v_filters -> 'role' else jsonb_build_array(v_filters ->> 'role') end) r where r = any (x."roles")))
        and (not (v_filters -> 'supplierStatus' is not null and jsonb_typeof(v_filters -> 'supplierStatus') <> 'null' and not (jsonb_typeof(v_filters -> 'supplierStatus') = 'array' and jsonb_array_length(v_filters -> 'supplierStatus') = 0)) or x."supplier_status"::text = any((case when jsonb_typeof(v_filters -> 'supplierStatus') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'supplierStatus')) else array[v_filters ->> 'supplierStatus'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search)
        and (v_after is null or (x."updated_at" <= (v_after ->> 0)::timestamptz and ((x."updated_at" < (v_after ->> 0)::timestamptz) or (x."updated_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."updated_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."people" x
      where x."tenant_id" = page_people.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'lifecycle' is not null and jsonb_typeof(v_filters -> 'lifecycle') <> 'null' and not (jsonb_typeof(v_filters -> 'lifecycle') = 'array' and jsonb_array_length(v_filters -> 'lifecycle') = 0)) or x."lifecycle" = any((case when jsonb_typeof(v_filters -> 'lifecycle') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'lifecycle')) else array[v_filters ->> 'lifecycle'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'role') = 'array' then v_filters -> 'role' else jsonb_build_array(v_filters ->> 'role') end) r where r = any (x."roles")))
        and (not (v_filters -> 'supplierStatus' is not null and jsonb_typeof(v_filters -> 'supplierStatus') <> 'null' and not (jsonb_typeof(v_filters -> 'supplierStatus') = 'array' and jsonb_array_length(v_filters -> 'supplierStatus') = 0)) or x."supplier_status"::text = any((case when jsonb_typeof(v_filters -> 'supplierStatus') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'supplierStatus')) else array[v_filters ->> 'supplierStatus'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_pipelines (
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
  v_filters jsonb := coalesce(page_pipelines.filters, '{}'::jsonb);
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
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'PIPELINE_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('subjectType') then
      raise exception 'facet is one of subjectType' using errcode = '22023', hint = 'PIPELINE_INVALID';
    end if;
    with s as (
      select (case v_facet when 'subjectType' then (x."subject_type")::text end) as v
      from "better_supabase"."pipelines" x
      where x."tenant_id" = page_pipelines.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'key' is not null and jsonb_typeof(v_filters -> 'key') <> 'null' and not (jsonb_typeof(v_filters -> 'key') = 'array' and jsonb_array_length(v_filters -> 'key') = 0)) or x."key" = any((case when jsonb_typeof(v_filters -> 'key') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'key')) else array[v_filters ->> 'key'] end)::text[]))
        and (not (v_filters -> 'scopeId' is not null and jsonb_typeof(v_filters -> 'scopeId') <> 'null' and not (jsonb_typeof(v_filters -> 'scopeId') = 'array' and jsonb_array_length(v_filters -> 'scopeId') = 0)) or x."scope_id"::text = any((case when jsonb_typeof(v_filters -> 'scopeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scopeId')) else array[v_filters ->> 'scopeId'] end)::text[]))
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
      select 1 from "better_supabase"."pipelines" x
      where x."tenant_id" = page_pipelines.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'key' is not null and jsonb_typeof(v_filters -> 'key') <> 'null' and not (jsonb_typeof(v_filters -> 'key') = 'array' and jsonb_array_length(v_filters -> 'key') = 0)) or x."key" = any((case when jsonb_typeof(v_filters -> 'key') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'key')) else array[v_filters ->> 'key'] end)::text[]))
        and (not (v_filters -> 'scopeId' is not null and jsonb_typeof(v_filters -> 'scopeId') <> 'null' and not (jsonb_typeof(v_filters -> 'scopeId') = 'array' and jsonb_array_length(v_filters -> 'scopeId') = 0)) or x."scope_id"::text = any((case when jsonb_typeof(v_filters -> 'scopeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scopeId')) else array[v_filters ->> 'scopeId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('rank', 'name', 'key') then
    raise exception 'sort is one of rank, name, key' using errcode = '22023', hint = 'PIPELINE_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'PIPELINE_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PIPELINE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('stages', coalesce((
      select jsonb_agg(to_jsonb(st) order by st."rank" collate "C")
      from "better_supabase"."pipeline_stages" st where st."pipeline_id" = x."id" and st."archived_at" is null
    ), '[]'::jsonb)) as j, jsonb_build_array((x."rank" collate "C")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."pipelines" x
      where x."tenant_id" = page_pipelines.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'key' is not null and jsonb_typeof(v_filters -> 'key') <> 'null' and not (jsonb_typeof(v_filters -> 'key') = 'array' and jsonb_array_length(v_filters -> 'key') = 0)) or x."key" = any((case when jsonb_typeof(v_filters -> 'key') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'key')) else array[v_filters ->> 'key'] end)::text[]))
        and (not (v_filters -> 'scopeId' is not null and jsonb_typeof(v_filters -> 'scopeId') <> 'null' and not (jsonb_typeof(v_filters -> 'scopeId') = 'array' and jsonb_array_length(v_filters -> 'scopeId') = 0)) or x."scope_id"::text = any((case when jsonb_typeof(v_filters -> 'scopeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scopeId')) else array[v_filters ->> 'scopeId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."rank" collate "C", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."rank" collate "C" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PIPELINE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('stages', coalesce((
      select jsonb_agg(to_jsonb(st) order by st."rank" collate "C")
      from "better_supabase"."pipeline_stages" st where st."pipeline_id" = x."id" and st."archived_at" is null
    ), '[]'::jsonb)) as j, jsonb_build_array((x."rank" collate "C")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."pipelines" x
      where x."tenant_id" = page_pipelines.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'key' is not null and jsonb_typeof(v_filters -> 'key') <> 'null' and not (jsonb_typeof(v_filters -> 'key') = 'array' and jsonb_array_length(v_filters -> 'key') = 0)) or x."key" = any((case when jsonb_typeof(v_filters -> 'key') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'key')) else array[v_filters ->> 'key'] end)::text[]))
        and (not (v_filters -> 'scopeId' is not null and jsonb_typeof(v_filters -> 'scopeId') <> 'null' and not (jsonb_typeof(v_filters -> 'scopeId') = 'array' and jsonb_array_length(v_filters -> 'scopeId') = 0)) or x."scope_id"::text = any((case when jsonb_typeof(v_filters -> 'scopeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scopeId')) else array[v_filters ->> 'scopeId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."rank" collate "C" <= (v_after ->> 0)::text and ((x."rank" collate "C" < (v_after ->> 0)::text) or (x."rank" collate "C" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."rank" collate "C" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'rank' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PIPELINE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('stages', coalesce((
      select jsonb_agg(to_jsonb(st) order by st."rank" collate "C")
      from "better_supabase"."pipeline_stages" st where st."pipeline_id" = x."id" and st."archived_at" is null
    ), '[]'::jsonb)) as j, jsonb_build_array((x."rank" collate "C")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."pipelines" x
      where x."tenant_id" = page_pipelines.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'key' is not null and jsonb_typeof(v_filters -> 'key') <> 'null' and not (jsonb_typeof(v_filters -> 'key') = 'array' and jsonb_array_length(v_filters -> 'key') = 0)) or x."key" = any((case when jsonb_typeof(v_filters -> 'key') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'key')) else array[v_filters ->> 'key'] end)::text[]))
        and (not (v_filters -> 'scopeId' is not null and jsonb_typeof(v_filters -> 'scopeId') <> 'null' and not (jsonb_typeof(v_filters -> 'scopeId') = 'array' and jsonb_array_length(v_filters -> 'scopeId') = 0)) or x."scope_id"::text = any((case when jsonb_typeof(v_filters -> 'scopeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scopeId')) else array[v_filters ->> 'scopeId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."rank" collate "C", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."rank" collate "C" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'rank' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PIPELINE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('stages', coalesce((
      select jsonb_agg(to_jsonb(st) order by st."rank" collate "C")
      from "better_supabase"."pipeline_stages" st where st."pipeline_id" = x."id" and st."archived_at" is null
    ), '[]'::jsonb)) as j, jsonb_build_array((x."rank" collate "C")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."pipelines" x
      where x."tenant_id" = page_pipelines.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'key' is not null and jsonb_typeof(v_filters -> 'key') <> 'null' and not (jsonb_typeof(v_filters -> 'key') = 'array' and jsonb_array_length(v_filters -> 'key') = 0)) or x."key" = any((case when jsonb_typeof(v_filters -> 'key') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'key')) else array[v_filters ->> 'key'] end)::text[]))
        and (not (v_filters -> 'scopeId' is not null and jsonb_typeof(v_filters -> 'scopeId') <> 'null' and not (jsonb_typeof(v_filters -> 'scopeId') = 'array' and jsonb_array_length(v_filters -> 'scopeId') = 0)) or x."scope_id"::text = any((case when jsonb_typeof(v_filters -> 'scopeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scopeId')) else array[v_filters ->> 'scopeId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."rank" collate "C" <= (v_after ->> 0)::text and ((x."rank" collate "C" < (v_after ->> 0)::text) or (x."rank" collate "C" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."rank" collate "C" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PIPELINE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('stages', coalesce((
      select jsonb_agg(to_jsonb(st) order by st."rank" collate "C")
      from "better_supabase"."pipeline_stages" st where st."pipeline_id" = x."id" and st."archived_at" is null
    ), '[]'::jsonb)) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."pipelines" x
      where x."tenant_id" = page_pipelines.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'key' is not null and jsonb_typeof(v_filters -> 'key') <> 'null' and not (jsonb_typeof(v_filters -> 'key') = 'array' and jsonb_array_length(v_filters -> 'key') = 0)) or x."key" = any((case when jsonb_typeof(v_filters -> 'key') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'key')) else array[v_filters ->> 'key'] end)::text[]))
        and (not (v_filters -> 'scopeId' is not null and jsonb_typeof(v_filters -> 'scopeId') <> 'null' and not (jsonb_typeof(v_filters -> 'scopeId') = 'array' and jsonb_array_length(v_filters -> 'scopeId') = 0)) or x."scope_id"::text = any((case when jsonb_typeof(v_filters -> 'scopeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scopeId')) else array[v_filters ->> 'scopeId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PIPELINE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('stages', coalesce((
      select jsonb_agg(to_jsonb(st) order by st."rank" collate "C")
      from "better_supabase"."pipeline_stages" st where st."pipeline_id" = x."id" and st."archived_at" is null
    ), '[]'::jsonb)) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."pipelines" x
      where x."tenant_id" = page_pipelines.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'key' is not null and jsonb_typeof(v_filters -> 'key') <> 'null' and not (jsonb_typeof(v_filters -> 'key') = 'array' and jsonb_array_length(v_filters -> 'key') = 0)) or x."key" = any((case when jsonb_typeof(v_filters -> 'key') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'key')) else array[v_filters ->> 'key'] end)::text[]))
        and (not (v_filters -> 'scopeId' is not null and jsonb_typeof(v_filters -> 'scopeId') <> 'null' and not (jsonb_typeof(v_filters -> 'scopeId') = 'array' and jsonb_array_length(v_filters -> 'scopeId') = 0)) or x."scope_id"::text = any((case when jsonb_typeof(v_filters -> 'scopeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scopeId')) else array[v_filters ->> 'scopeId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'key' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PIPELINE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('stages', coalesce((
      select jsonb_agg(to_jsonb(st) order by st."rank" collate "C")
      from "better_supabase"."pipeline_stages" st where st."pipeline_id" = x."id" and st."archived_at" is null
    ), '[]'::jsonb)) as j, jsonb_build_array((x."key")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."pipelines" x
      where x."tenant_id" = page_pipelines.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'key' is not null and jsonb_typeof(v_filters -> 'key') <> 'null' and not (jsonb_typeof(v_filters -> 'key') = 'array' and jsonb_array_length(v_filters -> 'key') = 0)) or x."key" = any((case when jsonb_typeof(v_filters -> 'key') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'key')) else array[v_filters ->> 'key'] end)::text[]))
        and (not (v_filters -> 'scopeId' is not null and jsonb_typeof(v_filters -> 'scopeId') <> 'null' and not (jsonb_typeof(v_filters -> 'scopeId') = 'array' and jsonb_array_length(v_filters -> 'scopeId') = 0)) or x."scope_id"::text = any((case when jsonb_typeof(v_filters -> 'scopeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scopeId')) else array[v_filters ->> 'scopeId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."key", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."key" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'key' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PIPELINE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('stages', coalesce((
      select jsonb_agg(to_jsonb(st) order by st."rank" collate "C")
      from "better_supabase"."pipeline_stages" st where st."pipeline_id" = x."id" and st."archived_at" is null
    ), '[]'::jsonb)) as j, jsonb_build_array((x."key")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."pipelines" x
      where x."tenant_id" = page_pipelines.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'key' is not null and jsonb_typeof(v_filters -> 'key') <> 'null' and not (jsonb_typeof(v_filters -> 'key') = 'array' and jsonb_array_length(v_filters -> 'key') = 0)) or x."key" = any((case when jsonb_typeof(v_filters -> 'key') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'key')) else array[v_filters ->> 'key'] end)::text[]))
        and (not (v_filters -> 'scopeId' is not null and jsonb_typeof(v_filters -> 'scopeId') <> 'null' and not (jsonb_typeof(v_filters -> 'scopeId') = 'array' and jsonb_array_length(v_filters -> 'scopeId') = 0)) or x."scope_id"::text = any((case when jsonb_typeof(v_filters -> 'scopeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scopeId')) else array[v_filters ->> 'scopeId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."key" <= (v_after ->> 0)::text and ((x."key" < (v_after ->> 0)::text) or (x."key" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."key" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."pipelines" x
      where x."tenant_id" = page_pipelines.tenant
        and x."archived_at" is null
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'key' is not null and jsonb_typeof(v_filters -> 'key') <> 'null' and not (jsonb_typeof(v_filters -> 'key') = 'array' and jsonb_array_length(v_filters -> 'key') = 0)) or x."key" = any((case when jsonb_typeof(v_filters -> 'key') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'key')) else array[v_filters ->> 'key'] end)::text[]))
        and (not (v_filters -> 'scopeId' is not null and jsonb_typeof(v_filters -> 'scopeId') <> 'null' and not (jsonb_typeof(v_filters -> 'scopeId') = 'array' and jsonb_array_length(v_filters -> 'scopeId') = 0)) or x."scope_id"::text = any((case when jsonb_typeof(v_filters -> 'scopeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scopeId')) else array[v_filters ->> 'scopeId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_quotes (
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
  v_filters jsonb := coalesce(page_quotes.filters, '{}'::jsonb);
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
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', page_quotes.tenant, 'quotes.read'), false)) then
    raise exception 'not allowed to read this organization''s quotes' using errcode = '42501', hint = 'QUOTE_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'QUOTE_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'currency', 'ownerId') then
      raise exception 'facet is one of status, currency, ownerId' using errcode = '22023', hint = 'QUOTE_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status"::text)::text when 'currency' then (x."currency")::text when 'ownerId' then (coalesce(x."owner_id"::text, ''))::text end) as v
      from "better_supabase"."quotes" x
      where x."tenant_id" = page_quotes.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'companyId' is not null and jsonb_typeof(v_filters -> 'companyId') <> 'null' and not (jsonb_typeof(v_filters -> 'companyId') = 'array' and jsonb_array_length(v_filters -> 'companyId') = 0)) or x."company_id"::text = any((case when jsonb_typeof(v_filters -> 'companyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'companyId')) else array[v_filters ->> 'companyId'] end)::text[]))
        and (not (v_filters -> 'contactId' is not null and jsonb_typeof(v_filters -> 'contactId') <> 'null' and not (jsonb_typeof(v_filters -> 'contactId') = 'array' and jsonb_array_length(v_filters -> 'contactId') = 0)) or x."contact_id"::text = any((case when jsonb_typeof(v_filters -> 'contactId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'contactId')) else array[v_filters ->> 'contactId'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
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
      select 1 from "better_supabase"."quotes" x
      where x."tenant_id" = page_quotes.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'companyId' is not null and jsonb_typeof(v_filters -> 'companyId') <> 'null' and not (jsonb_typeof(v_filters -> 'companyId') = 'array' and jsonb_array_length(v_filters -> 'companyId') = 0)) or x."company_id"::text = any((case when jsonb_typeof(v_filters -> 'companyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'companyId')) else array[v_filters ->> 'companyId'] end)::text[]))
        and (not (v_filters -> 'contactId' is not null and jsonb_typeof(v_filters -> 'contactId') <> 'null' and not (jsonb_typeof(v_filters -> 'contactId') = 'array' and jsonb_array_length(v_filters -> 'contactId') = 0)) or x."contact_id"::text = any((case when jsonb_typeof(v_filters -> 'contactId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'contactId')) else array[v_filters ->> 'contactId'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'validUntil', 'title') then
    raise exception 'sort is one of createdAt, validUntil, title' using errcode = '22023', hint = 'QUOTE_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'QUOTE_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'QUOTE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (to_jsonb(x) - 'token_hash') || jsonb_build_object('number', x."number"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text, 'discount_amount', x."discount_amount"::text, 'deposit_due', x."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'unit', ql."unit", 'discountKind', ql."discount_kind", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = x."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = x."id"), '[]'::jsonb)) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."quotes" x
      where x."tenant_id" = page_quotes.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'companyId' is not null and jsonb_typeof(v_filters -> 'companyId') <> 'null' and not (jsonb_typeof(v_filters -> 'companyId') = 'array' and jsonb_array_length(v_filters -> 'companyId') = 0)) or x."company_id"::text = any((case when jsonb_typeof(v_filters -> 'companyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'companyId')) else array[v_filters ->> 'companyId'] end)::text[]))
        and (not (v_filters -> 'contactId' is not null and jsonb_typeof(v_filters -> 'contactId') <> 'null' and not (jsonb_typeof(v_filters -> 'contactId') = 'array' and jsonb_array_length(v_filters -> 'contactId') = 0)) or x."contact_id"::text = any((case when jsonb_typeof(v_filters -> 'contactId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'contactId')) else array[v_filters ->> 'contactId'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'QUOTE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (to_jsonb(x) - 'token_hash') || jsonb_build_object('number', x."number"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text, 'discount_amount', x."discount_amount"::text, 'deposit_due', x."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'unit', ql."unit", 'discountKind', ql."discount_kind", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = x."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = x."id"), '[]'::jsonb)) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."quotes" x
      where x."tenant_id" = page_quotes.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'companyId' is not null and jsonb_typeof(v_filters -> 'companyId') <> 'null' and not (jsonb_typeof(v_filters -> 'companyId') = 'array' and jsonb_array_length(v_filters -> 'companyId') = 0)) or x."company_id"::text = any((case when jsonb_typeof(v_filters -> 'companyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'companyId')) else array[v_filters ->> 'companyId'] end)::text[]))
        and (not (v_filters -> 'contactId' is not null and jsonb_typeof(v_filters -> 'contactId') <> 'null' and not (jsonb_typeof(v_filters -> 'contactId') = 'array' and jsonb_array_length(v_filters -> 'contactId') = 0)) or x."contact_id"::text = any((case when jsonb_typeof(v_filters -> 'contactId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'contactId')) else array[v_filters ->> 'contactId'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'QUOTE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (to_jsonb(x) - 'token_hash') || jsonb_build_object('number', x."number"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text, 'discount_amount', x."discount_amount"::text, 'deposit_due', x."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'unit', ql."unit", 'discountKind', ql."discount_kind", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = x."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = x."id"), '[]'::jsonb)) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."quotes" x
      where x."tenant_id" = page_quotes.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'companyId' is not null and jsonb_typeof(v_filters -> 'companyId') <> 'null' and not (jsonb_typeof(v_filters -> 'companyId') = 'array' and jsonb_array_length(v_filters -> 'companyId') = 0)) or x."company_id"::text = any((case when jsonb_typeof(v_filters -> 'companyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'companyId')) else array[v_filters ->> 'companyId'] end)::text[]))
        and (not (v_filters -> 'contactId' is not null and jsonb_typeof(v_filters -> 'contactId') <> 'null' and not (jsonb_typeof(v_filters -> 'contactId') = 'array' and jsonb_array_length(v_filters -> 'contactId') = 0)) or x."contact_id"::text = any((case when jsonb_typeof(v_filters -> 'contactId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'contactId')) else array[v_filters ->> 'contactId'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'QUOTE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (to_jsonb(x) - 'token_hash') || jsonb_build_object('number', x."number"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text, 'discount_amount', x."discount_amount"::text, 'deposit_due', x."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'unit', ql."unit", 'discountKind', ql."discount_kind", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = x."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = x."id"), '[]'::jsonb)) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."quotes" x
      where x."tenant_id" = page_quotes.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'companyId' is not null and jsonb_typeof(v_filters -> 'companyId') <> 'null' and not (jsonb_typeof(v_filters -> 'companyId') = 'array' and jsonb_array_length(v_filters -> 'companyId') = 0)) or x."company_id"::text = any((case when jsonb_typeof(v_filters -> 'companyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'companyId')) else array[v_filters ->> 'companyId'] end)::text[]))
        and (not (v_filters -> 'contactId' is not null and jsonb_typeof(v_filters -> 'contactId') <> 'null' and not (jsonb_typeof(v_filters -> 'contactId') = 'array' and jsonb_array_length(v_filters -> 'contactId') = 0)) or x."contact_id"::text = any((case when jsonb_typeof(v_filters -> 'contactId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'contactId')) else array[v_filters ->> 'contactId'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'validUntil' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'QUOTE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (to_jsonb(x) - 'token_hash') || jsonb_build_object('number', x."number"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text, 'discount_amount', x."discount_amount"::text, 'deposit_due', x."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'unit', ql."unit", 'discountKind', ql."discount_kind", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = x."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = x."id"), '[]'::jsonb)) as j, jsonb_build_array((coalesce(x."valid_until", date '9999-12-31'))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."quotes" x
      where x."tenant_id" = page_quotes.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'companyId' is not null and jsonb_typeof(v_filters -> 'companyId') <> 'null' and not (jsonb_typeof(v_filters -> 'companyId') = 'array' and jsonb_array_length(v_filters -> 'companyId') = 0)) or x."company_id"::text = any((case when jsonb_typeof(v_filters -> 'companyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'companyId')) else array[v_filters ->> 'companyId'] end)::text[]))
        and (not (v_filters -> 'contactId' is not null and jsonb_typeof(v_filters -> 'contactId') <> 'null' and not (jsonb_typeof(v_filters -> 'contactId') = 'array' and jsonb_array_length(v_filters -> 'contactId') = 0)) or x."contact_id"::text = any((case when jsonb_typeof(v_filters -> 'contactId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'contactId')) else array[v_filters ->> 'contactId'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (coalesce(x."valid_until", date '9999-12-31'), x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by coalesce(x."valid_until", date '9999-12-31') asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'validUntil' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'QUOTE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (to_jsonb(x) - 'token_hash') || jsonb_build_object('number', x."number"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text, 'discount_amount', x."discount_amount"::text, 'deposit_due', x."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'unit', ql."unit", 'discountKind', ql."discount_kind", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = x."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = x."id"), '[]'::jsonb)) as j, jsonb_build_array((coalesce(x."valid_until", date '9999-12-31'))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."quotes" x
      where x."tenant_id" = page_quotes.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'companyId' is not null and jsonb_typeof(v_filters -> 'companyId') <> 'null' and not (jsonb_typeof(v_filters -> 'companyId') = 'array' and jsonb_array_length(v_filters -> 'companyId') = 0)) or x."company_id"::text = any((case when jsonb_typeof(v_filters -> 'companyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'companyId')) else array[v_filters ->> 'companyId'] end)::text[]))
        and (not (v_filters -> 'contactId' is not null and jsonb_typeof(v_filters -> 'contactId') <> 'null' and not (jsonb_typeof(v_filters -> 'contactId') = 'array' and jsonb_array_length(v_filters -> 'contactId') = 0)) or x."contact_id"::text = any((case when jsonb_typeof(v_filters -> 'contactId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'contactId')) else array[v_filters ->> 'contactId'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (coalesce(x."valid_until", date '9999-12-31') <= (v_after ->> 0)::date and ((coalesce(x."valid_until", date '9999-12-31') < (v_after ->> 0)::date) or (coalesce(x."valid_until", date '9999-12-31') = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."valid_until", date '9999-12-31') desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'QUOTE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (to_jsonb(x) - 'token_hash') || jsonb_build_object('number', x."number"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text, 'discount_amount', x."discount_amount"::text, 'deposit_due', x."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'unit', ql."unit", 'discountKind', ql."discount_kind", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = x."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = x."id"), '[]'::jsonb)) as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."quotes" x
      where x."tenant_id" = page_quotes.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'companyId' is not null and jsonb_typeof(v_filters -> 'companyId') <> 'null' and not (jsonb_typeof(v_filters -> 'companyId') = 'array' and jsonb_array_length(v_filters -> 'companyId') = 0)) or x."company_id"::text = any((case when jsonb_typeof(v_filters -> 'companyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'companyId')) else array[v_filters ->> 'companyId'] end)::text[]))
        and (not (v_filters -> 'contactId' is not null and jsonb_typeof(v_filters -> 'contactId') <> 'null' and not (jsonb_typeof(v_filters -> 'contactId') = 'array' and jsonb_array_length(v_filters -> 'contactId') = 0)) or x."contact_id"::text = any((case when jsonb_typeof(v_filters -> 'contactId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'contactId')) else array[v_filters ->> 'contactId'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (lower(x."title"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."title") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'QUOTE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (to_jsonb(x) - 'token_hash') || jsonb_build_object('number', x."number"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text, 'discount_amount', x."discount_amount"::text, 'deposit_due', x."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'unit', ql."unit", 'discountKind', ql."discount_kind", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = x."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = x."id"), '[]'::jsonb)) as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."quotes" x
      where x."tenant_id" = page_quotes.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'companyId' is not null and jsonb_typeof(v_filters -> 'companyId') <> 'null' and not (jsonb_typeof(v_filters -> 'companyId') = 'array' and jsonb_array_length(v_filters -> 'companyId') = 0)) or x."company_id"::text = any((case when jsonb_typeof(v_filters -> 'companyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'companyId')) else array[v_filters ->> 'companyId'] end)::text[]))
        and (not (v_filters -> 'contactId' is not null and jsonb_typeof(v_filters -> 'contactId') <> 'null' and not (jsonb_typeof(v_filters -> 'contactId') = 'array' and jsonb_array_length(v_filters -> 'contactId') = 0)) or x."contact_id"::text = any((case when jsonb_typeof(v_filters -> 'contactId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'contactId')) else array[v_filters ->> 'contactId'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
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
      select 1 from "better_supabase"."quotes" x
      where x."tenant_id" = page_quotes.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'companyId' is not null and jsonb_typeof(v_filters -> 'companyId') <> 'null' and not (jsonb_typeof(v_filters -> 'companyId') = 'array' and jsonb_array_length(v_filters -> 'companyId') = 0)) or x."company_id"::text = any((case when jsonb_typeof(v_filters -> 'companyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'companyId')) else array[v_filters ->> 'companyId'] end)::text[]))
        and (not (v_filters -> 'contactId' is not null and jsonb_typeof(v_filters -> 'contactId') <> 'null' and not (jsonb_typeof(v_filters -> 'contactId') = 'array' and jsonb_array_length(v_filters -> 'contactId') = 0)) or x."contact_id"::text = any((case when jsonb_typeof(v_filters -> 'contactId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'contactId')) else array[v_filters ->> 'contactId'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_segments (
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
  v_filters jsonb := coalesce(page_segments.filters, '{}'::jsonb);
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
  if not coalesce(better_supabase.can('tenant', page_segments.tenant, 'segments.read'), false) then
    raise exception 'You need segments.read to list segments' using errcode = '42501', hint = 'SEGMENT_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'SEGMENT_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('subjectType') then
      raise exception 'facet is one of subjectType' using errcode = '22023', hint = 'SEGMENT_INVALID';
    end if;
    with s as (
      select (case v_facet when 'subjectType' then (x."subject_type")::text end) as v
      from "better_supabase"."segments" x
      where x."tenant_id" = page_segments.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
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
      select 1 from "better_supabase"."segments" x
      where x."tenant_id" = page_segments.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'createdAt', 'memberCount') then
    raise exception 'sort is one of name, createdAt, memberCount' using errcode = '22023', hint = 'SEGMENT_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'SEGMENT_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SEGMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'conditions', x."conditions", 'memberCount', x."member_count", 'refreshedAt', x."refreshed_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."segments" x
      where x."tenant_id" = page_segments.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SEGMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'conditions', x."conditions", 'memberCount', x."member_count", 'refreshedAt', x."refreshed_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."segments" x
      where x."tenant_id" = page_segments.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SEGMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'conditions', x."conditions", 'memberCount', x."member_count", 'refreshedAt', x."refreshed_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."segments" x
      where x."tenant_id" = page_segments.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SEGMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'conditions', x."conditions", 'memberCount', x."member_count", 'refreshedAt', x."refreshed_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."segments" x
      where x."tenant_id" = page_segments.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SEGMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'conditions', x."conditions", 'memberCount', x."member_count", 'refreshedAt', x."refreshed_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."segments" x
      where x."tenant_id" = page_segments.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SEGMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'conditions', x."conditions", 'memberCount', x."member_count", 'refreshedAt', x."refreshed_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."segments" x
      where x."tenant_id" = page_segments.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'memberCount' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SEGMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'conditions', x."conditions", 'memberCount', x."member_count", 'refreshedAt', x."refreshed_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."member_count")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."segments" x
      where x."tenant_id" = page_segments.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."member_count", x."id") > ((v_after ->> 0)::integer, (v_after ->> 1)::uuid))
      order by x."member_count" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'memberCount' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SEGMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'conditions', x."conditions", 'memberCount', x."member_count", 'refreshedAt', x."refreshed_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."member_count")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."segments" x
      where x."tenant_id" = page_segments.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."member_count" <= (v_after ->> 0)::integer and ((x."member_count" < (v_after ->> 0)::integer) or (x."member_count" = (v_after ->> 0)::integer and x."id" > (v_after ->> 1)::uuid))))
      order by x."member_count" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."segments" x
      where x."tenant_id" = page_segments.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

REVOKE ALL ON FUNCTION "api"."get_deal"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_deal"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_pipeline"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_pipeline"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_quote"(uuid) FROM "service_role";

GRANT EXECUTE ON FUNCTION "api"."get_quote"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "api"."page_companies"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_companies"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_contract_obligations"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_contract_obligations"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_contracts"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_contracts"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_deals"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_deals"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_forecast_snapshots"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_forecast_snapshots"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_mail_accounts"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_mail_accounts"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_mail_threads"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_mail_threads"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_people"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_people"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_pipelines"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_pipelines"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_quotes"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_quotes"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_segments"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_segments"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_deal"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_deal"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_pipeline"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_pipeline"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_quote"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_quote"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_companies"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_companies"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_contract_obligations"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_contract_obligations"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_contracts"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_contracts"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_deals"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_deals"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_forecast_snapshots"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_forecast_snapshots"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_mail_accounts"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_mail_accounts"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_mail_threads"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_mail_threads"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_people"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_people"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_pipelines"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_pipelines"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_quotes"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_quotes"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_segments"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_segments"(uuid, jsonb) TO "authenticated", "service_role";
