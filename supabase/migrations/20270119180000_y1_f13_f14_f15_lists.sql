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

CREATE OR REPLACE FUNCTION api.get_project (
  project uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_project"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_tag (
  tag_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_tag"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_view (
  view_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_view"($1) $function$;

CREATE OR REPLACE FUNCTION api.page_announcements (
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_announcements"($1) $function$;

CREATE OR REPLACE FUNCTION api.page_maintenance_requests (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_maintenance_requests"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_my_reminders (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_my_reminders"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_projects (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_projects"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_prompts (
  tenant  uuid  DEFAULT NULL::uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_prompts"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_saved_views (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_saved_views"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_tags (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_tags"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_work_items (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_work_items"($1, $2) $function$;

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

CREATE OR REPLACE FUNCTION better_supabase.get_project (
  project uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select to_jsonb(x) || jsonb_build_object('budget_amount', x."budget_amount"::text) || jsonb_build_object('progress', (
      select case when count(*) = 0 then null else round(100.0 * count(*) filter (where y."state" = 'completed') / count(*) filter (where y."state" <> 'canceled')) end
      from "better_supabase"."work_items" y where y."project_id" = x."id" and y."archived_at" is null
    )) from "better_supabase"."work_projects" x where x."id" = get_project.project
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

CREATE OR REPLACE FUNCTION better_supabase.get_view (
  view_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'id', x."id",
    'list', x."list",
    'scope', x."scope",
    'ownerId', x."owner_id",
    'teamId', x."team_id",
    'name', x."name",
    'kind', x."kind",
    'state', x."state",
    'rank', x."rank",
    'isDefault', x."is_default",
    'updatedAt', x."updated_at",
    'preference', x.bsb_preference
  )
  from (select v.*, jsonb_build_object('isDefault', coalesce(p."is_default", false), 'hidden', coalesce(p."hidden", false), 'pinned', coalesce(p."pinned", false)) as bsb_preference from "better_supabase"."shared_views" v
  left join "better_supabase"."saved_view_preferences" p on p."view_id" = v."id" and p."user_id" = (select auth.uid())) x
  where x."id" = get_view.view_id
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

CREATE OR REPLACE FUNCTION better_supabase.page_maintenance_requests (
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
  v_filters jsonb := coalesce(page_maintenance_requests.filters, '{}'::jsonb);
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
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('state', 'priority') then
      raise exception 'facet is one of state, priority' using errcode = '22023', hint = 'TASK_INVALID';
    end if;
    with s as (
      select (case v_facet when 'state' then (x."state")::text when 'priority' then (x."priority"::text)::text end) as v
      from "better_supabase"."maintenance_requests" x
      where x."tenant_id" = page_maintenance_requests.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or x."state" = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
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
      select 1 from "better_supabase"."maintenance_requests" x
      where x."tenant_id" = page_maintenance_requests.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or x."state" = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('number', 'title', 'dueAt', 'createdAt') then
    raise exception 'sort is one of number, title, dueAt, createdAt' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) as j, jsonb_build_array((x."number")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."maintenance_requests" x
      where x."tenant_id" = page_maintenance_requests.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or x."state" = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (x."number", x."id") > ((v_after ->> 0)::bigint, (v_after ->> 1)::uuid))
      order by x."number" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) as j, jsonb_build_array((x."number")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."maintenance_requests" x
      where x."tenant_id" = page_maintenance_requests.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or x."state" = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (x."number" <= (v_after ->> 0)::bigint and ((x."number" < (v_after ->> 0)::bigint) or (x."number" = (v_after ->> 0)::bigint and x."id" > (v_after ->> 1)::uuid))))
      order by x."number" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'number' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) as j, jsonb_build_array((x."number")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."maintenance_requests" x
      where x."tenant_id" = page_maintenance_requests.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or x."state" = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (x."number", x."id") > ((v_after ->> 0)::bigint, (v_after ->> 1)::uuid))
      order by x."number" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'number' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) as j, jsonb_build_array((x."number")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."maintenance_requests" x
      where x."tenant_id" = page_maintenance_requests.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or x."state" = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (x."number" <= (v_after ->> 0)::bigint and ((x."number" < (v_after ->> 0)::bigint) or (x."number" = (v_after ->> 0)::bigint and x."id" > (v_after ->> 1)::uuid))))
      order by x."number" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."maintenance_requests" x
      where x."tenant_id" = page_maintenance_requests.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or x."state" = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (lower(x."title"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."title") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."maintenance_requests" x
      where x."tenant_id" = page_maintenance_requests.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or x."state" = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (lower(x."title") <= (v_after ->> 0)::text and ((lower(x."title") < (v_after ->> 0)::text) or (lower(x."title") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."title") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'dueAt' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) as j, jsonb_build_array((coalesce(x."due_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."maintenance_requests" x
      where x."tenant_id" = page_maintenance_requests.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or x."state" = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (coalesce(x."due_at", 'infinity'::timestamptz), x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."due_at", 'infinity'::timestamptz) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'dueAt' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) as j, jsonb_build_array((coalesce(x."due_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."maintenance_requests" x
      where x."tenant_id" = page_maintenance_requests.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or x."state" = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (coalesce(x."due_at", 'infinity'::timestamptz) <= (v_after ->> 0)::timestamptz and ((coalesce(x."due_at", 'infinity'::timestamptz) < (v_after ->> 0)::timestamptz) or (coalesce(x."due_at", 'infinity'::timestamptz) = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."due_at", 'infinity'::timestamptz) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."maintenance_requests" x
      where x."tenant_id" = page_maintenance_requests.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or x."state" = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."maintenance_requests" x
      where x."tenant_id" = page_maintenance_requests.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or x."state" = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
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
      select 1 from "better_supabase"."maintenance_requests" x
      where x."tenant_id" = page_maintenance_requests.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or x."state" = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
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

CREATE OR REPLACE FUNCTION better_supabase.page_projects (
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
  v_filters jsonb := coalesce(page_projects.filters, '{}'::jsonb);
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
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'TASK_PROJECT_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status') then
      raise exception 'facet is one of status' using errcode = '22023', hint = 'TASK_PROJECT_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status"::text)::text end) as v
      from "better_supabase"."work_projects" x
      where x."tenant_id" = page_projects.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id" = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::uuid[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
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
      select 1 from "better_supabase"."work_projects" x
      where x."tenant_id" = page_projects.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id" = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::uuid[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'key', 'createdAt') then
    raise exception 'sort is one of name, key, createdAt' using errcode = '22023', hint = 'TASK_PROJECT_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'TASK_PROJECT_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_PROJECT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('budget_amount', x."budget_amount"::text) || jsonb_build_object('progress', (
      select case when count(*) = 0 then null else round(100.0 * count(*) filter (where y."state" = 'completed') / count(*) filter (where y."state" <> 'canceled')) end
      from "better_supabase"."work_items" y where y."project_id" = x."id" and y."archived_at" is null
    )) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_projects" x
      where x."tenant_id" = page_projects.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id" = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::uuid[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_PROJECT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('budget_amount', x."budget_amount"::text) || jsonb_build_object('progress', (
      select case when count(*) = 0 then null else round(100.0 * count(*) filter (where y."state" = 'completed') / count(*) filter (where y."state" <> 'canceled')) end
      from "better_supabase"."work_items" y where y."project_id" = x."id" and y."archived_at" is null
    )) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_projects" x
      where x."tenant_id" = page_projects.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id" = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::uuid[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_PROJECT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('budget_amount', x."budget_amount"::text) || jsonb_build_object('progress', (
      select case when count(*) = 0 then null else round(100.0 * count(*) filter (where y."state" = 'completed') / count(*) filter (where y."state" <> 'canceled')) end
      from "better_supabase"."work_items" y where y."project_id" = x."id" and y."archived_at" is null
    )) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_projects" x
      where x."tenant_id" = page_projects.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id" = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::uuid[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_PROJECT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('budget_amount', x."budget_amount"::text) || jsonb_build_object('progress', (
      select case when count(*) = 0 then null else round(100.0 * count(*) filter (where y."state" = 'completed') / count(*) filter (where y."state" <> 'canceled')) end
      from "better_supabase"."work_items" y where y."project_id" = x."id" and y."archived_at" is null
    )) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_projects" x
      where x."tenant_id" = page_projects.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id" = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::uuid[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'key' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_PROJECT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('budget_amount', x."budget_amount"::text) || jsonb_build_object('progress', (
      select case when count(*) = 0 then null else round(100.0 * count(*) filter (where y."state" = 'completed') / count(*) filter (where y."state" <> 'canceled')) end
      from "better_supabase"."work_items" y where y."project_id" = x."id" and y."archived_at" is null
    )) as j, jsonb_build_array((x."key")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_projects" x
      where x."tenant_id" = page_projects.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id" = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::uuid[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."key", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."key" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'key' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_PROJECT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('budget_amount', x."budget_amount"::text) || jsonb_build_object('progress', (
      select case when count(*) = 0 then null else round(100.0 * count(*) filter (where y."state" = 'completed') / count(*) filter (where y."state" <> 'canceled')) end
      from "better_supabase"."work_items" y where y."project_id" = x."id" and y."archived_at" is null
    )) as j, jsonb_build_array((x."key")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_projects" x
      where x."tenant_id" = page_projects.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id" = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::uuid[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."key" <= (v_after ->> 0)::text and ((x."key" < (v_after ->> 0)::text) or (x."key" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."key" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_PROJECT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('budget_amount', x."budget_amount"::text) || jsonb_build_object('progress', (
      select case when count(*) = 0 then null else round(100.0 * count(*) filter (where y."state" = 'completed') / count(*) filter (where y."state" <> 'canceled')) end
      from "better_supabase"."work_items" y where y."project_id" = x."id" and y."archived_at" is null
    )) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_projects" x
      where x."tenant_id" = page_projects.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id" = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::uuid[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_PROJECT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('budget_amount', x."budget_amount"::text) || jsonb_build_object('progress', (
      select case when count(*) = 0 then null else round(100.0 * count(*) filter (where y."state" = 'completed') / count(*) filter (where y."state" <> 'canceled')) end
      from "better_supabase"."work_items" y where y."project_id" = x."id" and y."archived_at" is null
    )) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_projects" x
      where x."tenant_id" = page_projects.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id" = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::uuid[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
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
      select 1 from "better_supabase"."work_projects" x
      where x."tenant_id" = page_projects.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id" = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::uuid[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
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

CREATE OR REPLACE FUNCTION better_supabase.page_saved_views (
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
  v_filters jsonb := coalesce(page_saved_views.filters, '{}'::jsonb);
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
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'SAVED_VIEW_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('scope', 'kind') then
      raise exception 'facet is one of scope, kind' using errcode = '22023', hint = 'SAVED_VIEW_INVALID';
    end if;
    with s as (
      select (case v_facet when 'scope' then (x."scope")::text when 'kind' then (x."kind")::text end) as v
      from (select v.*, jsonb_build_object('isDefault', coalesce(p."is_default", false), 'hidden', coalesce(p."hidden", false), 'pinned', coalesce(p."pinned", false)) as bsb_preference from "better_supabase"."shared_views" v
  left join "better_supabase"."saved_view_preferences" p on p."view_id" = v."id" and p."user_id" = (select auth.uid())) x
      where x."tenant_id" = page_saved_views.tenant
        and (not (v_filters -> 'list' is not null and jsonb_typeof(v_filters -> 'list') <> 'null' and not (jsonb_typeof(v_filters -> 'list') = 'array' and jsonb_array_length(v_filters -> 'list') = 0)) or x."list" = any((case when jsonb_typeof(v_filters -> 'list') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'list')) else array[v_filters ->> 'list'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
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
      select 1 from (select v.*, jsonb_build_object('isDefault', coalesce(p."is_default", false), 'hidden', coalesce(p."hidden", false), 'pinned', coalesce(p."pinned", false)) as bsb_preference from "better_supabase"."shared_views" v
  left join "better_supabase"."saved_view_preferences" p on p."view_id" = v."id" and p."user_id" = (select auth.uid())) x
      where x."tenant_id" = page_saved_views.tenant
        and (not (v_filters -> 'list' is not null and jsonb_typeof(v_filters -> 'list') <> 'null' and not (jsonb_typeof(v_filters -> 'list') = 'array' and jsonb_array_length(v_filters -> 'list') = 0)) or x."list" = any((case when jsonb_typeof(v_filters -> 'list') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'list')) else array[v_filters ->> 'list'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('rank', 'name', 'updatedAt') then
    raise exception 'sort is one of rank, name, updatedAt' using errcode = '22023', hint = 'SAVED_VIEW_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'SAVED_VIEW_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SAVED_VIEW_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'list', x."list",
    'scope', x."scope",
    'ownerId', x."owner_id",
    'teamId', x."team_id",
    'name', x."name",
    'kind', x."kind",
    'state', x."state",
    'rank', x."rank",
    'isDefault', x."is_default",
    'updatedAt', x."updated_at",
    'preference', x.bsb_preference
  ) as j, jsonb_build_array((x."rank" collate "C")::text, (x."id")::text) as k
    from (
      select * from (select v.*, jsonb_build_object('isDefault', coalesce(p."is_default", false), 'hidden', coalesce(p."hidden", false), 'pinned', coalesce(p."pinned", false)) as bsb_preference from "better_supabase"."shared_views" v
  left join "better_supabase"."saved_view_preferences" p on p."view_id" = v."id" and p."user_id" = (select auth.uid())) x
      where x."tenant_id" = page_saved_views.tenant
        and (not (v_filters -> 'list' is not null and jsonb_typeof(v_filters -> 'list') <> 'null' and not (jsonb_typeof(v_filters -> 'list') = 'array' and jsonb_array_length(v_filters -> 'list') = 0)) or x."list" = any((case when jsonb_typeof(v_filters -> 'list') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'list')) else array[v_filters ->> 'list'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (x."rank" collate "C", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."rank" collate "C" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SAVED_VIEW_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'list', x."list",
    'scope', x."scope",
    'ownerId', x."owner_id",
    'teamId', x."team_id",
    'name', x."name",
    'kind', x."kind",
    'state', x."state",
    'rank', x."rank",
    'isDefault', x."is_default",
    'updatedAt', x."updated_at",
    'preference', x.bsb_preference
  ) as j, jsonb_build_array((x."rank" collate "C")::text, (x."id")::text) as k
    from (
      select * from (select v.*, jsonb_build_object('isDefault', coalesce(p."is_default", false), 'hidden', coalesce(p."hidden", false), 'pinned', coalesce(p."pinned", false)) as bsb_preference from "better_supabase"."shared_views" v
  left join "better_supabase"."saved_view_preferences" p on p."view_id" = v."id" and p."user_id" = (select auth.uid())) x
      where x."tenant_id" = page_saved_views.tenant
        and (not (v_filters -> 'list' is not null and jsonb_typeof(v_filters -> 'list') <> 'null' and not (jsonb_typeof(v_filters -> 'list') = 'array' and jsonb_array_length(v_filters -> 'list') = 0)) or x."list" = any((case when jsonb_typeof(v_filters -> 'list') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'list')) else array[v_filters ->> 'list'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (x."rank" collate "C" <= (v_after ->> 0)::text and ((x."rank" collate "C" < (v_after ->> 0)::text) or (x."rank" collate "C" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."rank" collate "C" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'rank' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SAVED_VIEW_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'list', x."list",
    'scope', x."scope",
    'ownerId', x."owner_id",
    'teamId', x."team_id",
    'name', x."name",
    'kind', x."kind",
    'state', x."state",
    'rank', x."rank",
    'isDefault', x."is_default",
    'updatedAt', x."updated_at",
    'preference', x.bsb_preference
  ) as j, jsonb_build_array((x."rank" collate "C")::text, (x."id")::text) as k
    from (
      select * from (select v.*, jsonb_build_object('isDefault', coalesce(p."is_default", false), 'hidden', coalesce(p."hidden", false), 'pinned', coalesce(p."pinned", false)) as bsb_preference from "better_supabase"."shared_views" v
  left join "better_supabase"."saved_view_preferences" p on p."view_id" = v."id" and p."user_id" = (select auth.uid())) x
      where x."tenant_id" = page_saved_views.tenant
        and (not (v_filters -> 'list' is not null and jsonb_typeof(v_filters -> 'list') <> 'null' and not (jsonb_typeof(v_filters -> 'list') = 'array' and jsonb_array_length(v_filters -> 'list') = 0)) or x."list" = any((case when jsonb_typeof(v_filters -> 'list') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'list')) else array[v_filters ->> 'list'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (x."rank" collate "C", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."rank" collate "C" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'rank' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SAVED_VIEW_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'list', x."list",
    'scope', x."scope",
    'ownerId', x."owner_id",
    'teamId', x."team_id",
    'name', x."name",
    'kind', x."kind",
    'state', x."state",
    'rank', x."rank",
    'isDefault', x."is_default",
    'updatedAt', x."updated_at",
    'preference', x.bsb_preference
  ) as j, jsonb_build_array((x."rank" collate "C")::text, (x."id")::text) as k
    from (
      select * from (select v.*, jsonb_build_object('isDefault', coalesce(p."is_default", false), 'hidden', coalesce(p."hidden", false), 'pinned', coalesce(p."pinned", false)) as bsb_preference from "better_supabase"."shared_views" v
  left join "better_supabase"."saved_view_preferences" p on p."view_id" = v."id" and p."user_id" = (select auth.uid())) x
      where x."tenant_id" = page_saved_views.tenant
        and (not (v_filters -> 'list' is not null and jsonb_typeof(v_filters -> 'list') <> 'null' and not (jsonb_typeof(v_filters -> 'list') = 'array' and jsonb_array_length(v_filters -> 'list') = 0)) or x."list" = any((case when jsonb_typeof(v_filters -> 'list') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'list')) else array[v_filters ->> 'list'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (x."rank" collate "C" <= (v_after ->> 0)::text and ((x."rank" collate "C" < (v_after ->> 0)::text) or (x."rank" collate "C" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."rank" collate "C" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SAVED_VIEW_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'list', x."list",
    'scope', x."scope",
    'ownerId', x."owner_id",
    'teamId', x."team_id",
    'name', x."name",
    'kind', x."kind",
    'state', x."state",
    'rank', x."rank",
    'isDefault', x."is_default",
    'updatedAt', x."updated_at",
    'preference', x.bsb_preference
  ) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from (select v.*, jsonb_build_object('isDefault', coalesce(p."is_default", false), 'hidden', coalesce(p."hidden", false), 'pinned', coalesce(p."pinned", false)) as bsb_preference from "better_supabase"."shared_views" v
  left join "better_supabase"."saved_view_preferences" p on p."view_id" = v."id" and p."user_id" = (select auth.uid())) x
      where x."tenant_id" = page_saved_views.tenant
        and (not (v_filters -> 'list' is not null and jsonb_typeof(v_filters -> 'list') <> 'null' and not (jsonb_typeof(v_filters -> 'list') = 'array' and jsonb_array_length(v_filters -> 'list') = 0)) or x."list" = any((case when jsonb_typeof(v_filters -> 'list') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'list')) else array[v_filters ->> 'list'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SAVED_VIEW_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'list', x."list",
    'scope', x."scope",
    'ownerId', x."owner_id",
    'teamId', x."team_id",
    'name', x."name",
    'kind', x."kind",
    'state', x."state",
    'rank', x."rank",
    'isDefault', x."is_default",
    'updatedAt', x."updated_at",
    'preference', x.bsb_preference
  ) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from (select v.*, jsonb_build_object('isDefault', coalesce(p."is_default", false), 'hidden', coalesce(p."hidden", false), 'pinned', coalesce(p."pinned", false)) as bsb_preference from "better_supabase"."shared_views" v
  left join "better_supabase"."saved_view_preferences" p on p."view_id" = v."id" and p."user_id" = (select auth.uid())) x
      where x."tenant_id" = page_saved_views.tenant
        and (not (v_filters -> 'list' is not null and jsonb_typeof(v_filters -> 'list') <> 'null' and not (jsonb_typeof(v_filters -> 'list') = 'array' and jsonb_array_length(v_filters -> 'list') = 0)) or x."list" = any((case when jsonb_typeof(v_filters -> 'list') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'list')) else array[v_filters ->> 'list'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SAVED_VIEW_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'list', x."list",
    'scope', x."scope",
    'ownerId', x."owner_id",
    'teamId', x."team_id",
    'name', x."name",
    'kind', x."kind",
    'state', x."state",
    'rank', x."rank",
    'isDefault', x."is_default",
    'updatedAt', x."updated_at",
    'preference', x.bsb_preference
  ) as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from (select v.*, jsonb_build_object('isDefault', coalesce(p."is_default", false), 'hidden', coalesce(p."hidden", false), 'pinned', coalesce(p."pinned", false)) as bsb_preference from "better_supabase"."shared_views" v
  left join "better_supabase"."saved_view_preferences" p on p."view_id" = v."id" and p."user_id" = (select auth.uid())) x
      where x."tenant_id" = page_saved_views.tenant
        and (not (v_filters -> 'list' is not null and jsonb_typeof(v_filters -> 'list') <> 'null' and not (jsonb_typeof(v_filters -> 'list') = 'array' and jsonb_array_length(v_filters -> 'list') = 0)) or x."list" = any((case when jsonb_typeof(v_filters -> 'list') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'list')) else array[v_filters ->> 'list'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (x."updated_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."updated_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SAVED_VIEW_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'list', x."list",
    'scope', x."scope",
    'ownerId', x."owner_id",
    'teamId', x."team_id",
    'name', x."name",
    'kind', x."kind",
    'state', x."state",
    'rank', x."rank",
    'isDefault', x."is_default",
    'updatedAt', x."updated_at",
    'preference', x.bsb_preference
  ) as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from (select v.*, jsonb_build_object('isDefault', coalesce(p."is_default", false), 'hidden', coalesce(p."hidden", false), 'pinned', coalesce(p."pinned", false)) as bsb_preference from "better_supabase"."shared_views" v
  left join "better_supabase"."saved_view_preferences" p on p."view_id" = v."id" and p."user_id" = (select auth.uid())) x
      where x."tenant_id" = page_saved_views.tenant
        and (not (v_filters -> 'list' is not null and jsonb_typeof(v_filters -> 'list') <> 'null' and not (jsonb_typeof(v_filters -> 'list') = 'array' and jsonb_array_length(v_filters -> 'list') = 0)) or x."list" = any((case when jsonb_typeof(v_filters -> 'list') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'list')) else array[v_filters ->> 'list'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search)
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
      select 1 from (select v.*, jsonb_build_object('isDefault', coalesce(p."is_default", false), 'hidden', coalesce(p."hidden", false), 'pinned', coalesce(p."pinned", false)) as bsb_preference from "better_supabase"."shared_views" v
  left join "better_supabase"."saved_view_preferences" p on p."view_id" = v."id" and p."user_id" = (select auth.uid())) x
      where x."tenant_id" = page_saved_views.tenant
        and (not (v_filters -> 'list' is not null and jsonb_typeof(v_filters -> 'list') <> 'null' and not (jsonb_typeof(v_filters -> 'list') = 'array' and jsonb_array_length(v_filters -> 'list') = 0)) or x."list" = any((case when jsonb_typeof(v_filters -> 'list') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'list')) else array[v_filters ->> 'list'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search)
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

CREATE OR REPLACE FUNCTION better_supabase.page_work_items (
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
  v_filters jsonb := coalesce(page_work_items.filters, '{}'::jsonb);
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
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('state', 'priority') then
      raise exception 'facet is one of state, priority' using errcode = '22023', hint = 'TASK_INVALID';
    end if;
    with s as (
      select (case v_facet when 'state' then (x."state")::text when 'priority' then (x."priority"::text)::text end) as v
      from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or x."state" = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
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
      select 1 from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or x."state" = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('number', 'title', 'dueAt', 'createdAt') then
    raise exception 'sort is one of number, title, dueAt, createdAt' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) as j, jsonb_build_array((x."number")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or x."state" = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (x."number", x."id") > ((v_after ->> 0)::bigint, (v_after ->> 1)::uuid))
      order by x."number" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) as j, jsonb_build_array((x."number")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or x."state" = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (x."number" <= (v_after ->> 0)::bigint and ((x."number" < (v_after ->> 0)::bigint) or (x."number" = (v_after ->> 0)::bigint and x."id" > (v_after ->> 1)::uuid))))
      order by x."number" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'number' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) as j, jsonb_build_array((x."number")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or x."state" = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (x."number", x."id") > ((v_after ->> 0)::bigint, (v_after ->> 1)::uuid))
      order by x."number" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'number' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) as j, jsonb_build_array((x."number")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or x."state" = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (x."number" <= (v_after ->> 0)::bigint and ((x."number" < (v_after ->> 0)::bigint) or (x."number" = (v_after ->> 0)::bigint and x."id" > (v_after ->> 1)::uuid))))
      order by x."number" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or x."state" = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (lower(x."title"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."title") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or x."state" = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (lower(x."title") <= (v_after ->> 0)::text and ((lower(x."title") < (v_after ->> 0)::text) or (lower(x."title") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."title") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'dueAt' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) as j, jsonb_build_array((coalesce(x."due_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or x."state" = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (coalesce(x."due_at", 'infinity'::timestamptz), x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."due_at", 'infinity'::timestamptz) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'dueAt' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) as j, jsonb_build_array((coalesce(x."due_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or x."state" = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (coalesce(x."due_at", 'infinity'::timestamptz) <= (v_after ->> 0)::timestamptz and ((coalesce(x."due_at", 'infinity'::timestamptz) < (v_after ->> 0)::timestamptz) or (coalesce(x."due_at", 'infinity'::timestamptz) = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."due_at", 'infinity'::timestamptz) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or x."state" = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or x."state" = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
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
      select 1 from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or x."state" = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
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

REVOKE ALL ON FUNCTION "api"."get_project"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_project"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_tag"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_tag"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_view"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_view"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_announcements"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_announcements"(jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_maintenance_requests"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_maintenance_requests"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_my_reminders"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_my_reminders"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_projects"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_projects"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_prompts"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_prompts"(uuid, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "api"."page_saved_views"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_saved_views"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_tags"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_tags"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_work_items"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_work_items"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_announcement"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_announcement"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_my_reminder"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_my_reminder"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_project"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_project"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_tag"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_tag"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_view"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_view"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_announcements"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_announcements"(jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_maintenance_requests"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_maintenance_requests"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_my_reminders"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_my_reminders"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_projects"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_projects"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_prompts"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_prompts"(uuid, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_saved_views"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_saved_views"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_tags"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_tags"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_work_items"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_work_items"(uuid, jsonb) TO "authenticated", "service_role";
