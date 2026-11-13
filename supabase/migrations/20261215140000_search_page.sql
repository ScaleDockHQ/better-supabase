SET local check_function_bodies = off;

DROP TRIGGER "bsb_search_customer_index" ON "public"."customers";

DROP INDEX "better_supabase"."search_documents_tenant_idx";

ALTER TABLE "better_supabase"."search_documents"
  ADD COLUMN "facets" jsonb NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE "better_supabase"."search_documents"
  ADD COLUMN "sort_key" text NOT NULL DEFAULT ''::text;

CREATE OR REPLACE FUNCTION api.search_page (
  q         text    DEFAULT NULL::text,
  types     text[]  DEFAULT NULL::text[],
  tenant    uuid    DEFAULT NULL::uuid,
  filter    jsonb   DEFAULT NULL::jsonb,
  after     text    DEFAULT NULL::text,
  page_size integer DEFAULT 20
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."search_page"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION better_supabase.search_page (
  q         text    DEFAULT NULL::text,
  types     text[]  DEFAULT NULL::text[],
  tenant    uuid    DEFAULT NULL::uuid,
  filter    jsonb   DEFAULT NULL::jsonb,
  after     text    DEFAULT NULL::text,
  page_size integer DEFAULT 20
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_q text := btrim(coalesce(search_page.q, ''));
  v_mode text := 'b';
  v_norm text;
  v_hash text;
  v_web tsquery;
  v_prefix tsquery;
  v_size integer := least(greatest(coalesce(search_page.page_size, 20), 1), 100);
  v_filter jsonb := coalesce(search_page.filter, '{}'::jsonb);
  v_cur jsonb;
  v_items jsonb;
  v_more boolean;
  v_last jsonb;
  v_next text;
begin
  if length(v_q) > 256 then
    raise exception 'a search query is at most 256 characters' using errcode = '22023', hint = 'SEARCH_QUERY_TOO_LONG';
  end if;
  if jsonb_typeof(v_filter) is distinct from 'object' then
    raise exception 'filter must be a JSON object of facet values' using errcode = '22023', hint = 'SEARCH_FILTER_INVALID';
  end if;
  if v_q <> '' then
    v_mode := 's';
    v_norm := "better_supabase"."search_normalize"(v_q);
    v_hash := md5(v_norm);
    v_web := websearch_to_tsquery('simple', v_norm);
    select to_tsquery('simple', string_agg(quote_literal(w) || ':*', ' & '))
      into v_prefix
      from regexp_split_to_table(v_norm, '[^[:alnum:]]+') w
      where w <> '';
  end if;
  if search_page.after is not null then
    begin
      v_cur := convert_from(decode(rpad(translate(search_page.after, '-_', '+/'), length(search_page.after) + (4 - length(search_page.after) % 4) % 4, '='), 'base64'), 'UTF8')::jsonb;
    exception when others then
      v_cur := null;
    end;
    if v_cur is null or jsonb_typeof(v_cur) is distinct from 'object'
      or v_cur ->> 'm' is distinct from v_mode
      or (v_mode = 's' and v_cur ->> 'h' is distinct from v_hash) then
      raise exception 'this cursor does not belong to this query' using errcode = '22023', hint = 'SEARCH_CURSOR_INVALID';
    end if;
  end if;
  if v_mode = 'b' then
    with lim as (
      select d."tenant_id" as tenant, d."subject_type" as subject_type, d."subject_id" as subject_id,
          d."title" as title, d."url" as url, d."body" as body, d."facets" as facets, d."sort_key" as sort_key, null::numeric as score
      from "better_supabase"."search_documents" d
      where (search_page.types is null or d."subject_type" = any (search_page.types))
          and (search_page.tenant is null or d."tenant_id" = search_page.tenant)
          and d."facets" @> v_filter
        and (v_cur is null or (d."sort_key", d."subject_id", d."subject_type") > (v_cur ->> 'k', v_cur ->> 'i', v_cur ->> 't'))
        and "better_supabase"."can_subject"(d."subject_type", d."subject_id", 'read')
      order by d."sort_key", d."subject_id", d."subject_type"
      limit v_size + 1
    ),
    page as (
      select l.*, row_number() over (order by l.sort_key, l.subject_id, l.subject_type) as rn from lim l
    )
    select coalesce(jsonb_agg(jsonb_build_object(
        'organizationId', p.tenant,
        'subjectType', p.subject_type,
        'subjectId', p.subject_id,
        'title', p.title,
        'url', p.url,
        'snippet', null,
        'score', case when p.score is null then null else round(p.score, 6) end,
        'facets', p.facets
      ) order by p.rn) filter (where p.rn <= v_size), '[]'::jsonb),
      count(*) > v_size,
      (select jsonb_build_object('m', v_mode, 'h', v_hash, 'k', l.sort_key, 'i', l.subject_id, 't', l.subject_type, 's', l.score)
        from page l where l.rn = v_size)
    into v_items, v_more, v_last
    from page p;
  else
    with pool as materialized (
      select d."subject_type" as subject_type, d."subject_id" as subject_id,
        round((2 * coalesce(ts_rank_cd(d."tsv", v_web), 0)
          + coalesce(ts_rank_cd(d."tsv", v_prefix), 0)
          + extensions.similarity(d."title_search", v_norm))::numeric, 6) as score
      from "better_supabase"."search_documents" d
      where (search_page.types is null or d."subject_type" = any (search_page.types))
          and (search_page.tenant is null or d."tenant_id" = search_page.tenant)
          and d."facets" @> v_filter
        and (d."tsv" @@ v_web
          or (v_prefix is not null and d."tsv" @@ v_prefix)
          or d."title_search" operator(extensions.%) v_norm)
      order by score desc, d."subject_type", d."subject_id"
      limit 500
    ),
    lim as (
      select d."tenant_id" as tenant, d."subject_type" as subject_type, d."subject_id" as subject_id,
          d."title" as title, d."url" as url, d."body" as body, d."facets" as facets, d."sort_key" as sort_key, h.score
      from pool h
      join "better_supabase"."search_documents" d on d."subject_type" = h.subject_type and d."subject_id" = h.subject_id
      where (v_cur is null
          or h.score < (v_cur ->> 's')::numeric
          or (h.score = (v_cur ->> 's')::numeric and (h.subject_type, h.subject_id) > (v_cur ->> 't', v_cur ->> 'i')))
        and "better_supabase"."can_subject"(h.subject_type, h.subject_id, 'read')
      order by h.score desc, h.subject_type, h.subject_id
      limit v_size + 1
    ),
    page as (
      select l.*, row_number() over (order by l.score desc, l.subject_type, l.subject_id) as rn from lim l
    )
    select coalesce(jsonb_agg(jsonb_build_object(
        'organizationId', p.tenant,
        'subjectType', p.subject_type,
        'subjectId', p.subject_id,
        'title', p.title,
        'url', p.url,
        'snippet', case when p.body is null then null
          else ts_headline('simple', p.body, coalesce(v_prefix, v_web), 'StartSel="", StopSel="", MaxWords=20, MinWords=8, MaxFragments=1')
        end,
        'score', case when p.score is null then null else round(p.score, 6) end,
        'facets', p.facets
      ) order by p.rn) filter (where p.rn <= v_size), '[]'::jsonb),
      count(*) > v_size,
      (select jsonb_build_object('m', v_mode, 'h', v_hash, 'k', l.sort_key, 'i', l.subject_id, 't', l.subject_type, 's', l.score)
        from page l where l.rn = v_size)
    into v_items, v_more, v_last
    from page p;
  end if;
  if v_more then
    v_next := translate(encode(convert_to(v_last::text, 'UTF8'), 'base64'), E'+/=\n', '-_');
  end if;
  return jsonb_build_object('items', v_items, 'nextCursor', v_next);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.search_refresh (
  subject_type text,
  subject_id   text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_title text;
  v_body text;
  v_url text;
  v_facets jsonb;
  v_found boolean := false;
  v_hash text;
begin
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_search_document_index"(text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text)', v_hook::oid::regproc)
        using search_refresh.subject_type, search_refresh.subject_id;
    end if;
  end;
  case search_refresh.subject_type
    when 'message' then
      select s."tenant_id", s."body"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."messages" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'conversation' then
      select s."tenant_id", s."title"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."conversations" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'channel' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."topic"::text, s."purpose"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."channels" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'company' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."domain"::text), ''), '/crm/contacts/' || s."id"::text, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."companies" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'person' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."email"::text, s."title"::text), ''), '/crm/contacts/' || s."id"::text, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."people" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'deal' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."identifier"::text, s."note"::text), ''), '/crm/deals', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."deals" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'course' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."summary"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."courses" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'post' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."body"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."posts" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'activity' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."body"::text, s."outcome"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."activities" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'quote' then
      select s."tenant_id", s."title"::text, null, '/crm/quotes/' || s."id"::text, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."quotes" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'work_item' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."identifier"::text, s."body"::text), ''), '/work', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."work_items" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'employee' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."email"::text, s."job_title"::text), ''), '/people/' || s."id"::text, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."employees" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'ledger_account' then
      select s."tenant_id", s."name"::text, null, '/finance', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."ledger_accounts" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'invoice' then
      select s."tenant_id", s."title"::text, null, '/finance/payables', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."invoices" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'product' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."description"::text, s."slug"::text), ''), '/shop', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."products" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'product_variant' then
      select s."tenant_id", s."sku"::text, nullif(concat_ws(E'\n', s."title"::text, s."barcode"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."product_variants" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'rfq' then
      select s."tenant_id", s."title"::text, null, '/rfqs', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."rfqs" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'till' then
      select s."tenant_id", s."name"::text, null, '/tills', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."tills" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'order' then
      select s."tenant_id", s."number"::text, null, '/shop/orders/' || s."id"::text, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."orders" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'calendar_event' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."description"::text, s."location"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."calendar_events" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'booking' then
      select s."tenant_id", s."customer_name"::text, null, '/calendar', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."bookings" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'asset' then
      select s."tenant_id", s."name"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."assets" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'asset_location' then
      select s."tenant_id", s."name"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."asset_locations" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'lease' then
      select s."tenant_id", s."title"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."leases" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'expense_report' then
      select s."tenant_id", s."title"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."expense_reports" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'expense_line' then
      select s."tenant_id", s."description"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."expense_lines" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'donation_fund' then
      select s."tenant_id", s."name"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."donation_funds" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'warranty_claim' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."manufacturer"::text, s."decision"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."warranty_claims" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'work_order' then
      select s."tenant_id", s."title"::text, null, '/field/dispatch', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."work_orders" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'shipment' then
      select s."tenant_id", s."reference"::text, null, '/field/shipments', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."shipments" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'contract' then
      select s."tenant_id", s."title"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."contracts" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'control' then
      select s."tenant_id", s."title"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."controls" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'compliance_policy' then
      select s."tenant_id", s."title"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."compliance_policies" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'qualification_type' then
      select s."tenant_id", s."name"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."qualification_types" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'risk' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."number"::text, s."description"::text, s."cause"::text, s."consequence"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."risks" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'case' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."number"::text, s."description"::text, s."root_cause"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."cases" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'inspection' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."number"::text, s."scope"::text, s."summary"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."inspections" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'inspection_program' then
      select s."tenant_id", s."name"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."inspection_programs" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'inspection_finding' then
      select s."tenant_id", s."title"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."inspection_findings" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'form' then
      select s."tenant_id", s."title"::text, null, '/forms/' || s."id"::text, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."forms" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'meeting' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."location"::text, s."summary"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."meetings" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'meeting_decision' then
      select s."tenant_id", s."title"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."meeting_decisions" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'maintenance_plan' then
      select s."tenant_id", s."title"::text, null, '/maintenance', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."maintenance_plans" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'dam_usage_right' then
      select s."tenant_id", s."licensee"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."dam_usage_rights" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'lims_sample' then
      select s."tenant_id", s."title"::text, null, '/lims', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."lims_samples" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'tax_code' then
      select s."tenant_id", s."name"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."tax_codes" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'production_order' then
      select s."tenant_id", s."number"::text, nullif(concat_ws(E'\n', s."note"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."production_orders" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'work_center' then
      select s."tenant_id", s."name"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."work_centers" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'bank_account' then
      select s."tenant_id", s."name"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."bank_accounts" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'care_plan' then
      select s."tenant_id", s."title"::text, null, '/care-plans', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."care_plans" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'incident' then
      select s."tenant_id", s."title"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."incidents" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'advisory' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."tracking_id"::text, s."summary"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."advisories" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'advisory_product' then
      select s."tenant_id", s."name"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."advisory_products" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'vulnerability' then
      select s."tenant_id", s."vuln_id"::text, nullif(concat_ws(E'\n', s."summary"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."vulnerabilities" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'content_entry' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."summary"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."content_entries" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'document' then
      select s."tenant_id", s."name"::text, null, '/documents/' || s."id"::text, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."documents" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'customer' then
      select s."organization_id", s."name"::text, null, '/customers/' || s."id"::text, jsonb_strip_nulls(jsonb_build_object('status', s."status"))
        into v_tenant, v_title, v_body, v_url, v_facets
        from "public"."customers" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'drive_node' then
      select s."tenant_id", f."name"::text, nullif(concat_ws(E'\n', f."content"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."drive_nodes" s
        join "better_supabase"."drive_node_search" f on f."id" = s."id"
        where s."id" = (search_refresh.subject_id)::uuid
        and f."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'project' then
      select s."organization_id", s."name"::text, null, '/projects/' || s."id"::text, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "public"."projects" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."deleted_at" is null;
      v_found := found;
    when 'task' then
      select s."organization_id", s."title"::text, null, '/projects/' || s."project_id"::text, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "public"."tasks" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    else
      raise exception 'this subject type has no search entry in config.recordTypes' using errcode = '22023', hint = 'SEARCH_SUBJECT_UNKNOWN';
  end case;
  if not v_found then
    delete from "better_supabase"."search_documents"
    where "subject_type" = search_refresh.subject_type and "subject_id" = search_refresh.subject_id;
    return false;
  end if;
  v_hash := md5(coalesce(v_title, '') || E'\x1f' || coalesce(v_body, ''));
  insert into "better_supabase"."search_documents" ("tenant_id", "subject_type", "subject_id", "title", "title_search", "body", "url", "tsv", "content_hash", "updated_at", "facets", "sort_key")
  values (
    v_tenant, search_refresh.subject_type, search_refresh.subject_id, v_title, "better_supabase"."search_normalize"(v_title), v_body, v_url,
    setweight(to_tsvector('simple', "better_supabase"."search_normalize"(v_title)), 'A')
      || setweight(to_tsvector('simple', "better_supabase"."search_normalize"(v_body)), 'B'),
    v_hash, now(), v_facets, left("better_supabase"."search_normalize"(v_title), 200)
  )
  on conflict ("subject_type", "subject_id") do update set
    "tenant_id" = excluded."tenant_id",
    "title" = excluded."title",
    "title_search" = excluded."title_search",
    "body" = excluded."body",
    "url" = excluded."url",
    "tsv" = excluded."tsv",
    "content_hash" = excluded."content_hash",
    "facets" = excluded."facets",
    "sort_key" = excluded."sort_key",
    "updated_at" = now()
  where ("better_supabase"."search_documents"."tenant_id", "better_supabase"."search_documents"."title", "better_supabase"."search_documents"."body", "better_supabase"."search_documents"."url", "better_supabase"."search_documents"."facets")
    is distinct from (excluded."tenant_id", excluded."title", excluded."body", excluded."url", excluded."facets");
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_search_document_index"(text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text)', v_hook::oid::regproc)
        using search_refresh.subject_type, search_refresh.subject_id;
    end if;
  end;
  return true;
end;
$function$;

CREATE INDEX search_documents_browse_idx ON better_supabase.search_documents USING btree (tenant_id, subject_type, sort_key, subject_id);

CREATE INDEX search_documents_facets_idx ON better_supabase.search_documents USING gin (facets jsonb_path_ops);

CREATE TRIGGER bsb_search_customer_index
  AFTER INSERT OR DELETE OR UPDATE OF id, organization_id, name, status, archived_at ON public.customers
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('customer', 'id');

REVOKE ALL ON FUNCTION "api"."search_page"(text, text[], uuid, jsonb, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."search_page"(text, text[], uuid, jsonb, text, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."search_page"(text, text[], uuid, jsonb, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."search_page"(text, text[], uuid, jsonb, text, integer) TO "authenticated", "service_role";
