SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.get_collection (
  collection uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_collection"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_review (
  review_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_review"($1) $function$;

CREATE OR REPLACE FUNCTION api.page_collections (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_collections"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_reviews (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_reviews"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.get_collection (
  collection uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'id', x."id",
    'organizationId', x."tenant_id",
    'subjectType', x."subject_type",
    'scope', x."scope",
    'ownerId', x."owner_id",
    'teamId', x."team_id",
    'name', x."name",
    'description', x."description",
    'archivedAt', x."archived_at",
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at")
  from "better_supabase"."subject_collections" x
  where x."id" = get_collection.collection
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_review (
  review_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."reviews"%rowtype;
begin
  select * into v_row from "better_supabase"."reviews" x where x."id" = get_review.review_id;
  if not found then
    raise exception 'review not found' using errcode = 'P0002', hint = 'REVIEW_NOT_FOUND';
  end if;
  if coalesce(v_row."author_id" = auth.uid(), false) then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'authorName', v_row."author_name", 'mine', coalesce(v_row."author_id" = auth.uid(), false), 'rating', v_row."rating", 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'verified', v_row."verified", 'rejectionReason', v_row."rejection_reason", 'reply', v_row."reply", 'repliedAt', v_row."replied_at", 'publishedAt', v_row."published_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  if v_row."status" <> 'published'
    or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."review_subject_readable"(v_row."tenant_id", v_row."subject_type", v_row."subject_id")) then
    raise exception 'review not found' using errcode = 'P0002', hint = 'REVIEW_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', null::uuid, 'authorName', v_row."author_name", 'mine', coalesce(v_row."author_id" = auth.uid(), false), 'rating', v_row."rating", 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'verified', v_row."verified", 'rejectionReason', v_row."rejection_reason", 'reply', v_row."reply", 'repliedAt', v_row."replied_at", 'publishedAt', v_row."published_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_agent_mandates (
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
  v_filters jsonb := coalesce(list_agent_mandates.filters, '{}'::jsonb);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_agent_mandates.tenant is not null and coalesce(better_supabase.can('tenant', list_agent_mandates.tenant, 'agent_checkout.read'), false))) then
    raise exception 'not allowed to read mandates' using errcode = '42501', hint = 'AGENT_MANDATE_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'AGENT_MANDATE_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'vct') then
      raise exception 'facet is one of status, vct' using errcode = '22023', hint = 'AGENT_MANDATE_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'vct' then (x."vct")::text end) as v
      from "better_supabase"."agent_mandates" x
      where x."tenant_id" = list_agent_mandates.tenant
        and (not (v_filters -> 'sessionId' is not null and jsonb_typeof(v_filters -> 'sessionId') <> 'null' and not (jsonb_typeof(v_filters -> 'sessionId') = 'array' and jsonb_array_length(v_filters -> 'sessionId') = 0)) or x."session_id"::text = any((case when jsonb_typeof(v_filters -> 'sessionId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'sessionId')) else array[v_filters ->> 'sessionId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'vct' is not null and jsonb_typeof(v_filters -> 'vct') <> 'null' and not (jsonb_typeof(v_filters -> 'vct') = 'array' and jsonb_array_length(v_filters -> 'vct') = 0)) or x."vct" = any((case when jsonb_typeof(v_filters -> 'vct') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'vct')) else array[v_filters ->> 'vct'] end)::text[]))
        and (v_search is null or coalesce(x."subject", '') ilike v_search or coalesce(x."issuer_kid", '') ilike v_search)
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
      select 1 from "better_supabase"."agent_mandates" x
      where x."tenant_id" = list_agent_mandates.tenant
        and (not (v_filters -> 'sessionId' is not null and jsonb_typeof(v_filters -> 'sessionId') <> 'null' and not (jsonb_typeof(v_filters -> 'sessionId') = 'array' and jsonb_array_length(v_filters -> 'sessionId') = 0)) or x."session_id"::text = any((case when jsonb_typeof(v_filters -> 'sessionId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'sessionId')) else array[v_filters ->> 'sessionId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'vct' is not null and jsonb_typeof(v_filters -> 'vct') <> 'null' and not (jsonb_typeof(v_filters -> 'vct') = 'array' and jsonb_array_length(v_filters -> 'vct') = 0)) or x."vct" = any((case when jsonb_typeof(v_filters -> 'vct') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'vct')) else array[v_filters ->> 'vct'] end)::text[]))
        and (v_search is null or coalesce(x."subject", '') ilike v_search or coalesce(x."issuer_kid", '') ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'expiresAt') then
    raise exception 'sort is one of createdAt, expiresAt' using errcode = '22023', hint = 'AGENT_MANDATE_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'AGENT_MANDATE_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_MANDATE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'sessionId', x."session_id", 'vct', x."vct", 'status', x."status", 'credential', x."credential", 'credentialHash', x."credential_hash", 'issuerKid', x."issuer_kid", 'subject', x."subject", 'expiresAt', x."expires_at", 'expired', (x."status" = 'active' and x."expires_at" <= now()), 'consumedAt', x."consumed_at", 'createdBy', x."created_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agent_mandates" x
      where x."tenant_id" = list_agent_mandates.tenant
        and (not (v_filters -> 'sessionId' is not null and jsonb_typeof(v_filters -> 'sessionId') <> 'null' and not (jsonb_typeof(v_filters -> 'sessionId') = 'array' and jsonb_array_length(v_filters -> 'sessionId') = 0)) or x."session_id"::text = any((case when jsonb_typeof(v_filters -> 'sessionId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'sessionId')) else array[v_filters ->> 'sessionId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'vct' is not null and jsonb_typeof(v_filters -> 'vct') <> 'null' and not (jsonb_typeof(v_filters -> 'vct') = 'array' and jsonb_array_length(v_filters -> 'vct') = 0)) or x."vct" = any((case when jsonb_typeof(v_filters -> 'vct') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'vct')) else array[v_filters ->> 'vct'] end)::text[]))
        and (v_search is null or coalesce(x."subject", '') ilike v_search or coalesce(x."issuer_kid", '') ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_MANDATE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'sessionId', x."session_id", 'vct', x."vct", 'status', x."status", 'credential', x."credential", 'credentialHash', x."credential_hash", 'issuerKid', x."issuer_kid", 'subject', x."subject", 'expiresAt', x."expires_at", 'expired', (x."status" = 'active' and x."expires_at" <= now()), 'consumedAt', x."consumed_at", 'createdBy', x."created_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agent_mandates" x
      where x."tenant_id" = list_agent_mandates.tenant
        and (not (v_filters -> 'sessionId' is not null and jsonb_typeof(v_filters -> 'sessionId') <> 'null' and not (jsonb_typeof(v_filters -> 'sessionId') = 'array' and jsonb_array_length(v_filters -> 'sessionId') = 0)) or x."session_id"::text = any((case when jsonb_typeof(v_filters -> 'sessionId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'sessionId')) else array[v_filters ->> 'sessionId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'vct' is not null and jsonb_typeof(v_filters -> 'vct') <> 'null' and not (jsonb_typeof(v_filters -> 'vct') = 'array' and jsonb_array_length(v_filters -> 'vct') = 0)) or x."vct" = any((case when jsonb_typeof(v_filters -> 'vct') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'vct')) else array[v_filters ->> 'vct'] end)::text[]))
        and (v_search is null or coalesce(x."subject", '') ilike v_search or coalesce(x."issuer_kid", '') ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_MANDATE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'sessionId', x."session_id", 'vct', x."vct", 'status', x."status", 'credential', x."credential", 'credentialHash', x."credential_hash", 'issuerKid', x."issuer_kid", 'subject', x."subject", 'expiresAt', x."expires_at", 'expired', (x."status" = 'active' and x."expires_at" <= now()), 'consumedAt', x."consumed_at", 'createdBy', x."created_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agent_mandates" x
      where x."tenant_id" = list_agent_mandates.tenant
        and (not (v_filters -> 'sessionId' is not null and jsonb_typeof(v_filters -> 'sessionId') <> 'null' and not (jsonb_typeof(v_filters -> 'sessionId') = 'array' and jsonb_array_length(v_filters -> 'sessionId') = 0)) or x."session_id"::text = any((case when jsonb_typeof(v_filters -> 'sessionId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'sessionId')) else array[v_filters ->> 'sessionId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'vct' is not null and jsonb_typeof(v_filters -> 'vct') <> 'null' and not (jsonb_typeof(v_filters -> 'vct') = 'array' and jsonb_array_length(v_filters -> 'vct') = 0)) or x."vct" = any((case when jsonb_typeof(v_filters -> 'vct') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'vct')) else array[v_filters ->> 'vct'] end)::text[]))
        and (v_search is null or coalesce(x."subject", '') ilike v_search or coalesce(x."issuer_kid", '') ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_MANDATE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'sessionId', x."session_id", 'vct', x."vct", 'status', x."status", 'credential', x."credential", 'credentialHash', x."credential_hash", 'issuerKid', x."issuer_kid", 'subject', x."subject", 'expiresAt', x."expires_at", 'expired', (x."status" = 'active' and x."expires_at" <= now()), 'consumedAt', x."consumed_at", 'createdBy', x."created_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agent_mandates" x
      where x."tenant_id" = list_agent_mandates.tenant
        and (not (v_filters -> 'sessionId' is not null and jsonb_typeof(v_filters -> 'sessionId') <> 'null' and not (jsonb_typeof(v_filters -> 'sessionId') = 'array' and jsonb_array_length(v_filters -> 'sessionId') = 0)) or x."session_id"::text = any((case when jsonb_typeof(v_filters -> 'sessionId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'sessionId')) else array[v_filters ->> 'sessionId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'vct' is not null and jsonb_typeof(v_filters -> 'vct') <> 'null' and not (jsonb_typeof(v_filters -> 'vct') = 'array' and jsonb_array_length(v_filters -> 'vct') = 0)) or x."vct" = any((case when jsonb_typeof(v_filters -> 'vct') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'vct')) else array[v_filters ->> 'vct'] end)::text[]))
        and (v_search is null or coalesce(x."subject", '') ilike v_search or coalesce(x."issuer_kid", '') ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'expiresAt' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_MANDATE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'sessionId', x."session_id", 'vct', x."vct", 'status', x."status", 'credential', x."credential", 'credentialHash', x."credential_hash", 'issuerKid', x."issuer_kid", 'subject', x."subject", 'expiresAt', x."expires_at", 'expired', (x."status" = 'active' and x."expires_at" <= now()), 'consumedAt', x."consumed_at", 'createdBy', x."created_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."expires_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agent_mandates" x
      where x."tenant_id" = list_agent_mandates.tenant
        and (not (v_filters -> 'sessionId' is not null and jsonb_typeof(v_filters -> 'sessionId') <> 'null' and not (jsonb_typeof(v_filters -> 'sessionId') = 'array' and jsonb_array_length(v_filters -> 'sessionId') = 0)) or x."session_id"::text = any((case when jsonb_typeof(v_filters -> 'sessionId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'sessionId')) else array[v_filters ->> 'sessionId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'vct' is not null and jsonb_typeof(v_filters -> 'vct') <> 'null' and not (jsonb_typeof(v_filters -> 'vct') = 'array' and jsonb_array_length(v_filters -> 'vct') = 0)) or x."vct" = any((case when jsonb_typeof(v_filters -> 'vct') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'vct')) else array[v_filters ->> 'vct'] end)::text[]))
        and (v_search is null or coalesce(x."subject", '') ilike v_search or coalesce(x."issuer_kid", '') ilike v_search)
        and (v_after is null or (x."expires_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."expires_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'expiresAt' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_MANDATE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'sessionId', x."session_id", 'vct', x."vct", 'status', x."status", 'credential', x."credential", 'credentialHash', x."credential_hash", 'issuerKid', x."issuer_kid", 'subject', x."subject", 'expiresAt', x."expires_at", 'expired', (x."status" = 'active' and x."expires_at" <= now()), 'consumedAt', x."consumed_at", 'createdBy', x."created_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."expires_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agent_mandates" x
      where x."tenant_id" = list_agent_mandates.tenant
        and (not (v_filters -> 'sessionId' is not null and jsonb_typeof(v_filters -> 'sessionId') <> 'null' and not (jsonb_typeof(v_filters -> 'sessionId') = 'array' and jsonb_array_length(v_filters -> 'sessionId') = 0)) or x."session_id"::text = any((case when jsonb_typeof(v_filters -> 'sessionId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'sessionId')) else array[v_filters ->> 'sessionId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'vct' is not null and jsonb_typeof(v_filters -> 'vct') <> 'null' and not (jsonb_typeof(v_filters -> 'vct') = 'array' and jsonb_array_length(v_filters -> 'vct') = 0)) or x."vct" = any((case when jsonb_typeof(v_filters -> 'vct') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'vct')) else array[v_filters ->> 'vct'] end)::text[]))
        and (v_search is null or coalesce(x."subject", '') ilike v_search or coalesce(x."issuer_kid", '') ilike v_search)
        and (v_after is null or (x."expires_at" <= (v_after ->> 0)::timestamptz and ((x."expires_at" < (v_after ->> 0)::timestamptz) or (x."expires_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."expires_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."agent_mandates" x
      where x."tenant_id" = list_agent_mandates.tenant
        and (not (v_filters -> 'sessionId' is not null and jsonb_typeof(v_filters -> 'sessionId') <> 'null' and not (jsonb_typeof(v_filters -> 'sessionId') = 'array' and jsonb_array_length(v_filters -> 'sessionId') = 0)) or x."session_id"::text = any((case when jsonb_typeof(v_filters -> 'sessionId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'sessionId')) else array[v_filters ->> 'sessionId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'vct' is not null and jsonb_typeof(v_filters -> 'vct') <> 'null' and not (jsonb_typeof(v_filters -> 'vct') = 'array' and jsonb_array_length(v_filters -> 'vct') = 0)) or x."vct" = any((case when jsonb_typeof(v_filters -> 'vct') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'vct')) else array[v_filters ->> 'vct'] end)::text[]))
        and (v_search is null or coalesce(x."subject", '') ilike v_search or coalesce(x."issuer_kid", '') ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_checkout_sessions (
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
  v_filters jsonb := coalesce(list_checkout_sessions.filters, '{}'::jsonb);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_checkout_sessions.tenant is not null and coalesce(better_supabase.can('tenant', list_checkout_sessions.tenant, 'agent_checkout.read'), false))) then
    raise exception 'not allowed to read checkout sessions' using errcode = '42501', hint = 'CHECKOUT_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'CHECKOUT_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'protocol') then
      raise exception 'facet is one of status, protocol' using errcode = '22023', hint = 'CHECKOUT_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'protocol' then (x."protocol")::text end) as v
      from "better_supabase"."checkout_sessions" x
      where x."tenant_id" = list_checkout_sessions.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'protocol' is not null and jsonb_typeof(v_filters -> 'protocol') <> 'null' and not (jsonb_typeof(v_filters -> 'protocol') = 'array' and jsonb_array_length(v_filters -> 'protocol') = 0)) or x."protocol" = any((case when jsonb_typeof(v_filters -> 'protocol') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'protocol')) else array[v_filters ->> 'protocol'] end)::text[]))
        and (not (v_filters -> 'cartId' is not null and jsonb_typeof(v_filters -> 'cartId') <> 'null' and not (jsonb_typeof(v_filters -> 'cartId') = 'array' and jsonb_array_length(v_filters -> 'cartId') = 0)) or x."cart_id"::text = any((case when jsonb_typeof(v_filters -> 'cartId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'cartId')) else array[v_filters ->> 'cartId'] end)::text[]))
        and (v_search is null or x."idempotency_key" ilike v_search or x."id"::text ilike v_search)
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
      select 1 from "better_supabase"."checkout_sessions" x
      where x."tenant_id" = list_checkout_sessions.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'protocol' is not null and jsonb_typeof(v_filters -> 'protocol') <> 'null' and not (jsonb_typeof(v_filters -> 'protocol') = 'array' and jsonb_array_length(v_filters -> 'protocol') = 0)) or x."protocol" = any((case when jsonb_typeof(v_filters -> 'protocol') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'protocol')) else array[v_filters ->> 'protocol'] end)::text[]))
        and (not (v_filters -> 'cartId' is not null and jsonb_typeof(v_filters -> 'cartId') <> 'null' and not (jsonb_typeof(v_filters -> 'cartId') = 'array' and jsonb_array_length(v_filters -> 'cartId') = 0)) or x."cart_id"::text = any((case when jsonb_typeof(v_filters -> 'cartId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'cartId')) else array[v_filters ->> 'cartId'] end)::text[]))
        and (v_search is null or x."idempotency_key" ilike v_search or x."id"::text ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'expiresAt') then
    raise exception 'sort is one of createdAt, expiresAt' using errcode = '22023', hint = 'CHECKOUT_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'CHECKOUT_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CHECKOUT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'cartId', x."cart_id", 'protocol', x."protocol", 'status', x."status", 'buyer', x."buyer", 'orderId', x."order_id", 'expiresAt', x."expires_at", 'expired', (x."status" in ('open', 'ready') and x."expires_at" is not null and x."expires_at" <= now()), 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."checkout_sessions" x
      where x."tenant_id" = list_checkout_sessions.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'protocol' is not null and jsonb_typeof(v_filters -> 'protocol') <> 'null' and not (jsonb_typeof(v_filters -> 'protocol') = 'array' and jsonb_array_length(v_filters -> 'protocol') = 0)) or x."protocol" = any((case when jsonb_typeof(v_filters -> 'protocol') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'protocol')) else array[v_filters ->> 'protocol'] end)::text[]))
        and (not (v_filters -> 'cartId' is not null and jsonb_typeof(v_filters -> 'cartId') <> 'null' and not (jsonb_typeof(v_filters -> 'cartId') = 'array' and jsonb_array_length(v_filters -> 'cartId') = 0)) or x."cart_id"::text = any((case when jsonb_typeof(v_filters -> 'cartId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'cartId')) else array[v_filters ->> 'cartId'] end)::text[]))
        and (v_search is null or x."idempotency_key" ilike v_search or x."id"::text ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CHECKOUT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'cartId', x."cart_id", 'protocol', x."protocol", 'status', x."status", 'buyer', x."buyer", 'orderId', x."order_id", 'expiresAt', x."expires_at", 'expired', (x."status" in ('open', 'ready') and x."expires_at" is not null and x."expires_at" <= now()), 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."checkout_sessions" x
      where x."tenant_id" = list_checkout_sessions.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'protocol' is not null and jsonb_typeof(v_filters -> 'protocol') <> 'null' and not (jsonb_typeof(v_filters -> 'protocol') = 'array' and jsonb_array_length(v_filters -> 'protocol') = 0)) or x."protocol" = any((case when jsonb_typeof(v_filters -> 'protocol') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'protocol')) else array[v_filters ->> 'protocol'] end)::text[]))
        and (not (v_filters -> 'cartId' is not null and jsonb_typeof(v_filters -> 'cartId') <> 'null' and not (jsonb_typeof(v_filters -> 'cartId') = 'array' and jsonb_array_length(v_filters -> 'cartId') = 0)) or x."cart_id"::text = any((case when jsonb_typeof(v_filters -> 'cartId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'cartId')) else array[v_filters ->> 'cartId'] end)::text[]))
        and (v_search is null or x."idempotency_key" ilike v_search or x."id"::text ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CHECKOUT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'cartId', x."cart_id", 'protocol', x."protocol", 'status', x."status", 'buyer', x."buyer", 'orderId', x."order_id", 'expiresAt', x."expires_at", 'expired', (x."status" in ('open', 'ready') and x."expires_at" is not null and x."expires_at" <= now()), 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."checkout_sessions" x
      where x."tenant_id" = list_checkout_sessions.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'protocol' is not null and jsonb_typeof(v_filters -> 'protocol') <> 'null' and not (jsonb_typeof(v_filters -> 'protocol') = 'array' and jsonb_array_length(v_filters -> 'protocol') = 0)) or x."protocol" = any((case when jsonb_typeof(v_filters -> 'protocol') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'protocol')) else array[v_filters ->> 'protocol'] end)::text[]))
        and (not (v_filters -> 'cartId' is not null and jsonb_typeof(v_filters -> 'cartId') <> 'null' and not (jsonb_typeof(v_filters -> 'cartId') = 'array' and jsonb_array_length(v_filters -> 'cartId') = 0)) or x."cart_id"::text = any((case when jsonb_typeof(v_filters -> 'cartId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'cartId')) else array[v_filters ->> 'cartId'] end)::text[]))
        and (v_search is null or x."idempotency_key" ilike v_search or x."id"::text ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CHECKOUT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'cartId', x."cart_id", 'protocol', x."protocol", 'status', x."status", 'buyer', x."buyer", 'orderId', x."order_id", 'expiresAt', x."expires_at", 'expired', (x."status" in ('open', 'ready') and x."expires_at" is not null and x."expires_at" <= now()), 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."checkout_sessions" x
      where x."tenant_id" = list_checkout_sessions.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'protocol' is not null and jsonb_typeof(v_filters -> 'protocol') <> 'null' and not (jsonb_typeof(v_filters -> 'protocol') = 'array' and jsonb_array_length(v_filters -> 'protocol') = 0)) or x."protocol" = any((case when jsonb_typeof(v_filters -> 'protocol') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'protocol')) else array[v_filters ->> 'protocol'] end)::text[]))
        and (not (v_filters -> 'cartId' is not null and jsonb_typeof(v_filters -> 'cartId') <> 'null' and not (jsonb_typeof(v_filters -> 'cartId') = 'array' and jsonb_array_length(v_filters -> 'cartId') = 0)) or x."cart_id"::text = any((case when jsonb_typeof(v_filters -> 'cartId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'cartId')) else array[v_filters ->> 'cartId'] end)::text[]))
        and (v_search is null or x."idempotency_key" ilike v_search or x."id"::text ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'expiresAt' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CHECKOUT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'cartId', x."cart_id", 'protocol', x."protocol", 'status', x."status", 'buyer', x."buyer", 'orderId', x."order_id", 'expiresAt', x."expires_at", 'expired', (x."status" in ('open', 'ready') and x."expires_at" is not null and x."expires_at" <= now()), 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."expires_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."checkout_sessions" x
      where x."tenant_id" = list_checkout_sessions.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'protocol' is not null and jsonb_typeof(v_filters -> 'protocol') <> 'null' and not (jsonb_typeof(v_filters -> 'protocol') = 'array' and jsonb_array_length(v_filters -> 'protocol') = 0)) or x."protocol" = any((case when jsonb_typeof(v_filters -> 'protocol') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'protocol')) else array[v_filters ->> 'protocol'] end)::text[]))
        and (not (v_filters -> 'cartId' is not null and jsonb_typeof(v_filters -> 'cartId') <> 'null' and not (jsonb_typeof(v_filters -> 'cartId') = 'array' and jsonb_array_length(v_filters -> 'cartId') = 0)) or x."cart_id"::text = any((case when jsonb_typeof(v_filters -> 'cartId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'cartId')) else array[v_filters ->> 'cartId'] end)::text[]))
        and (v_search is null or x."idempotency_key" ilike v_search or x."id"::text ilike v_search)
        and (v_after is null or (coalesce(x."expires_at", 'infinity'::timestamptz), x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."expires_at", 'infinity'::timestamptz) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'expiresAt' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CHECKOUT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'cartId', x."cart_id", 'protocol', x."protocol", 'status', x."status", 'buyer', x."buyer", 'orderId', x."order_id", 'expiresAt', x."expires_at", 'expired', (x."status" in ('open', 'ready') and x."expires_at" is not null and x."expires_at" <= now()), 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."expires_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."checkout_sessions" x
      where x."tenant_id" = list_checkout_sessions.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'protocol' is not null and jsonb_typeof(v_filters -> 'protocol') <> 'null' and not (jsonb_typeof(v_filters -> 'protocol') = 'array' and jsonb_array_length(v_filters -> 'protocol') = 0)) or x."protocol" = any((case when jsonb_typeof(v_filters -> 'protocol') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'protocol')) else array[v_filters ->> 'protocol'] end)::text[]))
        and (not (v_filters -> 'cartId' is not null and jsonb_typeof(v_filters -> 'cartId') <> 'null' and not (jsonb_typeof(v_filters -> 'cartId') = 'array' and jsonb_array_length(v_filters -> 'cartId') = 0)) or x."cart_id"::text = any((case when jsonb_typeof(v_filters -> 'cartId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'cartId')) else array[v_filters ->> 'cartId'] end)::text[]))
        and (v_search is null or x."idempotency_key" ilike v_search or x."id"::text ilike v_search)
        and (v_after is null or (coalesce(x."expires_at", 'infinity'::timestamptz) <= (v_after ->> 0)::timestamptz and ((coalesce(x."expires_at", 'infinity'::timestamptz) < (v_after ->> 0)::timestamptz) or (coalesce(x."expires_at", 'infinity'::timestamptz) = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."expires_at", 'infinity'::timestamptz) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."checkout_sessions" x
      where x."tenant_id" = list_checkout_sessions.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'protocol' is not null and jsonb_typeof(v_filters -> 'protocol') <> 'null' and not (jsonb_typeof(v_filters -> 'protocol') = 'array' and jsonb_array_length(v_filters -> 'protocol') = 0)) or x."protocol" = any((case when jsonb_typeof(v_filters -> 'protocol') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'protocol')) else array[v_filters ->> 'protocol'] end)::text[]))
        and (not (v_filters -> 'cartId' is not null and jsonb_typeof(v_filters -> 'cartId') <> 'null' and not (jsonb_typeof(v_filters -> 'cartId') = 'array' and jsonb_array_length(v_filters -> 'cartId') = 0)) or x."cart_id"::text = any((case when jsonb_typeof(v_filters -> 'cartId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'cartId')) else array[v_filters ->> 'cartId'] end)::text[]))
        and (v_search is null or x."idempotency_key" ilike v_search or x."id"::text ilike v_search)
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
      select 1 from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_search is null or x."title" ilike v_search)
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
        and (v_search is null or x."title" ilike v_search)
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
        and (v_search is null or x."title" ilike v_search)
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
        and (v_search is null or x."title" ilike v_search)
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
        and (v_search is null or x."title" ilike v_search)
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
        and (v_search is null or x."title" ilike v_search)
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
        and (v_search is null or x."title" ilike v_search)
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
        and (v_search is null or x."title" ilike v_search)
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
        and (v_search is null or x."title" ilike v_search)
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
        and (v_search is null or x."title" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_warranty_claims (
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
  v_filters jsonb := coalesce(list_warranty_claims.filters, '{}'::jsonb);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_warranty_claims.tenant is not null and coalesce(better_supabase.can('tenant', list_warranty_claims.tenant, 'warranty.read'), false))) then
    raise exception 'not allowed to read warranty claims' using errcode = '42501', hint = 'WARRANTY_FORBIDDEN';
  end if;
  if exists (
    select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'status') = 'array' then v_filters -> 'status' else jsonb_build_array(v_filters -> 'status') end) s
    where s not in ('draft', 'submitted', 'approved', 'denied', 'closed')
  ) then
    raise exception 'status is not a warranty status' using errcode = '22023', hint = 'WARRANTY_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'assetId') = 'array' then v_filters -> 'assetId' else jsonb_build_array(v_filters -> 'assetId') end) s
    where s !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
  ) then
    raise exception 'assetId must be a uuid' using errcode = '22023', hint = 'WARRANTY_INVALID';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'WARRANTY_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status') then
      raise exception 'facet is one of status' using errcode = '22023', hint = 'WARRANTY_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text end) as v
      from "better_supabase"."warranty_claims" x
      where x."tenant_id" = list_warranty_claims.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
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
      select 1 from "better_supabase"."warranty_claims" x
      where x."tenant_id" = list_warranty_claims.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (v_search is null or x."title" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'amount') then
    raise exception 'sort is one of createdAt, amount' using errcode = '22023', hint = 'WARRANTY_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'WARRANTY_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WARRANTY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'organizationId', x."tenant_id",
    'title', x."title",
    'assetId', x."asset_id",
    'supplierId', x."supplier_id",
    'manufacturer', x."manufacturer",
    'amount', x."amount"::text,
    'currency', x."currency",
    'status', x."status",
    'decision', x."decision",
    'decidedAt', x."decided_at",
    'decidedBy', x."decided_by") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."warranty_claims" x
      where x."tenant_id" = list_warranty_claims.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WARRANTY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'organizationId', x."tenant_id",
    'title', x."title",
    'assetId', x."asset_id",
    'supplierId', x."supplier_id",
    'manufacturer', x."manufacturer",
    'amount', x."amount"::text,
    'currency', x."currency",
    'status', x."status",
    'decision', x."decision",
    'decidedAt', x."decided_at",
    'decidedBy', x."decided_by") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."warranty_claims" x
      where x."tenant_id" = list_warranty_claims.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WARRANTY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'organizationId', x."tenant_id",
    'title', x."title",
    'assetId', x."asset_id",
    'supplierId', x."supplier_id",
    'manufacturer', x."manufacturer",
    'amount', x."amount"::text,
    'currency', x."currency",
    'status', x."status",
    'decision', x."decision",
    'decidedAt', x."decided_at",
    'decidedBy', x."decided_by") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."warranty_claims" x
      where x."tenant_id" = list_warranty_claims.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WARRANTY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'organizationId', x."tenant_id",
    'title', x."title",
    'assetId', x."asset_id",
    'supplierId', x."supplier_id",
    'manufacturer', x."manufacturer",
    'amount', x."amount"::text,
    'currency', x."currency",
    'status', x."status",
    'decision', x."decision",
    'decidedAt', x."decided_at",
    'decidedBy', x."decided_by") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."warranty_claims" x
      where x."tenant_id" = list_warranty_claims.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'amount' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WARRANTY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'organizationId', x."tenant_id",
    'title', x."title",
    'assetId', x."asset_id",
    'supplierId', x."supplier_id",
    'manufacturer', x."manufacturer",
    'amount', x."amount"::text,
    'currency', x."currency",
    'status', x."status",
    'decision', x."decision",
    'decidedAt', x."decided_at",
    'decidedBy', x."decided_by") as j, jsonb_build_array((x."amount")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."warranty_claims" x
      where x."tenant_id" = list_warranty_claims.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."amount", x."id") > ((v_after ->> 0)::bigint, (v_after ->> 1)::uuid))
      order by x."amount" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'amount' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WARRANTY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'organizationId', x."tenant_id",
    'title', x."title",
    'assetId', x."asset_id",
    'supplierId', x."supplier_id",
    'manufacturer', x."manufacturer",
    'amount', x."amount"::text,
    'currency', x."currency",
    'status', x."status",
    'decision', x."decision",
    'decidedAt', x."decided_at",
    'decidedBy', x."decided_by") as j, jsonb_build_array((x."amount")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."warranty_claims" x
      where x."tenant_id" = list_warranty_claims.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."amount" <= (v_after ->> 0)::bigint and ((x."amount" < (v_after ->> 0)::bigint) or (x."amount" = (v_after ->> 0)::bigint and x."id" > (v_after ->> 1)::uuid))))
      order by x."amount" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."warranty_claims" x
      where x."tenant_id" = list_warranty_claims.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (v_search is null or x."title" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_collections (
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
  v_filters jsonb := coalesce(page_collections.filters, '{}'::jsonb);
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
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'COLLECTION_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('subjectType', 'scope') then
      raise exception 'facet is one of subjectType, scope' using errcode = '22023', hint = 'COLLECTION_INVALID';
    end if;
    with s as (
      select (case v_facet when 'subjectType' then (x."subject_type")::text when 'scope' then (x."scope"::text)::text end) as v
      from "better_supabase"."subject_collections" x
      where x."tenant_id" = page_collections.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope"::text = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."name" ilike v_search or coalesce(x."description", '') ilike v_search)
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
      select 1 from "better_supabase"."subject_collections" x
      where x."tenant_id" = page_collections.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope"::text = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."name" ilike v_search or coalesce(x."description", '') ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'createdAt') then
    raise exception 'sort is one of name, createdAt' using errcode = '22023', hint = 'COLLECTION_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'COLLECTION_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COLLECTION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'organizationId', x."tenant_id",
    'subjectType', x."subject_type",
    'scope', x."scope",
    'ownerId', x."owner_id",
    'teamId', x."team_id",
    'name', x."name",
    'description', x."description",
    'archivedAt', x."archived_at",
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."subject_collections" x
      where x."tenant_id" = page_collections.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope"::text = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."name" ilike v_search or coalesce(x."description", '') ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COLLECTION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'organizationId', x."tenant_id",
    'subjectType', x."subject_type",
    'scope', x."scope",
    'ownerId', x."owner_id",
    'teamId', x."team_id",
    'name', x."name",
    'description', x."description",
    'archivedAt', x."archived_at",
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."subject_collections" x
      where x."tenant_id" = page_collections.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope"::text = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."name" ilike v_search or coalesce(x."description", '') ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COLLECTION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'organizationId', x."tenant_id",
    'subjectType', x."subject_type",
    'scope', x."scope",
    'ownerId', x."owner_id",
    'teamId', x."team_id",
    'name', x."name",
    'description', x."description",
    'archivedAt', x."archived_at",
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."subject_collections" x
      where x."tenant_id" = page_collections.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope"::text = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."name" ilike v_search or coalesce(x."description", '') ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COLLECTION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'organizationId', x."tenant_id",
    'subjectType', x."subject_type",
    'scope', x."scope",
    'ownerId', x."owner_id",
    'teamId', x."team_id",
    'name', x."name",
    'description', x."description",
    'archivedAt', x."archived_at",
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."subject_collections" x
      where x."tenant_id" = page_collections.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope"::text = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."name" ilike v_search or coalesce(x."description", '') ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COLLECTION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'organizationId', x."tenant_id",
    'subjectType', x."subject_type",
    'scope', x."scope",
    'ownerId', x."owner_id",
    'teamId', x."team_id",
    'name', x."name",
    'description', x."description",
    'archivedAt', x."archived_at",
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."subject_collections" x
      where x."tenant_id" = page_collections.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope"::text = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."name" ilike v_search or coalesce(x."description", '') ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COLLECTION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'organizationId', x."tenant_id",
    'subjectType', x."subject_type",
    'scope', x."scope",
    'ownerId', x."owner_id",
    'teamId', x."team_id",
    'name', x."name",
    'description', x."description",
    'archivedAt', x."archived_at",
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."subject_collections" x
      where x."tenant_id" = page_collections.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope"::text = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."name" ilike v_search or coalesce(x."description", '') ilike v_search)
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
      select 1 from "better_supabase"."subject_collections" x
      where x."tenant_id" = page_collections.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope"::text = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."name" ilike v_search or coalesce(x."description", '') ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_guests (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_filters jsonb := coalesce(page_guests.filters, '{}'::jsonb);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', page_guests.tenant, 'guests.read'), false)) then
    raise exception 'not allowed to read guests' using errcode = '42501', hint = 'GUEST_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'GUEST_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status') then
      raise exception 'facet is one of status' using errcode = '22023', hint = 'GUEST_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text end) as v
      from "better_supabase"."guests" x
      where x."tenant_id" = page_guests.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."email" ilike v_search or x."name" ilike v_search)
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
      select 1 from "better_supabase"."guests" x
      where x."tenant_id" = page_guests.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."email" ilike v_search or x."name" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'email') then
    raise exception 'sort is one of createdAt, email' using errcode = '22023', hint = 'GUEST_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'GUEST_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUEST_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'email', x."email", 'name', x."name", 'userId', x."user_id", 'partyType', x."party_type", 'partyId', x."party_id", 'status', x."status", 'invitedBy', x."invited_by", 'expiresAt', x."expires_at", 'acceptedAt', x."accepted_at", 'revokedAt', x."revoked_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guests" x
      where x."tenant_id" = page_guests.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."email" ilike v_search or x."name" ilike v_search)
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUEST_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'email', x."email", 'name', x."name", 'userId', x."user_id", 'partyType', x."party_type", 'partyId', x."party_id", 'status', x."status", 'invitedBy', x."invited_by", 'expiresAt', x."expires_at", 'acceptedAt', x."accepted_at", 'revokedAt', x."revoked_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guests" x
      where x."tenant_id" = page_guests.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."email" ilike v_search or x."name" ilike v_search)
        and (v_after is null or (x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUEST_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'email', x."email", 'name', x."name", 'userId', x."user_id", 'partyType', x."party_type", 'partyId', x."party_id", 'status', x."status", 'invitedBy', x."invited_by", 'expiresAt', x."expires_at", 'acceptedAt', x."accepted_at", 'revokedAt', x."revoked_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guests" x
      where x."tenant_id" = page_guests.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."email" ilike v_search or x."name" ilike v_search)
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUEST_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'email', x."email", 'name', x."name", 'userId', x."user_id", 'partyType', x."party_type", 'partyId', x."party_id", 'status', x."status", 'invitedBy', x."invited_by", 'expiresAt', x."expires_at", 'acceptedAt', x."accepted_at", 'revokedAt', x."revoked_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guests" x
      where x."tenant_id" = page_guests.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."email" ilike v_search or x."name" ilike v_search)
        and (v_after is null or (x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'email' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUEST_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'email', x."email", 'name', x."name", 'userId', x."user_id", 'partyType', x."party_type", 'partyId', x."party_id", 'status', x."status", 'invitedBy', x."invited_by", 'expiresAt', x."expires_at", 'acceptedAt', x."accepted_at", 'revokedAt', x."revoked_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."email")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guests" x
      where x."tenant_id" = page_guests.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."email" ilike v_search or x."name" ilike v_search)
        and (v_after is null or (x."email", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."email" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'email' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUEST_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'email', x."email", 'name', x."name", 'userId', x."user_id", 'partyType', x."party_type", 'partyId', x."party_id", 'status', x."status", 'invitedBy', x."invited_by", 'expiresAt', x."expires_at", 'acceptedAt', x."accepted_at", 'revokedAt', x."revoked_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."email")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guests" x
      where x."tenant_id" = page_guests.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."email" ilike v_search or x."name" ilike v_search)
        and (v_after is null or (x."email" <= (v_after ->> 0)::text and ((x."email" < (v_after ->> 0)::text) or (x."email" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."email" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."guests" x
      where x."tenant_id" = page_guests.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."email" ilike v_search or x."name" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_passes (
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
  v_filters jsonb := coalesce(page_passes.filters, '{}'::jsonb);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', page_passes.tenant, 'passes.read'), false)) then
    raise exception 'not allowed to read passes' using errcode = '42501', hint = 'PASS_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'PASS_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status') then
      raise exception 'facet is one of status' using errcode = '22023', hint = 'PASS_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text end) as v
      from "better_supabase"."passes" x
      where x."tenant_id" = page_passes.tenant
        and (not (v_filters -> 'holderUserId' is not null and jsonb_typeof(v_filters -> 'holderUserId') <> 'null' and not (jsonb_typeof(v_filters -> 'holderUserId') = 'array' and jsonb_array_length(v_filters -> 'holderUserId') = 0)) or x."holder_id" = any((case when jsonb_typeof(v_filters -> 'holderUserId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'holderUserId')) else array[v_filters ->> 'holderUserId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or coalesce(x."holder_name", '') ilike v_search or coalesce(x."holder_email", '') ilike v_search)
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
      select 1 from "better_supabase"."passes" x
      where x."tenant_id" = page_passes.tenant
        and (not (v_filters -> 'holderUserId' is not null and jsonb_typeof(v_filters -> 'holderUserId') <> 'null' and not (jsonb_typeof(v_filters -> 'holderUserId') = 'array' and jsonb_array_length(v_filters -> 'holderUserId') = 0)) or x."holder_id" = any((case when jsonb_typeof(v_filters -> 'holderUserId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'holderUserId')) else array[v_filters ->> 'holderUserId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or coalesce(x."holder_name", '') ilike v_search or coalesce(x."holder_email", '') ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'validFrom', 'validUntil') then
    raise exception 'sort is one of createdAt, validFrom, validUntil' using errcode = '22023', hint = 'PASS_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'PASS_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PASS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'kind', x."kind", 'holderUserId', x."holder_id", 'holderName', x."holder_name", 'holderEmail', x."holder_email", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'bookingId', x."booking_id", 'resourceId', x."resource_id", 'usesAllowed', x."uses_allowed", 'uses', x."uses", 'validFrom', x."starts_at", 'validUntil', x."expires_at", 'status', x."status", 'issuedBy', x."issued_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'revokedAt', x."revoked_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."passes" x
      where x."tenant_id" = page_passes.tenant
        and (not (v_filters -> 'holderUserId' is not null and jsonb_typeof(v_filters -> 'holderUserId') <> 'null' and not (jsonb_typeof(v_filters -> 'holderUserId') = 'array' and jsonb_array_length(v_filters -> 'holderUserId') = 0)) or x."holder_id" = any((case when jsonb_typeof(v_filters -> 'holderUserId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'holderUserId')) else array[v_filters ->> 'holderUserId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or coalesce(x."holder_name", '') ilike v_search or coalesce(x."holder_email", '') ilike v_search)
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PASS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'kind', x."kind", 'holderUserId', x."holder_id", 'holderName', x."holder_name", 'holderEmail', x."holder_email", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'bookingId', x."booking_id", 'resourceId', x."resource_id", 'usesAllowed', x."uses_allowed", 'uses', x."uses", 'validFrom', x."starts_at", 'validUntil', x."expires_at", 'status', x."status", 'issuedBy', x."issued_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'revokedAt', x."revoked_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."passes" x
      where x."tenant_id" = page_passes.tenant
        and (not (v_filters -> 'holderUserId' is not null and jsonb_typeof(v_filters -> 'holderUserId') <> 'null' and not (jsonb_typeof(v_filters -> 'holderUserId') = 'array' and jsonb_array_length(v_filters -> 'holderUserId') = 0)) or x."holder_id" = any((case when jsonb_typeof(v_filters -> 'holderUserId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'holderUserId')) else array[v_filters ->> 'holderUserId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or coalesce(x."holder_name", '') ilike v_search or coalesce(x."holder_email", '') ilike v_search)
        and (v_after is null or (x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PASS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'kind', x."kind", 'holderUserId', x."holder_id", 'holderName', x."holder_name", 'holderEmail', x."holder_email", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'bookingId', x."booking_id", 'resourceId', x."resource_id", 'usesAllowed', x."uses_allowed", 'uses', x."uses", 'validFrom', x."starts_at", 'validUntil', x."expires_at", 'status', x."status", 'issuedBy', x."issued_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'revokedAt', x."revoked_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."passes" x
      where x."tenant_id" = page_passes.tenant
        and (not (v_filters -> 'holderUserId' is not null and jsonb_typeof(v_filters -> 'holderUserId') <> 'null' and not (jsonb_typeof(v_filters -> 'holderUserId') = 'array' and jsonb_array_length(v_filters -> 'holderUserId') = 0)) or x."holder_id" = any((case when jsonb_typeof(v_filters -> 'holderUserId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'holderUserId')) else array[v_filters ->> 'holderUserId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or coalesce(x."holder_name", '') ilike v_search or coalesce(x."holder_email", '') ilike v_search)
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PASS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'kind', x."kind", 'holderUserId', x."holder_id", 'holderName', x."holder_name", 'holderEmail', x."holder_email", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'bookingId', x."booking_id", 'resourceId', x."resource_id", 'usesAllowed', x."uses_allowed", 'uses', x."uses", 'validFrom', x."starts_at", 'validUntil', x."expires_at", 'status', x."status", 'issuedBy', x."issued_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'revokedAt', x."revoked_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."passes" x
      where x."tenant_id" = page_passes.tenant
        and (not (v_filters -> 'holderUserId' is not null and jsonb_typeof(v_filters -> 'holderUserId') <> 'null' and not (jsonb_typeof(v_filters -> 'holderUserId') = 'array' and jsonb_array_length(v_filters -> 'holderUserId') = 0)) or x."holder_id" = any((case when jsonb_typeof(v_filters -> 'holderUserId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'holderUserId')) else array[v_filters ->> 'holderUserId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or coalesce(x."holder_name", '') ilike v_search or coalesce(x."holder_email", '') ilike v_search)
        and (v_after is null or (x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'validFrom' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PASS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'kind', x."kind", 'holderUserId', x."holder_id", 'holderName', x."holder_name", 'holderEmail', x."holder_email", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'bookingId', x."booking_id", 'resourceId', x."resource_id", 'usesAllowed', x."uses_allowed", 'uses', x."uses", 'validFrom', x."starts_at", 'validUntil', x."expires_at", 'status', x."status", 'issuedBy', x."issued_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'revokedAt', x."revoked_at") as j, jsonb_build_array((x."starts_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."passes" x
      where x."tenant_id" = page_passes.tenant
        and (not (v_filters -> 'holderUserId' is not null and jsonb_typeof(v_filters -> 'holderUserId') <> 'null' and not (jsonb_typeof(v_filters -> 'holderUserId') = 'array' and jsonb_array_length(v_filters -> 'holderUserId') = 0)) or x."holder_id" = any((case when jsonb_typeof(v_filters -> 'holderUserId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'holderUserId')) else array[v_filters ->> 'holderUserId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or coalesce(x."holder_name", '') ilike v_search or coalesce(x."holder_email", '') ilike v_search)
        and (v_after is null or (x."starts_at" >= (v_after ->> 0)::timestamptz and ((x."starts_at" > (v_after ->> 0)::timestamptz) or (x."starts_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."starts_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'validFrom' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PASS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'kind', x."kind", 'holderUserId', x."holder_id", 'holderName', x."holder_name", 'holderEmail', x."holder_email", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'bookingId', x."booking_id", 'resourceId', x."resource_id", 'usesAllowed', x."uses_allowed", 'uses', x."uses", 'validFrom', x."starts_at", 'validUntil', x."expires_at", 'status', x."status", 'issuedBy', x."issued_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'revokedAt', x."revoked_at") as j, jsonb_build_array((x."starts_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."passes" x
      where x."tenant_id" = page_passes.tenant
        and (not (v_filters -> 'holderUserId' is not null and jsonb_typeof(v_filters -> 'holderUserId') <> 'null' and not (jsonb_typeof(v_filters -> 'holderUserId') = 'array' and jsonb_array_length(v_filters -> 'holderUserId') = 0)) or x."holder_id" = any((case when jsonb_typeof(v_filters -> 'holderUserId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'holderUserId')) else array[v_filters ->> 'holderUserId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or coalesce(x."holder_name", '') ilike v_search or coalesce(x."holder_email", '') ilike v_search)
        and (v_after is null or (x."starts_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."starts_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'validUntil' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PASS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'kind', x."kind", 'holderUserId', x."holder_id", 'holderName', x."holder_name", 'holderEmail', x."holder_email", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'bookingId', x."booking_id", 'resourceId', x."resource_id", 'usesAllowed', x."uses_allowed", 'uses', x."uses", 'validFrom', x."starts_at", 'validUntil', x."expires_at", 'status', x."status", 'issuedBy', x."issued_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'revokedAt', x."revoked_at") as j, jsonb_build_array((coalesce(x."expires_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."passes" x
      where x."tenant_id" = page_passes.tenant
        and (not (v_filters -> 'holderUserId' is not null and jsonb_typeof(v_filters -> 'holderUserId') <> 'null' and not (jsonb_typeof(v_filters -> 'holderUserId') = 'array' and jsonb_array_length(v_filters -> 'holderUserId') = 0)) or x."holder_id" = any((case when jsonb_typeof(v_filters -> 'holderUserId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'holderUserId')) else array[v_filters ->> 'holderUserId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or coalesce(x."holder_name", '') ilike v_search or coalesce(x."holder_email", '') ilike v_search)
        and (v_after is null or (coalesce(x."expires_at", 'infinity'::timestamptz) >= (v_after ->> 0)::timestamptz and ((coalesce(x."expires_at", 'infinity'::timestamptz) > (v_after ->> 0)::timestamptz) or (coalesce(x."expires_at", 'infinity'::timestamptz) = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by coalesce(x."expires_at", 'infinity'::timestamptz) asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'validUntil' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PASS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'kind', x."kind", 'holderUserId', x."holder_id", 'holderName', x."holder_name", 'holderEmail', x."holder_email", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'bookingId', x."booking_id", 'resourceId', x."resource_id", 'usesAllowed', x."uses_allowed", 'uses', x."uses", 'validFrom', x."starts_at", 'validUntil', x."expires_at", 'status', x."status", 'issuedBy', x."issued_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'revokedAt', x."revoked_at") as j, jsonb_build_array((coalesce(x."expires_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."passes" x
      where x."tenant_id" = page_passes.tenant
        and (not (v_filters -> 'holderUserId' is not null and jsonb_typeof(v_filters -> 'holderUserId') <> 'null' and not (jsonb_typeof(v_filters -> 'holderUserId') = 'array' and jsonb_array_length(v_filters -> 'holderUserId') = 0)) or x."holder_id" = any((case when jsonb_typeof(v_filters -> 'holderUserId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'holderUserId')) else array[v_filters ->> 'holderUserId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or coalesce(x."holder_name", '') ilike v_search or coalesce(x."holder_email", '') ilike v_search)
        and (v_after is null or (coalesce(x."expires_at", 'infinity'::timestamptz), x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."expires_at", 'infinity'::timestamptz) desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."passes" x
      where x."tenant_id" = page_passes.tenant
        and (not (v_filters -> 'holderUserId' is not null and jsonb_typeof(v_filters -> 'holderUserId') <> 'null' and not (jsonb_typeof(v_filters -> 'holderUserId') = 'array' and jsonb_array_length(v_filters -> 'holderUserId') = 0)) or x."holder_id" = any((case when jsonb_typeof(v_filters -> 'holderUserId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'holderUserId')) else array[v_filters ->> 'holderUserId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or coalesce(x."holder_name", '') ilike v_search or coalesce(x."holder_email", '') ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_reviews (
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
  v_filters jsonb := coalesce(page_reviews.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_subject_type text := nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '');
  v_subject_id text := nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), '');
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 20), 1), 100);
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
  if jsonb_typeof(v_filters) <> 'object' or v_subject_type is null or v_subject_id is null then
    raise exception 'filters must name one subjectType and one subjectId' using errcode = '22023', hint = 'REVIEW_INVALID';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."review_subject_readable"(page_reviews.tenant, v_subject_type, v_subject_id)) then
    raise exception 'not allowed to read this record''s reviews' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'REVIEW_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('rating', 'verified') then
      raise exception 'facet is one of rating, verified' using errcode = '22023', hint = 'REVIEW_INVALID';
    end if;
    with s as (
      select (case v_facet when 'rating' then (x."rating"::text)::text when 'verified' then (x."verified"::text)::text end) as v
      from "better_supabase"."reviews" x
      where x."tenant_id" = page_reviews.tenant
        and x."subject_type" = v_subject_type
        and x."subject_id" = v_subject_id
        and x."status" = 'published'
        and (not (v_filters -> 'rating' is not null and jsonb_typeof(v_filters -> 'rating') <> 'null' and not (jsonb_typeof(v_filters -> 'rating') = 'array' and jsonb_array_length(v_filters -> 'rating') = 0)) or x."rating"::text = any((case when jsonb_typeof(v_filters -> 'rating') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'rating')) else array[v_filters ->> 'rating'] end)::text[]))
        and (not (v_filters -> 'verified' is not null and jsonb_typeof(v_filters -> 'verified') <> 'null' and not (jsonb_typeof(v_filters -> 'verified') = 'array' and jsonb_array_length(v_filters -> 'verified') = 0)) or x."verified"::text = any((case when jsonb_typeof(v_filters -> 'verified') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'verified')) else array[v_filters ->> 'verified'] end)::text[]))
        and (v_search is null or coalesce(x."title", '') ilike v_search or coalesce(x."body", '') ilike v_search)
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
      select 1 from "better_supabase"."reviews" x
      where x."tenant_id" = page_reviews.tenant
        and x."subject_type" = v_subject_type
        and x."subject_id" = v_subject_id
        and x."status" = 'published'
        and (not (v_filters -> 'rating' is not null and jsonb_typeof(v_filters -> 'rating') <> 'null' and not (jsonb_typeof(v_filters -> 'rating') = 'array' and jsonb_array_length(v_filters -> 'rating') = 0)) or x."rating"::text = any((case when jsonb_typeof(v_filters -> 'rating') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'rating')) else array[v_filters ->> 'rating'] end)::text[]))
        and (not (v_filters -> 'verified' is not null and jsonb_typeof(v_filters -> 'verified') <> 'null' and not (jsonb_typeof(v_filters -> 'verified') = 'array' and jsonb_array_length(v_filters -> 'verified') = 0)) or x."verified"::text = any((case when jsonb_typeof(v_filters -> 'verified') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'verified')) else array[v_filters ->> 'verified'] end)::text[]))
        and (v_search is null or coalesce(x."title", '') ilike v_search or coalesce(x."body", '') ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('publishedAt', 'rating') then
    raise exception 'sort is one of publishedAt, rating' using errcode = '22023', hint = 'REVIEW_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'REVIEW_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'REVIEW_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'authorId', null::uuid, 'authorName', x."author_name", 'mine', coalesce(x."author_id" = auth.uid(), false), 'rating', x."rating", 'title', x."title", 'body', x."body", 'status', x."status", 'verified', x."verified", 'rejectionReason', x."rejection_reason", 'reply', x."reply", 'repliedAt', x."replied_at", 'publishedAt', x."published_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."published_at", x."created_at"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."reviews" x
      where x."tenant_id" = page_reviews.tenant
        and x."subject_type" = v_subject_type
        and x."subject_id" = v_subject_id
        and x."status" = 'published'
        and (not (v_filters -> 'rating' is not null and jsonb_typeof(v_filters -> 'rating') <> 'null' and not (jsonb_typeof(v_filters -> 'rating') = 'array' and jsonb_array_length(v_filters -> 'rating') = 0)) or x."rating"::text = any((case when jsonb_typeof(v_filters -> 'rating') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'rating')) else array[v_filters ->> 'rating'] end)::text[]))
        and (not (v_filters -> 'verified' is not null and jsonb_typeof(v_filters -> 'verified') <> 'null' and not (jsonb_typeof(v_filters -> 'verified') = 'array' and jsonb_array_length(v_filters -> 'verified') = 0)) or x."verified"::text = any((case when jsonb_typeof(v_filters -> 'verified') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'verified')) else array[v_filters ->> 'verified'] end)::text[]))
        and (v_search is null or coalesce(x."title", '') ilike v_search or coalesce(x."body", '') ilike v_search)
        and (v_after is null or (coalesce(x."published_at", x."created_at") >= (v_after ->> 0)::timestamptz and ((coalesce(x."published_at", x."created_at") > (v_after ->> 0)::timestamptz) or (coalesce(x."published_at", x."created_at") = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by coalesce(x."published_at", x."created_at") asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'REVIEW_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'authorId', null::uuid, 'authorName', x."author_name", 'mine', coalesce(x."author_id" = auth.uid(), false), 'rating', x."rating", 'title', x."title", 'body', x."body", 'status', x."status", 'verified', x."verified", 'rejectionReason', x."rejection_reason", 'reply', x."reply", 'repliedAt', x."replied_at", 'publishedAt', x."published_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."published_at", x."created_at"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."reviews" x
      where x."tenant_id" = page_reviews.tenant
        and x."subject_type" = v_subject_type
        and x."subject_id" = v_subject_id
        and x."status" = 'published'
        and (not (v_filters -> 'rating' is not null and jsonb_typeof(v_filters -> 'rating') <> 'null' and not (jsonb_typeof(v_filters -> 'rating') = 'array' and jsonb_array_length(v_filters -> 'rating') = 0)) or x."rating"::text = any((case when jsonb_typeof(v_filters -> 'rating') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'rating')) else array[v_filters ->> 'rating'] end)::text[]))
        and (not (v_filters -> 'verified' is not null and jsonb_typeof(v_filters -> 'verified') <> 'null' and not (jsonb_typeof(v_filters -> 'verified') = 'array' and jsonb_array_length(v_filters -> 'verified') = 0)) or x."verified"::text = any((case when jsonb_typeof(v_filters -> 'verified') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'verified')) else array[v_filters ->> 'verified'] end)::text[]))
        and (v_search is null or coalesce(x."title", '') ilike v_search or coalesce(x."body", '') ilike v_search)
        and (v_after is null or (coalesce(x."published_at", x."created_at"), x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."published_at", x."created_at") desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'publishedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'REVIEW_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'authorId', null::uuid, 'authorName', x."author_name", 'mine', coalesce(x."author_id" = auth.uid(), false), 'rating', x."rating", 'title', x."title", 'body', x."body", 'status', x."status", 'verified', x."verified", 'rejectionReason', x."rejection_reason", 'reply', x."reply", 'repliedAt', x."replied_at", 'publishedAt', x."published_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."published_at", x."created_at"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."reviews" x
      where x."tenant_id" = page_reviews.tenant
        and x."subject_type" = v_subject_type
        and x."subject_id" = v_subject_id
        and x."status" = 'published'
        and (not (v_filters -> 'rating' is not null and jsonb_typeof(v_filters -> 'rating') <> 'null' and not (jsonb_typeof(v_filters -> 'rating') = 'array' and jsonb_array_length(v_filters -> 'rating') = 0)) or x."rating"::text = any((case when jsonb_typeof(v_filters -> 'rating') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'rating')) else array[v_filters ->> 'rating'] end)::text[]))
        and (not (v_filters -> 'verified' is not null and jsonb_typeof(v_filters -> 'verified') <> 'null' and not (jsonb_typeof(v_filters -> 'verified') = 'array' and jsonb_array_length(v_filters -> 'verified') = 0)) or x."verified"::text = any((case when jsonb_typeof(v_filters -> 'verified') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'verified')) else array[v_filters ->> 'verified'] end)::text[]))
        and (v_search is null or coalesce(x."title", '') ilike v_search or coalesce(x."body", '') ilike v_search)
        and (v_after is null or (coalesce(x."published_at", x."created_at") >= (v_after ->> 0)::timestamptz and ((coalesce(x."published_at", x."created_at") > (v_after ->> 0)::timestamptz) or (coalesce(x."published_at", x."created_at") = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by coalesce(x."published_at", x."created_at") asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'publishedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'REVIEW_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'authorId', null::uuid, 'authorName', x."author_name", 'mine', coalesce(x."author_id" = auth.uid(), false), 'rating', x."rating", 'title', x."title", 'body', x."body", 'status', x."status", 'verified', x."verified", 'rejectionReason', x."rejection_reason", 'reply', x."reply", 'repliedAt', x."replied_at", 'publishedAt', x."published_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."published_at", x."created_at"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."reviews" x
      where x."tenant_id" = page_reviews.tenant
        and x."subject_type" = v_subject_type
        and x."subject_id" = v_subject_id
        and x."status" = 'published'
        and (not (v_filters -> 'rating' is not null and jsonb_typeof(v_filters -> 'rating') <> 'null' and not (jsonb_typeof(v_filters -> 'rating') = 'array' and jsonb_array_length(v_filters -> 'rating') = 0)) or x."rating"::text = any((case when jsonb_typeof(v_filters -> 'rating') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'rating')) else array[v_filters ->> 'rating'] end)::text[]))
        and (not (v_filters -> 'verified' is not null and jsonb_typeof(v_filters -> 'verified') <> 'null' and not (jsonb_typeof(v_filters -> 'verified') = 'array' and jsonb_array_length(v_filters -> 'verified') = 0)) or x."verified"::text = any((case when jsonb_typeof(v_filters -> 'verified') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'verified')) else array[v_filters ->> 'verified'] end)::text[]))
        and (v_search is null or coalesce(x."title", '') ilike v_search or coalesce(x."body", '') ilike v_search)
        and (v_after is null or (coalesce(x."published_at", x."created_at"), x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."published_at", x."created_at") desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'rating' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'REVIEW_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'authorId', null::uuid, 'authorName', x."author_name", 'mine', coalesce(x."author_id" = auth.uid(), false), 'rating', x."rating", 'title', x."title", 'body', x."body", 'status', x."status", 'verified', x."verified", 'rejectionReason', x."rejection_reason", 'reply', x."reply", 'repliedAt', x."replied_at", 'publishedAt', x."published_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."rating")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."reviews" x
      where x."tenant_id" = page_reviews.tenant
        and x."subject_type" = v_subject_type
        and x."subject_id" = v_subject_id
        and x."status" = 'published'
        and (not (v_filters -> 'rating' is not null and jsonb_typeof(v_filters -> 'rating') <> 'null' and not (jsonb_typeof(v_filters -> 'rating') = 'array' and jsonb_array_length(v_filters -> 'rating') = 0)) or x."rating"::text = any((case when jsonb_typeof(v_filters -> 'rating') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'rating')) else array[v_filters ->> 'rating'] end)::text[]))
        and (not (v_filters -> 'verified' is not null and jsonb_typeof(v_filters -> 'verified') <> 'null' and not (jsonb_typeof(v_filters -> 'verified') = 'array' and jsonb_array_length(v_filters -> 'verified') = 0)) or x."verified"::text = any((case when jsonb_typeof(v_filters -> 'verified') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'verified')) else array[v_filters ->> 'verified'] end)::text[]))
        and (v_search is null or coalesce(x."title", '') ilike v_search or coalesce(x."body", '') ilike v_search)
        and (v_after is null or (x."rating" >= (v_after ->> 0)::integer and ((x."rating" > (v_after ->> 0)::integer) or (x."rating" = (v_after ->> 0)::integer and x."id" < (v_after ->> 1)::uuid))))
      order by x."rating" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'rating' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'REVIEW_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'authorId', null::uuid, 'authorName', x."author_name", 'mine', coalesce(x."author_id" = auth.uid(), false), 'rating', x."rating", 'title', x."title", 'body', x."body", 'status', x."status", 'verified', x."verified", 'rejectionReason', x."rejection_reason", 'reply', x."reply", 'repliedAt', x."replied_at", 'publishedAt', x."published_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."rating")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."reviews" x
      where x."tenant_id" = page_reviews.tenant
        and x."subject_type" = v_subject_type
        and x."subject_id" = v_subject_id
        and x."status" = 'published'
        and (not (v_filters -> 'rating' is not null and jsonb_typeof(v_filters -> 'rating') <> 'null' and not (jsonb_typeof(v_filters -> 'rating') = 'array' and jsonb_array_length(v_filters -> 'rating') = 0)) or x."rating"::text = any((case when jsonb_typeof(v_filters -> 'rating') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'rating')) else array[v_filters ->> 'rating'] end)::text[]))
        and (not (v_filters -> 'verified' is not null and jsonb_typeof(v_filters -> 'verified') <> 'null' and not (jsonb_typeof(v_filters -> 'verified') = 'array' and jsonb_array_length(v_filters -> 'verified') = 0)) or x."verified"::text = any((case when jsonb_typeof(v_filters -> 'verified') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'verified')) else array[v_filters ->> 'verified'] end)::text[]))
        and (v_search is null or coalesce(x."title", '') ilike v_search or coalesce(x."body", '') ilike v_search)
        and (v_after is null or (x."rating", x."id") < ((v_after ->> 0)::integer, (v_after ->> 1)::uuid))
      order by x."rating" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."reviews" x
      where x."tenant_id" = page_reviews.tenant
        and x."subject_type" = v_subject_type
        and x."subject_id" = v_subject_id
        and x."status" = 'published'
        and (not (v_filters -> 'rating' is not null and jsonb_typeof(v_filters -> 'rating') <> 'null' and not (jsonb_typeof(v_filters -> 'rating') = 'array' and jsonb_array_length(v_filters -> 'rating') = 0)) or x."rating"::text = any((case when jsonb_typeof(v_filters -> 'rating') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'rating')) else array[v_filters ->> 'rating'] end)::text[]))
        and (not (v_filters -> 'verified' is not null and jsonb_typeof(v_filters -> 'verified') <> 'null' and not (jsonb_typeof(v_filters -> 'verified') = 'array' and jsonb_array_length(v_filters -> 'verified') = 0)) or x."verified"::text = any((case when jsonb_typeof(v_filters -> 'verified') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'verified')) else array[v_filters ->> 'verified'] end)::text[]))
        and (v_search is null or coalesce(x."title", '') ilike v_search or coalesce(x."body", '') ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

REVOKE ALL ON FUNCTION "api"."get_collection"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_collection"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_review"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_review"(uuid) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_collections"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_collections"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_reviews"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_reviews"(uuid, jsonb) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_collection"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_collection"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_review"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_review"(uuid) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_collections"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_collections"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_reviews"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_reviews"(uuid, jsonb) TO "anon", "authenticated", "service_role";
