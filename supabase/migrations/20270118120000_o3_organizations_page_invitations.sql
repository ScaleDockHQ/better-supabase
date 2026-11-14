SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.page_organization_invitations (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_organization_invitations"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.page_organization_invitations (
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
  v_filters jsonb := coalesce(page_organization_invitations.filters, '{}'::jsonb);
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
  if not coalesce(better_supabase.member_can((select auth.uid()), tenant, 'members.invite'), false) then
    raise exception 'Not allowed to list invitations' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'INVITATION_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('role') then
      raise exception 'facet is one of role' using errcode = '22023', hint = 'INVITATION_INVALID';
    end if;
    with s as (
      select (case v_facet when 'role' then (i."role"::text)::text end) as v
      from "better_supabase"."invitations" i
      where i."tenant_id" = page_organization_invitations.tenant
        and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
        and i."expires_at" >= now()
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or i."role"::text = any((case when jsonb_typeof(v_filters -> 'role') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'role')) else array[v_filters ->> 'role'] end)::text[]))
        and (v_search is null or i."email" ilike v_search)
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
      select 1 from "better_supabase"."invitations" i
      where i."tenant_id" = page_organization_invitations.tenant
        and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
        and i."expires_at" >= now()
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or i."role"::text = any((case when jsonb_typeof(v_filters -> 'role') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'role')) else array[v_filters ->> 'role'] end)::text[]))
        and (v_search is null or i."email" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('expiresAt', 'email') then
    raise exception 'sort is one of expiresAt, email' using errcode = '22023', hint = 'INVITATION_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'INVITATION_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVITATION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', i."id", 'email', i."email", 'role', i."role"::text, 'expiresAt', i."expires_at") as j, jsonb_build_array((coalesce(i."expires_at", 'infinity'::timestamptz))::text, (i."id")::text) as k
    from (
      select * from "better_supabase"."invitations" i
      where i."tenant_id" = page_organization_invitations.tenant
        and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
        and i."expires_at" >= now()
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or i."role"::text = any((case when jsonb_typeof(v_filters -> 'role') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'role')) else array[v_filters ->> 'role'] end)::text[]))
        and (v_search is null or i."email" ilike v_search)
        and (v_after is null or (coalesce(i."expires_at", 'infinity'::timestamptz) >= (v_after ->> 0)::timestamptz and ((coalesce(i."expires_at", 'infinity'::timestamptz) > (v_after ->> 0)::timestamptz) or (coalesce(i."expires_at", 'infinity'::timestamptz) = (v_after ->> 0)::timestamptz and i."id" < (v_after ->> 1)::uuid))))
      order by coalesce(i."expires_at", 'infinity'::timestamptz) asc, i."id" desc
      limit v_limit + 1 offset v_offset
    ) i
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVITATION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', i."id", 'email', i."email", 'role', i."role"::text, 'expiresAt', i."expires_at") as j, jsonb_build_array((coalesce(i."expires_at", 'infinity'::timestamptz))::text, (i."id")::text) as k
    from (
      select * from "better_supabase"."invitations" i
      where i."tenant_id" = page_organization_invitations.tenant
        and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
        and i."expires_at" >= now()
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or i."role"::text = any((case when jsonb_typeof(v_filters -> 'role') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'role')) else array[v_filters ->> 'role'] end)::text[]))
        and (v_search is null or i."email" ilike v_search)
        and (v_after is null or (coalesce(i."expires_at", 'infinity'::timestamptz), i."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(i."expires_at", 'infinity'::timestamptz) desc, i."id" desc
      limit v_limit + 1 offset v_offset
    ) i
  ) p;
  elsif v_sort = 'expiresAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVITATION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', i."id", 'email', i."email", 'role', i."role"::text, 'expiresAt', i."expires_at") as j, jsonb_build_array((coalesce(i."expires_at", 'infinity'::timestamptz))::text, (i."id")::text) as k
    from (
      select * from "better_supabase"."invitations" i
      where i."tenant_id" = page_organization_invitations.tenant
        and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
        and i."expires_at" >= now()
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or i."role"::text = any((case when jsonb_typeof(v_filters -> 'role') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'role')) else array[v_filters ->> 'role'] end)::text[]))
        and (v_search is null or i."email" ilike v_search)
        and (v_after is null or (coalesce(i."expires_at", 'infinity'::timestamptz) >= (v_after ->> 0)::timestamptz and ((coalesce(i."expires_at", 'infinity'::timestamptz) > (v_after ->> 0)::timestamptz) or (coalesce(i."expires_at", 'infinity'::timestamptz) = (v_after ->> 0)::timestamptz and i."id" < (v_after ->> 1)::uuid))))
      order by coalesce(i."expires_at", 'infinity'::timestamptz) asc, i."id" desc
      limit v_limit + 1 offset v_offset
    ) i
  ) p;
  elsif v_sort = 'expiresAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVITATION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', i."id", 'email', i."email", 'role', i."role"::text, 'expiresAt', i."expires_at") as j, jsonb_build_array((coalesce(i."expires_at", 'infinity'::timestamptz))::text, (i."id")::text) as k
    from (
      select * from "better_supabase"."invitations" i
      where i."tenant_id" = page_organization_invitations.tenant
        and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
        and i."expires_at" >= now()
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or i."role"::text = any((case when jsonb_typeof(v_filters -> 'role') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'role')) else array[v_filters ->> 'role'] end)::text[]))
        and (v_search is null or i."email" ilike v_search)
        and (v_after is null or (coalesce(i."expires_at", 'infinity'::timestamptz), i."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(i."expires_at", 'infinity'::timestamptz) desc, i."id" desc
      limit v_limit + 1 offset v_offset
    ) i
  ) p;
  elsif v_sort = 'email' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVITATION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', i."id", 'email', i."email", 'role', i."role"::text, 'expiresAt', i."expires_at") as j, jsonb_build_array((lower(i."email"))::text, (i."id")::text) as k
    from (
      select * from "better_supabase"."invitations" i
      where i."tenant_id" = page_organization_invitations.tenant
        and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
        and i."expires_at" >= now()
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or i."role"::text = any((case when jsonb_typeof(v_filters -> 'role') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'role')) else array[v_filters ->> 'role'] end)::text[]))
        and (v_search is null or i."email" ilike v_search)
        and (v_after is null or (lower(i."email"), i."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(i."email") asc, i."id" asc
      limit v_limit + 1 offset v_offset
    ) i
  ) p;
  elsif v_sort = 'email' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVITATION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', i."id", 'email', i."email", 'role', i."role"::text, 'expiresAt', i."expires_at") as j, jsonb_build_array((lower(i."email"))::text, (i."id")::text) as k
    from (
      select * from "better_supabase"."invitations" i
      where i."tenant_id" = page_organization_invitations.tenant
        and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
        and i."expires_at" >= now()
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or i."role"::text = any((case when jsonb_typeof(v_filters -> 'role') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'role')) else array[v_filters ->> 'role'] end)::text[]))
        and (v_search is null or i."email" ilike v_search)
        and (v_after is null or (lower(i."email") <= (v_after ->> 0)::text and ((lower(i."email") < (v_after ->> 0)::text) or (lower(i."email") = (v_after ->> 0)::text and i."id" > (v_after ->> 1)::uuid))))
      order by lower(i."email") desc, i."id" asc
      limit v_limit + 1 offset v_offset
    ) i
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."invitations" i
      where i."tenant_id" = page_organization_invitations.tenant
        and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
        and i."expires_at" >= now()
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or i."role"::text = any((case when jsonb_typeof(v_filters -> 'role') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'role')) else array[v_filters ->> 'role'] end)::text[]))
        and (v_search is null or i."email" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

REVOKE ALL ON FUNCTION "api"."page_organization_invitations"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_organization_invitations"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_organization_invitations"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_organization_invitations"(uuid, jsonb) TO "authenticated", "service_role";
