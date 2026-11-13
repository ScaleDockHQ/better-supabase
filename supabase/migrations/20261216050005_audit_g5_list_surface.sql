SET local check_function_bodies = off;

DROP FUNCTION "api"."list_content_entries"(uuid, jsonb);

DROP FUNCTION "api"."list_courses"(uuid, text);

DROP FUNCTION "api"."list_legal_entities"(uuid, boolean);

DROP FUNCTION "better_supabase"."list_content_entries"(uuid, jsonb);

DROP FUNCTION "better_supabase"."list_courses"(uuid, text);

DROP FUNCTION "better_supabase"."list_legal_entities"(uuid, boolean);

CREATE OR REPLACE FUNCTION api.list_content_entries (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_content_entries"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_courses (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_courses"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_legal_entities (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_legal_entities"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.list_content_entries (
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
  v_filters jsonb := coalesce(list_content_entries.filters, '{}'::jsonb);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_content_entries.tenant is not null and coalesce(better_supabase.can('tenant', list_content_entries.tenant, 'content.read'), false))) then
    raise exception 'not allowed to read content' using errcode = '42501', hint = 'CONTENT_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'CONTENT_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('type', 'locale', 'status') then
      raise exception 'facet is one of type, locale, status' using errcode = '22023', hint = 'CONTENT_INVALID';
    end if;
    with s as (
      select (case v_facet when 'type' then (x."type")::text when 'locale' then (x."locale")::text when 'status' then (x."status")::text end) as v
      from "better_supabase"."content_entries" x
      where x."tenant_id" = list_content_entries.tenant
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."type"::text = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not (v_filters -> 'locale' is not null and jsonb_typeof(v_filters -> 'locale') <> 'null' and not (jsonb_typeof(v_filters -> 'locale') = 'array' and jsonb_array_length(v_filters -> 'locale') = 0)) or x."locale"::text = any((case when jsonb_typeof(v_filters -> 'locale') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locale')) else array[v_filters ->> 'locale'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'translationGroupId' is not null and jsonb_typeof(v_filters -> 'translationGroupId') <> 'null' and not (jsonb_typeof(v_filters -> 'translationGroupId') = 'array' and jsonb_array_length(v_filters -> 'translationGroupId') = 0)) or x."translation_group_id" = any((case when jsonb_typeof(v_filters -> 'translationGroupId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'translationGroupId')) else array[v_filters ->> 'translationGroupId'] end)::uuid[]))
        and (v_search is null or x."title" ilike v_search or x."slug" ilike v_search)
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
      select 1 from "better_supabase"."content_entries" x
      where x."tenant_id" = list_content_entries.tenant
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."type"::text = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not (v_filters -> 'locale' is not null and jsonb_typeof(v_filters -> 'locale') <> 'null' and not (jsonb_typeof(v_filters -> 'locale') = 'array' and jsonb_array_length(v_filters -> 'locale') = 0)) or x."locale"::text = any((case when jsonb_typeof(v_filters -> 'locale') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locale')) else array[v_filters ->> 'locale'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'translationGroupId' is not null and jsonb_typeof(v_filters -> 'translationGroupId') <> 'null' and not (jsonb_typeof(v_filters -> 'translationGroupId') = 'array' and jsonb_array_length(v_filters -> 'translationGroupId') = 0)) or x."translation_group_id" = any((case when jsonb_typeof(v_filters -> 'translationGroupId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'translationGroupId')) else array[v_filters ->> 'translationGroupId'] end)::uuid[]))
        and (v_search is null or x."title" ilike v_search or x."slug" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('updatedAt', 'title', 'createdAt', 'publishedAt') then
    raise exception 'sort is one of updatedAt, title, createdAt, publishedAt' using errcode = '22023', hint = 'CONTENT_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'CONTENT_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CONTENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'type', x."type", 'locale', x."locale", 'slug', x."slug", 'title', x."title", 'summary', x."summary", 'body', x."body", 'status', x."status", 'publishAt', x."publish_at", 'publishedAt', x."published_at", 'authorId', x."author_id", 'translationGroupId', x."translation_group_id", 'coverAttachmentId', x."cover_attachment_id", 'approvalId', x."approval_id", 'approvalStatus', (select r."status" from "better_supabase"."approval_requests" r where r."id" = x."approval_id"), 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."content_entries" x
      where x."tenant_id" = list_content_entries.tenant
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."type"::text = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not (v_filters -> 'locale' is not null and jsonb_typeof(v_filters -> 'locale') <> 'null' and not (jsonb_typeof(v_filters -> 'locale') = 'array' and jsonb_array_length(v_filters -> 'locale') = 0)) or x."locale"::text = any((case when jsonb_typeof(v_filters -> 'locale') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locale')) else array[v_filters ->> 'locale'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'translationGroupId' is not null and jsonb_typeof(v_filters -> 'translationGroupId') <> 'null' and not (jsonb_typeof(v_filters -> 'translationGroupId') = 'array' and jsonb_array_length(v_filters -> 'translationGroupId') = 0)) or x."translation_group_id" = any((case when jsonb_typeof(v_filters -> 'translationGroupId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'translationGroupId')) else array[v_filters ->> 'translationGroupId'] end)::uuid[]))
        and (v_search is null or x."title" ilike v_search or x."slug" ilike v_search)
        and (v_after is null or (x."updated_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."updated_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CONTENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'type', x."type", 'locale', x."locale", 'slug', x."slug", 'title', x."title", 'summary', x."summary", 'body', x."body", 'status', x."status", 'publishAt', x."publish_at", 'publishedAt', x."published_at", 'authorId', x."author_id", 'translationGroupId', x."translation_group_id", 'coverAttachmentId', x."cover_attachment_id", 'approvalId', x."approval_id", 'approvalStatus', (select r."status" from "better_supabase"."approval_requests" r where r."id" = x."approval_id"), 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."content_entries" x
      where x."tenant_id" = list_content_entries.tenant
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."type"::text = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not (v_filters -> 'locale' is not null and jsonb_typeof(v_filters -> 'locale') <> 'null' and not (jsonb_typeof(v_filters -> 'locale') = 'array' and jsonb_array_length(v_filters -> 'locale') = 0)) or x."locale"::text = any((case when jsonb_typeof(v_filters -> 'locale') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locale')) else array[v_filters ->> 'locale'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'translationGroupId' is not null and jsonb_typeof(v_filters -> 'translationGroupId') <> 'null' and not (jsonb_typeof(v_filters -> 'translationGroupId') = 'array' and jsonb_array_length(v_filters -> 'translationGroupId') = 0)) or x."translation_group_id" = any((case when jsonb_typeof(v_filters -> 'translationGroupId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'translationGroupId')) else array[v_filters ->> 'translationGroupId'] end)::uuid[]))
        and (v_search is null or x."title" ilike v_search or x."slug" ilike v_search)
        and (v_after is null or (x."updated_at" <= (v_after ->> 0)::timestamptz and ((x."updated_at" < (v_after ->> 0)::timestamptz) or (x."updated_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."updated_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CONTENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'type', x."type", 'locale', x."locale", 'slug', x."slug", 'title', x."title", 'summary', x."summary", 'body', x."body", 'status', x."status", 'publishAt', x."publish_at", 'publishedAt', x."published_at", 'authorId', x."author_id", 'translationGroupId', x."translation_group_id", 'coverAttachmentId', x."cover_attachment_id", 'approvalId', x."approval_id", 'approvalStatus', (select r."status" from "better_supabase"."approval_requests" r where r."id" = x."approval_id"), 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."content_entries" x
      where x."tenant_id" = list_content_entries.tenant
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."type"::text = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not (v_filters -> 'locale' is not null and jsonb_typeof(v_filters -> 'locale') <> 'null' and not (jsonb_typeof(v_filters -> 'locale') = 'array' and jsonb_array_length(v_filters -> 'locale') = 0)) or x."locale"::text = any((case when jsonb_typeof(v_filters -> 'locale') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locale')) else array[v_filters ->> 'locale'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'translationGroupId' is not null and jsonb_typeof(v_filters -> 'translationGroupId') <> 'null' and not (jsonb_typeof(v_filters -> 'translationGroupId') = 'array' and jsonb_array_length(v_filters -> 'translationGroupId') = 0)) or x."translation_group_id" = any((case when jsonb_typeof(v_filters -> 'translationGroupId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'translationGroupId')) else array[v_filters ->> 'translationGroupId'] end)::uuid[]))
        and (v_search is null or x."title" ilike v_search or x."slug" ilike v_search)
        and (v_after is null or (x."updated_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."updated_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CONTENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'type', x."type", 'locale', x."locale", 'slug', x."slug", 'title', x."title", 'summary', x."summary", 'body', x."body", 'status', x."status", 'publishAt', x."publish_at", 'publishedAt', x."published_at", 'authorId', x."author_id", 'translationGroupId', x."translation_group_id", 'coverAttachmentId', x."cover_attachment_id", 'approvalId', x."approval_id", 'approvalStatus', (select r."status" from "better_supabase"."approval_requests" r where r."id" = x."approval_id"), 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."content_entries" x
      where x."tenant_id" = list_content_entries.tenant
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."type"::text = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not (v_filters -> 'locale' is not null and jsonb_typeof(v_filters -> 'locale') <> 'null' and not (jsonb_typeof(v_filters -> 'locale') = 'array' and jsonb_array_length(v_filters -> 'locale') = 0)) or x."locale"::text = any((case when jsonb_typeof(v_filters -> 'locale') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locale')) else array[v_filters ->> 'locale'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'translationGroupId' is not null and jsonb_typeof(v_filters -> 'translationGroupId') <> 'null' and not (jsonb_typeof(v_filters -> 'translationGroupId') = 'array' and jsonb_array_length(v_filters -> 'translationGroupId') = 0)) or x."translation_group_id" = any((case when jsonb_typeof(v_filters -> 'translationGroupId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'translationGroupId')) else array[v_filters ->> 'translationGroupId'] end)::uuid[]))
        and (v_search is null or x."title" ilike v_search or x."slug" ilike v_search)
        and (v_after is null or (x."updated_at" <= (v_after ->> 0)::timestamptz and ((x."updated_at" < (v_after ->> 0)::timestamptz) or (x."updated_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."updated_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CONTENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'type', x."type", 'locale', x."locale", 'slug', x."slug", 'title', x."title", 'summary', x."summary", 'body', x."body", 'status', x."status", 'publishAt', x."publish_at", 'publishedAt', x."published_at", 'authorId', x."author_id", 'translationGroupId', x."translation_group_id", 'coverAttachmentId', x."cover_attachment_id", 'approvalId', x."approval_id", 'approvalStatus', (select r."status" from "better_supabase"."approval_requests" r where r."id" = x."approval_id"), 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."title")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."content_entries" x
      where x."tenant_id" = list_content_entries.tenant
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."type"::text = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not (v_filters -> 'locale' is not null and jsonb_typeof(v_filters -> 'locale') <> 'null' and not (jsonb_typeof(v_filters -> 'locale') = 'array' and jsonb_array_length(v_filters -> 'locale') = 0)) or x."locale"::text = any((case when jsonb_typeof(v_filters -> 'locale') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locale')) else array[v_filters ->> 'locale'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'translationGroupId' is not null and jsonb_typeof(v_filters -> 'translationGroupId') <> 'null' and not (jsonb_typeof(v_filters -> 'translationGroupId') = 'array' and jsonb_array_length(v_filters -> 'translationGroupId') = 0)) or x."translation_group_id" = any((case when jsonb_typeof(v_filters -> 'translationGroupId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'translationGroupId')) else array[v_filters ->> 'translationGroupId'] end)::uuid[]))
        and (v_search is null or x."title" ilike v_search or x."slug" ilike v_search)
        and (v_after is null or (x."title", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."title" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CONTENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'type', x."type", 'locale', x."locale", 'slug', x."slug", 'title', x."title", 'summary', x."summary", 'body', x."body", 'status', x."status", 'publishAt', x."publish_at", 'publishedAt', x."published_at", 'authorId', x."author_id", 'translationGroupId', x."translation_group_id", 'coverAttachmentId', x."cover_attachment_id", 'approvalId', x."approval_id", 'approvalStatus', (select r."status" from "better_supabase"."approval_requests" r where r."id" = x."approval_id"), 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."title")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."content_entries" x
      where x."tenant_id" = list_content_entries.tenant
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."type"::text = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not (v_filters -> 'locale' is not null and jsonb_typeof(v_filters -> 'locale') <> 'null' and not (jsonb_typeof(v_filters -> 'locale') = 'array' and jsonb_array_length(v_filters -> 'locale') = 0)) or x."locale"::text = any((case when jsonb_typeof(v_filters -> 'locale') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locale')) else array[v_filters ->> 'locale'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'translationGroupId' is not null and jsonb_typeof(v_filters -> 'translationGroupId') <> 'null' and not (jsonb_typeof(v_filters -> 'translationGroupId') = 'array' and jsonb_array_length(v_filters -> 'translationGroupId') = 0)) or x."translation_group_id" = any((case when jsonb_typeof(v_filters -> 'translationGroupId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'translationGroupId')) else array[v_filters ->> 'translationGroupId'] end)::uuid[]))
        and (v_search is null or x."title" ilike v_search or x."slug" ilike v_search)
        and (v_after is null or (x."title" <= (v_after ->> 0)::text and ((x."title" < (v_after ->> 0)::text) or (x."title" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."title" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CONTENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'type', x."type", 'locale', x."locale", 'slug', x."slug", 'title', x."title", 'summary', x."summary", 'body', x."body", 'status', x."status", 'publishAt', x."publish_at", 'publishedAt', x."published_at", 'authorId', x."author_id", 'translationGroupId', x."translation_group_id", 'coverAttachmentId', x."cover_attachment_id", 'approvalId', x."approval_id", 'approvalStatus', (select r."status" from "better_supabase"."approval_requests" r where r."id" = x."approval_id"), 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."content_entries" x
      where x."tenant_id" = list_content_entries.tenant
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."type"::text = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not (v_filters -> 'locale' is not null and jsonb_typeof(v_filters -> 'locale') <> 'null' and not (jsonb_typeof(v_filters -> 'locale') = 'array' and jsonb_array_length(v_filters -> 'locale') = 0)) or x."locale"::text = any((case when jsonb_typeof(v_filters -> 'locale') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locale')) else array[v_filters ->> 'locale'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'translationGroupId' is not null and jsonb_typeof(v_filters -> 'translationGroupId') <> 'null' and not (jsonb_typeof(v_filters -> 'translationGroupId') = 'array' and jsonb_array_length(v_filters -> 'translationGroupId') = 0)) or x."translation_group_id" = any((case when jsonb_typeof(v_filters -> 'translationGroupId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'translationGroupId')) else array[v_filters ->> 'translationGroupId'] end)::uuid[]))
        and (v_search is null or x."title" ilike v_search or x."slug" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CONTENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'type', x."type", 'locale', x."locale", 'slug', x."slug", 'title', x."title", 'summary', x."summary", 'body', x."body", 'status', x."status", 'publishAt', x."publish_at", 'publishedAt', x."published_at", 'authorId', x."author_id", 'translationGroupId', x."translation_group_id", 'coverAttachmentId', x."cover_attachment_id", 'approvalId', x."approval_id", 'approvalStatus', (select r."status" from "better_supabase"."approval_requests" r where r."id" = x."approval_id"), 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."content_entries" x
      where x."tenant_id" = list_content_entries.tenant
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."type"::text = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not (v_filters -> 'locale' is not null and jsonb_typeof(v_filters -> 'locale') <> 'null' and not (jsonb_typeof(v_filters -> 'locale') = 'array' and jsonb_array_length(v_filters -> 'locale') = 0)) or x."locale"::text = any((case when jsonb_typeof(v_filters -> 'locale') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locale')) else array[v_filters ->> 'locale'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'translationGroupId' is not null and jsonb_typeof(v_filters -> 'translationGroupId') <> 'null' and not (jsonb_typeof(v_filters -> 'translationGroupId') = 'array' and jsonb_array_length(v_filters -> 'translationGroupId') = 0)) or x."translation_group_id" = any((case when jsonb_typeof(v_filters -> 'translationGroupId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'translationGroupId')) else array[v_filters ->> 'translationGroupId'] end)::uuid[]))
        and (v_search is null or x."title" ilike v_search or x."slug" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'publishedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CONTENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'type', x."type", 'locale', x."locale", 'slug', x."slug", 'title', x."title", 'summary', x."summary", 'body', x."body", 'status', x."status", 'publishAt', x."publish_at", 'publishedAt', x."published_at", 'authorId', x."author_id", 'translationGroupId', x."translation_group_id", 'coverAttachmentId', x."cover_attachment_id", 'approvalId', x."approval_id", 'approvalStatus', (select r."status" from "better_supabase"."approval_requests" r where r."id" = x."approval_id"), 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."published_at", '-infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."content_entries" x
      where x."tenant_id" = list_content_entries.tenant
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."type"::text = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not (v_filters -> 'locale' is not null and jsonb_typeof(v_filters -> 'locale') <> 'null' and not (jsonb_typeof(v_filters -> 'locale') = 'array' and jsonb_array_length(v_filters -> 'locale') = 0)) or x."locale"::text = any((case when jsonb_typeof(v_filters -> 'locale') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locale')) else array[v_filters ->> 'locale'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'translationGroupId' is not null and jsonb_typeof(v_filters -> 'translationGroupId') <> 'null' and not (jsonb_typeof(v_filters -> 'translationGroupId') = 'array' and jsonb_array_length(v_filters -> 'translationGroupId') = 0)) or x."translation_group_id" = any((case when jsonb_typeof(v_filters -> 'translationGroupId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'translationGroupId')) else array[v_filters ->> 'translationGroupId'] end)::uuid[]))
        and (v_search is null or x."title" ilike v_search or x."slug" ilike v_search)
        and (v_after is null or (coalesce(x."published_at", '-infinity'::timestamptz), x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."published_at", '-infinity'::timestamptz) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'publishedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CONTENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'type', x."type", 'locale', x."locale", 'slug', x."slug", 'title', x."title", 'summary', x."summary", 'body', x."body", 'status', x."status", 'publishAt', x."publish_at", 'publishedAt', x."published_at", 'authorId', x."author_id", 'translationGroupId', x."translation_group_id", 'coverAttachmentId', x."cover_attachment_id", 'approvalId', x."approval_id", 'approvalStatus', (select r."status" from "better_supabase"."approval_requests" r where r."id" = x."approval_id"), 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."published_at", '-infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."content_entries" x
      where x."tenant_id" = list_content_entries.tenant
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."type"::text = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not (v_filters -> 'locale' is not null and jsonb_typeof(v_filters -> 'locale') <> 'null' and not (jsonb_typeof(v_filters -> 'locale') = 'array' and jsonb_array_length(v_filters -> 'locale') = 0)) or x."locale"::text = any((case when jsonb_typeof(v_filters -> 'locale') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locale')) else array[v_filters ->> 'locale'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'translationGroupId' is not null and jsonb_typeof(v_filters -> 'translationGroupId') <> 'null' and not (jsonb_typeof(v_filters -> 'translationGroupId') = 'array' and jsonb_array_length(v_filters -> 'translationGroupId') = 0)) or x."translation_group_id" = any((case when jsonb_typeof(v_filters -> 'translationGroupId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'translationGroupId')) else array[v_filters ->> 'translationGroupId'] end)::uuid[]))
        and (v_search is null or x."title" ilike v_search or x."slug" ilike v_search)
        and (v_after is null or (coalesce(x."published_at", '-infinity'::timestamptz) <= (v_after ->> 0)::timestamptz and ((coalesce(x."published_at", '-infinity'::timestamptz) < (v_after ->> 0)::timestamptz) or (coalesce(x."published_at", '-infinity'::timestamptz) = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."published_at", '-infinity'::timestamptz) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."content_entries" x
      where x."tenant_id" = list_content_entries.tenant
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."type"::text = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not (v_filters -> 'locale' is not null and jsonb_typeof(v_filters -> 'locale') <> 'null' and not (jsonb_typeof(v_filters -> 'locale') = 'array' and jsonb_array_length(v_filters -> 'locale') = 0)) or x."locale"::text = any((case when jsonb_typeof(v_filters -> 'locale') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locale')) else array[v_filters ->> 'locale'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'translationGroupId' is not null and jsonb_typeof(v_filters -> 'translationGroupId') <> 'null' and not (jsonb_typeof(v_filters -> 'translationGroupId') = 'array' and jsonb_array_length(v_filters -> 'translationGroupId') = 0)) or x."translation_group_id" = any((case when jsonb_typeof(v_filters -> 'translationGroupId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'translationGroupId')) else array[v_filters ->> 'translationGroupId'] end)::uuid[]))
        and (v_search is null or x."title" ilike v_search or x."slug" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_courses (
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
  v_filters jsonb := coalesce(list_courses.filters, '{}'::jsonb);
  v_manage boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_courses.tenant is not null and coalesce(better_supabase.can('tenant', list_courses.tenant, 'courses.manage'), false)));
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 200), 1), 500);
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
  if not (v_manage or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_courses.tenant is not null and coalesce(better_supabase.can('tenant', list_courses.tenant, 'courses.read'), false)))) then
    raise exception 'not allowed to read courses' using errcode = '42501', hint = 'COURSE_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'COURSE_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status') then
      raise exception 'facet is one of status' using errcode = '22023', hint = 'COURSE_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text end) as v
      from "better_supabase"."courses" x
      where x."tenant_id" = list_courses.tenant
        and (v_manage or x."status" = 'published')
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
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
      select 1 from "better_supabase"."courses" x
      where x."tenant_id" = list_courses.tenant
        and (v_manage or x."status" = 'published')
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('title') then
    raise exception 'sort is one of title' using errcode = '22023', hint = 'COURSE_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'COURSE_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COURSE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'summary', x."summary", 'status', x."status", 'certificate', x."issues_certificate", 'validForMonths', x."valid_for_months", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."title")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."courses" x
      where x."tenant_id" = list_courses.tenant
        and (v_manage or x."status" = 'published')
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."title", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."title" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COURSE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'summary', x."summary", 'status', x."status", 'certificate', x."issues_certificate", 'validForMonths', x."valid_for_months", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."title")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."courses" x
      where x."tenant_id" = list_courses.tenant
        and (v_manage or x."status" = 'published')
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."title" <= (v_after ->> 0)::text and ((x."title" < (v_after ->> 0)::text) or (x."title" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."title" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COURSE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'summary', x."summary", 'status', x."status", 'certificate', x."issues_certificate", 'validForMonths', x."valid_for_months", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."title")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."courses" x
      where x."tenant_id" = list_courses.tenant
        and (v_manage or x."status" = 'published')
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."title", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."title" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COURSE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'summary', x."summary", 'status', x."status", 'certificate', x."issues_certificate", 'validForMonths', x."valid_for_months", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."title")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."courses" x
      where x."tenant_id" = list_courses.tenant
        and (v_manage or x."status" = 'published')
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
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
      select 1 from "better_supabase"."courses" x
      where x."tenant_id" = list_courses.tenant
        and (v_manage or x."status" = 'published')
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_legal_entities (
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
  v_filters jsonb := coalesce(list_legal_entities.filters, '{}'::jsonb);
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 200), 1), 500);
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
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'LEGAL_ENTITY_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('isDefault') then
      raise exception 'facet is one of isDefault' using errcode = '22023', hint = 'LEGAL_ENTITY_INVALID';
    end if;
    with s as (
      select (case v_facet when 'isDefault' then (x."is_default")::text end) as v
      from "better_supabase"."legal_entities" x
      where x."tenant_id" = list_legal_entities.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'isDefault' is not null and jsonb_typeof(v_filters -> 'isDefault') <> 'null' and not (jsonb_typeof(v_filters -> 'isDefault') = 'array' and jsonb_array_length(v_filters -> 'isDefault') = 0)) or x."is_default"::text = any((case when jsonb_typeof(v_filters -> 'isDefault') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'isDefault')) else array[v_filters ->> 'isDefault'] end)::text[]))
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
      select 1 from "better_supabase"."legal_entities" x
      where x."tenant_id" = list_legal_entities.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'isDefault' is not null and jsonb_typeof(v_filters -> 'isDefault') <> 'null' and not (jsonb_typeof(v_filters -> 'isDefault') = 'array' and jsonb_array_length(v_filters -> 'isDefault') = 0)) or x."is_default"::text = any((case when jsonb_typeof(v_filters -> 'isDefault') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'isDefault')) else array[v_filters ->> 'isDefault'] end)::text[]))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('code', 'name') then
    raise exception 'sort is one of code, name' using errcode = '22023', hint = 'LEGAL_ENTITY_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'LEGAL_ENTITY_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEGAL_ENTITY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'code', x."code", 'name', x."name", 'address', x."address", 'vatNumber', x."vat_number", 'cocNumber', x."coc_number", 'iban', x."iban", 'bic', x."bic", 'logoAttachmentId', x."logo_attachment_id", 'defaultCurrency', x."default_currency", 'fiscal', x."fiscal", 'isDefault', x."is_default", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."is_default")::text, (x."code")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."legal_entities" x
      where x."tenant_id" = list_legal_entities.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'isDefault' is not null and jsonb_typeof(v_filters -> 'isDefault') <> 'null' and not (jsonb_typeof(v_filters -> 'isDefault') = 'array' and jsonb_array_length(v_filters -> 'isDefault') = 0)) or x."is_default"::text = any((case when jsonb_typeof(v_filters -> 'isDefault') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'isDefault')) else array[v_filters ->> 'isDefault'] end)::text[]))
        and (v_after is null or (x."is_default", x."code", x."id") > ((v_after ->> 0)::boolean, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."is_default" asc, x."code" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEGAL_ENTITY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'code', x."code", 'name', x."name", 'address', x."address", 'vatNumber', x."vat_number", 'cocNumber', x."coc_number", 'iban', x."iban", 'bic', x."bic", 'logoAttachmentId', x."logo_attachment_id", 'defaultCurrency', x."default_currency", 'fiscal', x."fiscal", 'isDefault', x."is_default", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."is_default")::text, (x."code")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."legal_entities" x
      where x."tenant_id" = list_legal_entities.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'isDefault' is not null and jsonb_typeof(v_filters -> 'isDefault') <> 'null' and not (jsonb_typeof(v_filters -> 'isDefault') = 'array' and jsonb_array_length(v_filters -> 'isDefault') = 0)) or x."is_default"::text = any((case when jsonb_typeof(v_filters -> 'isDefault') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'isDefault')) else array[v_filters ->> 'isDefault'] end)::text[]))
        and (v_after is null or (x."is_default" <= (v_after ->> 0)::boolean and ((x."is_default" < (v_after ->> 0)::boolean) or (x."is_default" = (v_after ->> 0)::boolean and x."code" > (v_after ->> 1)::text) or (x."is_default" = (v_after ->> 0)::boolean and x."code" = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."is_default" desc, x."code" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'code' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEGAL_ENTITY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'code', x."code", 'name', x."name", 'address', x."address", 'vatNumber', x."vat_number", 'cocNumber', x."coc_number", 'iban', x."iban", 'bic', x."bic", 'logoAttachmentId', x."logo_attachment_id", 'defaultCurrency', x."default_currency", 'fiscal', x."fiscal", 'isDefault', x."is_default", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."code")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."legal_entities" x
      where x."tenant_id" = list_legal_entities.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'isDefault' is not null and jsonb_typeof(v_filters -> 'isDefault') <> 'null' and not (jsonb_typeof(v_filters -> 'isDefault') = 'array' and jsonb_array_length(v_filters -> 'isDefault') = 0)) or x."is_default"::text = any((case when jsonb_typeof(v_filters -> 'isDefault') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'isDefault')) else array[v_filters ->> 'isDefault'] end)::text[]))
        and (v_after is null or (x."code", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."code" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'code' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEGAL_ENTITY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'code', x."code", 'name', x."name", 'address', x."address", 'vatNumber', x."vat_number", 'cocNumber', x."coc_number", 'iban', x."iban", 'bic', x."bic", 'logoAttachmentId', x."logo_attachment_id", 'defaultCurrency', x."default_currency", 'fiscal', x."fiscal", 'isDefault', x."is_default", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."code")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."legal_entities" x
      where x."tenant_id" = list_legal_entities.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'isDefault' is not null and jsonb_typeof(v_filters -> 'isDefault') <> 'null' and not (jsonb_typeof(v_filters -> 'isDefault') = 'array' and jsonb_array_length(v_filters -> 'isDefault') = 0)) or x."is_default"::text = any((case when jsonb_typeof(v_filters -> 'isDefault') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'isDefault')) else array[v_filters ->> 'isDefault'] end)::text[]))
        and (v_after is null or (x."code" <= (v_after ->> 0)::text and ((x."code" < (v_after ->> 0)::text) or (x."code" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."code" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEGAL_ENTITY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'code', x."code", 'name', x."name", 'address', x."address", 'vatNumber', x."vat_number", 'cocNumber', x."coc_number", 'iban', x."iban", 'bic', x."bic", 'logoAttachmentId', x."logo_attachment_id", 'defaultCurrency', x."default_currency", 'fiscal', x."fiscal", 'isDefault', x."is_default", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."legal_entities" x
      where x."tenant_id" = list_legal_entities.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'isDefault' is not null and jsonb_typeof(v_filters -> 'isDefault') <> 'null' and not (jsonb_typeof(v_filters -> 'isDefault') = 'array' and jsonb_array_length(v_filters -> 'isDefault') = 0)) or x."is_default"::text = any((case when jsonb_typeof(v_filters -> 'isDefault') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'isDefault')) else array[v_filters ->> 'isDefault'] end)::text[]))
        and (v_after is null or (x."name", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."name" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEGAL_ENTITY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'code', x."code", 'name', x."name", 'address', x."address", 'vatNumber', x."vat_number", 'cocNumber', x."coc_number", 'iban', x."iban", 'bic', x."bic", 'logoAttachmentId', x."logo_attachment_id", 'defaultCurrency', x."default_currency", 'fiscal', x."fiscal", 'isDefault', x."is_default", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."legal_entities" x
      where x."tenant_id" = list_legal_entities.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'isDefault' is not null and jsonb_typeof(v_filters -> 'isDefault') <> 'null' and not (jsonb_typeof(v_filters -> 'isDefault') = 'array' and jsonb_array_length(v_filters -> 'isDefault') = 0)) or x."is_default"::text = any((case when jsonb_typeof(v_filters -> 'isDefault') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'isDefault')) else array[v_filters ->> 'isDefault'] end)::text[]))
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
      select 1 from "better_supabase"."legal_entities" x
      where x."tenant_id" = list_legal_entities.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'isDefault' is not null and jsonb_typeof(v_filters -> 'isDefault') <> 'null' and not (jsonb_typeof(v_filters -> 'isDefault') = 'array' and jsonb_array_length(v_filters -> 'isDefault') = 0)) or x."is_default"::text = any((case when jsonb_typeof(v_filters -> 'isDefault') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'isDefault')) else array[v_filters ->> 'isDefault'] end)::text[]))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

REVOKE ALL ON FUNCTION "api"."list_content_entries"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_content_entries"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_courses"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_courses"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_legal_entities"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_legal_entities"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_content_entries"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_content_entries"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_courses"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_courses"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_legal_entities"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_legal_entities"(uuid, jsonb) TO "authenticated", "service_role";
