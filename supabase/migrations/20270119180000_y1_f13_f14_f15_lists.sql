SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.get_announcement (
  id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_announcement"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_my_reminder (
  reminder uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_my_reminder"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_tag (
  tag_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_tag"($1) $function$;

CREATE OR REPLACE FUNCTION api.page_announcements (
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_announcements"($1) $function$;

CREATE OR REPLACE FUNCTION api.page_my_reminders (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_my_reminders"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_prompts (
  tenant  uuid  DEFAULT NULL::uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_prompts"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_tags (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_tags"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.get_announcement (
  id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  return (
    select to_jsonb(x)
    from "better_supabase"."announcements" x where x."id" = get_announcement.id
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_my_reminder (
  reminder uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('id', r."id", 'subjectType', r."subject_type", 'subjectId', r."subject_id", 'method', r."method", 'offsetMinutes', r."offset_minutes", 'remindAt', r."remind_at")
  from "better_supabase"."reminders" r
  where r."id" = get_my_reminder.reminder
    and r."user_id" = auth.uid()
    and coalesce(better_supabase.can('tenant', r."tenant_id", 'reminders.manage'), false);
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_tag (
  tag_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
begin
  select t."tenant_id" into v_tenant from "better_supabase"."tags" t where t."id" = get_tag.tag_id;
  if not found then
    return null;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'tags.read'), false) or coalesce(better_supabase.can('tenant', v_tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to read tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  return (select jsonb_build_object('id', t."id", 'kind', t."kind", 'name', t."name", 'slug', t."slug", 'color', t."color", 'description', t."description", 'rank', t."rank") from "better_supabase"."tags" t where t."id" = get_tag.tag_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_announcements (
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
  v_filters jsonb := coalesce(page_announcements.filters, '{}'::jsonb);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('severity', 'audience') then
      raise exception 'facet is one of severity, audience' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
    end if;
    with s as (
      select (case v_facet when 'severity' then (x."severity")::text when 'audience' then (x."audience")::text end) as v
      from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or x."severity" = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or x."audience" = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
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
      select 1 from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or x."severity" = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or x."audience" = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('startsAt', 'title', 'createdAt') then
    raise exception 'sort is one of startsAt, title, createdAt' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."starts_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or x."severity" = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or x."audience" = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (x."starts_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."starts_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."starts_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or x."severity" = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or x."audience" = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (x."starts_at" <= (v_after ->> 0)::timestamptz and ((x."starts_at" < (v_after ->> 0)::timestamptz) or (x."starts_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."starts_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startsAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."starts_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or x."severity" = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or x."audience" = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (x."starts_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."starts_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startsAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."starts_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or x."severity" = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or x."audience" = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (x."starts_at" <= (v_after ->> 0)::timestamptz and ((x."starts_at" < (v_after ->> 0)::timestamptz) or (x."starts_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."starts_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or x."severity" = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or x."audience" = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (lower(x."title"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."title") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or x."severity" = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or x."audience" = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (lower(x."title") <= (v_after ->> 0)::text and ((lower(x."title") < (v_after ->> 0)::text) or (lower(x."title") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."title") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or x."severity" = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or x."audience" = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or x."severity" = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or x."audience" = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
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
      select 1 from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or x."severity" = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or x."audience" = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_my_reminders (
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
  v_filters jsonb := coalesce(page_my_reminders.filters, '{}'::jsonb);
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
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', page_my_reminders.tenant, 'reminders.manage'), false)) then
    raise exception 'not allowed to manage reminders' using errcode = '42501', hint = 'REMINDER_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'REMINDER_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('method', 'subjectType') then
      raise exception 'facet is one of method, subjectType' using errcode = '22023', hint = 'REMINDER_INVALID';
    end if;
    with s as (
      select (case v_facet when 'method' then (x."method")::text when 'subjectType' then (x."subject_type")::text end) as v
      from "better_supabase"."reminders" x
      where x."tenant_id" = page_my_reminders.tenant
        and x."user_id" = auth.uid()
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'method' is not null and jsonb_typeof(v_filters -> 'method') <> 'null' and not (jsonb_typeof(v_filters -> 'method') = 'array' and jsonb_array_length(v_filters -> 'method') = 0)) or x."method" = any((case when jsonb_typeof(v_filters -> 'method') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'method')) else array[v_filters ->> 'method'] end)::text[]))
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
      select 1 from "better_supabase"."reminders" x
      where x."tenant_id" = page_my_reminders.tenant
        and x."user_id" = auth.uid()
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'method' is not null and jsonb_typeof(v_filters -> 'method') <> 'null' and not (jsonb_typeof(v_filters -> 'method') = 'array' and jsonb_array_length(v_filters -> 'method') = 0)) or x."method" = any((case when jsonb_typeof(v_filters -> 'method') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'method')) else array[v_filters ->> 'method'] end)::text[]))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('offsetMinutes', 'subjectType') then
    raise exception 'sort is one of offsetMinutes, subjectType' using errcode = '22023', hint = 'REMINDER_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'REMINDER_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'REMINDER_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'method', x."method", 'offsetMinutes', x."offset_minutes", 'remindAt', x."remind_at") as j, jsonb_build_array((x."offset_minutes")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."reminders" x
      where x."tenant_id" = page_my_reminders.tenant
        and x."user_id" = auth.uid()
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'method' is not null and jsonb_typeof(v_filters -> 'method') <> 'null' and not (jsonb_typeof(v_filters -> 'method') = 'array' and jsonb_array_length(v_filters -> 'method') = 0)) or x."method" = any((case when jsonb_typeof(v_filters -> 'method') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'method')) else array[v_filters ->> 'method'] end)::text[]))
        and (v_after is null or (x."offset_minutes", x."id") > ((v_after ->> 0)::integer, (v_after ->> 1)::uuid))
      order by x."offset_minutes" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'REMINDER_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'method', x."method", 'offsetMinutes', x."offset_minutes", 'remindAt', x."remind_at") as j, jsonb_build_array((x."offset_minutes")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."reminders" x
      where x."tenant_id" = page_my_reminders.tenant
        and x."user_id" = auth.uid()
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'method' is not null and jsonb_typeof(v_filters -> 'method') <> 'null' and not (jsonb_typeof(v_filters -> 'method') = 'array' and jsonb_array_length(v_filters -> 'method') = 0)) or x."method" = any((case when jsonb_typeof(v_filters -> 'method') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'method')) else array[v_filters ->> 'method'] end)::text[]))
        and (v_after is null or (x."offset_minutes" <= (v_after ->> 0)::integer and ((x."offset_minutes" < (v_after ->> 0)::integer) or (x."offset_minutes" = (v_after ->> 0)::integer and x."id" > (v_after ->> 1)::uuid))))
      order by x."offset_minutes" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'offsetMinutes' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'REMINDER_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'method', x."method", 'offsetMinutes', x."offset_minutes", 'remindAt', x."remind_at") as j, jsonb_build_array((x."offset_minutes")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."reminders" x
      where x."tenant_id" = page_my_reminders.tenant
        and x."user_id" = auth.uid()
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'method' is not null and jsonb_typeof(v_filters -> 'method') <> 'null' and not (jsonb_typeof(v_filters -> 'method') = 'array' and jsonb_array_length(v_filters -> 'method') = 0)) or x."method" = any((case when jsonb_typeof(v_filters -> 'method') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'method')) else array[v_filters ->> 'method'] end)::text[]))
        and (v_after is null or (x."offset_minutes", x."id") > ((v_after ->> 0)::integer, (v_after ->> 1)::uuid))
      order by x."offset_minutes" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'offsetMinutes' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'REMINDER_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'method', x."method", 'offsetMinutes', x."offset_minutes", 'remindAt', x."remind_at") as j, jsonb_build_array((x."offset_minutes")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."reminders" x
      where x."tenant_id" = page_my_reminders.tenant
        and x."user_id" = auth.uid()
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'method' is not null and jsonb_typeof(v_filters -> 'method') <> 'null' and not (jsonb_typeof(v_filters -> 'method') = 'array' and jsonb_array_length(v_filters -> 'method') = 0)) or x."method" = any((case when jsonb_typeof(v_filters -> 'method') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'method')) else array[v_filters ->> 'method'] end)::text[]))
        and (v_after is null or (x."offset_minutes" <= (v_after ->> 0)::integer and ((x."offset_minutes" < (v_after ->> 0)::integer) or (x."offset_minutes" = (v_after ->> 0)::integer and x."id" > (v_after ->> 1)::uuid))))
      order by x."offset_minutes" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'subjectType' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'REMINDER_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'method', x."method", 'offsetMinutes', x."offset_minutes", 'remindAt', x."remind_at") as j, jsonb_build_array((x."subject_type")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."reminders" x
      where x."tenant_id" = page_my_reminders.tenant
        and x."user_id" = auth.uid()
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'method' is not null and jsonb_typeof(v_filters -> 'method') <> 'null' and not (jsonb_typeof(v_filters -> 'method') = 'array' and jsonb_array_length(v_filters -> 'method') = 0)) or x."method" = any((case when jsonb_typeof(v_filters -> 'method') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'method')) else array[v_filters ->> 'method'] end)::text[]))
        and (v_after is null or (x."subject_type", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."subject_type" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'subjectType' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'REMINDER_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'method', x."method", 'offsetMinutes', x."offset_minutes", 'remindAt', x."remind_at") as j, jsonb_build_array((x."subject_type")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."reminders" x
      where x."tenant_id" = page_my_reminders.tenant
        and x."user_id" = auth.uid()
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'method' is not null and jsonb_typeof(v_filters -> 'method') <> 'null' and not (jsonb_typeof(v_filters -> 'method') = 'array' and jsonb_array_length(v_filters -> 'method') = 0)) or x."method" = any((case when jsonb_typeof(v_filters -> 'method') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'method')) else array[v_filters ->> 'method'] end)::text[]))
        and (v_after is null or (x."subject_type" <= (v_after ->> 0)::text and ((x."subject_type" < (v_after ->> 0)::text) or (x."subject_type" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."subject_type" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."reminders" x
      where x."tenant_id" = page_my_reminders.tenant
        and x."user_id" = auth.uid()
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'method' is not null and jsonb_typeof(v_filters -> 'method') <> 'null' and not (jsonb_typeof(v_filters -> 'method') = 'array' and jsonb_array_length(v_filters -> 'method') = 0)) or x."method" = any((case when jsonb_typeof(v_filters -> 'method') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'method')) else array[v_filters ->> 'method'] end)::text[]))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_prompts (
  tenant  uuid  DEFAULT NULL::uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_prompts.filters, '{}'::jsonb);
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
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'PROMPT_INVALID';
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from (
    select g."name" as name,
      max(g."version") as latest_version,
      count(*) as version_count,
      max(g."created_at") as updated_at,
      coalesce((
        select jsonb_object_agg(y."label", y."version") from "better_supabase"."prompt_labels" y
        where coalesce(y."tenant_id"::text, '') = coalesce(page_prompts.tenant::text, '') and y."name" = g."name"
      ), '{}'::jsonb) as labels
    from "better_supabase"."prompt_versions" g
    where coalesce(g."tenant_id"::text, '') = coalesce(page_prompts.tenant::text, '')
    group by g."name"
  ) x
      where (not (v_filters -> 'name' is not null and jsonb_typeof(v_filters -> 'name') <> 'null' and not (jsonb_typeof(v_filters -> 'name') = 'array' and jsonb_array_length(v_filters -> 'name') = 0)) or x.name = any((case when jsonb_typeof(v_filters -> 'name') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'name')) else array[v_filters ->> 'name'] end)::text[]))
        and (not (v_filters -> 'label' is not null and jsonb_typeof(v_filters -> 'label') <> 'null' and not (jsonb_typeof(v_filters -> 'label') = 'array' and jsonb_array_length(v_filters -> 'label') = 0)) or x.labels ?| (case when jsonb_typeof(v_filters -> 'label') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'label')) else array[v_filters ->> 'label'] end))
        and (v_search is null or x.name ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'updatedAt', 'versionCount') then
    raise exception 'sort is one of name, updatedAt, versionCount' using errcode = '22023', hint = 'PROMPT_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'PROMPT_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 1) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PROMPT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('name', x.name, 'tenant_id', page_prompts.tenant, 'latest_version', x.latest_version, 'version_count', x.version_count, 'updated_at', x.updated_at, 'labels', x.labels) as j, jsonb_build_array((x.name)::text) as k
    from (
      select * from (
    select g."name" as name,
      max(g."version") as latest_version,
      count(*) as version_count,
      max(g."created_at") as updated_at,
      coalesce((
        select jsonb_object_agg(y."label", y."version") from "better_supabase"."prompt_labels" y
        where coalesce(y."tenant_id"::text, '') = coalesce(page_prompts.tenant::text, '') and y."name" = g."name"
      ), '{}'::jsonb) as labels
    from "better_supabase"."prompt_versions" g
    where coalesce(g."tenant_id"::text, '') = coalesce(page_prompts.tenant::text, '')
    group by g."name"
  ) x
      where (not (v_filters -> 'name' is not null and jsonb_typeof(v_filters -> 'name') <> 'null' and not (jsonb_typeof(v_filters -> 'name') = 'array' and jsonb_array_length(v_filters -> 'name') = 0)) or x.name = any((case when jsonb_typeof(v_filters -> 'name') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'name')) else array[v_filters ->> 'name'] end)::text[]))
        and (not (v_filters -> 'label' is not null and jsonb_typeof(v_filters -> 'label') <> 'null' and not (jsonb_typeof(v_filters -> 'label') = 'array' and jsonb_array_length(v_filters -> 'label') = 0)) or x.labels ?| (case when jsonb_typeof(v_filters -> 'label') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'label')) else array[v_filters ->> 'label'] end))
        and (v_search is null or x.name ilike v_search)
        and (v_after is null or (x.name) > ((v_after ->> 0)::text))
      order by x.name asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 1) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PROMPT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('name', x.name, 'tenant_id', page_prompts.tenant, 'latest_version', x.latest_version, 'version_count', x.version_count, 'updated_at', x.updated_at, 'labels', x.labels) as j, jsonb_build_array((x.name)::text) as k
    from (
      select * from (
    select g."name" as name,
      max(g."version") as latest_version,
      count(*) as version_count,
      max(g."created_at") as updated_at,
      coalesce((
        select jsonb_object_agg(y."label", y."version") from "better_supabase"."prompt_labels" y
        where coalesce(y."tenant_id"::text, '') = coalesce(page_prompts.tenant::text, '') and y."name" = g."name"
      ), '{}'::jsonb) as labels
    from "better_supabase"."prompt_versions" g
    where coalesce(g."tenant_id"::text, '') = coalesce(page_prompts.tenant::text, '')
    group by g."name"
  ) x
      where (not (v_filters -> 'name' is not null and jsonb_typeof(v_filters -> 'name') <> 'null' and not (jsonb_typeof(v_filters -> 'name') = 'array' and jsonb_array_length(v_filters -> 'name') = 0)) or x.name = any((case when jsonb_typeof(v_filters -> 'name') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'name')) else array[v_filters ->> 'name'] end)::text[]))
        and (not (v_filters -> 'label' is not null and jsonb_typeof(v_filters -> 'label') <> 'null' and not (jsonb_typeof(v_filters -> 'label') = 'array' and jsonb_array_length(v_filters -> 'label') = 0)) or x.labels ?| (case when jsonb_typeof(v_filters -> 'label') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'label')) else array[v_filters ->> 'label'] end))
        and (v_search is null or x.name ilike v_search)
        and (v_after is null or (x.name) < ((v_after ->> 0)::text))
      order by x.name desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 1) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PROMPT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('name', x.name, 'tenant_id', page_prompts.tenant, 'latest_version', x.latest_version, 'version_count', x.version_count, 'updated_at', x.updated_at, 'labels', x.labels) as j, jsonb_build_array((x.name)::text) as k
    from (
      select * from (
    select g."name" as name,
      max(g."version") as latest_version,
      count(*) as version_count,
      max(g."created_at") as updated_at,
      coalesce((
        select jsonb_object_agg(y."label", y."version") from "better_supabase"."prompt_labels" y
        where coalesce(y."tenant_id"::text, '') = coalesce(page_prompts.tenant::text, '') and y."name" = g."name"
      ), '{}'::jsonb) as labels
    from "better_supabase"."prompt_versions" g
    where coalesce(g."tenant_id"::text, '') = coalesce(page_prompts.tenant::text, '')
    group by g."name"
  ) x
      where (not (v_filters -> 'name' is not null and jsonb_typeof(v_filters -> 'name') <> 'null' and not (jsonb_typeof(v_filters -> 'name') = 'array' and jsonb_array_length(v_filters -> 'name') = 0)) or x.name = any((case when jsonb_typeof(v_filters -> 'name') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'name')) else array[v_filters ->> 'name'] end)::text[]))
        and (not (v_filters -> 'label' is not null and jsonb_typeof(v_filters -> 'label') <> 'null' and not (jsonb_typeof(v_filters -> 'label') = 'array' and jsonb_array_length(v_filters -> 'label') = 0)) or x.labels ?| (case when jsonb_typeof(v_filters -> 'label') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'label')) else array[v_filters ->> 'label'] end))
        and (v_search is null or x.name ilike v_search)
        and (v_after is null or (x.name) > ((v_after ->> 0)::text))
      order by x.name asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 1) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PROMPT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('name', x.name, 'tenant_id', page_prompts.tenant, 'latest_version', x.latest_version, 'version_count', x.version_count, 'updated_at', x.updated_at, 'labels', x.labels) as j, jsonb_build_array((x.name)::text) as k
    from (
      select * from (
    select g."name" as name,
      max(g."version") as latest_version,
      count(*) as version_count,
      max(g."created_at") as updated_at,
      coalesce((
        select jsonb_object_agg(y."label", y."version") from "better_supabase"."prompt_labels" y
        where coalesce(y."tenant_id"::text, '') = coalesce(page_prompts.tenant::text, '') and y."name" = g."name"
      ), '{}'::jsonb) as labels
    from "better_supabase"."prompt_versions" g
    where coalesce(g."tenant_id"::text, '') = coalesce(page_prompts.tenant::text, '')
    group by g."name"
  ) x
      where (not (v_filters -> 'name' is not null and jsonb_typeof(v_filters -> 'name') <> 'null' and not (jsonb_typeof(v_filters -> 'name') = 'array' and jsonb_array_length(v_filters -> 'name') = 0)) or x.name = any((case when jsonb_typeof(v_filters -> 'name') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'name')) else array[v_filters ->> 'name'] end)::text[]))
        and (not (v_filters -> 'label' is not null and jsonb_typeof(v_filters -> 'label') <> 'null' and not (jsonb_typeof(v_filters -> 'label') = 'array' and jsonb_array_length(v_filters -> 'label') = 0)) or x.labels ?| (case when jsonb_typeof(v_filters -> 'label') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'label')) else array[v_filters ->> 'label'] end))
        and (v_search is null or x.name ilike v_search)
        and (v_after is null or (x.name) < ((v_after ->> 0)::text))
      order by x.name desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PROMPT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('name', x.name, 'tenant_id', page_prompts.tenant, 'latest_version', x.latest_version, 'version_count', x.version_count, 'updated_at', x.updated_at, 'labels', x.labels) as j, jsonb_build_array((coalesce(x.updated_at, 'epoch'::timestamptz))::text, (x.name)::text) as k
    from (
      select * from (
    select g."name" as name,
      max(g."version") as latest_version,
      count(*) as version_count,
      max(g."created_at") as updated_at,
      coalesce((
        select jsonb_object_agg(y."label", y."version") from "better_supabase"."prompt_labels" y
        where coalesce(y."tenant_id"::text, '') = coalesce(page_prompts.tenant::text, '') and y."name" = g."name"
      ), '{}'::jsonb) as labels
    from "better_supabase"."prompt_versions" g
    where coalesce(g."tenant_id"::text, '') = coalesce(page_prompts.tenant::text, '')
    group by g."name"
  ) x
      where (not (v_filters -> 'name' is not null and jsonb_typeof(v_filters -> 'name') <> 'null' and not (jsonb_typeof(v_filters -> 'name') = 'array' and jsonb_array_length(v_filters -> 'name') = 0)) or x.name = any((case when jsonb_typeof(v_filters -> 'name') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'name')) else array[v_filters ->> 'name'] end)::text[]))
        and (not (v_filters -> 'label' is not null and jsonb_typeof(v_filters -> 'label') <> 'null' and not (jsonb_typeof(v_filters -> 'label') = 'array' and jsonb_array_length(v_filters -> 'label') = 0)) or x.labels ?| (case when jsonb_typeof(v_filters -> 'label') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'label')) else array[v_filters ->> 'label'] end))
        and (v_search is null or x.name ilike v_search)
        and (v_after is null or (coalesce(x.updated_at, 'epoch'::timestamptz), x.name) > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::text))
      order by coalesce(x.updated_at, 'epoch'::timestamptz) asc, x.name asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PROMPT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('name', x.name, 'tenant_id', page_prompts.tenant, 'latest_version', x.latest_version, 'version_count', x.version_count, 'updated_at', x.updated_at, 'labels', x.labels) as j, jsonb_build_array((coalesce(x.updated_at, 'epoch'::timestamptz))::text, (x.name)::text) as k
    from (
      select * from (
    select g."name" as name,
      max(g."version") as latest_version,
      count(*) as version_count,
      max(g."created_at") as updated_at,
      coalesce((
        select jsonb_object_agg(y."label", y."version") from "better_supabase"."prompt_labels" y
        where coalesce(y."tenant_id"::text, '') = coalesce(page_prompts.tenant::text, '') and y."name" = g."name"
      ), '{}'::jsonb) as labels
    from "better_supabase"."prompt_versions" g
    where coalesce(g."tenant_id"::text, '') = coalesce(page_prompts.tenant::text, '')
    group by g."name"
  ) x
      where (not (v_filters -> 'name' is not null and jsonb_typeof(v_filters -> 'name') <> 'null' and not (jsonb_typeof(v_filters -> 'name') = 'array' and jsonb_array_length(v_filters -> 'name') = 0)) or x.name = any((case when jsonb_typeof(v_filters -> 'name') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'name')) else array[v_filters ->> 'name'] end)::text[]))
        and (not (v_filters -> 'label' is not null and jsonb_typeof(v_filters -> 'label') <> 'null' and not (jsonb_typeof(v_filters -> 'label') = 'array' and jsonb_array_length(v_filters -> 'label') = 0)) or x.labels ?| (case when jsonb_typeof(v_filters -> 'label') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'label')) else array[v_filters ->> 'label'] end))
        and (v_search is null or x.name ilike v_search)
        and (v_after is null or (coalesce(x.updated_at, 'epoch'::timestamptz) <= (v_after ->> 0)::timestamptz and ((coalesce(x.updated_at, 'epoch'::timestamptz) < (v_after ->> 0)::timestamptz) or (coalesce(x.updated_at, 'epoch'::timestamptz) = (v_after ->> 0)::timestamptz and x.name > (v_after ->> 1)::text))))
      order by coalesce(x.updated_at, 'epoch'::timestamptz) desc, x.name asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'versionCount' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PROMPT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('name', x.name, 'tenant_id', page_prompts.tenant, 'latest_version', x.latest_version, 'version_count', x.version_count, 'updated_at', x.updated_at, 'labels', x.labels) as j, jsonb_build_array((x.version_count)::text, (x.name)::text) as k
    from (
      select * from (
    select g."name" as name,
      max(g."version") as latest_version,
      count(*) as version_count,
      max(g."created_at") as updated_at,
      coalesce((
        select jsonb_object_agg(y."label", y."version") from "better_supabase"."prompt_labels" y
        where coalesce(y."tenant_id"::text, '') = coalesce(page_prompts.tenant::text, '') and y."name" = g."name"
      ), '{}'::jsonb) as labels
    from "better_supabase"."prompt_versions" g
    where coalesce(g."tenant_id"::text, '') = coalesce(page_prompts.tenant::text, '')
    group by g."name"
  ) x
      where (not (v_filters -> 'name' is not null and jsonb_typeof(v_filters -> 'name') <> 'null' and not (jsonb_typeof(v_filters -> 'name') = 'array' and jsonb_array_length(v_filters -> 'name') = 0)) or x.name = any((case when jsonb_typeof(v_filters -> 'name') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'name')) else array[v_filters ->> 'name'] end)::text[]))
        and (not (v_filters -> 'label' is not null and jsonb_typeof(v_filters -> 'label') <> 'null' and not (jsonb_typeof(v_filters -> 'label') = 'array' and jsonb_array_length(v_filters -> 'label') = 0)) or x.labels ?| (case when jsonb_typeof(v_filters -> 'label') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'label')) else array[v_filters ->> 'label'] end))
        and (v_search is null or x.name ilike v_search)
        and (v_after is null or (x.version_count, x.name) > ((v_after ->> 0)::bigint, (v_after ->> 1)::text))
      order by x.version_count asc, x.name asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'versionCount' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PROMPT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('name', x.name, 'tenant_id', page_prompts.tenant, 'latest_version', x.latest_version, 'version_count', x.version_count, 'updated_at', x.updated_at, 'labels', x.labels) as j, jsonb_build_array((x.version_count)::text, (x.name)::text) as k
    from (
      select * from (
    select g."name" as name,
      max(g."version") as latest_version,
      count(*) as version_count,
      max(g."created_at") as updated_at,
      coalesce((
        select jsonb_object_agg(y."label", y."version") from "better_supabase"."prompt_labels" y
        where coalesce(y."tenant_id"::text, '') = coalesce(page_prompts.tenant::text, '') and y."name" = g."name"
      ), '{}'::jsonb) as labels
    from "better_supabase"."prompt_versions" g
    where coalesce(g."tenant_id"::text, '') = coalesce(page_prompts.tenant::text, '')
    group by g."name"
  ) x
      where (not (v_filters -> 'name' is not null and jsonb_typeof(v_filters -> 'name') <> 'null' and not (jsonb_typeof(v_filters -> 'name') = 'array' and jsonb_array_length(v_filters -> 'name') = 0)) or x.name = any((case when jsonb_typeof(v_filters -> 'name') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'name')) else array[v_filters ->> 'name'] end)::text[]))
        and (not (v_filters -> 'label' is not null and jsonb_typeof(v_filters -> 'label') <> 'null' and not (jsonb_typeof(v_filters -> 'label') = 'array' and jsonb_array_length(v_filters -> 'label') = 0)) or x.labels ?| (case when jsonb_typeof(v_filters -> 'label') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'label')) else array[v_filters ->> 'label'] end))
        and (v_search is null or x.name ilike v_search)
        and (v_after is null or (x.version_count <= (v_after ->> 0)::bigint and ((x.version_count < (v_after ->> 0)::bigint) or (x.version_count = (v_after ->> 0)::bigint and x.name > (v_after ->> 1)::text))))
      order by x.version_count desc, x.name asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from (
    select g."name" as name,
      max(g."version") as latest_version,
      count(*) as version_count,
      max(g."created_at") as updated_at,
      coalesce((
        select jsonb_object_agg(y."label", y."version") from "better_supabase"."prompt_labels" y
        where coalesce(y."tenant_id"::text, '') = coalesce(page_prompts.tenant::text, '') and y."name" = g."name"
      ), '{}'::jsonb) as labels
    from "better_supabase"."prompt_versions" g
    where coalesce(g."tenant_id"::text, '') = coalesce(page_prompts.tenant::text, '')
    group by g."name"
  ) x
      where (not (v_filters -> 'name' is not null and jsonb_typeof(v_filters -> 'name') <> 'null' and not (jsonb_typeof(v_filters -> 'name') = 'array' and jsonb_array_length(v_filters -> 'name') = 0)) or x.name = any((case when jsonb_typeof(v_filters -> 'name') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'name')) else array[v_filters ->> 'name'] end)::text[]))
        and (not (v_filters -> 'label' is not null and jsonb_typeof(v_filters -> 'label') <> 'null' and not (jsonb_typeof(v_filters -> 'label') = 'array' and jsonb_array_length(v_filters -> 'label') = 0)) or x.labels ?| (case when jsonb_typeof(v_filters -> 'label') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'label')) else array[v_filters ->> 'label'] end))
        and (v_search is null or x.name ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_tags (
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
  v_filters jsonb := coalesce(page_tags.filters, '{}'::jsonb);
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
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', page_tags.tenant, 'tags.read'), false) or coalesce(better_supabase.can('tenant', page_tags.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to read tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('kind') then
      raise exception 'facet is one of kind' using errcode = '22023', hint = 'TAG_INVALID';
    end if;
    with s as (
      select (case v_facet when 'kind' then (x."kind"::text)::text end) as v
      from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
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
      select 1 from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('rank', 'name', 'kind', 'createdAt') then
    raise exception 'sort is one of rank, name, kind, createdAt' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."rank" collate "C")::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."rank" collate "C", lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."rank" collate "C" asc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."rank" collate "C")::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."rank" collate "C" <= (v_after ->> 0)::text and ((x."rank" collate "C" < (v_after ->> 0)::text) or (x."rank" collate "C" = (v_after ->> 0)::text and lower(x."name") > (v_after ->> 1)::text) or (x."rank" collate "C" = (v_after ->> 0)::text and lower(x."name") = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."rank" collate "C" desc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'rank' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."rank" collate "C")::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."rank" collate "C", lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."rank" collate "C" asc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'rank' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."rank" collate "C")::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."rank" collate "C" <= (v_after ->> 0)::text and ((x."rank" collate "C" < (v_after ->> 0)::text) or (x."rank" collate "C" = (v_after ->> 0)::text and lower(x."name") > (v_after ->> 1)::text) or (x."rank" collate "C" = (v_after ->> 0)::text and lower(x."name") = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."rank" collate "C" desc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'kind' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."kind"::text)::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."kind"::text, lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."kind"::text asc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'kind' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."kind"::text)::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."kind"::text <= (v_after ->> 0)::text and ((x."kind"::text < (v_after ->> 0)::text) or (x."kind"::text = (v_after ->> 0)::text and lower(x."name") > (v_after ->> 1)::text) or (x."kind"::text = (v_after ->> 0)::text and lower(x."name") = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."kind"::text desc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
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
      select 1 from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

REVOKE ALL ON FUNCTION "api"."get_announcement"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_announcement"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_my_reminder"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_my_reminder"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_tag"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_tag"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_announcements"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_announcements"(jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_my_reminders"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_my_reminders"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_prompts"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_prompts"(uuid, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "api"."page_tags"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_tags"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_announcement"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_announcement"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_my_reminder"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_my_reminder"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_tag"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_tag"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_announcements"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_announcements"(jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_my_reminders"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_my_reminders"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_prompts"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_prompts"(uuid, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_tags"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_tags"(uuid, jsonb) TO "authenticated", "service_role";
