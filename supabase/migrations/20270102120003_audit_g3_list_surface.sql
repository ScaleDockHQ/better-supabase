SET local check_function_bodies = off;

DROP FUNCTION "api"."list_gifts"(uuid, text, text, uuid, uuid, text, integer);

DROP FUNCTION "api"."list_leases"(uuid, text, uuid, text, text, integer);

DROP FUNCTION "api"."list_pledges"(uuid, text, text, text, integer);

DROP FUNCTION "api"."list_production_orders"(uuid, jsonb);

DROP FUNCTION "api"."list_shipments"(uuid, text, text, text, text, timestamp WITH time zone, integer);

DROP FUNCTION "better_supabase"."list_gifts"(uuid, text, text, uuid, uuid, text, integer);

DROP FUNCTION "better_supabase"."list_leases"(uuid, text, uuid, text, text, integer);

DROP FUNCTION "better_supabase"."list_pledges"(uuid, text, text, text, integer);

DROP FUNCTION "better_supabase"."list_production_orders"(uuid, jsonb);

DROP FUNCTION "better_supabase"."list_shipments"(uuid, text, text, text, text, timestamp WITH time zone, integer);

CREATE OR REPLACE FUNCTION api.list_gifts (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_gifts"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_leases (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_leases"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_pledges (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_pledges"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_production_orders (
  tenant  uuid,
  filters jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_production_orders"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_shipments (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_shipments"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.list_commission_plans (
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
  v_filters jsonb := coalesce(list_commission_plans.filters, '{}'::jsonb);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_commission_plans.tenant is not null and coalesce(better_supabase.can('tenant', list_commission_plans.tenant, 'commissions.read'), false))) then
    raise exception 'not allowed to read commission plans' using errcode = '42501', hint = 'COMMISSION_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('kind') then
      raise exception 'facet is one of kind' using errcode = '22023', hint = 'COMMISSION_INVALID';
    end if;
    with s as (
      select (case v_facet when 'kind' then (x."kind")::text end) as v
      from "better_supabase"."commission_plans" x
      where x."tenant_id" = list_commission_plans.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
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
      select 1 from "better_supabase"."commission_plans" x
      where x."tenant_id" = list_commission_plans.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'name') then
    raise exception 'sort is one of createdAt, name' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'kind', x."kind", 'rateBps', x."rate_bps", 'tiers', x."tiers", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('assignments', coalesce((
        select jsonb_agg(jsonb_build_object('id', a."id", 'organizationId', a."tenant_id", 'planId', a."plan_id", 'sellerId', a."seller_id", 'subjectType', a."subject_type", 'subjectId', a."subject_id", 'startsOn', a."starts_on", 'endsOn', a."ends_on", 'createdAt', a."created_at") order by a."starts_on" desc, a."created_at" desc)
        from "better_supabase"."commission_assignments" a where a."plan_id" = x."id"
      ), '[]'::jsonb)) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."commission_plans" x
      where x."tenant_id" = list_commission_plans.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'kind', x."kind", 'rateBps', x."rate_bps", 'tiers', x."tiers", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('assignments', coalesce((
        select jsonb_agg(jsonb_build_object('id', a."id", 'organizationId', a."tenant_id", 'planId', a."plan_id", 'sellerId', a."seller_id", 'subjectType', a."subject_type", 'subjectId', a."subject_id", 'startsOn', a."starts_on", 'endsOn', a."ends_on", 'createdAt', a."created_at") order by a."starts_on" desc, a."created_at" desc)
        from "better_supabase"."commission_assignments" a where a."plan_id" = x."id"
      ), '[]'::jsonb)) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."commission_plans" x
      where x."tenant_id" = list_commission_plans.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'kind', x."kind", 'rateBps', x."rate_bps", 'tiers', x."tiers", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('assignments', coalesce((
        select jsonb_agg(jsonb_build_object('id', a."id", 'organizationId', a."tenant_id", 'planId', a."plan_id", 'sellerId', a."seller_id", 'subjectType', a."subject_type", 'subjectId', a."subject_id", 'startsOn', a."starts_on", 'endsOn', a."ends_on", 'createdAt', a."created_at") order by a."starts_on" desc, a."created_at" desc)
        from "better_supabase"."commission_assignments" a where a."plan_id" = x."id"
      ), '[]'::jsonb)) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."commission_plans" x
      where x."tenant_id" = list_commission_plans.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'kind', x."kind", 'rateBps', x."rate_bps", 'tiers', x."tiers", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('assignments', coalesce((
        select jsonb_agg(jsonb_build_object('id', a."id", 'organizationId', a."tenant_id", 'planId', a."plan_id", 'sellerId', a."seller_id", 'subjectType', a."subject_type", 'subjectId', a."subject_id", 'startsOn', a."starts_on", 'endsOn', a."ends_on", 'createdAt', a."created_at") order by a."starts_on" desc, a."created_at" desc)
        from "better_supabase"."commission_assignments" a where a."plan_id" = x."id"
      ), '[]'::jsonb)) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."commission_plans" x
      where x."tenant_id" = list_commission_plans.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'kind', x."kind", 'rateBps', x."rate_bps", 'tiers', x."tiers", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('assignments', coalesce((
        select jsonb_agg(jsonb_build_object('id', a."id", 'organizationId', a."tenant_id", 'planId', a."plan_id", 'sellerId', a."seller_id", 'subjectType', a."subject_type", 'subjectId', a."subject_id", 'startsOn', a."starts_on", 'endsOn', a."ends_on", 'createdAt', a."created_at") order by a."starts_on" desc, a."created_at" desc)
        from "better_supabase"."commission_assignments" a where a."plan_id" = x."id"
      ), '[]'::jsonb)) as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."commission_plans" x
      where x."tenant_id" = list_commission_plans.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_after is null or (x."name", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."name" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'kind', x."kind", 'rateBps', x."rate_bps", 'tiers', x."tiers", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('assignments', coalesce((
        select jsonb_agg(jsonb_build_object('id', a."id", 'organizationId', a."tenant_id", 'planId', a."plan_id", 'sellerId', a."seller_id", 'subjectType', a."subject_type", 'subjectId', a."subject_id", 'startsOn', a."starts_on", 'endsOn', a."ends_on", 'createdAt', a."created_at") order by a."starts_on" desc, a."created_at" desc)
        from "better_supabase"."commission_assignments" a where a."plan_id" = x."id"
      ), '[]'::jsonb)) as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."commission_plans" x
      where x."tenant_id" = list_commission_plans.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
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
      select 1 from "better_supabase"."commission_plans" x
      where x."tenant_id" = list_commission_plans.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_commission_statements (
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
  v_filters jsonb := coalesce(list_commission_statements.filters, '{}'::jsonb);
  v_all boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_commission_statements.tenant is not null and coalesce(better_supabase.can('tenant', list_commission_statements.tenant, 'commissions.read'), false)));
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
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'seller') then
      raise exception 'facet is one of status, seller' using errcode = '22023', hint = 'COMMISSION_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'seller' then (x."seller_id")::text end) as v
      from "better_supabase"."commission_statements" x
      where x."tenant_id" = list_commission_statements.tenant
        and (v_all or x."seller_id" = (select auth.uid()))
        and (not (v_filters -> 'seller' is not null and jsonb_typeof(v_filters -> 'seller') <> 'null' and not (jsonb_typeof(v_filters -> 'seller') = 'array' and jsonb_array_length(v_filters -> 'seller') = 0)) or x."seller_id" = any((case when jsonb_typeof(v_filters -> 'seller') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'seller')) else array[v_filters ->> 'seller'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
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
      select 1 from "better_supabase"."commission_statements" x
      where x."tenant_id" = list_commission_statements.tenant
        and (v_all or x."seller_id" = (select auth.uid()))
        and (not (v_filters -> 'seller' is not null and jsonb_typeof(v_filters -> 'seller') <> 'null' and not (jsonb_typeof(v_filters -> 'seller') = 'array' and jsonb_array_length(v_filters -> 'seller') = 0)) or x."seller_id" = any((case when jsonb_typeof(v_filters -> 'seller') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'seller')) else array[v_filters ->> 'seller'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('endsOn', 'createdAt', 'total') then
    raise exception 'sort is one of endsOn, createdAt, total' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'sellerId', x."seller_id", 'currency', x."currency", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'status', x."status", 'total', x."total"::text, 'ledgerTransactionId', x."ledger_transaction_id", 'finalizedAt', x."finalized_at", 'paidAt', x."paid_at", 'paidBy', x."paid_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."ends_on")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."commission_statements" x
      where x."tenant_id" = list_commission_statements.tenant
        and (v_all or x."seller_id" = (select auth.uid()))
        and (not (v_filters -> 'seller' is not null and jsonb_typeof(v_filters -> 'seller') <> 'null' and not (jsonb_typeof(v_filters -> 'seller') = 'array' and jsonb_array_length(v_filters -> 'seller') = 0)) or x."seller_id" = any((case when jsonb_typeof(v_filters -> 'seller') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'seller')) else array[v_filters ->> 'seller'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."ends_on" >= (v_after ->> 0)::date and ((x."ends_on" > (v_after ->> 0)::date) or (x."ends_on" = (v_after ->> 0)::date and x."created_at" < (v_after ->> 1)::timestamptz) or (x."ends_on" = (v_after ->> 0)::date and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."ends_on" asc, x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'sellerId', x."seller_id", 'currency', x."currency", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'status', x."status", 'total', x."total"::text, 'ledgerTransactionId', x."ledger_transaction_id", 'finalizedAt', x."finalized_at", 'paidAt', x."paid_at", 'paidBy', x."paid_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."ends_on")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."commission_statements" x
      where x."tenant_id" = list_commission_statements.tenant
        and (v_all or x."seller_id" = (select auth.uid()))
        and (not (v_filters -> 'seller' is not null and jsonb_typeof(v_filters -> 'seller') <> 'null' and not (jsonb_typeof(v_filters -> 'seller') = 'array' and jsonb_array_length(v_filters -> 'seller') = 0)) or x."seller_id" = any((case when jsonb_typeof(v_filters -> 'seller') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'seller')) else array[v_filters ->> 'seller'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."ends_on" <= (v_after ->> 0)::date and ((x."ends_on" < (v_after ->> 0)::date) or (x."ends_on" = (v_after ->> 0)::date and x."created_at" < (v_after ->> 1)::timestamptz) or (x."ends_on" = (v_after ->> 0)::date and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."ends_on" desc, x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'endsOn' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'sellerId', x."seller_id", 'currency', x."currency", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'status', x."status", 'total', x."total"::text, 'ledgerTransactionId', x."ledger_transaction_id", 'finalizedAt', x."finalized_at", 'paidAt', x."paid_at", 'paidBy', x."paid_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."ends_on")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."commission_statements" x
      where x."tenant_id" = list_commission_statements.tenant
        and (v_all or x."seller_id" = (select auth.uid()))
        and (not (v_filters -> 'seller' is not null and jsonb_typeof(v_filters -> 'seller') <> 'null' and not (jsonb_typeof(v_filters -> 'seller') = 'array' and jsonb_array_length(v_filters -> 'seller') = 0)) or x."seller_id" = any((case when jsonb_typeof(v_filters -> 'seller') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'seller')) else array[v_filters ->> 'seller'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."ends_on" >= (v_after ->> 0)::date and ((x."ends_on" > (v_after ->> 0)::date) or (x."ends_on" = (v_after ->> 0)::date and x."created_at" < (v_after ->> 1)::timestamptz) or (x."ends_on" = (v_after ->> 0)::date and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."ends_on" asc, x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'endsOn' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'sellerId', x."seller_id", 'currency', x."currency", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'status', x."status", 'total', x."total"::text, 'ledgerTransactionId', x."ledger_transaction_id", 'finalizedAt', x."finalized_at", 'paidAt', x."paid_at", 'paidBy', x."paid_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."ends_on")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."commission_statements" x
      where x."tenant_id" = list_commission_statements.tenant
        and (v_all or x."seller_id" = (select auth.uid()))
        and (not (v_filters -> 'seller' is not null and jsonb_typeof(v_filters -> 'seller') <> 'null' and not (jsonb_typeof(v_filters -> 'seller') = 'array' and jsonb_array_length(v_filters -> 'seller') = 0)) or x."seller_id" = any((case when jsonb_typeof(v_filters -> 'seller') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'seller')) else array[v_filters ->> 'seller'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."ends_on" <= (v_after ->> 0)::date and ((x."ends_on" < (v_after ->> 0)::date) or (x."ends_on" = (v_after ->> 0)::date and x."created_at" < (v_after ->> 1)::timestamptz) or (x."ends_on" = (v_after ->> 0)::date and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."ends_on" desc, x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'sellerId', x."seller_id", 'currency', x."currency", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'status', x."status", 'total', x."total"::text, 'ledgerTransactionId', x."ledger_transaction_id", 'finalizedAt', x."finalized_at", 'paidAt', x."paid_at", 'paidBy', x."paid_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."commission_statements" x
      where x."tenant_id" = list_commission_statements.tenant
        and (v_all or x."seller_id" = (select auth.uid()))
        and (not (v_filters -> 'seller' is not null and jsonb_typeof(v_filters -> 'seller') <> 'null' and not (jsonb_typeof(v_filters -> 'seller') = 'array' and jsonb_array_length(v_filters -> 'seller') = 0)) or x."seller_id" = any((case when jsonb_typeof(v_filters -> 'seller') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'seller')) else array[v_filters ->> 'seller'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."created_at" < (v_after ->> 1)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."created_at" asc, x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'sellerId', x."seller_id", 'currency', x."currency", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'status', x."status", 'total', x."total"::text, 'ledgerTransactionId', x."ledger_transaction_id", 'finalizedAt', x."finalized_at", 'paidAt', x."paid_at", 'paidBy', x."paid_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."commission_statements" x
      where x."tenant_id" = list_commission_statements.tenant
        and (v_all or x."seller_id" = (select auth.uid()))
        and (not (v_filters -> 'seller' is not null and jsonb_typeof(v_filters -> 'seller') <> 'null' and not (jsonb_typeof(v_filters -> 'seller') = 'array' and jsonb_array_length(v_filters -> 'seller') = 0)) or x."seller_id" = any((case when jsonb_typeof(v_filters -> 'seller') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'seller')) else array[v_filters ->> 'seller'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."created_at" < (v_after ->> 1)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."created_at" desc, x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'total' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'sellerId', x."seller_id", 'currency', x."currency", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'status', x."status", 'total', x."total"::text, 'ledgerTransactionId', x."ledger_transaction_id", 'finalizedAt', x."finalized_at", 'paidAt', x."paid_at", 'paidBy', x."paid_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."total")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."commission_statements" x
      where x."tenant_id" = list_commission_statements.tenant
        and (v_all or x."seller_id" = (select auth.uid()))
        and (not (v_filters -> 'seller' is not null and jsonb_typeof(v_filters -> 'seller') <> 'null' and not (jsonb_typeof(v_filters -> 'seller') = 'array' and jsonb_array_length(v_filters -> 'seller') = 0)) or x."seller_id" = any((case when jsonb_typeof(v_filters -> 'seller') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'seller')) else array[v_filters ->> 'seller'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."total" >= (v_after ->> 0)::numeric and ((x."total" > (v_after ->> 0)::numeric) or (x."total" = (v_after ->> 0)::numeric and x."created_at" < (v_after ->> 1)::timestamptz) or (x."total" = (v_after ->> 0)::numeric and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."total" asc, x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'total' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'sellerId', x."seller_id", 'currency', x."currency", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'status', x."status", 'total', x."total"::text, 'ledgerTransactionId', x."ledger_transaction_id", 'finalizedAt', x."finalized_at", 'paidAt', x."paid_at", 'paidBy', x."paid_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."total")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."commission_statements" x
      where x."tenant_id" = list_commission_statements.tenant
        and (v_all or x."seller_id" = (select auth.uid()))
        and (not (v_filters -> 'seller' is not null and jsonb_typeof(v_filters -> 'seller') <> 'null' and not (jsonb_typeof(v_filters -> 'seller') = 'array' and jsonb_array_length(v_filters -> 'seller') = 0)) or x."seller_id" = any((case when jsonb_typeof(v_filters -> 'seller') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'seller')) else array[v_filters ->> 'seller'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."total" <= (v_after ->> 0)::numeric and ((x."total" < (v_after ->> 0)::numeric) or (x."total" = (v_after ->> 0)::numeric and x."created_at" < (v_after ->> 1)::timestamptz) or (x."total" = (v_after ->> 0)::numeric and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."total" desc, x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."commission_statements" x
      where x."tenant_id" = list_commission_statements.tenant
        and (v_all or x."seller_id" = (select auth.uid()))
        and (not (v_filters -> 'seller' is not null and jsonb_typeof(v_filters -> 'seller') <> 'null' and not (jsonb_typeof(v_filters -> 'seller') = 'array' and jsonb_array_length(v_filters -> 'seller') = 0)) or x."seller_id" = any((case when jsonb_typeof(v_filters -> 'seller') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'seller')) else array[v_filters ->> 'seller'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_commissions (
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
  v_filters jsonb := coalesce(list_commissions.filters, '{}'::jsonb);
  v_all boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_commissions.tenant is not null and coalesce(better_supabase.can('tenant', list_commissions.tenant, 'commissions.read'), false)));
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
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'seller') then
      raise exception 'facet is one of status, seller' using errcode = '22023', hint = 'COMMISSION_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'seller' then (x."seller_id")::text end) as v
      from "better_supabase"."commissions" x
      where x."tenant_id" = list_commissions.tenant
        and (v_all or x."seller_id" = (select auth.uid()))
        and (not (v_filters -> 'seller' is not null and jsonb_typeof(v_filters -> 'seller') <> 'null' and not (jsonb_typeof(v_filters -> 'seller') = 'array' and jsonb_array_length(v_filters -> 'seller') = 0)) or x."seller_id" = any((case when jsonb_typeof(v_filters -> 'seller') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'seller')) else array[v_filters ->> 'seller'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
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
      select 1 from "better_supabase"."commissions" x
      where x."tenant_id" = list_commissions.tenant
        and (v_all or x."seller_id" = (select auth.uid()))
        and (not (v_filters -> 'seller' is not null and jsonb_typeof(v_filters -> 'seller') <> 'null' and not (jsonb_typeof(v_filters -> 'seller') = 'array' and jsonb_array_length(v_filters -> 'seller') = 0)) or x."seller_id" = any((case when jsonb_typeof(v_filters -> 'seller') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'seller')) else array[v_filters ->> 'seller'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('occurredOn', 'createdAt', 'amount') then
    raise exception 'sort is one of occurredOn, createdAt, amount' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'planId', x."plan_id", 'sellerId', x."seller_id", 'sourceType', x."source_type", 'sourceId', x."source_id", 'basis', x."basis"::text, 'amount', x."amount"::text, 'currency', x."currency", 'occurredOn', x."occurred_on", 'status', x."status", 'statementId', x."statement_id", 'ledgerTransactionId', x."ledger_transaction_id", 'reversedAt', x."reversed_at", 'createdAt', x."created_at") as j, jsonb_build_array((x."occurred_on")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."commissions" x
      where x."tenant_id" = list_commissions.tenant
        and (v_all or x."seller_id" = (select auth.uid()))
        and (not (v_filters -> 'seller' is not null and jsonb_typeof(v_filters -> 'seller') <> 'null' and not (jsonb_typeof(v_filters -> 'seller') = 'array' and jsonb_array_length(v_filters -> 'seller') = 0)) or x."seller_id" = any((case when jsonb_typeof(v_filters -> 'seller') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'seller')) else array[v_filters ->> 'seller'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."occurred_on" >= (v_after ->> 0)::date and ((x."occurred_on" > (v_after ->> 0)::date) or (x."occurred_on" = (v_after ->> 0)::date and x."created_at" < (v_after ->> 1)::timestamptz) or (x."occurred_on" = (v_after ->> 0)::date and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."occurred_on" asc, x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'planId', x."plan_id", 'sellerId', x."seller_id", 'sourceType', x."source_type", 'sourceId', x."source_id", 'basis', x."basis"::text, 'amount', x."amount"::text, 'currency', x."currency", 'occurredOn', x."occurred_on", 'status', x."status", 'statementId', x."statement_id", 'ledgerTransactionId', x."ledger_transaction_id", 'reversedAt', x."reversed_at", 'createdAt', x."created_at") as j, jsonb_build_array((x."occurred_on")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."commissions" x
      where x."tenant_id" = list_commissions.tenant
        and (v_all or x."seller_id" = (select auth.uid()))
        and (not (v_filters -> 'seller' is not null and jsonb_typeof(v_filters -> 'seller') <> 'null' and not (jsonb_typeof(v_filters -> 'seller') = 'array' and jsonb_array_length(v_filters -> 'seller') = 0)) or x."seller_id" = any((case when jsonb_typeof(v_filters -> 'seller') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'seller')) else array[v_filters ->> 'seller'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."occurred_on" <= (v_after ->> 0)::date and ((x."occurred_on" < (v_after ->> 0)::date) or (x."occurred_on" = (v_after ->> 0)::date and x."created_at" < (v_after ->> 1)::timestamptz) or (x."occurred_on" = (v_after ->> 0)::date and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."occurred_on" desc, x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'occurredOn' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'planId', x."plan_id", 'sellerId', x."seller_id", 'sourceType', x."source_type", 'sourceId', x."source_id", 'basis', x."basis"::text, 'amount', x."amount"::text, 'currency', x."currency", 'occurredOn', x."occurred_on", 'status', x."status", 'statementId', x."statement_id", 'ledgerTransactionId', x."ledger_transaction_id", 'reversedAt', x."reversed_at", 'createdAt', x."created_at") as j, jsonb_build_array((x."occurred_on")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."commissions" x
      where x."tenant_id" = list_commissions.tenant
        and (v_all or x."seller_id" = (select auth.uid()))
        and (not (v_filters -> 'seller' is not null and jsonb_typeof(v_filters -> 'seller') <> 'null' and not (jsonb_typeof(v_filters -> 'seller') = 'array' and jsonb_array_length(v_filters -> 'seller') = 0)) or x."seller_id" = any((case when jsonb_typeof(v_filters -> 'seller') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'seller')) else array[v_filters ->> 'seller'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."occurred_on" >= (v_after ->> 0)::date and ((x."occurred_on" > (v_after ->> 0)::date) or (x."occurred_on" = (v_after ->> 0)::date and x."created_at" < (v_after ->> 1)::timestamptz) or (x."occurred_on" = (v_after ->> 0)::date and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."occurred_on" asc, x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'occurredOn' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'planId', x."plan_id", 'sellerId', x."seller_id", 'sourceType', x."source_type", 'sourceId', x."source_id", 'basis', x."basis"::text, 'amount', x."amount"::text, 'currency', x."currency", 'occurredOn', x."occurred_on", 'status', x."status", 'statementId', x."statement_id", 'ledgerTransactionId', x."ledger_transaction_id", 'reversedAt', x."reversed_at", 'createdAt', x."created_at") as j, jsonb_build_array((x."occurred_on")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."commissions" x
      where x."tenant_id" = list_commissions.tenant
        and (v_all or x."seller_id" = (select auth.uid()))
        and (not (v_filters -> 'seller' is not null and jsonb_typeof(v_filters -> 'seller') <> 'null' and not (jsonb_typeof(v_filters -> 'seller') = 'array' and jsonb_array_length(v_filters -> 'seller') = 0)) or x."seller_id" = any((case when jsonb_typeof(v_filters -> 'seller') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'seller')) else array[v_filters ->> 'seller'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."occurred_on" <= (v_after ->> 0)::date and ((x."occurred_on" < (v_after ->> 0)::date) or (x."occurred_on" = (v_after ->> 0)::date and x."created_at" < (v_after ->> 1)::timestamptz) or (x."occurred_on" = (v_after ->> 0)::date and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."occurred_on" desc, x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'planId', x."plan_id", 'sellerId', x."seller_id", 'sourceType', x."source_type", 'sourceId', x."source_id", 'basis', x."basis"::text, 'amount', x."amount"::text, 'currency', x."currency", 'occurredOn', x."occurred_on", 'status', x."status", 'statementId', x."statement_id", 'ledgerTransactionId', x."ledger_transaction_id", 'reversedAt', x."reversed_at", 'createdAt', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."commissions" x
      where x."tenant_id" = list_commissions.tenant
        and (v_all or x."seller_id" = (select auth.uid()))
        and (not (v_filters -> 'seller' is not null and jsonb_typeof(v_filters -> 'seller') <> 'null' and not (jsonb_typeof(v_filters -> 'seller') = 'array' and jsonb_array_length(v_filters -> 'seller') = 0)) or x."seller_id" = any((case when jsonb_typeof(v_filters -> 'seller') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'seller')) else array[v_filters ->> 'seller'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."created_at" < (v_after ->> 1)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."created_at" asc, x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'planId', x."plan_id", 'sellerId', x."seller_id", 'sourceType', x."source_type", 'sourceId', x."source_id", 'basis', x."basis"::text, 'amount', x."amount"::text, 'currency', x."currency", 'occurredOn', x."occurred_on", 'status', x."status", 'statementId', x."statement_id", 'ledgerTransactionId', x."ledger_transaction_id", 'reversedAt', x."reversed_at", 'createdAt', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."commissions" x
      where x."tenant_id" = list_commissions.tenant
        and (v_all or x."seller_id" = (select auth.uid()))
        and (not (v_filters -> 'seller' is not null and jsonb_typeof(v_filters -> 'seller') <> 'null' and not (jsonb_typeof(v_filters -> 'seller') = 'array' and jsonb_array_length(v_filters -> 'seller') = 0)) or x."seller_id" = any((case when jsonb_typeof(v_filters -> 'seller') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'seller')) else array[v_filters ->> 'seller'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."created_at" < (v_after ->> 1)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."created_at" desc, x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'amount' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'planId', x."plan_id", 'sellerId', x."seller_id", 'sourceType', x."source_type", 'sourceId', x."source_id", 'basis', x."basis"::text, 'amount', x."amount"::text, 'currency', x."currency", 'occurredOn', x."occurred_on", 'status', x."status", 'statementId', x."statement_id", 'ledgerTransactionId', x."ledger_transaction_id", 'reversedAt', x."reversed_at", 'createdAt', x."created_at") as j, jsonb_build_array((x."amount")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."commissions" x
      where x."tenant_id" = list_commissions.tenant
        and (v_all or x."seller_id" = (select auth.uid()))
        and (not (v_filters -> 'seller' is not null and jsonb_typeof(v_filters -> 'seller') <> 'null' and not (jsonb_typeof(v_filters -> 'seller') = 'array' and jsonb_array_length(v_filters -> 'seller') = 0)) or x."seller_id" = any((case when jsonb_typeof(v_filters -> 'seller') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'seller')) else array[v_filters ->> 'seller'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."amount" >= (v_after ->> 0)::numeric and ((x."amount" > (v_after ->> 0)::numeric) or (x."amount" = (v_after ->> 0)::numeric and x."created_at" < (v_after ->> 1)::timestamptz) or (x."amount" = (v_after ->> 0)::numeric and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."amount" asc, x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'amount' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'planId', x."plan_id", 'sellerId', x."seller_id", 'sourceType', x."source_type", 'sourceId', x."source_id", 'basis', x."basis"::text, 'amount', x."amount"::text, 'currency', x."currency", 'occurredOn', x."occurred_on", 'status', x."status", 'statementId', x."statement_id", 'ledgerTransactionId', x."ledger_transaction_id", 'reversedAt', x."reversed_at", 'createdAt', x."created_at") as j, jsonb_build_array((x."amount")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."commissions" x
      where x."tenant_id" = list_commissions.tenant
        and (v_all or x."seller_id" = (select auth.uid()))
        and (not (v_filters -> 'seller' is not null and jsonb_typeof(v_filters -> 'seller') <> 'null' and not (jsonb_typeof(v_filters -> 'seller') = 'array' and jsonb_array_length(v_filters -> 'seller') = 0)) or x."seller_id" = any((case when jsonb_typeof(v_filters -> 'seller') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'seller')) else array[v_filters ->> 'seller'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."amount" <= (v_after ->> 0)::numeric and ((x."amount" < (v_after ->> 0)::numeric) or (x."amount" = (v_after ->> 0)::numeric and x."created_at" < (v_after ->> 1)::timestamptz) or (x."amount" = (v_after ->> 0)::numeric and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."amount" desc, x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."commissions" x
      where x."tenant_id" = list_commissions.tenant
        and (v_all or x."seller_id" = (select auth.uid()))
        and (not (v_filters -> 'seller' is not null and jsonb_typeof(v_filters -> 'seller') <> 'null' and not (jsonb_typeof(v_filters -> 'seller') = 'array' and jsonb_array_length(v_filters -> 'seller') = 0)) or x."seller_id" = any((case when jsonb_typeof(v_filters -> 'seller') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'seller')) else array[v_filters ->> 'seller'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

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
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_leases (
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
  v_filters jsonb := coalesce(list_leases.filters, '{}'::jsonb);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_leases.tenant, 'leases.read'), false)) then
    raise exception 'not allowed to read leases' using errcode = '42501', hint = 'LEASES_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'unitId') then
      raise exception 'facet is one of status, unitId' using errcode = '22023', hint = 'LEASE_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'unitId' then (x."unit_id")::text end) as v
      from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
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
      select 1 from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('startsOn', 'endsOn', 'createdAt') then
    raise exception 'sort is one of startsOn, endsOn, createdAt' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = x."tenant_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."starts_on")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (x."starts_on", x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by x."starts_on" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = x."tenant_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."starts_on")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (x."starts_on" <= (v_after ->> 0)::date and ((x."starts_on" < (v_after ->> 0)::date) or (x."starts_on" = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by x."starts_on" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startsOn' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = x."tenant_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."starts_on")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (x."starts_on", x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by x."starts_on" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startsOn' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = x."tenant_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."starts_on")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (x."starts_on" <= (v_after ->> 0)::date and ((x."starts_on" < (v_after ->> 0)::date) or (x."starts_on" = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by x."starts_on" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'endsOn' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = x."tenant_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."ends_on", 'infinity'::date))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (coalesce(x."ends_on", 'infinity'::date), x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by coalesce(x."ends_on", 'infinity'::date) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'endsOn' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = x."tenant_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."ends_on", 'infinity'::date))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (coalesce(x."ends_on", 'infinity'::date) <= (v_after ->> 0)::date and ((coalesce(x."ends_on", 'infinity'::date) < (v_after ->> 0)::date) or (coalesce(x."ends_on", 'infinity'::date) = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."ends_on", 'infinity'::date) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = x."tenant_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = x."tenant_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
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
      select 1 from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_periods (
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
  v_filters jsonb := coalesce(list_periods.filters, '{}'::jsonb);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_periods.tenant is not null and coalesce(better_supabase.can('tenant', list_periods.tenant, 'periods.read'), false))) then
    raise exception 'not allowed to read periods' using errcode = '42501', hint = 'PERIOD_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'PERIOD_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('kind', 'status') then
      raise exception 'facet is one of kind, status' using errcode = '22023', hint = 'PERIOD_INVALID';
    end if;
    with s as (
      select (case v_facet when 'kind' then (x."kind")::text when 'status' then (x."status")::text end) as v
      from "better_supabase"."periods" x
      where x."tenant_id" = list_periods.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
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
      select 1 from "better_supabase"."periods" x
      where x."tenant_id" = list_periods.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('startsOn', 'endsOn') then
    raise exception 'sort is one of startsOn, endsOn' using errcode = '22023', hint = 'PERIOD_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'PERIOD_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PERIOD_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'kind', x."kind", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'status', x."status", 'closedAt', x."closed_at", 'closedBy', x."closed_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."starts_on")::text, (x."kind")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."periods" x
      where x."tenant_id" = list_periods.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."starts_on", x."kind", x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."starts_on" asc, x."kind" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PERIOD_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'kind', x."kind", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'status', x."status", 'closedAt', x."closed_at", 'closedBy', x."closed_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."starts_on")::text, (x."kind")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."periods" x
      where x."tenant_id" = list_periods.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."starts_on" <= (v_after ->> 0)::date and ((x."starts_on" < (v_after ->> 0)::date) or (x."starts_on" = (v_after ->> 0)::date and x."kind" > (v_after ->> 1)::text) or (x."starts_on" = (v_after ->> 0)::date and x."kind" = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."starts_on" desc, x."kind" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startsOn' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PERIOD_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'kind', x."kind", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'status', x."status", 'closedAt', x."closed_at", 'closedBy', x."closed_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."starts_on")::text, (x."kind")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."periods" x
      where x."tenant_id" = list_periods.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."starts_on", x."kind", x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."starts_on" asc, x."kind" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startsOn' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PERIOD_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'kind', x."kind", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'status', x."status", 'closedAt', x."closed_at", 'closedBy', x."closed_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."starts_on")::text, (x."kind")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."periods" x
      where x."tenant_id" = list_periods.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."starts_on" <= (v_after ->> 0)::date and ((x."starts_on" < (v_after ->> 0)::date) or (x."starts_on" = (v_after ->> 0)::date and x."kind" > (v_after ->> 1)::text) or (x."starts_on" = (v_after ->> 0)::date and x."kind" = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."starts_on" desc, x."kind" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'endsOn' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PERIOD_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'kind', x."kind", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'status', x."status", 'closedAt', x."closed_at", 'closedBy', x."closed_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."ends_on")::text, (x."kind")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."periods" x
      where x."tenant_id" = list_periods.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."ends_on", x."kind", x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."ends_on" asc, x."kind" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'endsOn' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PERIOD_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'kind', x."kind", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'status', x."status", 'closedAt', x."closed_at", 'closedBy', x."closed_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."ends_on")::text, (x."kind")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."periods" x
      where x."tenant_id" = list_periods.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."ends_on" <= (v_after ->> 0)::date and ((x."ends_on" < (v_after ->> 0)::date) or (x."ends_on" = (v_after ->> 0)::date and x."kind" > (v_after ->> 1)::text) or (x."ends_on" = (v_after ->> 0)::date and x."kind" = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."ends_on" desc, x."kind" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."periods" x
      where x."tenant_id" = list_periods.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
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
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_production_orders (
  tenant  uuid,
  filters jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_production_orders.filters, '{}'::jsonb);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_production_orders.tenant is not null and coalesce(better_supabase.can('tenant', list_production_orders.tenant, 'manufacturing.read'), false))) then
    raise exception 'not allowed to read production orders' using errcode = '42501', hint = 'MANUFACTURING_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status') then
      raise exception 'facet is one of status' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text end) as v
      from "better_supabase"."production_orders" x
      where x."tenant_id" = list_production_orders.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id" = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
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
      select 1 from "better_supabase"."production_orders" x
      where x."tenant_id" = list_production_orders.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id" = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('dueOn', 'createdAt', 'number') then
    raise exception 'sort is one of dueOn, createdAt, number' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'number', x."number", 'variantId', x."variant_id", 'bomId', x."bom_id", 'quantity', x."quantity"::text, 'locationId', x."location_id", 'dueOn', x."due_on", 'status', x."status", 'producedQuantity', x."produced_quantity"::text, 'scrapQuantity', x."scrap_quantity"::text, 'outputLotId', x."output_lot_id", 'materialCost', x."material_cost"::text, 'laborCost', x."labor_cost"::text, 'currency', x."currency", 'note', x."note", 'releasedAt', x."released_at", 'startedAt', x."started_at", 'completedAt', x."completed_at", 'canceledAt', x."canceled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."due_on", 'infinity'::date))::text, (x."sequence")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."production_orders" x
      where x."tenant_id" = list_production_orders.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id" = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (v_after is null or (coalesce(x."due_on", 'infinity'::date) >= (v_after ->> 0)::date and ((coalesce(x."due_on", 'infinity'::date) > (v_after ->> 0)::date) or (coalesce(x."due_on", 'infinity'::date) = (v_after ->> 0)::date and x."sequence" < (v_after ->> 1)::bigint) or (coalesce(x."due_on", 'infinity'::date) = (v_after ->> 0)::date and x."sequence" = (v_after ->> 1)::bigint and x."id" > (v_after ->> 2)::uuid))))
      order by coalesce(x."due_on", 'infinity'::date) asc, x."sequence" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'number', x."number", 'variantId', x."variant_id", 'bomId', x."bom_id", 'quantity', x."quantity"::text, 'locationId', x."location_id", 'dueOn', x."due_on", 'status', x."status", 'producedQuantity', x."produced_quantity"::text, 'scrapQuantity', x."scrap_quantity"::text, 'outputLotId', x."output_lot_id", 'materialCost', x."material_cost"::text, 'laborCost', x."labor_cost"::text, 'currency', x."currency", 'note', x."note", 'releasedAt', x."released_at", 'startedAt', x."started_at", 'completedAt', x."completed_at", 'canceledAt', x."canceled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."due_on", 'infinity'::date))::text, (x."sequence")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."production_orders" x
      where x."tenant_id" = list_production_orders.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id" = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (v_after is null or (coalesce(x."due_on", 'infinity'::date) <= (v_after ->> 0)::date and ((coalesce(x."due_on", 'infinity'::date) < (v_after ->> 0)::date) or (coalesce(x."due_on", 'infinity'::date) = (v_after ->> 0)::date and x."sequence" < (v_after ->> 1)::bigint) or (coalesce(x."due_on", 'infinity'::date) = (v_after ->> 0)::date and x."sequence" = (v_after ->> 1)::bigint and x."id" > (v_after ->> 2)::uuid))))
      order by coalesce(x."due_on", 'infinity'::date) desc, x."sequence" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'dueOn' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'number', x."number", 'variantId', x."variant_id", 'bomId', x."bom_id", 'quantity', x."quantity"::text, 'locationId', x."location_id", 'dueOn', x."due_on", 'status', x."status", 'producedQuantity', x."produced_quantity"::text, 'scrapQuantity', x."scrap_quantity"::text, 'outputLotId', x."output_lot_id", 'materialCost', x."material_cost"::text, 'laborCost', x."labor_cost"::text, 'currency', x."currency", 'note', x."note", 'releasedAt', x."released_at", 'startedAt', x."started_at", 'completedAt', x."completed_at", 'canceledAt', x."canceled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."due_on", 'infinity'::date))::text, (x."sequence")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."production_orders" x
      where x."tenant_id" = list_production_orders.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id" = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (v_after is null or (coalesce(x."due_on", 'infinity'::date) >= (v_after ->> 0)::date and ((coalesce(x."due_on", 'infinity'::date) > (v_after ->> 0)::date) or (coalesce(x."due_on", 'infinity'::date) = (v_after ->> 0)::date and x."sequence" < (v_after ->> 1)::bigint) or (coalesce(x."due_on", 'infinity'::date) = (v_after ->> 0)::date and x."sequence" = (v_after ->> 1)::bigint and x."id" > (v_after ->> 2)::uuid))))
      order by coalesce(x."due_on", 'infinity'::date) asc, x."sequence" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'dueOn' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'number', x."number", 'variantId', x."variant_id", 'bomId', x."bom_id", 'quantity', x."quantity"::text, 'locationId', x."location_id", 'dueOn', x."due_on", 'status', x."status", 'producedQuantity', x."produced_quantity"::text, 'scrapQuantity', x."scrap_quantity"::text, 'outputLotId', x."output_lot_id", 'materialCost', x."material_cost"::text, 'laborCost', x."labor_cost"::text, 'currency', x."currency", 'note', x."note", 'releasedAt', x."released_at", 'startedAt', x."started_at", 'completedAt', x."completed_at", 'canceledAt', x."canceled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."due_on", 'infinity'::date))::text, (x."sequence")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."production_orders" x
      where x."tenant_id" = list_production_orders.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id" = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (v_after is null or (coalesce(x."due_on", 'infinity'::date) <= (v_after ->> 0)::date and ((coalesce(x."due_on", 'infinity'::date) < (v_after ->> 0)::date) or (coalesce(x."due_on", 'infinity'::date) = (v_after ->> 0)::date and x."sequence" < (v_after ->> 1)::bigint) or (coalesce(x."due_on", 'infinity'::date) = (v_after ->> 0)::date and x."sequence" = (v_after ->> 1)::bigint and x."id" > (v_after ->> 2)::uuid))))
      order by coalesce(x."due_on", 'infinity'::date) desc, x."sequence" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'number', x."number", 'variantId', x."variant_id", 'bomId', x."bom_id", 'quantity', x."quantity"::text, 'locationId', x."location_id", 'dueOn', x."due_on", 'status', x."status", 'producedQuantity', x."produced_quantity"::text, 'scrapQuantity', x."scrap_quantity"::text, 'outputLotId', x."output_lot_id", 'materialCost', x."material_cost"::text, 'laborCost', x."labor_cost"::text, 'currency', x."currency", 'note', x."note", 'releasedAt', x."released_at", 'startedAt', x."started_at", 'completedAt', x."completed_at", 'canceledAt', x."canceled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."production_orders" x
      where x."tenant_id" = list_production_orders.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id" = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'number', x."number", 'variantId', x."variant_id", 'bomId', x."bom_id", 'quantity', x."quantity"::text, 'locationId', x."location_id", 'dueOn', x."due_on", 'status', x."status", 'producedQuantity', x."produced_quantity"::text, 'scrapQuantity', x."scrap_quantity"::text, 'outputLotId', x."output_lot_id", 'materialCost', x."material_cost"::text, 'laborCost', x."labor_cost"::text, 'currency', x."currency", 'note', x."note", 'releasedAt', x."released_at", 'startedAt', x."started_at", 'completedAt', x."completed_at", 'canceledAt', x."canceled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."production_orders" x
      where x."tenant_id" = list_production_orders.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id" = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'number' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'number', x."number", 'variantId', x."variant_id", 'bomId', x."bom_id", 'quantity', x."quantity"::text, 'locationId', x."location_id", 'dueOn', x."due_on", 'status', x."status", 'producedQuantity', x."produced_quantity"::text, 'scrapQuantity', x."scrap_quantity"::text, 'outputLotId', x."output_lot_id", 'materialCost', x."material_cost"::text, 'laborCost', x."labor_cost"::text, 'currency', x."currency", 'note', x."note", 'releasedAt', x."released_at", 'startedAt', x."started_at", 'completedAt', x."completed_at", 'canceledAt', x."canceled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."sequence")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."production_orders" x
      where x."tenant_id" = list_production_orders.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id" = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (v_after is null or (x."sequence", x."id") > ((v_after ->> 0)::bigint, (v_after ->> 1)::uuid))
      order by x."sequence" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'number' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'number', x."number", 'variantId', x."variant_id", 'bomId', x."bom_id", 'quantity', x."quantity"::text, 'locationId', x."location_id", 'dueOn', x."due_on", 'status', x."status", 'producedQuantity', x."produced_quantity"::text, 'scrapQuantity', x."scrap_quantity"::text, 'outputLotId', x."output_lot_id", 'materialCost', x."material_cost"::text, 'laborCost', x."labor_cost"::text, 'currency', x."currency", 'note', x."note", 'releasedAt', x."released_at", 'startedAt', x."started_at", 'completedAt', x."completed_at", 'canceledAt', x."canceled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."sequence")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."production_orders" x
      where x."tenant_id" = list_production_orders.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id" = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (v_after is null or (x."sequence" <= (v_after ->> 0)::bigint and ((x."sequence" < (v_after ->> 0)::bigint) or (x."sequence" = (v_after ->> 0)::bigint and x."id" > (v_after ->> 1)::uuid))))
      order by x."sequence" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."production_orders" x
      where x."tenant_id" = list_production_orders.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id" = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_referral_codes (
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
  v_filters jsonb := coalesce(list_referral_codes.filters, '{}'::jsonb);
  v_all boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_referral_codes.tenant is not null and coalesce(better_supabase.can('tenant', list_referral_codes.tenant, 'referrals.read'), false)));
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
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'REFERRAL_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('referrer') then
      raise exception 'facet is one of referrer' using errcode = '22023', hint = 'REFERRAL_INVALID';
    end if;
    with s as (
      select (case v_facet when 'referrer' then (x."referrer_id")::text end) as v
      from "better_supabase"."referral_codes" x
      where x."tenant_id" = list_referral_codes.tenant
        and (v_all or x."referrer_id" = (select auth.uid()))
        and (not (v_filters -> 'referrer' is not null and jsonb_typeof(v_filters -> 'referrer') <> 'null' and not (jsonb_typeof(v_filters -> 'referrer') = 'array' and jsonb_array_length(v_filters -> 'referrer') = 0)) or x."referrer_id" = any((case when jsonb_typeof(v_filters -> 'referrer') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'referrer')) else array[v_filters ->> 'referrer'] end)::uuid[]))
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
      select 1 from "better_supabase"."referral_codes" x
      where x."tenant_id" = list_referral_codes.tenant
        and (v_all or x."referrer_id" = (select auth.uid()))
        and (not (v_filters -> 'referrer' is not null and jsonb_typeof(v_filters -> 'referrer') <> 'null' and not (jsonb_typeof(v_filters -> 'referrer') = 'array' and jsonb_array_length(v_filters -> 'referrer') = 0)) or x."referrer_id" = any((case when jsonb_typeof(v_filters -> 'referrer') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'referrer')) else array[v_filters ->> 'referrer'] end)::uuid[]))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt') then
    raise exception 'sort is one of createdAt' using errcode = '22023', hint = 'REFERRAL_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'REFERRAL_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'REFERRAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'code', x."code", 'referrerId', x."referrer_id", 'invitationId', x."invitation_id", 'rewardAmount', x."reward_amount"::text, 'rewardUnit', x."reward_unit", 'maxUses', x."max_uses", 'uses', x."uses", 'active', x."active", 'expiresAt', x."expires_at", 'createdAt', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."referral_codes" x
      where x."tenant_id" = list_referral_codes.tenant
        and (v_all or x."referrer_id" = (select auth.uid()))
        and (not (v_filters -> 'referrer' is not null and jsonb_typeof(v_filters -> 'referrer') <> 'null' and not (jsonb_typeof(v_filters -> 'referrer') = 'array' and jsonb_array_length(v_filters -> 'referrer') = 0)) or x."referrer_id" = any((case when jsonb_typeof(v_filters -> 'referrer') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'referrer')) else array[v_filters ->> 'referrer'] end)::uuid[]))
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'REFERRAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'code', x."code", 'referrerId', x."referrer_id", 'invitationId', x."invitation_id", 'rewardAmount', x."reward_amount"::text, 'rewardUnit', x."reward_unit", 'maxUses', x."max_uses", 'uses', x."uses", 'active', x."active", 'expiresAt', x."expires_at", 'createdAt', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."referral_codes" x
      where x."tenant_id" = list_referral_codes.tenant
        and (v_all or x."referrer_id" = (select auth.uid()))
        and (not (v_filters -> 'referrer' is not null and jsonb_typeof(v_filters -> 'referrer') <> 'null' and not (jsonb_typeof(v_filters -> 'referrer') = 'array' and jsonb_array_length(v_filters -> 'referrer') = 0)) or x."referrer_id" = any((case when jsonb_typeof(v_filters -> 'referrer') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'referrer')) else array[v_filters ->> 'referrer'] end)::uuid[]))
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'REFERRAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'code', x."code", 'referrerId', x."referrer_id", 'invitationId', x."invitation_id", 'rewardAmount', x."reward_amount"::text, 'rewardUnit', x."reward_unit", 'maxUses', x."max_uses", 'uses', x."uses", 'active', x."active", 'expiresAt', x."expires_at", 'createdAt', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."referral_codes" x
      where x."tenant_id" = list_referral_codes.tenant
        and (v_all or x."referrer_id" = (select auth.uid()))
        and (not (v_filters -> 'referrer' is not null and jsonb_typeof(v_filters -> 'referrer') <> 'null' and not (jsonb_typeof(v_filters -> 'referrer') = 'array' and jsonb_array_length(v_filters -> 'referrer') = 0)) or x."referrer_id" = any((case when jsonb_typeof(v_filters -> 'referrer') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'referrer')) else array[v_filters ->> 'referrer'] end)::uuid[]))
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'REFERRAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'code', x."code", 'referrerId', x."referrer_id", 'invitationId', x."invitation_id", 'rewardAmount', x."reward_amount"::text, 'rewardUnit', x."reward_unit", 'maxUses', x."max_uses", 'uses', x."uses", 'active', x."active", 'expiresAt', x."expires_at", 'createdAt', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."referral_codes" x
      where x."tenant_id" = list_referral_codes.tenant
        and (v_all or x."referrer_id" = (select auth.uid()))
        and (not (v_filters -> 'referrer' is not null and jsonb_typeof(v_filters -> 'referrer') <> 'null' and not (jsonb_typeof(v_filters -> 'referrer') = 'array' and jsonb_array_length(v_filters -> 'referrer') = 0)) or x."referrer_id" = any((case when jsonb_typeof(v_filters -> 'referrer') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'referrer')) else array[v_filters ->> 'referrer'] end)::uuid[]))
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
      select 1 from "better_supabase"."referral_codes" x
      where x."tenant_id" = list_referral_codes.tenant
        and (v_all or x."referrer_id" = (select auth.uid()))
        and (not (v_filters -> 'referrer' is not null and jsonb_typeof(v_filters -> 'referrer') <> 'null' and not (jsonb_typeof(v_filters -> 'referrer') = 'array' and jsonb_array_length(v_filters -> 'referrer') = 0)) or x."referrer_id" = any((case when jsonb_typeof(v_filters -> 'referrer') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'referrer')) else array[v_filters ->> 'referrer'] end)::uuid[]))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_referrals (
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
  v_filters jsonb := coalesce(list_referrals.filters, '{}'::jsonb);
  v_all boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_referrals.tenant is not null and coalesce(better_supabase.can('tenant', list_referrals.tenant, 'referrals.read'), false)));
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
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'REFERRAL_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'referrer') then
      raise exception 'facet is one of status, referrer' using errcode = '22023', hint = 'REFERRAL_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'referrer' then (x."referrer_id")::text end) as v
      from "better_supabase"."referrals" x
      where x."tenant_id" = list_referrals.tenant
        and (v_all or x."referrer_id" = (select auth.uid()))
        and (not (v_filters -> 'referrer' is not null and jsonb_typeof(v_filters -> 'referrer') <> 'null' and not (jsonb_typeof(v_filters -> 'referrer') = 'array' and jsonb_array_length(v_filters -> 'referrer') = 0)) or x."referrer_id" = any((case when jsonb_typeof(v_filters -> 'referrer') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'referrer')) else array[v_filters ->> 'referrer'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
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
      select 1 from "better_supabase"."referrals" x
      where x."tenant_id" = list_referrals.tenant
        and (v_all or x."referrer_id" = (select auth.uid()))
        and (not (v_filters -> 'referrer' is not null and jsonb_typeof(v_filters -> 'referrer') <> 'null' and not (jsonb_typeof(v_filters -> 'referrer') = 'array' and jsonb_array_length(v_filters -> 'referrer') = 0)) or x."referrer_id" = any((case when jsonb_typeof(v_filters -> 'referrer') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'referrer')) else array[v_filters ->> 'referrer'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt') then
    raise exception 'sort is one of createdAt' using errcode = '22023', hint = 'REFERRAL_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'REFERRAL_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'REFERRAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'codeId', x."code_id", 'referrerId', x."referrer_id", 'referredUserId', x."referred_id", 'referredOrganizationId', x."referred_organization_id", 'referredEmail', x."referred_email", 'status', x."status", 'rewardAmount', x."reward_amount"::text, 'rewardUnit', x."reward_unit", 'qualifiedAt', x."qualified_at", 'rewardedAt', x."rewarded_at", 'ledgerTransactionId', x."ledger_transaction_id", 'createdAt', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."referrals" x
      where x."tenant_id" = list_referrals.tenant
        and (v_all or x."referrer_id" = (select auth.uid()))
        and (not (v_filters -> 'referrer' is not null and jsonb_typeof(v_filters -> 'referrer') <> 'null' and not (jsonb_typeof(v_filters -> 'referrer') = 'array' and jsonb_array_length(v_filters -> 'referrer') = 0)) or x."referrer_id" = any((case when jsonb_typeof(v_filters -> 'referrer') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'referrer')) else array[v_filters ->> 'referrer'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'REFERRAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'codeId', x."code_id", 'referrerId', x."referrer_id", 'referredUserId', x."referred_id", 'referredOrganizationId', x."referred_organization_id", 'referredEmail', x."referred_email", 'status', x."status", 'rewardAmount', x."reward_amount"::text, 'rewardUnit', x."reward_unit", 'qualifiedAt', x."qualified_at", 'rewardedAt', x."rewarded_at", 'ledgerTransactionId', x."ledger_transaction_id", 'createdAt', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."referrals" x
      where x."tenant_id" = list_referrals.tenant
        and (v_all or x."referrer_id" = (select auth.uid()))
        and (not (v_filters -> 'referrer' is not null and jsonb_typeof(v_filters -> 'referrer') <> 'null' and not (jsonb_typeof(v_filters -> 'referrer') = 'array' and jsonb_array_length(v_filters -> 'referrer') = 0)) or x."referrer_id" = any((case when jsonb_typeof(v_filters -> 'referrer') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'referrer')) else array[v_filters ->> 'referrer'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'REFERRAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'codeId', x."code_id", 'referrerId', x."referrer_id", 'referredUserId', x."referred_id", 'referredOrganizationId', x."referred_organization_id", 'referredEmail', x."referred_email", 'status', x."status", 'rewardAmount', x."reward_amount"::text, 'rewardUnit', x."reward_unit", 'qualifiedAt', x."qualified_at", 'rewardedAt', x."rewarded_at", 'ledgerTransactionId', x."ledger_transaction_id", 'createdAt', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."referrals" x
      where x."tenant_id" = list_referrals.tenant
        and (v_all or x."referrer_id" = (select auth.uid()))
        and (not (v_filters -> 'referrer' is not null and jsonb_typeof(v_filters -> 'referrer') <> 'null' and not (jsonb_typeof(v_filters -> 'referrer') = 'array' and jsonb_array_length(v_filters -> 'referrer') = 0)) or x."referrer_id" = any((case when jsonb_typeof(v_filters -> 'referrer') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'referrer')) else array[v_filters ->> 'referrer'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'REFERRAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'codeId', x."code_id", 'referrerId', x."referrer_id", 'referredUserId', x."referred_id", 'referredOrganizationId', x."referred_organization_id", 'referredEmail', x."referred_email", 'status', x."status", 'rewardAmount', x."reward_amount"::text, 'rewardUnit', x."reward_unit", 'qualifiedAt', x."qualified_at", 'rewardedAt', x."rewarded_at", 'ledgerTransactionId', x."ledger_transaction_id", 'createdAt', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."referrals" x
      where x."tenant_id" = list_referrals.tenant
        and (v_all or x."referrer_id" = (select auth.uid()))
        and (not (v_filters -> 'referrer' is not null and jsonb_typeof(v_filters -> 'referrer') <> 'null' and not (jsonb_typeof(v_filters -> 'referrer') = 'array' and jsonb_array_length(v_filters -> 'referrer') = 0)) or x."referrer_id" = any((case when jsonb_typeof(v_filters -> 'referrer') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'referrer')) else array[v_filters ->> 'referrer'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
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
      select 1 from "better_supabase"."referrals" x
      where x."tenant_id" = list_referrals.tenant
        and (v_all or x."referrer_id" = (select auth.uid()))
        and (not (v_filters -> 'referrer' is not null and jsonb_typeof(v_filters -> 'referrer') <> 'null' and not (jsonb_typeof(v_filters -> 'referrer') = 'array' and jsonb_array_length(v_filters -> 'referrer') = 0)) or x."referrer_id" = any((case when jsonb_typeof(v_filters -> 'referrer') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'referrer')) else array[v_filters ->> 'referrer'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_shipments (
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
  v_filters jsonb := coalesce(list_shipments.filters, '{}'::jsonb);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_shipments.tenant, 'shipments.read'), false)) then
    raise exception 'not allowed to read shipments' using errcode = '42501', hint = 'SHIPMENT_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'SHIPMENT_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'carrier') then
      raise exception 'facet is one of status, carrier' using errcode = '22023', hint = 'SHIPMENT_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'carrier' then (x."carrier")::text end) as v
      from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
        and (not v_filters ? 'subjectType' or (x."subject_type" = v_filters ->> 'subjectType' and x."subject_id" = v_filters ->> 'subjectId'))
        and (nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '') is null or x."created_at" < nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '')::timestamptz)
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
      select 1 from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
        and (not v_filters ? 'subjectType' or (x."subject_type" = v_filters ->> 'subjectType' and x."subject_id" = v_filters ->> 'subjectId'))
        and (nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '') is null or x."created_at" < nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '')::timestamptz)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'deliveredAt') then
    raise exception 'sort is one of createdAt, deliveredAt' using errcode = '22023', hint = 'SHIPMENT_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'SHIPMENT_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SHIPMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
        and (not v_filters ? 'subjectType' or (x."subject_type" = v_filters ->> 'subjectType' and x."subject_id" = v_filters ->> 'subjectId'))
        and (nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '') is null or x."created_at" < nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '')::timestamptz)
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SHIPMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
        and (not v_filters ? 'subjectType' or (x."subject_type" = v_filters ->> 'subjectType' and x."subject_id" = v_filters ->> 'subjectId'))
        and (nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '') is null or x."created_at" < nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '')::timestamptz)
        and (v_after is null or (x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SHIPMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
        and (not v_filters ? 'subjectType' or (x."subject_type" = v_filters ->> 'subjectType' and x."subject_id" = v_filters ->> 'subjectId'))
        and (nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '') is null or x."created_at" < nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '')::timestamptz)
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SHIPMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
        and (not v_filters ? 'subjectType' or (x."subject_type" = v_filters ->> 'subjectType' and x."subject_id" = v_filters ->> 'subjectId'))
        and (nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '') is null or x."created_at" < nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '')::timestamptz)
        and (v_after is null or (x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'deliveredAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SHIPMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((coalesce(x."delivered_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
        and (not v_filters ? 'subjectType' or (x."subject_type" = v_filters ->> 'subjectType' and x."subject_id" = v_filters ->> 'subjectId'))
        and (nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '') is null or x."created_at" < nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '')::timestamptz)
        and (v_after is null or (coalesce(x."delivered_at", 'infinity'::timestamptz) >= (v_after ->> 0)::timestamptz and ((coalesce(x."delivered_at", 'infinity'::timestamptz) > (v_after ->> 0)::timestamptz) or (coalesce(x."delivered_at", 'infinity'::timestamptz) = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by coalesce(x."delivered_at", 'infinity'::timestamptz) asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'deliveredAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SHIPMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((coalesce(x."delivered_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
        and (not v_filters ? 'subjectType' or (x."subject_type" = v_filters ->> 'subjectType' and x."subject_id" = v_filters ->> 'subjectId'))
        and (nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '') is null or x."created_at" < nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '')::timestamptz)
        and (v_after is null or (coalesce(x."delivered_at", 'infinity'::timestamptz), x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."delivered_at", 'infinity'::timestamptz) desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
        and (not v_filters ? 'subjectType' or (x."subject_type" = v_filters ->> 'subjectType' and x."subject_id" = v_filters ->> 'subjectId'))
        and (nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '') is null or x."created_at" < nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '')::timestamptz)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

REVOKE ALL ON FUNCTION "api"."list_gifts"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_gifts"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_leases"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_leases"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_pledges"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_pledges"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_production_orders"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_production_orders"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_shipments"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_shipments"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_gifts"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_gifts"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_leases"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_leases"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_pledges"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_pledges"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_production_orders"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_production_orders"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_shipments"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_shipments"(uuid, jsonb) TO "authenticated", "service_role";
