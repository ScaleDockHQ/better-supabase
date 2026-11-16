SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.page_api_keys (
  tenant  uuid  DEFAULT NULL::uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_api_keys"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_organization_domains (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_organization_domains"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_service_principals (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_service_principals"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_sso_providers (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_sso_providers"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.page_api_keys (
  tenant  uuid  DEFAULT NULL::uuid,
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
  v_filters jsonb := coalesce(page_api_keys.filters, '{}'::jsonb);
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
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'API_KEY_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('revoked') then
      raise exception 'facet is one of revoked' using errcode = '22023', hint = 'API_KEY_INVALID';
    end if;
    with s as (
      select (case v_facet when 'revoked' then ((x."revoked_at" is not null)::text)::text end) as v
      from "better_supabase"."api_keys" x
      where (case when page_api_keys.tenant is null then x."user_id" = auth.uid() else x."tenant_id" = page_api_keys.tenant and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', page_api_keys.tenant, 'api_keys.manage'), false) or x."user_id" = auth.uid()) end)
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (not (v_filters -> 'revoked' is not null and jsonb_typeof(v_filters -> 'revoked') <> 'null' and not (jsonb_typeof(v_filters -> 'revoked') = 'array' and jsonb_array_length(v_filters -> 'revoked') = 0)) or (x."revoked_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'revoked') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'revoked')) else array[v_filters ->> 'revoked'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."prefix" ilike v_search)
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
      select 1 from "better_supabase"."api_keys" x
      where (case when page_api_keys.tenant is null then x."user_id" = auth.uid() else x."tenant_id" = page_api_keys.tenant and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', page_api_keys.tenant, 'api_keys.manage'), false) or x."user_id" = auth.uid()) end)
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (not (v_filters -> 'revoked' is not null and jsonb_typeof(v_filters -> 'revoked') <> 'null' and not (jsonb_typeof(v_filters -> 'revoked') = 'array' and jsonb_array_length(v_filters -> 'revoked') = 0)) or (x."revoked_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'revoked') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'revoked')) else array[v_filters ->> 'revoked'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."prefix" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'name', 'expiresAt', 'lastUsedAt') then
    raise exception 'sort is one of createdAt, name, expiresAt, lastUsedAt' using errcode = '22023', hint = 'API_KEY_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'API_KEY_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'API_KEY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'organization_id', x."tenant_id",
    'user_id', x."user_id",
    'name', x."name",
    'prefix', x."prefix",
    'public_id', x."public_id",
    'scopes', to_jsonb(x."scopes"),
    'kind', x."kind",
    'rate_limit', x."rate_limit",
    'expires_at', x."expires_at",
    'last_used_at', x."last_used_at",
    'revoked_at', x."revoked_at",
    'rotated_from', x."rotated_from",
    'created_by', x."created_by",
    'created_at', x."created_at",
    'state', case
      when x."revoked_at" is not null and x."revoked_at" <= now() then 'revoked'
      when x."expires_at" is not null and x."expires_at" <= now() then 'expired'
      when x."revoked_at" is not null then 'grace'
      else 'active'
    end,
    'successor_id', (select s."id" from "better_supabase"."api_keys" s where s."rotated_from" = x."id" order by s."created_at" desc limit 1)
  ) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."api_keys" x
      where (case when page_api_keys.tenant is null then x."user_id" = auth.uid() else x."tenant_id" = page_api_keys.tenant and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', page_api_keys.tenant, 'api_keys.manage'), false) or x."user_id" = auth.uid()) end)
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (not (v_filters -> 'revoked' is not null and jsonb_typeof(v_filters -> 'revoked') <> 'null' and not (jsonb_typeof(v_filters -> 'revoked') = 'array' and jsonb_array_length(v_filters -> 'revoked') = 0)) or (x."revoked_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'revoked') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'revoked')) else array[v_filters ->> 'revoked'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."prefix" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'API_KEY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'organization_id', x."tenant_id",
    'user_id', x."user_id",
    'name', x."name",
    'prefix', x."prefix",
    'public_id', x."public_id",
    'scopes', to_jsonb(x."scopes"),
    'kind', x."kind",
    'rate_limit', x."rate_limit",
    'expires_at', x."expires_at",
    'last_used_at', x."last_used_at",
    'revoked_at', x."revoked_at",
    'rotated_from', x."rotated_from",
    'created_by', x."created_by",
    'created_at', x."created_at",
    'state', case
      when x."revoked_at" is not null and x."revoked_at" <= now() then 'revoked'
      when x."expires_at" is not null and x."expires_at" <= now() then 'expired'
      when x."revoked_at" is not null then 'grace'
      else 'active'
    end,
    'successor_id', (select s."id" from "better_supabase"."api_keys" s where s."rotated_from" = x."id" order by s."created_at" desc limit 1)
  ) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."api_keys" x
      where (case when page_api_keys.tenant is null then x."user_id" = auth.uid() else x."tenant_id" = page_api_keys.tenant and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', page_api_keys.tenant, 'api_keys.manage'), false) or x."user_id" = auth.uid()) end)
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (not (v_filters -> 'revoked' is not null and jsonb_typeof(v_filters -> 'revoked') <> 'null' and not (jsonb_typeof(v_filters -> 'revoked') = 'array' and jsonb_array_length(v_filters -> 'revoked') = 0)) or (x."revoked_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'revoked') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'revoked')) else array[v_filters ->> 'revoked'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."prefix" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'API_KEY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'organization_id', x."tenant_id",
    'user_id', x."user_id",
    'name', x."name",
    'prefix', x."prefix",
    'public_id', x."public_id",
    'scopes', to_jsonb(x."scopes"),
    'kind', x."kind",
    'rate_limit', x."rate_limit",
    'expires_at', x."expires_at",
    'last_used_at', x."last_used_at",
    'revoked_at', x."revoked_at",
    'rotated_from', x."rotated_from",
    'created_by', x."created_by",
    'created_at', x."created_at",
    'state', case
      when x."revoked_at" is not null and x."revoked_at" <= now() then 'revoked'
      when x."expires_at" is not null and x."expires_at" <= now() then 'expired'
      when x."revoked_at" is not null then 'grace'
      else 'active'
    end,
    'successor_id', (select s."id" from "better_supabase"."api_keys" s where s."rotated_from" = x."id" order by s."created_at" desc limit 1)
  ) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."api_keys" x
      where (case when page_api_keys.tenant is null then x."user_id" = auth.uid() else x."tenant_id" = page_api_keys.tenant and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', page_api_keys.tenant, 'api_keys.manage'), false) or x."user_id" = auth.uid()) end)
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (not (v_filters -> 'revoked' is not null and jsonb_typeof(v_filters -> 'revoked') <> 'null' and not (jsonb_typeof(v_filters -> 'revoked') = 'array' and jsonb_array_length(v_filters -> 'revoked') = 0)) or (x."revoked_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'revoked') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'revoked')) else array[v_filters ->> 'revoked'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."prefix" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'API_KEY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'organization_id', x."tenant_id",
    'user_id', x."user_id",
    'name', x."name",
    'prefix', x."prefix",
    'public_id', x."public_id",
    'scopes', to_jsonb(x."scopes"),
    'kind', x."kind",
    'rate_limit', x."rate_limit",
    'expires_at', x."expires_at",
    'last_used_at', x."last_used_at",
    'revoked_at', x."revoked_at",
    'rotated_from', x."rotated_from",
    'created_by', x."created_by",
    'created_at', x."created_at",
    'state', case
      when x."revoked_at" is not null and x."revoked_at" <= now() then 'revoked'
      when x."expires_at" is not null and x."expires_at" <= now() then 'expired'
      when x."revoked_at" is not null then 'grace'
      else 'active'
    end,
    'successor_id', (select s."id" from "better_supabase"."api_keys" s where s."rotated_from" = x."id" order by s."created_at" desc limit 1)
  ) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."api_keys" x
      where (case when page_api_keys.tenant is null then x."user_id" = auth.uid() else x."tenant_id" = page_api_keys.tenant and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', page_api_keys.tenant, 'api_keys.manage'), false) or x."user_id" = auth.uid()) end)
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (not (v_filters -> 'revoked' is not null and jsonb_typeof(v_filters -> 'revoked') <> 'null' and not (jsonb_typeof(v_filters -> 'revoked') = 'array' and jsonb_array_length(v_filters -> 'revoked') = 0)) or (x."revoked_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'revoked') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'revoked')) else array[v_filters ->> 'revoked'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."prefix" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'API_KEY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'organization_id', x."tenant_id",
    'user_id', x."user_id",
    'name', x."name",
    'prefix', x."prefix",
    'public_id', x."public_id",
    'scopes', to_jsonb(x."scopes"),
    'kind', x."kind",
    'rate_limit', x."rate_limit",
    'expires_at', x."expires_at",
    'last_used_at', x."last_used_at",
    'revoked_at', x."revoked_at",
    'rotated_from', x."rotated_from",
    'created_by', x."created_by",
    'created_at', x."created_at",
    'state', case
      when x."revoked_at" is not null and x."revoked_at" <= now() then 'revoked'
      when x."expires_at" is not null and x."expires_at" <= now() then 'expired'
      when x."revoked_at" is not null then 'grace'
      else 'active'
    end,
    'successor_id', (select s."id" from "better_supabase"."api_keys" s where s."rotated_from" = x."id" order by s."created_at" desc limit 1)
  ) as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."api_keys" x
      where (case when page_api_keys.tenant is null then x."user_id" = auth.uid() else x."tenant_id" = page_api_keys.tenant and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', page_api_keys.tenant, 'api_keys.manage'), false) or x."user_id" = auth.uid()) end)
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (not (v_filters -> 'revoked' is not null and jsonb_typeof(v_filters -> 'revoked') <> 'null' and not (jsonb_typeof(v_filters -> 'revoked') = 'array' and jsonb_array_length(v_filters -> 'revoked') = 0)) or (x."revoked_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'revoked') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'revoked')) else array[v_filters ->> 'revoked'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."prefix" ilike v_search)
        and (v_after is null or (x."name", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."name" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'API_KEY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'organization_id', x."tenant_id",
    'user_id', x."user_id",
    'name', x."name",
    'prefix', x."prefix",
    'public_id', x."public_id",
    'scopes', to_jsonb(x."scopes"),
    'kind', x."kind",
    'rate_limit', x."rate_limit",
    'expires_at', x."expires_at",
    'last_used_at', x."last_used_at",
    'revoked_at', x."revoked_at",
    'rotated_from', x."rotated_from",
    'created_by', x."created_by",
    'created_at', x."created_at",
    'state', case
      when x."revoked_at" is not null and x."revoked_at" <= now() then 'revoked'
      when x."expires_at" is not null and x."expires_at" <= now() then 'expired'
      when x."revoked_at" is not null then 'grace'
      else 'active'
    end,
    'successor_id', (select s."id" from "better_supabase"."api_keys" s where s."rotated_from" = x."id" order by s."created_at" desc limit 1)
  ) as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."api_keys" x
      where (case when page_api_keys.tenant is null then x."user_id" = auth.uid() else x."tenant_id" = page_api_keys.tenant and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', page_api_keys.tenant, 'api_keys.manage'), false) or x."user_id" = auth.uid()) end)
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (not (v_filters -> 'revoked' is not null and jsonb_typeof(v_filters -> 'revoked') <> 'null' and not (jsonb_typeof(v_filters -> 'revoked') = 'array' and jsonb_array_length(v_filters -> 'revoked') = 0)) or (x."revoked_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'revoked') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'revoked')) else array[v_filters ->> 'revoked'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."prefix" ilike v_search)
        and (v_after is null or (x."name" <= (v_after ->> 0)::text and ((x."name" < (v_after ->> 0)::text) or (x."name" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."name" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'expiresAt' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'API_KEY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'organization_id', x."tenant_id",
    'user_id', x."user_id",
    'name', x."name",
    'prefix', x."prefix",
    'public_id', x."public_id",
    'scopes', to_jsonb(x."scopes"),
    'kind', x."kind",
    'rate_limit', x."rate_limit",
    'expires_at', x."expires_at",
    'last_used_at', x."last_used_at",
    'revoked_at', x."revoked_at",
    'rotated_from', x."rotated_from",
    'created_by', x."created_by",
    'created_at', x."created_at",
    'state', case
      when x."revoked_at" is not null and x."revoked_at" <= now() then 'revoked'
      when x."expires_at" is not null and x."expires_at" <= now() then 'expired'
      when x."revoked_at" is not null then 'grace'
      else 'active'
    end,
    'successor_id', (select s."id" from "better_supabase"."api_keys" s where s."rotated_from" = x."id" order by s."created_at" desc limit 1)
  ) as j, jsonb_build_array((x."expires_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."api_keys" x
      where (case when page_api_keys.tenant is null then x."user_id" = auth.uid() else x."tenant_id" = page_api_keys.tenant and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', page_api_keys.tenant, 'api_keys.manage'), false) or x."user_id" = auth.uid()) end)
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (not (v_filters -> 'revoked' is not null and jsonb_typeof(v_filters -> 'revoked') <> 'null' and not (jsonb_typeof(v_filters -> 'revoked') = 'array' and jsonb_array_length(v_filters -> 'revoked') = 0)) or (x."revoked_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'revoked') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'revoked')) else array[v_filters ->> 'revoked'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."prefix" ilike v_search)
        and (v_after is null or (x."expires_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."expires_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'expiresAt' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'API_KEY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'organization_id', x."tenant_id",
    'user_id', x."user_id",
    'name', x."name",
    'prefix', x."prefix",
    'public_id', x."public_id",
    'scopes', to_jsonb(x."scopes"),
    'kind', x."kind",
    'rate_limit', x."rate_limit",
    'expires_at', x."expires_at",
    'last_used_at', x."last_used_at",
    'revoked_at', x."revoked_at",
    'rotated_from', x."rotated_from",
    'created_by', x."created_by",
    'created_at', x."created_at",
    'state', case
      when x."revoked_at" is not null and x."revoked_at" <= now() then 'revoked'
      when x."expires_at" is not null and x."expires_at" <= now() then 'expired'
      when x."revoked_at" is not null then 'grace'
      else 'active'
    end,
    'successor_id', (select s."id" from "better_supabase"."api_keys" s where s."rotated_from" = x."id" order by s."created_at" desc limit 1)
  ) as j, jsonb_build_array((x."expires_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."api_keys" x
      where (case when page_api_keys.tenant is null then x."user_id" = auth.uid() else x."tenant_id" = page_api_keys.tenant and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', page_api_keys.tenant, 'api_keys.manage'), false) or x."user_id" = auth.uid()) end)
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (not (v_filters -> 'revoked' is not null and jsonb_typeof(v_filters -> 'revoked') <> 'null' and not (jsonb_typeof(v_filters -> 'revoked') = 'array' and jsonb_array_length(v_filters -> 'revoked') = 0)) or (x."revoked_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'revoked') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'revoked')) else array[v_filters ->> 'revoked'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."prefix" ilike v_search)
        and (v_after is null or (x."expires_at" <= (v_after ->> 0)::timestamptz and ((x."expires_at" < (v_after ->> 0)::timestamptz) or (x."expires_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."expires_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'lastUsedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'API_KEY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'organization_id', x."tenant_id",
    'user_id', x."user_id",
    'name', x."name",
    'prefix', x."prefix",
    'public_id', x."public_id",
    'scopes', to_jsonb(x."scopes"),
    'kind', x."kind",
    'rate_limit', x."rate_limit",
    'expires_at', x."expires_at",
    'last_used_at', x."last_used_at",
    'revoked_at', x."revoked_at",
    'rotated_from', x."rotated_from",
    'created_by', x."created_by",
    'created_at', x."created_at",
    'state', case
      when x."revoked_at" is not null and x."revoked_at" <= now() then 'revoked'
      when x."expires_at" is not null and x."expires_at" <= now() then 'expired'
      when x."revoked_at" is not null then 'grace'
      else 'active'
    end,
    'successor_id', (select s."id" from "better_supabase"."api_keys" s where s."rotated_from" = x."id" order by s."created_at" desc limit 1)
  ) as j, jsonb_build_array((x."last_used_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."api_keys" x
      where (case when page_api_keys.tenant is null then x."user_id" = auth.uid() else x."tenant_id" = page_api_keys.tenant and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', page_api_keys.tenant, 'api_keys.manage'), false) or x."user_id" = auth.uid()) end)
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (not (v_filters -> 'revoked' is not null and jsonb_typeof(v_filters -> 'revoked') <> 'null' and not (jsonb_typeof(v_filters -> 'revoked') = 'array' and jsonb_array_length(v_filters -> 'revoked') = 0)) or (x."revoked_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'revoked') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'revoked')) else array[v_filters ->> 'revoked'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."prefix" ilike v_search)
        and (v_after is null or (x."last_used_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."last_used_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'lastUsedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'API_KEY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'organization_id', x."tenant_id",
    'user_id', x."user_id",
    'name', x."name",
    'prefix', x."prefix",
    'public_id', x."public_id",
    'scopes', to_jsonb(x."scopes"),
    'kind', x."kind",
    'rate_limit', x."rate_limit",
    'expires_at', x."expires_at",
    'last_used_at', x."last_used_at",
    'revoked_at', x."revoked_at",
    'rotated_from', x."rotated_from",
    'created_by', x."created_by",
    'created_at', x."created_at",
    'state', case
      when x."revoked_at" is not null and x."revoked_at" <= now() then 'revoked'
      when x."expires_at" is not null and x."expires_at" <= now() then 'expired'
      when x."revoked_at" is not null then 'grace'
      else 'active'
    end,
    'successor_id', (select s."id" from "better_supabase"."api_keys" s where s."rotated_from" = x."id" order by s."created_at" desc limit 1)
  ) as j, jsonb_build_array((x."last_used_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."api_keys" x
      where (case when page_api_keys.tenant is null then x."user_id" = auth.uid() else x."tenant_id" = page_api_keys.tenant and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', page_api_keys.tenant, 'api_keys.manage'), false) or x."user_id" = auth.uid()) end)
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (not (v_filters -> 'revoked' is not null and jsonb_typeof(v_filters -> 'revoked') <> 'null' and not (jsonb_typeof(v_filters -> 'revoked') = 'array' and jsonb_array_length(v_filters -> 'revoked') = 0)) or (x."revoked_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'revoked') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'revoked')) else array[v_filters ->> 'revoked'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."prefix" ilike v_search)
        and (v_after is null or (x."last_used_at" <= (v_after ->> 0)::timestamptz and ((x."last_used_at" < (v_after ->> 0)::timestamptz) or (x."last_used_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."last_used_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."api_keys" x
      where (case when page_api_keys.tenant is null then x."user_id" = auth.uid() else x."tenant_id" = page_api_keys.tenant and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', page_api_keys.tenant, 'api_keys.manage'), false) or x."user_id" = auth.uid()) end)
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (not (v_filters -> 'revoked' is not null and jsonb_typeof(v_filters -> 'revoked') <> 'null' and not (jsonb_typeof(v_filters -> 'revoked') = 'array' and jsonb_array_length(v_filters -> 'revoked') = 0)) or (x."revoked_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'revoked') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'revoked')) else array[v_filters ->> 'revoked'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."prefix" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_organization_domains (
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
  v_filters jsonb := coalesce(page_organization_domains.filters, '{}'::jsonb);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not coalesce(better_supabase.can('tenant', page_organization_domains.tenant, 'sso.manage'), false) then
    raise exception 'You may not manage this organization''s domains' using errcode = '42501', hint = 'SSO_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'SSO_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('verified', 'enforceSso') then
      raise exception 'facet is one of verified, enforceSso' using errcode = '22023', hint = 'SSO_INVALID';
    end if;
    with s as (
      select (case v_facet when 'verified' then ((x."verified_at" is not null)::text)::text when 'enforceSso' then (x."enforce_sso"::text)::text end) as v
      from "better_supabase"."sso_domains" x
      where x."tenant_id" = page_organization_domains.tenant
        and (not (v_filters -> 'verified' is not null and jsonb_typeof(v_filters -> 'verified') <> 'null' and not (jsonb_typeof(v_filters -> 'verified') = 'array' and jsonb_array_length(v_filters -> 'verified') = 0)) or (x."verified_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'verified') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'verified')) else array[v_filters ->> 'verified'] end)::text[]))
        and (not (v_filters -> 'enforceSso' is not null and jsonb_typeof(v_filters -> 'enforceSso') <> 'null' and not (jsonb_typeof(v_filters -> 'enforceSso') = 'array' and jsonb_array_length(v_filters -> 'enforceSso') = 0)) or x."enforce_sso"::text = any((case when jsonb_typeof(v_filters -> 'enforceSso') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enforceSso')) else array[v_filters ->> 'enforceSso'] end)::text[]))
        and (not (v_filters -> 'autoJoinRole' is not null and jsonb_typeof(v_filters -> 'autoJoinRole') <> 'null' and not (jsonb_typeof(v_filters -> 'autoJoinRole') = 'array' and jsonb_array_length(v_filters -> 'autoJoinRole') = 0)) or x."auto_join_role"::text = any((case when jsonb_typeof(v_filters -> 'autoJoinRole') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'autoJoinRole')) else array[v_filters ->> 'autoJoinRole'] end)::text[]))
        and (v_search is null or x."domain" ilike v_search)
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
      select 1 from "better_supabase"."sso_domains" x
      where x."tenant_id" = page_organization_domains.tenant
        and (not (v_filters -> 'verified' is not null and jsonb_typeof(v_filters -> 'verified') <> 'null' and not (jsonb_typeof(v_filters -> 'verified') = 'array' and jsonb_array_length(v_filters -> 'verified') = 0)) or (x."verified_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'verified') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'verified')) else array[v_filters ->> 'verified'] end)::text[]))
        and (not (v_filters -> 'enforceSso' is not null and jsonb_typeof(v_filters -> 'enforceSso') <> 'null' and not (jsonb_typeof(v_filters -> 'enforceSso') = 'array' and jsonb_array_length(v_filters -> 'enforceSso') = 0)) or x."enforce_sso"::text = any((case when jsonb_typeof(v_filters -> 'enforceSso') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enforceSso')) else array[v_filters ->> 'enforceSso'] end)::text[]))
        and (not (v_filters -> 'autoJoinRole' is not null and jsonb_typeof(v_filters -> 'autoJoinRole') <> 'null' and not (jsonb_typeof(v_filters -> 'autoJoinRole') = 'array' and jsonb_array_length(v_filters -> 'autoJoinRole') = 0)) or x."auto_join_role"::text = any((case when jsonb_typeof(v_filters -> 'autoJoinRole') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'autoJoinRole')) else array[v_filters ->> 'autoJoinRole'] end)::text[]))
        and (v_search is null or x."domain" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('domain', 'verifiedAt') then
    raise exception 'sort is one of domain, verifiedAt' using errcode = '22023', hint = 'SSO_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'SSO_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SSO_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) - 'verification_token' || jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || x."domain", 'value', 'better-supabase-domain-verification=' || x."verification_token")) as j, jsonb_build_array((x."domain")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."sso_domains" x
      where x."tenant_id" = page_organization_domains.tenant
        and (not (v_filters -> 'verified' is not null and jsonb_typeof(v_filters -> 'verified') <> 'null' and not (jsonb_typeof(v_filters -> 'verified') = 'array' and jsonb_array_length(v_filters -> 'verified') = 0)) or (x."verified_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'verified') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'verified')) else array[v_filters ->> 'verified'] end)::text[]))
        and (not (v_filters -> 'enforceSso' is not null and jsonb_typeof(v_filters -> 'enforceSso') <> 'null' and not (jsonb_typeof(v_filters -> 'enforceSso') = 'array' and jsonb_array_length(v_filters -> 'enforceSso') = 0)) or x."enforce_sso"::text = any((case when jsonb_typeof(v_filters -> 'enforceSso') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enforceSso')) else array[v_filters ->> 'enforceSso'] end)::text[]))
        and (not (v_filters -> 'autoJoinRole' is not null and jsonb_typeof(v_filters -> 'autoJoinRole') <> 'null' and not (jsonb_typeof(v_filters -> 'autoJoinRole') = 'array' and jsonb_array_length(v_filters -> 'autoJoinRole') = 0)) or x."auto_join_role"::text = any((case when jsonb_typeof(v_filters -> 'autoJoinRole') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'autoJoinRole')) else array[v_filters ->> 'autoJoinRole'] end)::text[]))
        and (v_search is null or x."domain" ilike v_search)
        and (v_after is null or (x."domain", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."domain" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SSO_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) - 'verification_token' || jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || x."domain", 'value', 'better-supabase-domain-verification=' || x."verification_token")) as j, jsonb_build_array((x."domain")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."sso_domains" x
      where x."tenant_id" = page_organization_domains.tenant
        and (not (v_filters -> 'verified' is not null and jsonb_typeof(v_filters -> 'verified') <> 'null' and not (jsonb_typeof(v_filters -> 'verified') = 'array' and jsonb_array_length(v_filters -> 'verified') = 0)) or (x."verified_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'verified') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'verified')) else array[v_filters ->> 'verified'] end)::text[]))
        and (not (v_filters -> 'enforceSso' is not null and jsonb_typeof(v_filters -> 'enforceSso') <> 'null' and not (jsonb_typeof(v_filters -> 'enforceSso') = 'array' and jsonb_array_length(v_filters -> 'enforceSso') = 0)) or x."enforce_sso"::text = any((case when jsonb_typeof(v_filters -> 'enforceSso') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enforceSso')) else array[v_filters ->> 'enforceSso'] end)::text[]))
        and (not (v_filters -> 'autoJoinRole' is not null and jsonb_typeof(v_filters -> 'autoJoinRole') <> 'null' and not (jsonb_typeof(v_filters -> 'autoJoinRole') = 'array' and jsonb_array_length(v_filters -> 'autoJoinRole') = 0)) or x."auto_join_role"::text = any((case when jsonb_typeof(v_filters -> 'autoJoinRole') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'autoJoinRole')) else array[v_filters ->> 'autoJoinRole'] end)::text[]))
        and (v_search is null or x."domain" ilike v_search)
        and (v_after is null or (x."domain" <= (v_after ->> 0)::text and ((x."domain" < (v_after ->> 0)::text) or (x."domain" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."domain" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'domain' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SSO_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) - 'verification_token' || jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || x."domain", 'value', 'better-supabase-domain-verification=' || x."verification_token")) as j, jsonb_build_array((x."domain")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."sso_domains" x
      where x."tenant_id" = page_organization_domains.tenant
        and (not (v_filters -> 'verified' is not null and jsonb_typeof(v_filters -> 'verified') <> 'null' and not (jsonb_typeof(v_filters -> 'verified') = 'array' and jsonb_array_length(v_filters -> 'verified') = 0)) or (x."verified_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'verified') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'verified')) else array[v_filters ->> 'verified'] end)::text[]))
        and (not (v_filters -> 'enforceSso' is not null and jsonb_typeof(v_filters -> 'enforceSso') <> 'null' and not (jsonb_typeof(v_filters -> 'enforceSso') = 'array' and jsonb_array_length(v_filters -> 'enforceSso') = 0)) or x."enforce_sso"::text = any((case when jsonb_typeof(v_filters -> 'enforceSso') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enforceSso')) else array[v_filters ->> 'enforceSso'] end)::text[]))
        and (not (v_filters -> 'autoJoinRole' is not null and jsonb_typeof(v_filters -> 'autoJoinRole') <> 'null' and not (jsonb_typeof(v_filters -> 'autoJoinRole') = 'array' and jsonb_array_length(v_filters -> 'autoJoinRole') = 0)) or x."auto_join_role"::text = any((case when jsonb_typeof(v_filters -> 'autoJoinRole') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'autoJoinRole')) else array[v_filters ->> 'autoJoinRole'] end)::text[]))
        and (v_search is null or x."domain" ilike v_search)
        and (v_after is null or (x."domain", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."domain" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'domain' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SSO_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) - 'verification_token' || jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || x."domain", 'value', 'better-supabase-domain-verification=' || x."verification_token")) as j, jsonb_build_array((x."domain")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."sso_domains" x
      where x."tenant_id" = page_organization_domains.tenant
        and (not (v_filters -> 'verified' is not null and jsonb_typeof(v_filters -> 'verified') <> 'null' and not (jsonb_typeof(v_filters -> 'verified') = 'array' and jsonb_array_length(v_filters -> 'verified') = 0)) or (x."verified_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'verified') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'verified')) else array[v_filters ->> 'verified'] end)::text[]))
        and (not (v_filters -> 'enforceSso' is not null and jsonb_typeof(v_filters -> 'enforceSso') <> 'null' and not (jsonb_typeof(v_filters -> 'enforceSso') = 'array' and jsonb_array_length(v_filters -> 'enforceSso') = 0)) or x."enforce_sso"::text = any((case when jsonb_typeof(v_filters -> 'enforceSso') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enforceSso')) else array[v_filters ->> 'enforceSso'] end)::text[]))
        and (not (v_filters -> 'autoJoinRole' is not null and jsonb_typeof(v_filters -> 'autoJoinRole') <> 'null' and not (jsonb_typeof(v_filters -> 'autoJoinRole') = 'array' and jsonb_array_length(v_filters -> 'autoJoinRole') = 0)) or x."auto_join_role"::text = any((case when jsonb_typeof(v_filters -> 'autoJoinRole') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'autoJoinRole')) else array[v_filters ->> 'autoJoinRole'] end)::text[]))
        and (v_search is null or x."domain" ilike v_search)
        and (v_after is null or (x."domain" <= (v_after ->> 0)::text and ((x."domain" < (v_after ->> 0)::text) or (x."domain" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."domain" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'verifiedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SSO_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) - 'verification_token' || jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || x."domain", 'value', 'better-supabase-domain-verification=' || x."verification_token")) as j, jsonb_build_array((x."verified_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."sso_domains" x
      where x."tenant_id" = page_organization_domains.tenant
        and (not (v_filters -> 'verified' is not null and jsonb_typeof(v_filters -> 'verified') <> 'null' and not (jsonb_typeof(v_filters -> 'verified') = 'array' and jsonb_array_length(v_filters -> 'verified') = 0)) or (x."verified_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'verified') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'verified')) else array[v_filters ->> 'verified'] end)::text[]))
        and (not (v_filters -> 'enforceSso' is not null and jsonb_typeof(v_filters -> 'enforceSso') <> 'null' and not (jsonb_typeof(v_filters -> 'enforceSso') = 'array' and jsonb_array_length(v_filters -> 'enforceSso') = 0)) or x."enforce_sso"::text = any((case when jsonb_typeof(v_filters -> 'enforceSso') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enforceSso')) else array[v_filters ->> 'enforceSso'] end)::text[]))
        and (not (v_filters -> 'autoJoinRole' is not null and jsonb_typeof(v_filters -> 'autoJoinRole') <> 'null' and not (jsonb_typeof(v_filters -> 'autoJoinRole') = 'array' and jsonb_array_length(v_filters -> 'autoJoinRole') = 0)) or x."auto_join_role"::text = any((case when jsonb_typeof(v_filters -> 'autoJoinRole') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'autoJoinRole')) else array[v_filters ->> 'autoJoinRole'] end)::text[]))
        and (v_search is null or x."domain" ilike v_search)
        and (v_after is null or (x."verified_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."verified_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'verifiedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SSO_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) - 'verification_token' || jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || x."domain", 'value', 'better-supabase-domain-verification=' || x."verification_token")) as j, jsonb_build_array((x."verified_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."sso_domains" x
      where x."tenant_id" = page_organization_domains.tenant
        and (not (v_filters -> 'verified' is not null and jsonb_typeof(v_filters -> 'verified') <> 'null' and not (jsonb_typeof(v_filters -> 'verified') = 'array' and jsonb_array_length(v_filters -> 'verified') = 0)) or (x."verified_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'verified') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'verified')) else array[v_filters ->> 'verified'] end)::text[]))
        and (not (v_filters -> 'enforceSso' is not null and jsonb_typeof(v_filters -> 'enforceSso') <> 'null' and not (jsonb_typeof(v_filters -> 'enforceSso') = 'array' and jsonb_array_length(v_filters -> 'enforceSso') = 0)) or x."enforce_sso"::text = any((case when jsonb_typeof(v_filters -> 'enforceSso') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enforceSso')) else array[v_filters ->> 'enforceSso'] end)::text[]))
        and (not (v_filters -> 'autoJoinRole' is not null and jsonb_typeof(v_filters -> 'autoJoinRole') <> 'null' and not (jsonb_typeof(v_filters -> 'autoJoinRole') = 'array' and jsonb_array_length(v_filters -> 'autoJoinRole') = 0)) or x."auto_join_role"::text = any((case when jsonb_typeof(v_filters -> 'autoJoinRole') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'autoJoinRole')) else array[v_filters ->> 'autoJoinRole'] end)::text[]))
        and (v_search is null or x."domain" ilike v_search)
        and (v_after is null or (x."verified_at" <= (v_after ->> 0)::timestamptz and ((x."verified_at" < (v_after ->> 0)::timestamptz) or (x."verified_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."verified_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."sso_domains" x
      where x."tenant_id" = page_organization_domains.tenant
        and (not (v_filters -> 'verified' is not null and jsonb_typeof(v_filters -> 'verified') <> 'null' and not (jsonb_typeof(v_filters -> 'verified') = 'array' and jsonb_array_length(v_filters -> 'verified') = 0)) or (x."verified_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'verified') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'verified')) else array[v_filters ->> 'verified'] end)::text[]))
        and (not (v_filters -> 'enforceSso' is not null and jsonb_typeof(v_filters -> 'enforceSso') <> 'null' and not (jsonb_typeof(v_filters -> 'enforceSso') = 'array' and jsonb_array_length(v_filters -> 'enforceSso') = 0)) or x."enforce_sso"::text = any((case when jsonb_typeof(v_filters -> 'enforceSso') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enforceSso')) else array[v_filters ->> 'enforceSso'] end)::text[]))
        and (not (v_filters -> 'autoJoinRole' is not null and jsonb_typeof(v_filters -> 'autoJoinRole') <> 'null' and not (jsonb_typeof(v_filters -> 'autoJoinRole') = 'array' and jsonb_array_length(v_filters -> 'autoJoinRole') = 0)) or x."auto_join_role"::text = any((case when jsonb_typeof(v_filters -> 'autoJoinRole') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'autoJoinRole')) else array[v_filters ->> 'autoJoinRole'] end)::text[]))
        and (v_search is null or x."domain" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_service_principals (
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
  v_filters jsonb := coalesce(page_service_principals.filters, '{}'::jsonb);
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
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'SERVICE_PRINCIPAL_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('role', 'isDefault', 'disabled') then
      raise exception 'facet is one of role, isDefault, disabled' using errcode = '22023', hint = 'SERVICE_PRINCIPAL_INVALID';
    end if;
    with s as (
      select (case v_facet when 'role' then (x."role"::text)::text when 'isDefault' then (x."is_default"::text)::text when 'disabled' then ((x."disabled_at" is not null)::text)::text end) as v
      from "better_supabase"."service_principals" x
      where x."tenant_id" = page_service_principals.tenant
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or x."role"::text = any((case when jsonb_typeof(v_filters -> 'role') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'role')) else array[v_filters ->> 'role'] end)::text[]))
        and (not (v_filters -> 'isDefault' is not null and jsonb_typeof(v_filters -> 'isDefault') <> 'null' and not (jsonb_typeof(v_filters -> 'isDefault') = 'array' and jsonb_array_length(v_filters -> 'isDefault') = 0)) or x."is_default"::text = any((case when jsonb_typeof(v_filters -> 'isDefault') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'isDefault')) else array[v_filters ->> 'isDefault'] end)::text[]))
        and (not (v_filters -> 'disabled' is not null and jsonb_typeof(v_filters -> 'disabled') <> 'null' and not (jsonb_typeof(v_filters -> 'disabled') = 'array' and jsonb_array_length(v_filters -> 'disabled') = 0)) or (x."disabled_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'disabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'disabled')) else array[v_filters ->> 'disabled'] end)::text[]))
        and (v_search is null or x."name" ilike v_search)
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
      select 1 from "better_supabase"."service_principals" x
      where x."tenant_id" = page_service_principals.tenant
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or x."role"::text = any((case when jsonb_typeof(v_filters -> 'role') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'role')) else array[v_filters ->> 'role'] end)::text[]))
        and (not (v_filters -> 'isDefault' is not null and jsonb_typeof(v_filters -> 'isDefault') <> 'null' and not (jsonb_typeof(v_filters -> 'isDefault') = 'array' and jsonb_array_length(v_filters -> 'isDefault') = 0)) or x."is_default"::text = any((case when jsonb_typeof(v_filters -> 'isDefault') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'isDefault')) else array[v_filters ->> 'isDefault'] end)::text[]))
        and (not (v_filters -> 'disabled' is not null and jsonb_typeof(v_filters -> 'disabled') <> 'null' and not (jsonb_typeof(v_filters -> 'disabled') = 'array' and jsonb_array_length(v_filters -> 'disabled') = 0)) or (x."disabled_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'disabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'disabled')) else array[v_filters ->> 'disabled'] end)::text[]))
        and (v_search is null or x."name" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'createdAt') then
    raise exception 'sort is one of name, createdAt' using errcode = '22023', hint = 'SERVICE_PRINCIPAL_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'SERVICE_PRINCIPAL_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SERVICE_PRINCIPAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
      'id', x."id", 'name', x."name", 'role', x."role", 'isDefault', x."is_default",
      'createdBy', x."created_by", 'createdAt', x."created_at", 'disabledAt', x."disabled_at"
    ) as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."service_principals" x
      where x."tenant_id" = page_service_principals.tenant
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or x."role"::text = any((case when jsonb_typeof(v_filters -> 'role') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'role')) else array[v_filters ->> 'role'] end)::text[]))
        and (not (v_filters -> 'isDefault' is not null and jsonb_typeof(v_filters -> 'isDefault') <> 'null' and not (jsonb_typeof(v_filters -> 'isDefault') = 'array' and jsonb_array_length(v_filters -> 'isDefault') = 0)) or x."is_default"::text = any((case when jsonb_typeof(v_filters -> 'isDefault') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'isDefault')) else array[v_filters ->> 'isDefault'] end)::text[]))
        and (not (v_filters -> 'disabled' is not null and jsonb_typeof(v_filters -> 'disabled') <> 'null' and not (jsonb_typeof(v_filters -> 'disabled') = 'array' and jsonb_array_length(v_filters -> 'disabled') = 0)) or (x."disabled_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'disabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'disabled')) else array[v_filters ->> 'disabled'] end)::text[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (x."name", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."name" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SERVICE_PRINCIPAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
      'id', x."id", 'name', x."name", 'role', x."role", 'isDefault', x."is_default",
      'createdBy', x."created_by", 'createdAt', x."created_at", 'disabledAt', x."disabled_at"
    ) as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."service_principals" x
      where x."tenant_id" = page_service_principals.tenant
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or x."role"::text = any((case when jsonb_typeof(v_filters -> 'role') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'role')) else array[v_filters ->> 'role'] end)::text[]))
        and (not (v_filters -> 'isDefault' is not null and jsonb_typeof(v_filters -> 'isDefault') <> 'null' and not (jsonb_typeof(v_filters -> 'isDefault') = 'array' and jsonb_array_length(v_filters -> 'isDefault') = 0)) or x."is_default"::text = any((case when jsonb_typeof(v_filters -> 'isDefault') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'isDefault')) else array[v_filters ->> 'isDefault'] end)::text[]))
        and (not (v_filters -> 'disabled' is not null and jsonb_typeof(v_filters -> 'disabled') <> 'null' and not (jsonb_typeof(v_filters -> 'disabled') = 'array' and jsonb_array_length(v_filters -> 'disabled') = 0)) or (x."disabled_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'disabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'disabled')) else array[v_filters ->> 'disabled'] end)::text[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (x."name" <= (v_after ->> 0)::text and ((x."name" < (v_after ->> 0)::text) or (x."name" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."name" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SERVICE_PRINCIPAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
      'id', x."id", 'name', x."name", 'role', x."role", 'isDefault', x."is_default",
      'createdBy', x."created_by", 'createdAt', x."created_at", 'disabledAt', x."disabled_at"
    ) as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."service_principals" x
      where x."tenant_id" = page_service_principals.tenant
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or x."role"::text = any((case when jsonb_typeof(v_filters -> 'role') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'role')) else array[v_filters ->> 'role'] end)::text[]))
        and (not (v_filters -> 'isDefault' is not null and jsonb_typeof(v_filters -> 'isDefault') <> 'null' and not (jsonb_typeof(v_filters -> 'isDefault') = 'array' and jsonb_array_length(v_filters -> 'isDefault') = 0)) or x."is_default"::text = any((case when jsonb_typeof(v_filters -> 'isDefault') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'isDefault')) else array[v_filters ->> 'isDefault'] end)::text[]))
        and (not (v_filters -> 'disabled' is not null and jsonb_typeof(v_filters -> 'disabled') <> 'null' and not (jsonb_typeof(v_filters -> 'disabled') = 'array' and jsonb_array_length(v_filters -> 'disabled') = 0)) or (x."disabled_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'disabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'disabled')) else array[v_filters ->> 'disabled'] end)::text[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (x."name", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."name" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SERVICE_PRINCIPAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
      'id', x."id", 'name', x."name", 'role', x."role", 'isDefault', x."is_default",
      'createdBy', x."created_by", 'createdAt', x."created_at", 'disabledAt', x."disabled_at"
    ) as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."service_principals" x
      where x."tenant_id" = page_service_principals.tenant
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or x."role"::text = any((case when jsonb_typeof(v_filters -> 'role') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'role')) else array[v_filters ->> 'role'] end)::text[]))
        and (not (v_filters -> 'isDefault' is not null and jsonb_typeof(v_filters -> 'isDefault') <> 'null' and not (jsonb_typeof(v_filters -> 'isDefault') = 'array' and jsonb_array_length(v_filters -> 'isDefault') = 0)) or x."is_default"::text = any((case when jsonb_typeof(v_filters -> 'isDefault') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'isDefault')) else array[v_filters ->> 'isDefault'] end)::text[]))
        and (not (v_filters -> 'disabled' is not null and jsonb_typeof(v_filters -> 'disabled') <> 'null' and not (jsonb_typeof(v_filters -> 'disabled') = 'array' and jsonb_array_length(v_filters -> 'disabled') = 0)) or (x."disabled_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'disabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'disabled')) else array[v_filters ->> 'disabled'] end)::text[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (x."name" <= (v_after ->> 0)::text and ((x."name" < (v_after ->> 0)::text) or (x."name" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."name" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SERVICE_PRINCIPAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
      'id', x."id", 'name', x."name", 'role', x."role", 'isDefault', x."is_default",
      'createdBy', x."created_by", 'createdAt', x."created_at", 'disabledAt', x."disabled_at"
    ) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."service_principals" x
      where x."tenant_id" = page_service_principals.tenant
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or x."role"::text = any((case when jsonb_typeof(v_filters -> 'role') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'role')) else array[v_filters ->> 'role'] end)::text[]))
        and (not (v_filters -> 'isDefault' is not null and jsonb_typeof(v_filters -> 'isDefault') <> 'null' and not (jsonb_typeof(v_filters -> 'isDefault') = 'array' and jsonb_array_length(v_filters -> 'isDefault') = 0)) or x."is_default"::text = any((case when jsonb_typeof(v_filters -> 'isDefault') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'isDefault')) else array[v_filters ->> 'isDefault'] end)::text[]))
        and (not (v_filters -> 'disabled' is not null and jsonb_typeof(v_filters -> 'disabled') <> 'null' and not (jsonb_typeof(v_filters -> 'disabled') = 'array' and jsonb_array_length(v_filters -> 'disabled') = 0)) or (x."disabled_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'disabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'disabled')) else array[v_filters ->> 'disabled'] end)::text[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SERVICE_PRINCIPAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
      'id', x."id", 'name', x."name", 'role', x."role", 'isDefault', x."is_default",
      'createdBy', x."created_by", 'createdAt', x."created_at", 'disabledAt', x."disabled_at"
    ) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."service_principals" x
      where x."tenant_id" = page_service_principals.tenant
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or x."role"::text = any((case when jsonb_typeof(v_filters -> 'role') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'role')) else array[v_filters ->> 'role'] end)::text[]))
        and (not (v_filters -> 'isDefault' is not null and jsonb_typeof(v_filters -> 'isDefault') <> 'null' and not (jsonb_typeof(v_filters -> 'isDefault') = 'array' and jsonb_array_length(v_filters -> 'isDefault') = 0)) or x."is_default"::text = any((case when jsonb_typeof(v_filters -> 'isDefault') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'isDefault')) else array[v_filters ->> 'isDefault'] end)::text[]))
        and (not (v_filters -> 'disabled' is not null and jsonb_typeof(v_filters -> 'disabled') <> 'null' and not (jsonb_typeof(v_filters -> 'disabled') = 'array' and jsonb_array_length(v_filters -> 'disabled') = 0)) or (x."disabled_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'disabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'disabled')) else array[v_filters ->> 'disabled'] end)::text[]))
        and (v_search is null or x."name" ilike v_search)
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
      select 1 from "better_supabase"."service_principals" x
      where x."tenant_id" = page_service_principals.tenant
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or x."role"::text = any((case when jsonb_typeof(v_filters -> 'role') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'role')) else array[v_filters ->> 'role'] end)::text[]))
        and (not (v_filters -> 'isDefault' is not null and jsonb_typeof(v_filters -> 'isDefault') <> 'null' and not (jsonb_typeof(v_filters -> 'isDefault') = 'array' and jsonb_array_length(v_filters -> 'isDefault') = 0)) or x."is_default"::text = any((case when jsonb_typeof(v_filters -> 'isDefault') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'isDefault')) else array[v_filters ->> 'isDefault'] end)::text[]))
        and (not (v_filters -> 'disabled' is not null and jsonb_typeof(v_filters -> 'disabled') <> 'null' and not (jsonb_typeof(v_filters -> 'disabled') = 'array' and jsonb_array_length(v_filters -> 'disabled') = 0)) or (x."disabled_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'disabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'disabled')) else array[v_filters ->> 'disabled'] end)::text[]))
        and (v_search is null or x."name" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_sso_providers (
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
  v_filters jsonb := coalesce(page_sso_providers.filters, '{}'::jsonb);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not coalesce(better_supabase.can('tenant', page_sso_providers.tenant, 'sso.manage'), false) then
    raise exception 'You may not manage this organization''s SSO' using errcode = '42501', hint = 'SSO_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'SSO_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('type') then
      raise exception 'facet is one of type' using errcode = '22023', hint = 'SSO_INVALID';
    end if;
    with s as (
      select (case v_facet when 'type' then (x."type"::text)::text end) as v
      from "better_supabase"."sso_providers" x
      where x."tenant_id" = page_sso_providers.tenant
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."type"::text = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
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
      select 1 from "better_supabase"."sso_providers" x
      where x."tenant_id" = page_sso_providers.tenant
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."type"::text = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt') then
    raise exception 'sort is one of createdAt' using errcode = '22023', hint = 'SSO_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'SSO_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SSO_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x.*) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."sso_providers" x
      where x."tenant_id" = page_sso_providers.tenant
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."type"::text = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SSO_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x.*) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."sso_providers" x
      where x."tenant_id" = page_sso_providers.tenant
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."type"::text = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SSO_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x.*) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."sso_providers" x
      where x."tenant_id" = page_sso_providers.tenant
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."type"::text = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SSO_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x.*) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."sso_providers" x
      where x."tenant_id" = page_sso_providers.tenant
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."type"::text = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
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
      select 1 from "better_supabase"."sso_providers" x
      where x."tenant_id" = page_sso_providers.tenant
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."type"::text = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

REVOKE ALL ON FUNCTION "api"."page_api_keys"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_api_keys"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_organization_domains"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_organization_domains"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_service_principals"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_service_principals"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_sso_providers"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_sso_providers"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_api_keys"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_api_keys"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_organization_domains"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_organization_domains"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_service_principals"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_service_principals"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_sso_providers"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_sso_providers"(uuid, jsonb) TO "authenticated", "service_role";
