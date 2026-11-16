SET local check_function_bodies = off;

DROP FUNCTION "api"."review_queue"(uuid, text, integer, timestamp WITH time zone, text, text);

DROP FUNCTION "better_supabase"."review_queue"(uuid, text, integer, timestamp WITH time zone, text, text);

CREATE OR REPLACE FUNCTION api.page_stock_bins (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_stock_bins"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_stock_locations (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_stock_locations"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_stock_variants (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_stock_variants"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.review_queue (
  tenant       uuid,
  status       text                     DEFAULT 'pending'::text,
  page_size    integer                  DEFAULT 50,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  subject_type text                     DEFAULT NULL::text,
  subject_id   text                     DEFAULT NULL::text,
  statuses     text[]                   DEFAULT NULL::text[]
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."review_queue"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION better_supabase.list_gifts (
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
  v_filters jsonb := coalesce(list_gifts.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 100), 1), 1000);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_gifts.tenant, 'donations.read'), false)) then
    raise exception 'not allowed to read donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'DONATION_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'fundId') then
      raise exception 'facet is one of status, fundId' using errcode = '22023', hint = 'DONATION_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'fundId' then (x."fund_id")::text end) as v
      from "better_supabase"."donations" x
      where x."tenant_id" = list_gifts.tenant
        and (not (v_filters -> 'donorType' is not null and jsonb_typeof(v_filters -> 'donorType') <> 'null' and not (jsonb_typeof(v_filters -> 'donorType') = 'array' and jsonb_array_length(v_filters -> 'donorType') = 0)) or x."donor_type" = any((case when jsonb_typeof(v_filters -> 'donorType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'donorType')) else array[v_filters ->> 'donorType'] end)::text[]))
        and (not (v_filters -> 'donorId' is not null and jsonb_typeof(v_filters -> 'donorId') <> 'null' and not (jsonb_typeof(v_filters -> 'donorId') = 'array' and jsonb_array_length(v_filters -> 'donorId') = 0)) or x."donor_id" = any((case when jsonb_typeof(v_filters -> 'donorId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'donorId')) else array[v_filters ->> 'donorId'] end)::text[]))
        and (not (v_filters -> 'fundId' is not null and jsonb_typeof(v_filters -> 'fundId') <> 'null' and not (jsonb_typeof(v_filters -> 'fundId') = 'array' and jsonb_array_length(v_filters -> 'fundId') = 0)) or x."fund_id" = any((case when jsonb_typeof(v_filters -> 'fundId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'fundId')) else array[v_filters ->> 'fundId'] end)::uuid[]))
        and (not (v_filters -> 'pledgeId' is not null and jsonb_typeof(v_filters -> 'pledgeId') <> 'null' and not (jsonb_typeof(v_filters -> 'pledgeId') = 'array' and jsonb_array_length(v_filters -> 'pledgeId') = 0)) or x."pledge_id" = any((case when jsonb_typeof(v_filters -> 'pledgeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pledgeId')) else array[v_filters ->> 'pledgeId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."donor_id" ilike v_search or coalesce(x."payment_reference", '') ilike v_search or coalesce(x."note", '') ilike v_search)
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
      select 1 from "better_supabase"."donations" x
      where x."tenant_id" = list_gifts.tenant
        and (not (v_filters -> 'donorType' is not null and jsonb_typeof(v_filters -> 'donorType') <> 'null' and not (jsonb_typeof(v_filters -> 'donorType') = 'array' and jsonb_array_length(v_filters -> 'donorType') = 0)) or x."donor_type" = any((case when jsonb_typeof(v_filters -> 'donorType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'donorType')) else array[v_filters ->> 'donorType'] end)::text[]))
        and (not (v_filters -> 'donorId' is not null and jsonb_typeof(v_filters -> 'donorId') <> 'null' and not (jsonb_typeof(v_filters -> 'donorId') = 'array' and jsonb_array_length(v_filters -> 'donorId') = 0)) or x."donor_id" = any((case when jsonb_typeof(v_filters -> 'donorId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'donorId')) else array[v_filters ->> 'donorId'] end)::text[]))
        and (not (v_filters -> 'fundId' is not null and jsonb_typeof(v_filters -> 'fundId') <> 'null' and not (jsonb_typeof(v_filters -> 'fundId') = 'array' and jsonb_array_length(v_filters -> 'fundId') = 0)) or x."fund_id" = any((case when jsonb_typeof(v_filters -> 'fundId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'fundId')) else array[v_filters ->> 'fundId'] end)::uuid[]))
        and (not (v_filters -> 'pledgeId' is not null and jsonb_typeof(v_filters -> 'pledgeId') <> 'null' and not (jsonb_typeof(v_filters -> 'pledgeId') = 'array' and jsonb_array_length(v_filters -> 'pledgeId') = 0)) or x."pledge_id" = any((case when jsonb_typeof(v_filters -> 'pledgeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pledgeId')) else array[v_filters ->> 'pledgeId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."donor_id" ilike v_search or coalesce(x."payment_reference", '') ilike v_search or coalesce(x."note", '') ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('receivedOn', 'createdAt') then
    raise exception 'sort is one of receivedOn, createdAt' using errcode = '22023', hint = 'DONATION_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'DONATION_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DONATION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'donorType', x."donor_type", 'donorId', x."donor_id", 'fundId', x."fund_id", 'pledgeId', x."pledge_id", 'periodStart', x."period_start", 'amount', x."amount"::text, 'currency', x."currency", 'receivedOn', x."received_on", 'method', x."method", 'status', x."status", 'provider', x."provider", 'paymentReference', x."payment_reference", 'transactionId', x."transaction_id", 'refundTransactionId', x."refund_transaction_id", 'receiptId', x."receipt_id", 'note', x."note", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."received_on")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."donations" x
      where x."tenant_id" = list_gifts.tenant
        and (not (v_filters -> 'donorType' is not null and jsonb_typeof(v_filters -> 'donorType') <> 'null' and not (jsonb_typeof(v_filters -> 'donorType') = 'array' and jsonb_array_length(v_filters -> 'donorType') = 0)) or x."donor_type" = any((case when jsonb_typeof(v_filters -> 'donorType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'donorType')) else array[v_filters ->> 'donorType'] end)::text[]))
        and (not (v_filters -> 'donorId' is not null and jsonb_typeof(v_filters -> 'donorId') <> 'null' and not (jsonb_typeof(v_filters -> 'donorId') = 'array' and jsonb_array_length(v_filters -> 'donorId') = 0)) or x."donor_id" = any((case when jsonb_typeof(v_filters -> 'donorId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'donorId')) else array[v_filters ->> 'donorId'] end)::text[]))
        and (not (v_filters -> 'fundId' is not null and jsonb_typeof(v_filters -> 'fundId') <> 'null' and not (jsonb_typeof(v_filters -> 'fundId') = 'array' and jsonb_array_length(v_filters -> 'fundId') = 0)) or x."fund_id" = any((case when jsonb_typeof(v_filters -> 'fundId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'fundId')) else array[v_filters ->> 'fundId'] end)::uuid[]))
        and (not (v_filters -> 'pledgeId' is not null and jsonb_typeof(v_filters -> 'pledgeId') <> 'null' and not (jsonb_typeof(v_filters -> 'pledgeId') = 'array' and jsonb_array_length(v_filters -> 'pledgeId') = 0)) or x."pledge_id" = any((case when jsonb_typeof(v_filters -> 'pledgeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pledgeId')) else array[v_filters ->> 'pledgeId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."donor_id" ilike v_search or coalesce(x."payment_reference", '') ilike v_search or coalesce(x."note", '') ilike v_search)
        and (v_after is null or (x."received_on" >= (v_after ->> 0)::date and ((x."received_on" > (v_after ->> 0)::date) or (x."received_on" = (v_after ->> 0)::date and x."created_at" < (v_after ->> 1)::timestamptz) or (x."received_on" = (v_after ->> 0)::date and x."created_at" = (v_after ->> 1)::timestamptz and x."id" < (v_after ->> 2)::uuid))))
      order by x."received_on" asc, x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DONATION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'donorType', x."donor_type", 'donorId', x."donor_id", 'fundId', x."fund_id", 'pledgeId', x."pledge_id", 'periodStart', x."period_start", 'amount', x."amount"::text, 'currency', x."currency", 'receivedOn', x."received_on", 'method', x."method", 'status', x."status", 'provider', x."provider", 'paymentReference', x."payment_reference", 'transactionId', x."transaction_id", 'refundTransactionId', x."refund_transaction_id", 'receiptId', x."receipt_id", 'note', x."note", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."received_on")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."donations" x
      where x."tenant_id" = list_gifts.tenant
        and (not (v_filters -> 'donorType' is not null and jsonb_typeof(v_filters -> 'donorType') <> 'null' and not (jsonb_typeof(v_filters -> 'donorType') = 'array' and jsonb_array_length(v_filters -> 'donorType') = 0)) or x."donor_type" = any((case when jsonb_typeof(v_filters -> 'donorType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'donorType')) else array[v_filters ->> 'donorType'] end)::text[]))
        and (not (v_filters -> 'donorId' is not null and jsonb_typeof(v_filters -> 'donorId') <> 'null' and not (jsonb_typeof(v_filters -> 'donorId') = 'array' and jsonb_array_length(v_filters -> 'donorId') = 0)) or x."donor_id" = any((case when jsonb_typeof(v_filters -> 'donorId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'donorId')) else array[v_filters ->> 'donorId'] end)::text[]))
        and (not (v_filters -> 'fundId' is not null and jsonb_typeof(v_filters -> 'fundId') <> 'null' and not (jsonb_typeof(v_filters -> 'fundId') = 'array' and jsonb_array_length(v_filters -> 'fundId') = 0)) or x."fund_id" = any((case when jsonb_typeof(v_filters -> 'fundId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'fundId')) else array[v_filters ->> 'fundId'] end)::uuid[]))
        and (not (v_filters -> 'pledgeId' is not null and jsonb_typeof(v_filters -> 'pledgeId') <> 'null' and not (jsonb_typeof(v_filters -> 'pledgeId') = 'array' and jsonb_array_length(v_filters -> 'pledgeId') = 0)) or x."pledge_id" = any((case when jsonb_typeof(v_filters -> 'pledgeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pledgeId')) else array[v_filters ->> 'pledgeId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."donor_id" ilike v_search or coalesce(x."payment_reference", '') ilike v_search or coalesce(x."note", '') ilike v_search)
        and (v_after is null or (x."received_on", x."created_at", x."id") < ((v_after ->> 0)::date, (v_after ->> 1)::timestamptz, (v_after ->> 2)::uuid))
      order by x."received_on" desc, x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'receivedOn' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DONATION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'donorType', x."donor_type", 'donorId', x."donor_id", 'fundId', x."fund_id", 'pledgeId', x."pledge_id", 'periodStart', x."period_start", 'amount', x."amount"::text, 'currency', x."currency", 'receivedOn', x."received_on", 'method', x."method", 'status', x."status", 'provider', x."provider", 'paymentReference', x."payment_reference", 'transactionId', x."transaction_id", 'refundTransactionId', x."refund_transaction_id", 'receiptId', x."receipt_id", 'note', x."note", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."received_on")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."donations" x
      where x."tenant_id" = list_gifts.tenant
        and (not (v_filters -> 'donorType' is not null and jsonb_typeof(v_filters -> 'donorType') <> 'null' and not (jsonb_typeof(v_filters -> 'donorType') = 'array' and jsonb_array_length(v_filters -> 'donorType') = 0)) or x."donor_type" = any((case when jsonb_typeof(v_filters -> 'donorType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'donorType')) else array[v_filters ->> 'donorType'] end)::text[]))
        and (not (v_filters -> 'donorId' is not null and jsonb_typeof(v_filters -> 'donorId') <> 'null' and not (jsonb_typeof(v_filters -> 'donorId') = 'array' and jsonb_array_length(v_filters -> 'donorId') = 0)) or x."donor_id" = any((case when jsonb_typeof(v_filters -> 'donorId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'donorId')) else array[v_filters ->> 'donorId'] end)::text[]))
        and (not (v_filters -> 'fundId' is not null and jsonb_typeof(v_filters -> 'fundId') <> 'null' and not (jsonb_typeof(v_filters -> 'fundId') = 'array' and jsonb_array_length(v_filters -> 'fundId') = 0)) or x."fund_id" = any((case when jsonb_typeof(v_filters -> 'fundId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'fundId')) else array[v_filters ->> 'fundId'] end)::uuid[]))
        and (not (v_filters -> 'pledgeId' is not null and jsonb_typeof(v_filters -> 'pledgeId') <> 'null' and not (jsonb_typeof(v_filters -> 'pledgeId') = 'array' and jsonb_array_length(v_filters -> 'pledgeId') = 0)) or x."pledge_id" = any((case when jsonb_typeof(v_filters -> 'pledgeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pledgeId')) else array[v_filters ->> 'pledgeId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."donor_id" ilike v_search or coalesce(x."payment_reference", '') ilike v_search or coalesce(x."note", '') ilike v_search)
        and (v_after is null or (x."received_on" >= (v_after ->> 0)::date and ((x."received_on" > (v_after ->> 0)::date) or (x."received_on" = (v_after ->> 0)::date and x."created_at" < (v_after ->> 1)::timestamptz) or (x."received_on" = (v_after ->> 0)::date and x."created_at" = (v_after ->> 1)::timestamptz and x."id" < (v_after ->> 2)::uuid))))
      order by x."received_on" asc, x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'receivedOn' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DONATION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'donorType', x."donor_type", 'donorId', x."donor_id", 'fundId', x."fund_id", 'pledgeId', x."pledge_id", 'periodStart', x."period_start", 'amount', x."amount"::text, 'currency', x."currency", 'receivedOn', x."received_on", 'method', x."method", 'status', x."status", 'provider', x."provider", 'paymentReference', x."payment_reference", 'transactionId', x."transaction_id", 'refundTransactionId', x."refund_transaction_id", 'receiptId', x."receipt_id", 'note', x."note", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."received_on")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."donations" x
      where x."tenant_id" = list_gifts.tenant
        and (not (v_filters -> 'donorType' is not null and jsonb_typeof(v_filters -> 'donorType') <> 'null' and not (jsonb_typeof(v_filters -> 'donorType') = 'array' and jsonb_array_length(v_filters -> 'donorType') = 0)) or x."donor_type" = any((case when jsonb_typeof(v_filters -> 'donorType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'donorType')) else array[v_filters ->> 'donorType'] end)::text[]))
        and (not (v_filters -> 'donorId' is not null and jsonb_typeof(v_filters -> 'donorId') <> 'null' and not (jsonb_typeof(v_filters -> 'donorId') = 'array' and jsonb_array_length(v_filters -> 'donorId') = 0)) or x."donor_id" = any((case when jsonb_typeof(v_filters -> 'donorId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'donorId')) else array[v_filters ->> 'donorId'] end)::text[]))
        and (not (v_filters -> 'fundId' is not null and jsonb_typeof(v_filters -> 'fundId') <> 'null' and not (jsonb_typeof(v_filters -> 'fundId') = 'array' and jsonb_array_length(v_filters -> 'fundId') = 0)) or x."fund_id" = any((case when jsonb_typeof(v_filters -> 'fundId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'fundId')) else array[v_filters ->> 'fundId'] end)::uuid[]))
        and (not (v_filters -> 'pledgeId' is not null and jsonb_typeof(v_filters -> 'pledgeId') <> 'null' and not (jsonb_typeof(v_filters -> 'pledgeId') = 'array' and jsonb_array_length(v_filters -> 'pledgeId') = 0)) or x."pledge_id" = any((case when jsonb_typeof(v_filters -> 'pledgeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pledgeId')) else array[v_filters ->> 'pledgeId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."donor_id" ilike v_search or coalesce(x."payment_reference", '') ilike v_search or coalesce(x."note", '') ilike v_search)
        and (v_after is null or (x."received_on", x."created_at", x."id") < ((v_after ->> 0)::date, (v_after ->> 1)::timestamptz, (v_after ->> 2)::uuid))
      order by x."received_on" desc, x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DONATION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'donorType', x."donor_type", 'donorId', x."donor_id", 'fundId', x."fund_id", 'pledgeId', x."pledge_id", 'periodStart', x."period_start", 'amount', x."amount"::text, 'currency', x."currency", 'receivedOn', x."received_on", 'method', x."method", 'status', x."status", 'provider', x."provider", 'paymentReference', x."payment_reference", 'transactionId', x."transaction_id", 'refundTransactionId', x."refund_transaction_id", 'receiptId', x."receipt_id", 'note', x."note", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."donations" x
      where x."tenant_id" = list_gifts.tenant
        and (not (v_filters -> 'donorType' is not null and jsonb_typeof(v_filters -> 'donorType') <> 'null' and not (jsonb_typeof(v_filters -> 'donorType') = 'array' and jsonb_array_length(v_filters -> 'donorType') = 0)) or x."donor_type" = any((case when jsonb_typeof(v_filters -> 'donorType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'donorType')) else array[v_filters ->> 'donorType'] end)::text[]))
        and (not (v_filters -> 'donorId' is not null and jsonb_typeof(v_filters -> 'donorId') <> 'null' and not (jsonb_typeof(v_filters -> 'donorId') = 'array' and jsonb_array_length(v_filters -> 'donorId') = 0)) or x."donor_id" = any((case when jsonb_typeof(v_filters -> 'donorId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'donorId')) else array[v_filters ->> 'donorId'] end)::text[]))
        and (not (v_filters -> 'fundId' is not null and jsonb_typeof(v_filters -> 'fundId') <> 'null' and not (jsonb_typeof(v_filters -> 'fundId') = 'array' and jsonb_array_length(v_filters -> 'fundId') = 0)) or x."fund_id" = any((case when jsonb_typeof(v_filters -> 'fundId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'fundId')) else array[v_filters ->> 'fundId'] end)::uuid[]))
        and (not (v_filters -> 'pledgeId' is not null and jsonb_typeof(v_filters -> 'pledgeId') <> 'null' and not (jsonb_typeof(v_filters -> 'pledgeId') = 'array' and jsonb_array_length(v_filters -> 'pledgeId') = 0)) or x."pledge_id" = any((case when jsonb_typeof(v_filters -> 'pledgeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pledgeId')) else array[v_filters ->> 'pledgeId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."donor_id" ilike v_search or coalesce(x."payment_reference", '') ilike v_search or coalesce(x."note", '') ilike v_search)
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DONATION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'donorType', x."donor_type", 'donorId', x."donor_id", 'fundId', x."fund_id", 'pledgeId', x."pledge_id", 'periodStart', x."period_start", 'amount', x."amount"::text, 'currency', x."currency", 'receivedOn', x."received_on", 'method', x."method", 'status', x."status", 'provider', x."provider", 'paymentReference', x."payment_reference", 'transactionId', x."transaction_id", 'refundTransactionId', x."refund_transaction_id", 'receiptId', x."receipt_id", 'note', x."note", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."donations" x
      where x."tenant_id" = list_gifts.tenant
        and (not (v_filters -> 'donorType' is not null and jsonb_typeof(v_filters -> 'donorType') <> 'null' and not (jsonb_typeof(v_filters -> 'donorType') = 'array' and jsonb_array_length(v_filters -> 'donorType') = 0)) or x."donor_type" = any((case when jsonb_typeof(v_filters -> 'donorType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'donorType')) else array[v_filters ->> 'donorType'] end)::text[]))
        and (not (v_filters -> 'donorId' is not null and jsonb_typeof(v_filters -> 'donorId') <> 'null' and not (jsonb_typeof(v_filters -> 'donorId') = 'array' and jsonb_array_length(v_filters -> 'donorId') = 0)) or x."donor_id" = any((case when jsonb_typeof(v_filters -> 'donorId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'donorId')) else array[v_filters ->> 'donorId'] end)::text[]))
        and (not (v_filters -> 'fundId' is not null and jsonb_typeof(v_filters -> 'fundId') <> 'null' and not (jsonb_typeof(v_filters -> 'fundId') = 'array' and jsonb_array_length(v_filters -> 'fundId') = 0)) or x."fund_id" = any((case when jsonb_typeof(v_filters -> 'fundId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'fundId')) else array[v_filters ->> 'fundId'] end)::uuid[]))
        and (not (v_filters -> 'pledgeId' is not null and jsonb_typeof(v_filters -> 'pledgeId') <> 'null' and not (jsonb_typeof(v_filters -> 'pledgeId') = 'array' and jsonb_array_length(v_filters -> 'pledgeId') = 0)) or x."pledge_id" = any((case when jsonb_typeof(v_filters -> 'pledgeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pledgeId')) else array[v_filters ->> 'pledgeId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."donor_id" ilike v_search or coalesce(x."payment_reference", '') ilike v_search or coalesce(x."note", '') ilike v_search)
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
      select 1 from "better_supabase"."donations" x
      where x."tenant_id" = list_gifts.tenant
        and (not (v_filters -> 'donorType' is not null and jsonb_typeof(v_filters -> 'donorType') <> 'null' and not (jsonb_typeof(v_filters -> 'donorType') = 'array' and jsonb_array_length(v_filters -> 'donorType') = 0)) or x."donor_type" = any((case when jsonb_typeof(v_filters -> 'donorType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'donorType')) else array[v_filters ->> 'donorType'] end)::text[]))
        and (not (v_filters -> 'donorId' is not null and jsonb_typeof(v_filters -> 'donorId') <> 'null' and not (jsonb_typeof(v_filters -> 'donorId') = 'array' and jsonb_array_length(v_filters -> 'donorId') = 0)) or x."donor_id" = any((case when jsonb_typeof(v_filters -> 'donorId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'donorId')) else array[v_filters ->> 'donorId'] end)::text[]))
        and (not (v_filters -> 'fundId' is not null and jsonb_typeof(v_filters -> 'fundId') <> 'null' and not (jsonb_typeof(v_filters -> 'fundId') = 'array' and jsonb_array_length(v_filters -> 'fundId') = 0)) or x."fund_id" = any((case when jsonb_typeof(v_filters -> 'fundId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'fundId')) else array[v_filters ->> 'fundId'] end)::uuid[]))
        and (not (v_filters -> 'pledgeId' is not null and jsonb_typeof(v_filters -> 'pledgeId') <> 'null' and not (jsonb_typeof(v_filters -> 'pledgeId') = 'array' and jsonb_array_length(v_filters -> 'pledgeId') = 0)) or x."pledge_id" = any((case when jsonb_typeof(v_filters -> 'pledgeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pledgeId')) else array[v_filters ->> 'pledgeId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."donor_id" ilike v_search or coalesce(x."payment_reference", '') ilike v_search or coalesce(x."note", '') ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_pick_lists (
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
  v_filters jsonb := coalesce(list_pick_lists.filters, '{}'::jsonb);
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
  v_all boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_pick_lists.tenant is not null and coalesce(better_supabase.can('tenant', list_pick_lists.tenant, 'warehouse.read'), false)));
begin
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'documentType') then
      raise exception 'facet is one of status, documentType' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'documentType' then (x."document_type")::text end) as v
      from "better_supabase"."pick_lists" x
      where x."tenant_id" = list_pick_lists.tenant
        and (not (v_filters -> 'waveId' is not null and jsonb_typeof(v_filters -> 'waveId') <> 'null' and not (jsonb_typeof(v_filters -> 'waveId') = 'array' and jsonb_array_length(v_filters -> 'waveId') = 0)) or x."wave_id" = any((case when jsonb_typeof(v_filters -> 'waveId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'waveId')) else array[v_filters ->> 'waveId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'documentType' is not null and jsonb_typeof(v_filters -> 'documentType') <> 'null' and not (jsonb_typeof(v_filters -> 'documentType') = 'array' and jsonb_array_length(v_filters -> 'documentType') = 0)) or x."document_type" = any((case when jsonb_typeof(v_filters -> 'documentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentType')) else array[v_filters ->> 'documentType'] end)::text[]))
        and (not (v_filters -> 'documentId' is not null and jsonb_typeof(v_filters -> 'documentId') <> 'null' and not (jsonb_typeof(v_filters -> 'documentId') = 'array' and jsonb_array_length(v_filters -> 'documentId') = 0)) or x."document_id" = any((case when jsonb_typeof(v_filters -> 'documentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentId')) else array[v_filters ->> 'documentId'] end)::text[]))
        and ((v_all and not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false)) or coalesce(x."assignee_id" = auth.uid(), false))
        and (v_search is null or x."document_id" ilike v_search or x."document_type" ilike v_search)
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
      select 1 from "better_supabase"."pick_lists" x
      where x."tenant_id" = list_pick_lists.tenant
        and (not (v_filters -> 'waveId' is not null and jsonb_typeof(v_filters -> 'waveId') <> 'null' and not (jsonb_typeof(v_filters -> 'waveId') = 'array' and jsonb_array_length(v_filters -> 'waveId') = 0)) or x."wave_id" = any((case when jsonb_typeof(v_filters -> 'waveId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'waveId')) else array[v_filters ->> 'waveId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'documentType' is not null and jsonb_typeof(v_filters -> 'documentType') <> 'null' and not (jsonb_typeof(v_filters -> 'documentType') = 'array' and jsonb_array_length(v_filters -> 'documentType') = 0)) or x."document_type" = any((case when jsonb_typeof(v_filters -> 'documentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentType')) else array[v_filters ->> 'documentType'] end)::text[]))
        and (not (v_filters -> 'documentId' is not null and jsonb_typeof(v_filters -> 'documentId') <> 'null' and not (jsonb_typeof(v_filters -> 'documentId') = 'array' and jsonb_array_length(v_filters -> 'documentId') = 0)) or x."document_id" = any((case when jsonb_typeof(v_filters -> 'documentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentId')) else array[v_filters ->> 'documentId'] end)::text[]))
        and ((v_all and not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false)) or coalesce(x."assignee_id" = auth.uid(), false))
        and (v_search is null or x."document_id" ilike v_search or x."document_type" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'pickedAt') then
    raise exception 'sort is one of createdAt, pickedAt' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, "better_supabase"."pick_list_json"(x."id") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."pick_lists" x
      where x."tenant_id" = list_pick_lists.tenant
        and (not (v_filters -> 'waveId' is not null and jsonb_typeof(v_filters -> 'waveId') <> 'null' and not (jsonb_typeof(v_filters -> 'waveId') = 'array' and jsonb_array_length(v_filters -> 'waveId') = 0)) or x."wave_id" = any((case when jsonb_typeof(v_filters -> 'waveId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'waveId')) else array[v_filters ->> 'waveId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'documentType' is not null and jsonb_typeof(v_filters -> 'documentType') <> 'null' and not (jsonb_typeof(v_filters -> 'documentType') = 'array' and jsonb_array_length(v_filters -> 'documentType') = 0)) or x."document_type" = any((case when jsonb_typeof(v_filters -> 'documentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentType')) else array[v_filters ->> 'documentType'] end)::text[]))
        and (not (v_filters -> 'documentId' is not null and jsonb_typeof(v_filters -> 'documentId') <> 'null' and not (jsonb_typeof(v_filters -> 'documentId') = 'array' and jsonb_array_length(v_filters -> 'documentId') = 0)) or x."document_id" = any((case when jsonb_typeof(v_filters -> 'documentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentId')) else array[v_filters ->> 'documentId'] end)::text[]))
        and ((v_all and not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false)) or coalesce(x."assignee_id" = auth.uid(), false))
        and (v_search is null or x."document_id" ilike v_search or x."document_type" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, "better_supabase"."pick_list_json"(x."id") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."pick_lists" x
      where x."tenant_id" = list_pick_lists.tenant
        and (not (v_filters -> 'waveId' is not null and jsonb_typeof(v_filters -> 'waveId') <> 'null' and not (jsonb_typeof(v_filters -> 'waveId') = 'array' and jsonb_array_length(v_filters -> 'waveId') = 0)) or x."wave_id" = any((case when jsonb_typeof(v_filters -> 'waveId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'waveId')) else array[v_filters ->> 'waveId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'documentType' is not null and jsonb_typeof(v_filters -> 'documentType') <> 'null' and not (jsonb_typeof(v_filters -> 'documentType') = 'array' and jsonb_array_length(v_filters -> 'documentType') = 0)) or x."document_type" = any((case when jsonb_typeof(v_filters -> 'documentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentType')) else array[v_filters ->> 'documentType'] end)::text[]))
        and (not (v_filters -> 'documentId' is not null and jsonb_typeof(v_filters -> 'documentId') <> 'null' and not (jsonb_typeof(v_filters -> 'documentId') = 'array' and jsonb_array_length(v_filters -> 'documentId') = 0)) or x."document_id" = any((case when jsonb_typeof(v_filters -> 'documentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentId')) else array[v_filters ->> 'documentId'] end)::text[]))
        and ((v_all and not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false)) or coalesce(x."assignee_id" = auth.uid(), false))
        and (v_search is null or x."document_id" ilike v_search or x."document_type" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, "better_supabase"."pick_list_json"(x."id") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."pick_lists" x
      where x."tenant_id" = list_pick_lists.tenant
        and (not (v_filters -> 'waveId' is not null and jsonb_typeof(v_filters -> 'waveId') <> 'null' and not (jsonb_typeof(v_filters -> 'waveId') = 'array' and jsonb_array_length(v_filters -> 'waveId') = 0)) or x."wave_id" = any((case when jsonb_typeof(v_filters -> 'waveId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'waveId')) else array[v_filters ->> 'waveId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'documentType' is not null and jsonb_typeof(v_filters -> 'documentType') <> 'null' and not (jsonb_typeof(v_filters -> 'documentType') = 'array' and jsonb_array_length(v_filters -> 'documentType') = 0)) or x."document_type" = any((case when jsonb_typeof(v_filters -> 'documentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentType')) else array[v_filters ->> 'documentType'] end)::text[]))
        and (not (v_filters -> 'documentId' is not null and jsonb_typeof(v_filters -> 'documentId') <> 'null' and not (jsonb_typeof(v_filters -> 'documentId') = 'array' and jsonb_array_length(v_filters -> 'documentId') = 0)) or x."document_id" = any((case when jsonb_typeof(v_filters -> 'documentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentId')) else array[v_filters ->> 'documentId'] end)::text[]))
        and ((v_all and not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false)) or coalesce(x."assignee_id" = auth.uid(), false))
        and (v_search is null or x."document_id" ilike v_search or x."document_type" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, "better_supabase"."pick_list_json"(x."id") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."pick_lists" x
      where x."tenant_id" = list_pick_lists.tenant
        and (not (v_filters -> 'waveId' is not null and jsonb_typeof(v_filters -> 'waveId') <> 'null' and not (jsonb_typeof(v_filters -> 'waveId') = 'array' and jsonb_array_length(v_filters -> 'waveId') = 0)) or x."wave_id" = any((case when jsonb_typeof(v_filters -> 'waveId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'waveId')) else array[v_filters ->> 'waveId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'documentType' is not null and jsonb_typeof(v_filters -> 'documentType') <> 'null' and not (jsonb_typeof(v_filters -> 'documentType') = 'array' and jsonb_array_length(v_filters -> 'documentType') = 0)) or x."document_type" = any((case when jsonb_typeof(v_filters -> 'documentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentType')) else array[v_filters ->> 'documentType'] end)::text[]))
        and (not (v_filters -> 'documentId' is not null and jsonb_typeof(v_filters -> 'documentId') <> 'null' and not (jsonb_typeof(v_filters -> 'documentId') = 'array' and jsonb_array_length(v_filters -> 'documentId') = 0)) or x."document_id" = any((case when jsonb_typeof(v_filters -> 'documentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentId')) else array[v_filters ->> 'documentId'] end)::text[]))
        and ((v_all and not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false)) or coalesce(x."assignee_id" = auth.uid(), false))
        and (v_search is null or x."document_id" ilike v_search or x."document_type" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'pickedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, "better_supabase"."pick_list_json"(x."id") as j, jsonb_build_array((coalesce(x."picked_at", '-infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."pick_lists" x
      where x."tenant_id" = list_pick_lists.tenant
        and (not (v_filters -> 'waveId' is not null and jsonb_typeof(v_filters -> 'waveId') <> 'null' and not (jsonb_typeof(v_filters -> 'waveId') = 'array' and jsonb_array_length(v_filters -> 'waveId') = 0)) or x."wave_id" = any((case when jsonb_typeof(v_filters -> 'waveId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'waveId')) else array[v_filters ->> 'waveId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'documentType' is not null and jsonb_typeof(v_filters -> 'documentType') <> 'null' and not (jsonb_typeof(v_filters -> 'documentType') = 'array' and jsonb_array_length(v_filters -> 'documentType') = 0)) or x."document_type" = any((case when jsonb_typeof(v_filters -> 'documentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentType')) else array[v_filters ->> 'documentType'] end)::text[]))
        and (not (v_filters -> 'documentId' is not null and jsonb_typeof(v_filters -> 'documentId') <> 'null' and not (jsonb_typeof(v_filters -> 'documentId') = 'array' and jsonb_array_length(v_filters -> 'documentId') = 0)) or x."document_id" = any((case when jsonb_typeof(v_filters -> 'documentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentId')) else array[v_filters ->> 'documentId'] end)::text[]))
        and ((v_all and not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false)) or coalesce(x."assignee_id" = auth.uid(), false))
        and (v_search is null or x."document_id" ilike v_search or x."document_type" ilike v_search)
        and (v_after is null or (coalesce(x."picked_at", '-infinity'::timestamptz), x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."picked_at", '-infinity'::timestamptz) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'pickedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, "better_supabase"."pick_list_json"(x."id") as j, jsonb_build_array((coalesce(x."picked_at", '-infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."pick_lists" x
      where x."tenant_id" = list_pick_lists.tenant
        and (not (v_filters -> 'waveId' is not null and jsonb_typeof(v_filters -> 'waveId') <> 'null' and not (jsonb_typeof(v_filters -> 'waveId') = 'array' and jsonb_array_length(v_filters -> 'waveId') = 0)) or x."wave_id" = any((case when jsonb_typeof(v_filters -> 'waveId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'waveId')) else array[v_filters ->> 'waveId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'documentType' is not null and jsonb_typeof(v_filters -> 'documentType') <> 'null' and not (jsonb_typeof(v_filters -> 'documentType') = 'array' and jsonb_array_length(v_filters -> 'documentType') = 0)) or x."document_type" = any((case when jsonb_typeof(v_filters -> 'documentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentType')) else array[v_filters ->> 'documentType'] end)::text[]))
        and (not (v_filters -> 'documentId' is not null and jsonb_typeof(v_filters -> 'documentId') <> 'null' and not (jsonb_typeof(v_filters -> 'documentId') = 'array' and jsonb_array_length(v_filters -> 'documentId') = 0)) or x."document_id" = any((case when jsonb_typeof(v_filters -> 'documentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentId')) else array[v_filters ->> 'documentId'] end)::text[]))
        and ((v_all and not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false)) or coalesce(x."assignee_id" = auth.uid(), false))
        and (v_search is null or x."document_id" ilike v_search or x."document_type" ilike v_search)
        and (v_after is null or (coalesce(x."picked_at", '-infinity'::timestamptz) <= (v_after ->> 0)::timestamptz and ((coalesce(x."picked_at", '-infinity'::timestamptz) < (v_after ->> 0)::timestamptz) or (coalesce(x."picked_at", '-infinity'::timestamptz) = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."picked_at", '-infinity'::timestamptz) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."pick_lists" x
      where x."tenant_id" = list_pick_lists.tenant
        and (not (v_filters -> 'waveId' is not null and jsonb_typeof(v_filters -> 'waveId') <> 'null' and not (jsonb_typeof(v_filters -> 'waveId') = 'array' and jsonb_array_length(v_filters -> 'waveId') = 0)) or x."wave_id" = any((case when jsonb_typeof(v_filters -> 'waveId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'waveId')) else array[v_filters ->> 'waveId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'documentType' is not null and jsonb_typeof(v_filters -> 'documentType') <> 'null' and not (jsonb_typeof(v_filters -> 'documentType') = 'array' and jsonb_array_length(v_filters -> 'documentType') = 0)) or x."document_type" = any((case when jsonb_typeof(v_filters -> 'documentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentType')) else array[v_filters ->> 'documentType'] end)::text[]))
        and (not (v_filters -> 'documentId' is not null and jsonb_typeof(v_filters -> 'documentId') <> 'null' and not (jsonb_typeof(v_filters -> 'documentId') = 'array' and jsonb_array_length(v_filters -> 'documentId') = 0)) or x."document_id" = any((case when jsonb_typeof(v_filters -> 'documentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentId')) else array[v_filters ->> 'documentId'] end)::text[]))
        and ((v_all and not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false)) or coalesce(x."assignee_id" = auth.uid(), false))
        and (v_search is null or x."document_id" ilike v_search or x."document_type" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_pledges (
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
  v_filters jsonb := coalesce(list_pledges.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 100), 1), 1000);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_pledges.tenant, 'donations.read'), false)) then
    raise exception 'not allowed to read donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'DONATION_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status') then
      raise exception 'facet is one of status' using errcode = '22023', hint = 'DONATION_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text end) as v
      from "better_supabase"."pledges" x
      where x."tenant_id" = list_pledges.tenant
        and (not (v_filters -> 'donorType' is not null and jsonb_typeof(v_filters -> 'donorType') <> 'null' and not (jsonb_typeof(v_filters -> 'donorType') = 'array' and jsonb_array_length(v_filters -> 'donorType') = 0)) or x."donor_type" = any((case when jsonb_typeof(v_filters -> 'donorType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'donorType')) else array[v_filters ->> 'donorType'] end)::text[]))
        and (not (v_filters -> 'donorId' is not null and jsonb_typeof(v_filters -> 'donorId') <> 'null' and not (jsonb_typeof(v_filters -> 'donorId') = 'array' and jsonb_array_length(v_filters -> 'donorId') = 0)) or x."donor_id" = any((case when jsonb_typeof(v_filters -> 'donorId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'donorId')) else array[v_filters ->> 'donorId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."donor_id" ilike v_search or coalesce(x."note", '') ilike v_search)
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
      select 1 from "better_supabase"."pledges" x
      where x."tenant_id" = list_pledges.tenant
        and (not (v_filters -> 'donorType' is not null and jsonb_typeof(v_filters -> 'donorType') <> 'null' and not (jsonb_typeof(v_filters -> 'donorType') = 'array' and jsonb_array_length(v_filters -> 'donorType') = 0)) or x."donor_type" = any((case when jsonb_typeof(v_filters -> 'donorType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'donorType')) else array[v_filters ->> 'donorType'] end)::text[]))
        and (not (v_filters -> 'donorId' is not null and jsonb_typeof(v_filters -> 'donorId') <> 'null' and not (jsonb_typeof(v_filters -> 'donorId') = 'array' and jsonb_array_length(v_filters -> 'donorId') = 0)) or x."donor_id" = any((case when jsonb_typeof(v_filters -> 'donorId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'donorId')) else array[v_filters ->> 'donorId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."donor_id" ilike v_search or coalesce(x."note", '') ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt') then
    raise exception 'sort is one of createdAt' using errcode = '22023', hint = 'DONATION_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'DONATION_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DONATION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'donorType', x."donor_type", 'donorId', x."donor_id", 'fundId', x."fund_id", 'amount', x."amount"::text, 'currency', x."currency", 'frequency', x."frequency", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'status', x."status", 'provider', x."provider", 'providerCustomer', x."provider_customer", 'note', x."note", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."pledges" x
      where x."tenant_id" = list_pledges.tenant
        and (not (v_filters -> 'donorType' is not null and jsonb_typeof(v_filters -> 'donorType') <> 'null' and not (jsonb_typeof(v_filters -> 'donorType') = 'array' and jsonb_array_length(v_filters -> 'donorType') = 0)) or x."donor_type" = any((case when jsonb_typeof(v_filters -> 'donorType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'donorType')) else array[v_filters ->> 'donorType'] end)::text[]))
        and (not (v_filters -> 'donorId' is not null and jsonb_typeof(v_filters -> 'donorId') <> 'null' and not (jsonb_typeof(v_filters -> 'donorId') = 'array' and jsonb_array_length(v_filters -> 'donorId') = 0)) or x."donor_id" = any((case when jsonb_typeof(v_filters -> 'donorId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'donorId')) else array[v_filters ->> 'donorId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."donor_id" ilike v_search or coalesce(x."note", '') ilike v_search)
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DONATION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'donorType', x."donor_type", 'donorId', x."donor_id", 'fundId', x."fund_id", 'amount', x."amount"::text, 'currency', x."currency", 'frequency', x."frequency", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'status', x."status", 'provider', x."provider", 'providerCustomer', x."provider_customer", 'note', x."note", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."pledges" x
      where x."tenant_id" = list_pledges.tenant
        and (not (v_filters -> 'donorType' is not null and jsonb_typeof(v_filters -> 'donorType') <> 'null' and not (jsonb_typeof(v_filters -> 'donorType') = 'array' and jsonb_array_length(v_filters -> 'donorType') = 0)) or x."donor_type" = any((case when jsonb_typeof(v_filters -> 'donorType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'donorType')) else array[v_filters ->> 'donorType'] end)::text[]))
        and (not (v_filters -> 'donorId' is not null and jsonb_typeof(v_filters -> 'donorId') <> 'null' and not (jsonb_typeof(v_filters -> 'donorId') = 'array' and jsonb_array_length(v_filters -> 'donorId') = 0)) or x."donor_id" = any((case when jsonb_typeof(v_filters -> 'donorId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'donorId')) else array[v_filters ->> 'donorId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."donor_id" ilike v_search or coalesce(x."note", '') ilike v_search)
        and (v_after is null or (x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DONATION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'donorType', x."donor_type", 'donorId', x."donor_id", 'fundId', x."fund_id", 'amount', x."amount"::text, 'currency', x."currency", 'frequency', x."frequency", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'status', x."status", 'provider', x."provider", 'providerCustomer', x."provider_customer", 'note', x."note", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."pledges" x
      where x."tenant_id" = list_pledges.tenant
        and (not (v_filters -> 'donorType' is not null and jsonb_typeof(v_filters -> 'donorType') <> 'null' and not (jsonb_typeof(v_filters -> 'donorType') = 'array' and jsonb_array_length(v_filters -> 'donorType') = 0)) or x."donor_type" = any((case when jsonb_typeof(v_filters -> 'donorType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'donorType')) else array[v_filters ->> 'donorType'] end)::text[]))
        and (not (v_filters -> 'donorId' is not null and jsonb_typeof(v_filters -> 'donorId') <> 'null' and not (jsonb_typeof(v_filters -> 'donorId') = 'array' and jsonb_array_length(v_filters -> 'donorId') = 0)) or x."donor_id" = any((case when jsonb_typeof(v_filters -> 'donorId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'donorId')) else array[v_filters ->> 'donorId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."donor_id" ilike v_search or coalesce(x."note", '') ilike v_search)
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DONATION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'donorType', x."donor_type", 'donorId', x."donor_id", 'fundId', x."fund_id", 'amount', x."amount"::text, 'currency', x."currency", 'frequency', x."frequency", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'status', x."status", 'provider', x."provider", 'providerCustomer', x."provider_customer", 'note', x."note", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."pledges" x
      where x."tenant_id" = list_pledges.tenant
        and (not (v_filters -> 'donorType' is not null and jsonb_typeof(v_filters -> 'donorType') <> 'null' and not (jsonb_typeof(v_filters -> 'donorType') = 'array' and jsonb_array_length(v_filters -> 'donorType') = 0)) or x."donor_type" = any((case when jsonb_typeof(v_filters -> 'donorType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'donorType')) else array[v_filters ->> 'donorType'] end)::text[]))
        and (not (v_filters -> 'donorId' is not null and jsonb_typeof(v_filters -> 'donorId') <> 'null' and not (jsonb_typeof(v_filters -> 'donorId') = 'array' and jsonb_array_length(v_filters -> 'donorId') = 0)) or x."donor_id" = any((case when jsonb_typeof(v_filters -> 'donorId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'donorId')) else array[v_filters ->> 'donorId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."donor_id" ilike v_search or coalesce(x."note", '') ilike v_search)
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
      select 1 from "better_supabase"."pledges" x
      where x."tenant_id" = list_pledges.tenant
        and (not (v_filters -> 'donorType' is not null and jsonb_typeof(v_filters -> 'donorType') <> 'null' and not (jsonb_typeof(v_filters -> 'donorType') = 'array' and jsonb_array_length(v_filters -> 'donorType') = 0)) or x."donor_type" = any((case when jsonb_typeof(v_filters -> 'donorType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'donorType')) else array[v_filters ->> 'donorType'] end)::text[]))
        and (not (v_filters -> 'donorId' is not null and jsonb_typeof(v_filters -> 'donorId') <> 'null' and not (jsonb_typeof(v_filters -> 'donorId') = 'array' and jsonb_array_length(v_filters -> 'donorId') = 0)) or x."donor_id" = any((case when jsonb_typeof(v_filters -> 'donorId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'donorId')) else array[v_filters ->> 'donorId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."donor_id" ilike v_search or coalesce(x."note", '') ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_stock_bins (
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
  v_filters jsonb := coalesce(page_stock_bins.filters, '{}'::jsonb);
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
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('locationId', 'active') then
      raise exception 'facet is one of locationId, active' using errcode = '22023', hint = 'INVENTORY_INVALID';
    end if;
    with s as (
      select (case v_facet when 'locationId' then (x."location_id"::text)::text when 'active' then (x."active"::text)::text end) as v
      from "better_supabase"."stock_bins" x
      where x."tenant_id" = page_stock_bins.tenant
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id" = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::uuid[]))
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or x."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
        and (not (v_filters -> 'hold' is not null and jsonb_typeof(v_filters -> 'hold') <> 'null' and not (jsonb_typeof(v_filters -> 'hold') = 'array' and jsonb_array_length(v_filters -> 'hold') = 0)) or x."hold"::text = any((case when jsonb_typeof(v_filters -> 'hold') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'hold')) else array[v_filters ->> 'hold'] end)::text[]))
        and (v_search is null or x."code" ilike v_search or coalesce(x."name", '') ilike v_search)
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
      select 1 from "better_supabase"."stock_bins" x
      where x."tenant_id" = page_stock_bins.tenant
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id" = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::uuid[]))
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or x."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
        and (not (v_filters -> 'hold' is not null and jsonb_typeof(v_filters -> 'hold') <> 'null' and not (jsonb_typeof(v_filters -> 'hold') = 'array' and jsonb_array_length(v_filters -> 'hold') = 0)) or x."hold"::text = any((case when jsonb_typeof(v_filters -> 'hold') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'hold')) else array[v_filters ->> 'hold'] end)::text[]))
        and (v_search is null or x."code" ilike v_search or coalesce(x."name", '') ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('code') then
    raise exception 'sort is one of code' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'locationId', x."location_id", 'code', x."code", 'name', x."name", 'hold', x."hold", 'active', x."active") as j, jsonb_build_array((x."code")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."stock_bins" x
      where x."tenant_id" = page_stock_bins.tenant
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id" = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::uuid[]))
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or x."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
        and (not (v_filters -> 'hold' is not null and jsonb_typeof(v_filters -> 'hold') <> 'null' and not (jsonb_typeof(v_filters -> 'hold') = 'array' and jsonb_array_length(v_filters -> 'hold') = 0)) or x."hold"::text = any((case when jsonb_typeof(v_filters -> 'hold') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'hold')) else array[v_filters ->> 'hold'] end)::text[]))
        and (v_search is null or x."code" ilike v_search or coalesce(x."name", '') ilike v_search)
        and (v_after is null or (x."code", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."code" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'locationId', x."location_id", 'code', x."code", 'name', x."name", 'hold', x."hold", 'active', x."active") as j, jsonb_build_array((x."code")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."stock_bins" x
      where x."tenant_id" = page_stock_bins.tenant
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id" = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::uuid[]))
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or x."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
        and (not (v_filters -> 'hold' is not null and jsonb_typeof(v_filters -> 'hold') <> 'null' and not (jsonb_typeof(v_filters -> 'hold') = 'array' and jsonb_array_length(v_filters -> 'hold') = 0)) or x."hold"::text = any((case when jsonb_typeof(v_filters -> 'hold') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'hold')) else array[v_filters ->> 'hold'] end)::text[]))
        and (v_search is null or x."code" ilike v_search or coalesce(x."name", '') ilike v_search)
        and (v_after is null or (x."code" <= (v_after ->> 0)::text and ((x."code" < (v_after ->> 0)::text) or (x."code" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."code" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'code' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'locationId', x."location_id", 'code', x."code", 'name', x."name", 'hold', x."hold", 'active', x."active") as j, jsonb_build_array((x."code")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."stock_bins" x
      where x."tenant_id" = page_stock_bins.tenant
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id" = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::uuid[]))
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or x."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
        and (not (v_filters -> 'hold' is not null and jsonb_typeof(v_filters -> 'hold') <> 'null' and not (jsonb_typeof(v_filters -> 'hold') = 'array' and jsonb_array_length(v_filters -> 'hold') = 0)) or x."hold"::text = any((case when jsonb_typeof(v_filters -> 'hold') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'hold')) else array[v_filters ->> 'hold'] end)::text[]))
        and (v_search is null or x."code" ilike v_search or coalesce(x."name", '') ilike v_search)
        and (v_after is null or (x."code", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."code" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'code' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'locationId', x."location_id", 'code', x."code", 'name', x."name", 'hold', x."hold", 'active', x."active") as j, jsonb_build_array((x."code")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."stock_bins" x
      where x."tenant_id" = page_stock_bins.tenant
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id" = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::uuid[]))
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or x."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
        and (not (v_filters -> 'hold' is not null and jsonb_typeof(v_filters -> 'hold') <> 'null' and not (jsonb_typeof(v_filters -> 'hold') = 'array' and jsonb_array_length(v_filters -> 'hold') = 0)) or x."hold"::text = any((case when jsonb_typeof(v_filters -> 'hold') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'hold')) else array[v_filters ->> 'hold'] end)::text[]))
        and (v_search is null or x."code" ilike v_search or coalesce(x."name", '') ilike v_search)
        and (v_after is null or (x."code" <= (v_after ->> 0)::text and ((x."code" < (v_after ->> 0)::text) or (x."code" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."code" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."stock_bins" x
      where x."tenant_id" = page_stock_bins.tenant
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id" = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::uuid[]))
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or x."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
        and (not (v_filters -> 'hold' is not null and jsonb_typeof(v_filters -> 'hold') <> 'null' and not (jsonb_typeof(v_filters -> 'hold') = 'array' and jsonb_array_length(v_filters -> 'hold') = 0)) or x."hold"::text = any((case when jsonb_typeof(v_filters -> 'hold') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'hold')) else array[v_filters ->> 'hold'] end)::text[]))
        and (v_search is null or x."code" ilike v_search or coalesce(x."name", '') ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_stock_locations (
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
  v_filters jsonb := coalesce(page_stock_locations.filters, '{}'::jsonb);
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
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('kind', 'active') then
      raise exception 'facet is one of kind, active' using errcode = '22023', hint = 'INVENTORY_INVALID';
    end if;
    with s as (
      select (case v_facet when 'kind' then (x."kind")::text when 'active' then (x."active"::text)::text end) as v
      from "better_supabase"."inventory_locations" x
      where x."tenant_id" = page_stock_locations.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or x."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
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
      select 1 from "better_supabase"."inventory_locations" x
      where x."tenant_id" = page_stock_locations.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or x."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
        and (v_search is null or x."code" ilike v_search or x."name" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('code', 'name') then
    raise exception 'sort is one of code, name' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'code', x."code", 'name', x."name", 'kind', x."kind", 'active', x."active") as j, jsonb_build_array((x."code")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."inventory_locations" x
      where x."tenant_id" = page_stock_locations.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or x."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
        and (v_search is null or x."code" ilike v_search or x."name" ilike v_search)
        and (v_after is null or (x."code", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."code" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'code', x."code", 'name', x."name", 'kind', x."kind", 'active', x."active") as j, jsonb_build_array((x."code")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."inventory_locations" x
      where x."tenant_id" = page_stock_locations.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or x."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
        and (v_search is null or x."code" ilike v_search or x."name" ilike v_search)
        and (v_after is null or (x."code" <= (v_after ->> 0)::text and ((x."code" < (v_after ->> 0)::text) or (x."code" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."code" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'code' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'code', x."code", 'name', x."name", 'kind', x."kind", 'active', x."active") as j, jsonb_build_array((x."code")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."inventory_locations" x
      where x."tenant_id" = page_stock_locations.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or x."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
        and (v_search is null or x."code" ilike v_search or x."name" ilike v_search)
        and (v_after is null or (x."code", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."code" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'code' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'code', x."code", 'name', x."name", 'kind', x."kind", 'active', x."active") as j, jsonb_build_array((x."code")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."inventory_locations" x
      where x."tenant_id" = page_stock_locations.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or x."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
        and (v_search is null or x."code" ilike v_search or x."name" ilike v_search)
        and (v_after is null or (x."code" <= (v_after ->> 0)::text and ((x."code" < (v_after ->> 0)::text) or (x."code" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."code" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'code', x."code", 'name', x."name", 'kind', x."kind", 'active', x."active") as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."inventory_locations" x
      where x."tenant_id" = page_stock_locations.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or x."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
        and (v_search is null or x."code" ilike v_search or x."name" ilike v_search)
        and (v_after is null or (x."name", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."name" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'code', x."code", 'name', x."name", 'kind', x."kind", 'active', x."active") as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."inventory_locations" x
      where x."tenant_id" = page_stock_locations.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or x."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
        and (v_search is null or x."code" ilike v_search or x."name" ilike v_search)
        and (v_after is null or (x."name" <= (v_after ->> 0)::text and ((x."name" < (v_after ->> 0)::text) or (x."name" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."name" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."inventory_locations" x
      where x."tenant_id" = page_stock_locations.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or x."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
        and (v_search is null or x."code" ilike v_search or x."name" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_stock_variants (
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
  v_filters jsonb := coalesce(page_stock_variants.filters, '{}'::jsonb);
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
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "better_supabase"."product_variants" x
      where x."tenant_id" = page_stock_variants.tenant
        and (not (v_filters -> 'productId' is not null and jsonb_typeof(v_filters -> 'productId') <> 'null' and not (jsonb_typeof(v_filters -> 'productId') = 'array' and jsonb_array_length(v_filters -> 'productId') = 0)) or x."product_id" = any((case when jsonb_typeof(v_filters -> 'productId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'productId')) else array[v_filters ->> 'productId'] end)::uuid[]))
        and (v_search is null or x."sku" ilike v_search or coalesce(x."title", '') ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('sku', 'title') then
    raise exception 'sort is one of sku, title' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'productId', x."product_id", 'sku', x."sku", 'title', x."title") as j, jsonb_build_array((x."sku")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."product_variants" x
      where x."tenant_id" = page_stock_variants.tenant
        and (not (v_filters -> 'productId' is not null and jsonb_typeof(v_filters -> 'productId') <> 'null' and not (jsonb_typeof(v_filters -> 'productId') = 'array' and jsonb_array_length(v_filters -> 'productId') = 0)) or x."product_id" = any((case when jsonb_typeof(v_filters -> 'productId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'productId')) else array[v_filters ->> 'productId'] end)::uuid[]))
        and (v_search is null or x."sku" ilike v_search or coalesce(x."title", '') ilike v_search)
        and (v_after is null or (x."sku", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."sku" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'productId', x."product_id", 'sku', x."sku", 'title', x."title") as j, jsonb_build_array((x."sku")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."product_variants" x
      where x."tenant_id" = page_stock_variants.tenant
        and (not (v_filters -> 'productId' is not null and jsonb_typeof(v_filters -> 'productId') <> 'null' and not (jsonb_typeof(v_filters -> 'productId') = 'array' and jsonb_array_length(v_filters -> 'productId') = 0)) or x."product_id" = any((case when jsonb_typeof(v_filters -> 'productId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'productId')) else array[v_filters ->> 'productId'] end)::uuid[]))
        and (v_search is null or x."sku" ilike v_search or coalesce(x."title", '') ilike v_search)
        and (v_after is null or (x."sku" <= (v_after ->> 0)::text and ((x."sku" < (v_after ->> 0)::text) or (x."sku" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."sku" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'sku' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'productId', x."product_id", 'sku', x."sku", 'title', x."title") as j, jsonb_build_array((x."sku")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."product_variants" x
      where x."tenant_id" = page_stock_variants.tenant
        and (not (v_filters -> 'productId' is not null and jsonb_typeof(v_filters -> 'productId') <> 'null' and not (jsonb_typeof(v_filters -> 'productId') = 'array' and jsonb_array_length(v_filters -> 'productId') = 0)) or x."product_id" = any((case when jsonb_typeof(v_filters -> 'productId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'productId')) else array[v_filters ->> 'productId'] end)::uuid[]))
        and (v_search is null or x."sku" ilike v_search or coalesce(x."title", '') ilike v_search)
        and (v_after is null or (x."sku", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."sku" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'sku' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'productId', x."product_id", 'sku', x."sku", 'title', x."title") as j, jsonb_build_array((x."sku")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."product_variants" x
      where x."tenant_id" = page_stock_variants.tenant
        and (not (v_filters -> 'productId' is not null and jsonb_typeof(v_filters -> 'productId') <> 'null' and not (jsonb_typeof(v_filters -> 'productId') = 'array' and jsonb_array_length(v_filters -> 'productId') = 0)) or x."product_id" = any((case when jsonb_typeof(v_filters -> 'productId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'productId')) else array[v_filters ->> 'productId'] end)::uuid[]))
        and (v_search is null or x."sku" ilike v_search or coalesce(x."title", '') ilike v_search)
        and (v_after is null or (x."sku" <= (v_after ->> 0)::text and ((x."sku" < (v_after ->> 0)::text) or (x."sku" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."sku" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'productId', x."product_id", 'sku', x."sku", 'title', x."title") as j, jsonb_build_array((x."title")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."product_variants" x
      where x."tenant_id" = page_stock_variants.tenant
        and (not (v_filters -> 'productId' is not null and jsonb_typeof(v_filters -> 'productId') <> 'null' and not (jsonb_typeof(v_filters -> 'productId') = 'array' and jsonb_array_length(v_filters -> 'productId') = 0)) or x."product_id" = any((case when jsonb_typeof(v_filters -> 'productId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'productId')) else array[v_filters ->> 'productId'] end)::uuid[]))
        and (v_search is null or x."sku" ilike v_search or coalesce(x."title", '') ilike v_search)
        and (v_after is null or (x."title", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."title" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'productId', x."product_id", 'sku', x."sku", 'title', x."title") as j, jsonb_build_array((x."title")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."product_variants" x
      where x."tenant_id" = page_stock_variants.tenant
        and (not (v_filters -> 'productId' is not null and jsonb_typeof(v_filters -> 'productId') <> 'null' and not (jsonb_typeof(v_filters -> 'productId') = 'array' and jsonb_array_length(v_filters -> 'productId') = 0)) or x."product_id" = any((case when jsonb_typeof(v_filters -> 'productId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'productId')) else array[v_filters ->> 'productId'] end)::uuid[]))
        and (v_search is null or x."sku" ilike v_search or coalesce(x."title", '') ilike v_search)
        and (v_after is null or (x."title" <= (v_after ->> 0)::text and ((x."title" < (v_after ->> 0)::text) or (x."title" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."title" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."product_variants" x
      where x."tenant_id" = page_stock_variants.tenant
        and (not (v_filters -> 'productId' is not null and jsonb_typeof(v_filters -> 'productId') <> 'null' and not (jsonb_typeof(v_filters -> 'productId') = 'array' and jsonb_array_length(v_filters -> 'productId') = 0)) or x."product_id" = any((case when jsonb_typeof(v_filters -> 'productId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'productId')) else array[v_filters ->> 'productId'] end)::uuid[]))
        and (v_search is null or x."sku" ilike v_search or coalesce(x."title", '') ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.review_queue (
  tenant       uuid,
  status       text                     DEFAULT 'pending'::text,
  page_size    integer                  DEFAULT 50,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  subject_type text                     DEFAULT NULL::text,
  subject_id   text                     DEFAULT NULL::text,
  statuses     text[]                   DEFAULT NULL::text[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_rows jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', review_queue.tenant, 'reviews.manage'), false)) then
    raise exception 'not allowed to moderate reviews' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(q.item order by q.created desc, q.id desc), '[]'::jsonb) into v_rows
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'authorId', x."author_id", 'authorName', x."author_name", 'mine', coalesce(x."author_id" = auth.uid(), false), 'rating', x."rating", 'title', x."title", 'body', x."body", 'status', x."status", 'verified', x."verified", 'rejectionReason', x."rejection_reason", 'reply', x."reply", 'repliedAt', x."replied_at", 'publishedAt', x."published_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as item, x."created_at" as created, x."id" as id
    from "better_supabase"."reviews" x
    where x."tenant_id" = review_queue.tenant
      and (review_queue.status is null or x."status" = review_queue.status)
      and (coalesce(cardinality(review_queue.statuses), 0) = 0 or x."status" in (select s from unnest(review_queue.statuses) s))
      and (review_queue.subject_type is null or x."subject_type" = review_queue.subject_type)
      and (review_queue.subject_id is null or x."subject_id" = review_queue.subject_id)
      and (review_queue.before is null or x."created_at" < review_queue.before)
    order by x."created_at" desc, x."id" desc
    limit least(greatest(coalesce(review_queue.page_size, 50), 1), 200)
  ) q;
  return v_rows;
end;
$function$;

REVOKE ALL ON FUNCTION "api"."page_stock_bins"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_stock_bins"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_stock_locations"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_stock_locations"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_stock_variants"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_stock_variants"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."review_queue"(uuid, text, integer, timestamp WITH time zone, text, text, text[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."review_queue"(uuid, text, integer, timestamp WITH time zone, text, text, text[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_stock_bins"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_stock_bins"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_stock_locations"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_stock_locations"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_stock_variants"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_stock_variants"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."review_queue"(uuid, text, integer, timestamp WITH time zone, text, text, text[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."review_queue"(uuid, text, integer, timestamp WITH time zone, text, text, text[]) TO "authenticated", "service_role";
